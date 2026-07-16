import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community_models.dart';

class CommunityService {
  CommunityService._();
  static final CommunityService instance = CommunityService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const List<String> _hardOwnerUids = <String>[
    '7CYI66sIq3UbOHwq2qi85bpFL7x2',
    'fQwIV1wg5pUsz9zVMLpyqAdUAFL2',
  ];

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('communityPosts');
  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('communityReports');

  CollectionReference<Map<String, dynamic>> _commentsCollection(
    String postId,
    String sourceCollection,
  ) {
    final safeSource = sourceCollection == 'posts' ? 'posts' : 'communityPosts';
    return _db.collection(safeSource).doc(postId).collection('comments');
  }

  String? get currentUid => _auth.currentUser?.uid;

  Future<CommunityAuthorProfile> loadCurrentProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
          code: 'not-signed-in', message: 'يجب تسجيل الدخول');
    }

    final snap = await _db.doc('users/${user.uid}').get();
    final data = snap.data() ?? const <String, dynamic>{};

    final role = (data['role'] ?? 'user').toString().toLowerCase().trim();
    final showAsSupport =
        role == 'owner' || role == 'admin' || role == 'support';

    final rawName = _firstNotEmpty([
      data['displayName'],
      data['name'],
      data['username'],
      user.displayName,
      user.email?.split('@').first,
    ]);

    final username = _firstNotEmpty([
      data['username'],
      data['userName'],
      user.email?.split('@').first,
    ]).replaceFirst('@', '').trim();

    final photo = _firstNotEmpty([
      data['photoUrl'],
      data['photoURL'],
      data['profileImageUrl'],
      user.photoURL,
    ]);

    return CommunityAuthorProfile(
      uid: user.uid,
      displayName:
          showAsSupport ? 'دعم وازن' : (rawName.isEmpty ? 'مستخدم وازن' : rawName),
      username: showAsSupport ? '' : username,
      photoUrl: showAsSupport ? '' : photo,
      role: role.isEmpty ? 'user' : role,
      showAsSupport: showAsSupport,
    );
  }

  Future<String> createPost({
    required CommunityCategory category,
    required String content,
    String? recipeId,
    String? recipeTitle,
  }) async {
    final trimmed = content.trim();
    if (trimmed.length < 3) {
      throw ArgumentError('اكتب محتوى أوضح قبل النشر');
    }
    if (trimmed.length > 1800) {
      throw ArgumentError('النص طويل جدًا. اختصره إلى 1800 حرف كحد أقصى.');
    }

    final profile = await loadCurrentProfile();
    await _assertAllowedToPost(profile.uid);

    final ref = _posts.doc();
    await ref.set({
      'authorUid': profile.uid,
      'authorName': profile.displayName,
      'authorUsername': profile.username,
      'authorPhotoUrl': profile.photoUrl,
      'authorRole': profile.role,
      'supportDisplay': profile.showAsSupport,
      'category': category.firestoreValue,
      'content': trimmed,
      'likesCount': 0,
      'commentsCount': 0,
      'trendScore': 0,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if ((recipeId ?? '').trim().isNotEmpty) 'recipeId': recipeId!.trim(),
      if ((recipeTitle ?? '').trim().isNotEmpty)
        'recipeTitle': recipeTitle!.trim(),
    });
    return ref.id;
  }

  Stream<List<CommunityPost>> streamPosts({required CommunitySort sort}) {
    return _posts
        .orderBy(sort.orderField, descending: true)
        .limit(160)
        .snapshots()
        .map((snap) => snap.docs
            .map(CommunityPost.fromDoc)
            .where((p) => !p.isDeleted && p.content.trim().isNotEmpty)
            .toList(growable: false));
  }

  Stream<bool> streamIsLiked(String postId, String uid) {
    return _posts
        .doc(postId)
        .collection('likes')
        .doc(uid)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<void> toggleLike(CommunityPost post) async {
    final uid = currentUid;
    if (uid == null) {
      throw FirebaseAuthException(
          code: 'not-signed-in', message: 'يجب تسجيل الدخول');
    }

    final likeRef = _posts.doc(post.id).collection('likes').doc(uid);
    final mirrorRef = _db.doc('users/$uid/communityLikes/${post.id}');
    final likeSnap = await likeRef.get();

    final batch = _db.batch();
    if (likeSnap.exists) {
      batch.delete(likeRef);
      batch.delete(mirrorRef);
      batch.update(_posts.doc(post.id), {
        'likesCount': FieldValue.increment(-1),
        'trendScore': FieldValue.increment(-2),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.set(likeRef, {
        'uid': uid,
        'postId': post.id,
        'authorUid': post.authorUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(mirrorRef, {
        'postId': post.id,
        'authorUid': post.authorUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_posts.doc(post.id), {
        'likesCount': FieldValue.increment(1),
        'trendScore': FieldValue.increment(2),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    if (!likeSnap.exists) {
      unawaited(_safeSendCommunityNotification(
        toUid: post.authorUid,
        senderUid: uid,
        senderName: 'مستخدم وازن',
        type: 'community_post_like',
        title: 'إعجاب جديد في مجتمع وازن',
        body: 'شخص أعجب بمنشورك في مجتمع وازن.',
        postId: post.id,
      ));
    }
  }

  Future<String?> resolveCommentAuthorUid(CommunityComment comment) {
    return _resolveUserUid(
      uid: comment.authorUid,
      username: comment.authorUsername,
      fallbackName: comment.authorName,
    );
  }

  Future<String?> resolveReplyTargetUid(CommunityComment comment) {
    return _resolveUserUid(
      uid: comment.replyToUid,
      username: comment.replyToUsername,
      fallbackName: comment.replyToName,
    );
  }

  Future<String?> _resolveUserUid({
    String? uid,
    String? username,
    String? fallbackName,
  }) async {
    final direct = (uid ?? '').trim();
    if (direct.isNotEmpty) return direct;

    var handle = (username ?? '').trim().replaceFirst('@', '');
    if (handle.isEmpty) {
      final nameCandidate = (fallbackName ?? '').trim().replaceFirst('@', '');
      if (nameCandidate.isNotEmpty &&
          !nameCandidate.contains(RegExp(r'\s')) &&
          nameCandidate != 'مستخدم وازن') {
        handle = nameCandidate;
      }
    }
    if (handle.isEmpty) return null;

    // Older records sometimes saved only the username. Resolve it lazily when
    // a profile is opened instead of rewriting historical user content.
    final candidates = <String>{handle, handle.toLowerCase()};
    for (final candidate in candidates) {
      try {
        final usernameDoc = await _db.collection('usernames').doc(candidate).get();
        final data = usernameDoc.data() ?? const <String, dynamic>{};
        final resolved = _firstNotEmpty([
          data['ownerUid'],
          data['uid'],
          data['userId'],
        ]);
        if (resolved.isNotEmpty) return resolved;
      } catch (_) {
        // Continue to the users query fallback.
      }
    }

    for (final field in const ['username', 'userName']) {
      for (final candidate in candidates) {
        try {
          final snap = await _db
              .collection('users')
              .where(field, isEqualTo: candidate)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) return snap.docs.first.id;
        } catch (_) {
          // Try the next historical field name/casing.
        }
      }
    }
    return null;
  }

  Future<void> addComment({
    required CommunityPost post,
    required String text,
    CommunityComment? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.length < 2) throw ArgumentError('اكتب تعليقًا أوضح');
    if (trimmed.length > 700) throw ArgumentError('التعليق طويل جدًا');

    final profile = await loadCurrentProfile();
    await _assertAllowedToPost(profile.uid);

    final postRef = _posts.doc(post.id);
    // Keep replies beside the comment they belong to. This preserves old
    // threads saved by previous app versions under posts/{postId}/comments.
    final targetSource = replyTo?.sourceCollection == 'posts'
        ? 'posts'
        : 'communityPosts';
    final commentRef = _commentsCollection(post.id, targetSource).doc();
    final rootCommentId = replyTo == null
        ? commentRef.id
        : ((replyTo.rootCommentId ?? '').trim().isNotEmpty
            ? replyTo.rootCommentId!.trim()
            : replyTo.id);

    final batch = _db.batch();
    batch.set(commentRef, {
      'authorUid': profile.uid,
      'authorName': profile.displayName,
      'authorUsername': profile.username,
      'authorPhotoUrl': profile.photoUrl,
      'authorRole': profile.role,
      'supportDisplay': profile.showAsSupport,
      'text': trimmed,
      'isDeleted': false,
      'isPinned': false,
      'rootCommentId': rootCommentId,
      'parentCommentId': replyTo?.id,
      if (replyTo != null) 'replyToUid': replyTo.authorUid,
      if (replyTo != null) 'replyToName': replyTo.authorName,
      if (replyTo != null) 'replyToUsername': replyTo.authorUsername,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {
      'commentsCount': FieldValue.increment(1),
      'trendScore': FieldValue.increment(3),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    unawaited(_notifyAfterNewComment(
      post: post,
      commentId: commentRef.id,
      sender: profile,
      commentText: trimmed,
      replyTo: replyTo,
    ));
  }

  Stream<List<CommunityComment>> streamComments(String postId, {int limit = 3}) {
    // Do not order or filter in Firestore here. Old app releases used fields
    // such as timestamp/content and some documents have no createdAt field.
    // Firestore orderBy(createdAt) silently excludes those documents.
    late final StreamController<List<CommunityComment>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? currentSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? legacySub;

    QuerySnapshot<Map<String, dynamic>>? currentSnapshot;
    QuerySnapshot<Map<String, dynamic>>? legacySnapshot;
    Object? currentError;
    Object? legacyError;
    var currentReady = false;
    var legacyReady = false;

    void emit() {
      if (controller.isClosed || (!currentReady && !legacyReady)) return;

      final byId = <String, CommunityComment>{};

      // Load legacy first. If a migrated copy with the same id exists in the
      // new collection, the current copy replaces it and no duplicate appears.
      void addUsable(CommunityComment comment, {required bool overwrite}) {
        if (comment.isDeleted || comment.text.trim().isEmpty) return;
        if (overwrite || !byId.containsKey(comment.id)) {
          byId[comment.id] = comment;
        }
      }

      for (final doc in legacySnapshot?.docs ??
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
        addUsable(
          CommunityComment.fromDoc(
            postId: postId,
            doc: doc,
            sourceCollection: 'posts',
          ),
          overwrite: false,
        );
      }
      for (final doc in currentSnapshot?.docs ??
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
        addUsable(
          CommunityComment.fromDoc(
            postId: postId,
            doc: doc,
            sourceCollection: 'communityPosts',
          ),
          overwrite: true,
        );
      }

      final arranged = _arrangeComments(
        byId.values.toList(growable: false),
        limit: limit,
      );

      if (arranged.isEmpty &&
          currentReady &&
          legacyReady &&
          currentError != null &&
          legacyError != null) {
        controller.addError(currentError!);
        return;
      }
      controller.add(arranged);
    }

    controller = StreamController<List<CommunityComment>>(
      onListen: () {
        currentSub = _commentsCollection(postId, 'communityPosts')
            .snapshots()
            .listen((snapshot) {
          currentSnapshot = snapshot;
          currentReady = true;
          currentError = null;
          emit();
        }, onError: (Object error, StackTrace stack) {
          currentReady = true;
          currentError = error;
          emit();
        });

        legacySub = _commentsCollection(postId, 'posts')
            .snapshots()
            .listen((snapshot) {
          legacySnapshot = snapshot;
          legacyReady = true;
          legacyError = null;
          emit();
        }, onError: (Object error, StackTrace stack) {
          legacyReady = true;
          legacyError = error;
          emit();
        });
      },
      onCancel: () async {
        await currentSub?.cancel();
        await legacySub?.cancel();
      },
    );

    return controller.stream;
  }

  List<CommunityComment> _arrangeComments(
    List<CommunityComment> comments, {
    required int limit,
  }) {
    int compareDate(CommunityComment a, CommunityComment b) {
      if (a.hasKnownCreatedAt != b.hasKnownCreatedAt) {
        return a.hasKnownCreatedAt ? 1 : -1;
      }
      final byDate = a.createdAt.compareTo(b.createdAt);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    }

    final roots = comments.where((c) => !c.isReply).toList(growable: true)
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return compareDate(a, b);
      });

    final rootIds = roots.map((c) => c.id).toSet();
    final allIds = comments.map((c) => c.id).toSet();
    final repliesByRoot = <String, List<CommunityComment>>{};
    final repliesByParent = <String, List<CommunityComment>>{};
    final orphanReplies = <CommunityComment>[];

    for (final comment in comments.where((c) => c.isReply)) {
      final declaredRoot = (comment.rootCommentId ?? '').trim();
      final declaredParent = (comment.parentCommentId ?? '').trim();
      final rootId = declaredRoot.isNotEmpty ? declaredRoot : declaredParent;
      if (rootId.isEmpty || !rootIds.contains(rootId)) {
        orphanReplies.add(comment);
        continue;
      }

      repliesByRoot.putIfAbsent(rootId, () => <CommunityComment>[]).add(comment);
      final safeParent = declaredParent.isNotEmpty && allIds.contains(declaredParent)
          ? declaredParent
          : rootId;
      repliesByParent
          .putIfAbsent(safeParent, () => <CommunityComment>[])
          .add(comment);
    }

    for (final replies in repliesByRoot.values) {
      replies.sort(compareDate);
    }
    for (final replies in repliesByParent.values) {
      replies.sort(compareDate);
    }

    final ordered = <CommunityComment>[];
    final visited = <String>{};

    void appendReplies(String parentId) {
      final children = repliesByParent[parentId] ?? const <CommunityComment>[];
      for (final child in children) {
        if (!visited.add(child.id)) continue;
        ordered.add(child);
        appendReplies(child.id);
      }
    }

    for (final root in roots) {
      ordered.add(root);
      visited.add(root.id);
      appendReplies(root.id);

      // A malformed historical reply may reference the correct root but an
      // unavailable parent. Keep it in this thread instead of losing it.
      for (final reply in repliesByRoot[root.id] ?? const <CommunityComment>[]) {
        if (!visited.add(reply.id)) continue;
        ordered.add(reply);
        appendReplies(reply.id);
      }
    }
    orphanReplies.sort(compareDate);
    ordered.addAll(orphanReplies.where((c) => visited.add(c.id)));

    if (limit <= 0 || ordered.length <= limit) {
      return List<CommunityComment>.unmodifiable(ordered);
    }

    // Preview the latest complete threads, never a detached reply without its
    // parent. The full comments sheet still receives every comment.
    final preview = <CommunityComment>[];
    for (final root in roots.reversed) {
      final thread = <CommunityComment>[
        root,
        ...(repliesByRoot[root.id] ?? const <CommunityComment>[]),
      ];
      if (preview.isNotEmpty && preview.length + thread.length > limit) break;
      preview.insertAll(0, thread);
      if (preview.length >= limit) break;
    }
    if (preview.isEmpty) {
      preview.addAll(ordered.take(limit));
    }
    return List<CommunityComment>.unmodifiable(preview);
  }

  Stream<List<String>> streamMyLikedPostIds(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('communityLikes')
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList(growable: false));
  }

  Future<List<CommunityPost>> getPostsByIds(List<String> ids) async {
    if (ids.isEmpty) return const <CommunityPost>[];
    final futures = ids.take(80).map((id) => _posts.doc(id).get());
    final snaps = await Future.wait(futures);
    return snaps
        .where((s) => s.exists)
        .map(CommunityPost.fromDoc)
        .where((p) => !p.isDeleted && p.content.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> reportPost({
    required CommunityPost post,
    required String reason,
    String? details,
  }) async {
    final profile = await loadCurrentProfile();
    if (profile.uid == post.authorUid) {
      throw StateError('لا يمكنك الإبلاغ عن منشورك');
    }

    final cleanReason = reason.trim().isEmpty ? 'other' : reason.trim();
    final cleanDetails = (details ?? '').trim();
    if (cleanDetails.length > 700) {
      throw ArgumentError('تفاصيل البلاغ طويلة جدًا');
    }

    final reportRef = _reports.doc('${post.id}_${profile.uid}');
    var createdNewReport = false;
    await _db.runTransaction((tx) async {
      final reportSnap = await tx.get(reportRef);
      createdNewReport = !reportSnap.exists;
      tx.set(reportRef, {
        'type': 'community_post',
        'status': 'open',
        'reason': cleanReason,
        'details': cleanDetails,
        'postId': post.id,
        'postAuthorUid': post.authorUid,
        'postAuthorName': post.authorName,
        'postAuthorPhotoUrl': post.authorPhotoUrl,
        'postCategory': post.category.firestoreValue,
        'postContent': post.content,
        'postCreatedAt': Timestamp.fromDate(post.createdAt),
        'reporterUid': profile.uid,
        'reporterName': profile.displayName,
        'reporterPhotoUrl': profile.photoUrl,
        'reporterRole': profile.role,
        'source': 'community_page',
        if (!reportSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!reportSnap.exists) {
        tx.set(_posts.doc(post.id), {
          'reportsCount': FieldValue.increment(1),
          'lastReportedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    if (createdNewReport) {
      unawaited(_notifyStaffAboutReport(
        reportId: reportRef.id,
        post: post,
        reporter: profile,
        reason: cleanReason,
      ));
    }
  }

  Future<void> deletePost(CommunityPost post) async {
    final profile = await loadCurrentProfile();
    final canDelete = profile.uid == post.authorUid || profile.showAsSupport;
    if (!canDelete) throw StateError('لا تملك صلاحية حذف هذا المنشور');
    await _posts.doc(post.id).set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': profile.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (profile.uid != post.authorUid) {
      unawaited(_safeSendCommunityNotification(
        toUid: post.authorUid,
        senderUid: profile.uid,
        senderName: profile.displayName,
        type: 'community_post_deleted',
        title: 'تم إخفاء منشورك في مجتمع وازن',
        body: 'تمت مراجعة منشورك وإخفاؤه من مجتمع وازن.',
        postId: post.id,
      ));
    }
  }

  Future<void> deleteComment({
    required CommunityPost post,
    required CommunityComment comment,
  }) async {
    final profile = await loadCurrentProfile();
    final canDelete = profile.uid == comment.authorUid || profile.showAsSupport;
    if (!canDelete) throw StateError('لا تملك صلاحية حذف هذا التعليق');
    if (comment.isDeleted) return;

    final commentRef =
        _commentsCollection(post.id, comment.sourceCollection).doc(comment.id);
    final canTouchPostCounter = profile.uid == post.authorUid || profile.showAsSupport;

    if (canTouchPostCounter) {
      final batch = _db.batch();
      batch.set(commentRef, {
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': profile.uid,
        'isPinned': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_posts.doc(post.id), {
        'commentsCount': FieldValue.increment(-1),
        'trendScore': FieldValue.increment(-3),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } else {
      await commentRef.set({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': profile.uid,
        'isPinned': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (profile.uid != comment.authorUid) {
      unawaited(_safeSendCommunityNotification(
        toUid: comment.authorUid,
        senderUid: profile.uid,
        senderName: profile.displayName,
        type: 'community_comment_deleted',
        title: 'تم حذف تعليقك في مجتمع وازن',
        body: 'تمت مراجعة تعليقك وحذفه من أحد منشورات المجتمع.',
        postId: post.id,
        commentId: comment.id,
      ));
    }
  }

  Future<void> setCommentPinned({
    required CommunityPost post,
    required CommunityComment comment,
    required bool pinned,
  }) async {
    final profile = await loadCurrentProfile();
    final canPin = profile.uid == post.authorUid || profile.showAsSupport;
    if (!canPin) throw StateError('تثبيت التعليقات متاح لصاحب المنشور فقط');

    final commentsRef =
        _commentsCollection(post.id, comment.sourceCollection);
    final batch = _db.batch();

    if (pinned) {
      final existing = await commentsRef
          .where('isPinned', isEqualTo: true)
          .limit(20)
          .get();
      for (final doc in existing.docs) {
        if (doc.id == comment.id) continue;
        batch.set(doc.reference, {
          'isPinned': false,
          'pinnedAt': null,
          'pinnedBy': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    batch.set(commentsRef.doc(comment.id), {
      'isPinned': pinned,
      'pinnedAt': pinned ? FieldValue.serverTimestamp() : null,
      'pinnedBy': pinned ? profile.uid : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    if (pinned && profile.uid != comment.authorUid) {
      unawaited(_safeSendCommunityNotification(
        toUid: comment.authorUid,
        senderUid: profile.uid,
        senderName: profile.displayName,
        type: 'community_comment_pinned',
        title: 'تم تثبيت تعليقك',
        body: 'صاحب المنشور ثبّت تعليقك في مجتمع وازن.',
        postId: post.id,
        commentId: comment.id,
      ));
    }
  }

  Future<void> _notifyAfterNewComment({
    required CommunityPost post,
    required String commentId,
    required CommunityAuthorProfile sender,
    required String commentText,
    CommunityComment? replyTo,
  }) async {
    try {
      final body = _snippet(commentText, fallback: 'كتب تعليقًا في مجتمع وازن.');
      final notified = <String>{sender.uid};

      if (replyTo != null &&
          replyTo.authorUid.trim().isNotEmpty &&
          replyTo.authorUid != sender.uid) {
        notified.add(replyTo.authorUid);
        await _safeSendCommunityNotification(
          toUid: replyTo.authorUid,
          senderUid: sender.uid,
          senderName: sender.displayName,
          type: 'community_comment_reply',
          title: '${sender.displayName} رد على تعليقك',
          body: body,
          postId: post.id,
          commentId: commentId,
        );
      }

      if (post.authorUid.trim().isNotEmpty && !notified.contains(post.authorUid)) {
        await _safeSendCommunityNotification(
          toUid: post.authorUid,
          senderUid: sender.uid,
          senderName: sender.displayName,
          type: 'community_post_comment',
          title: '${sender.displayName} علّق على منشورك',
          body: body,
          postId: post.id,
          commentId: commentId,
        );
      }
    } catch (_) {
      // الإشعارات لا تمنع التعليق أو الرد من النجاح.
    }
  }

  Future<void> _notifyStaffAboutReport({
    required String reportId,
    required CommunityPost post,
    required CommunityAuthorProfile reporter,
    required String reason,
  }) async {
    try {
      final targets = await _staffTargetUids(excludeUid: reporter.uid);
      final reasonLabel = _communityReasonLabel(reason);
      for (final uid in targets.take(40)) {
        await _safeSendCommunityNotification(
          toUid: uid,
          senderUid: reporter.uid,
          senderName: reporter.displayName,
          type: 'community_report_created',
          title: 'بلاغ جديد في مجتمع وازن',
          body: '$reasonLabel على منشور: ${_snippet(post.content, fallback: 'منشور في المجتمع')}',
          postId: post.id,
          reportId: reportId,
          priority: 'high',
        );
      }
    } catch (_) {
      // ignore
    }
  }

  Future<Set<String>> _staffTargetUids({String? excludeUid}) async {
    final out = <String>{..._hardOwnerUids};
    try {
      final snap = await _db
          .collection('users')
          .where('role', whereIn: const [
            'owner',
            'Owner',
            'OWNER',
            'admin',
            'Admin',
            'ADMIN',
            'support',
            'Support',
            'SUPPORT',
          ])
          .limit(80)
          .get();
      for (final doc in snap.docs) {
        out.add(doc.id);
      }
    } catch (_) {
      // hard owners يكفون كـ fallback إذا فشل الاستعلام.
    }
    if (excludeUid != null) out.remove(excludeUid);
    out.removeWhere((uid) => uid.trim().isEmpty);
    return out;
  }

  Future<void> _safeSendCommunityNotification({
    required String toUid,
    required String senderUid,
    required String senderName,
    required String type,
    required String title,
    required String body,
    String? postId,
    String? commentId,
    String? reportId,
    String priority = 'normal',
  }) async {
    try {
      final target = toUid.trim();
      if (target.isEmpty || target == senderUid) return;
      await _db
          .collection('notifications')
          .doc(target)
          .collection('inbox')
          .add({
        'title': title.trim().isEmpty ? 'مجتمع وازن' : title.trim(),
        'body': body.trim().isEmpty ? 'لديك تحديث جديد في مجتمع وازن.' : body.trim(),
        'notificationType': type,
        'type': type,
        'source': 'community',
        'active': true,
        'read': false,
        'priority': priority,
        'senderUid': senderUid,
        'senderName': senderName,
        'targetUid': target,
        if ((postId ?? '').trim().isNotEmpty) 'postId': postId!.trim(),
        if ((commentId ?? '').trim().isNotEmpty)
          'commentId': commentId!.trim(),
        if ((reportId ?? '').trim().isNotEmpty) 'reportId': reportId!.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'scheduledAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // تجاهل فشل الإشعار حتى لا تتعطل تجربة المجتمع.
    }
  }

  Future<void> _assertAllowedToPost(String uid) async {
    final snap = await _db.doc('users/$uid').get();
    final data = snap.data() ?? const <String, dynamic>{};
    if (data['isBanned'] == true) {
      throw StateError('حسابك محظور من النشر في وازن');
    }

    final communityTs = data['communitySuspendedUntil'];
    if (communityTs is Timestamp &&
        DateTime.now().isBefore(communityTs.toDate())) {
      throw StateError('النشر في مجتمع وازن معلّق مؤقتًا لحسابك');
    }

    final recipesTs = data['recipesSuspendedUntil'];
    if (recipesTs is Timestamp && DateTime.now().isBefore(recipesTs.toDate())) {
      throw StateError('النشر معلّق مؤقتًا لحسابك');
    }
  }

  String _firstNotEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _snippet(String text, {required String fallback}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return fallback;
    if (clean.length <= 95) return clean;
    return '${clean.substring(0, 92)}...';
  }

  String _communityReasonLabel(String reason) {
    switch (reason) {
      case 'abuse':
        return 'إساءة أو تنمّر';
      case 'spam':
        return 'سبام أو إعلان مزعج';
      case 'misleading':
        return 'معلومة مضللة';
      case 'unsafe':
        return 'محتوى غير آمن';
      case 'other':
      default:
        return 'بلاغ مجتمع';
    }
  }
}

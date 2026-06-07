import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_models.dart';
import '../core/data/wazen_user_store.dart';

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

  String? get currentUid => _auth.currentUser?.uid;

  Future<CommunityAuthorProfile> loadCurrentProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
          code: 'not-signed-in', message: 'يجب تسجيل الدخول');
    }

    // كاش أولًا: فتح الكومبوزر/المجتمع ما يتوقف على Firestore.
    var data = await WazenUserStore.readCachedUser(user.uid, authUser: user);
    if (data.isEmpty) {
      data = WazenUserStore.normalize(const <String, dynamic>{}, authUser: user, uid: user.uid);
    }
    unawaited(WazenUserStore.readUserDocFast(user.uid));

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

  Stream<List<CommunityPost>> streamPosts({required CommunitySort sort}) async* {
    final cacheKey = 'community_posts_cache_${sort.firestoreCacheKey}';
    final cached = await _readCachedPosts(cacheKey);
    if (cached.isNotEmpty) yield cached;

    yield* _posts
        .orderBy(sort.orderField, descending: true)
        .limit(160)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          final list = snap.docs
              .map(CommunityPost.fromDoc)
              .where((p) => !p.isDeleted && p.content.trim().isNotEmpty)
              .toList(growable: false);
          unawaited(_saveCachedPosts(cacheKey, list));
          return list;
        });
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

  Future<void> addComment({required CommunityPost post, required String text}) async {
    final trimmed = text.trim();
    if (trimmed.length < 2) throw ArgumentError('اكتب تعليقًا أوضح');
    if (trimmed.length > 700) throw ArgumentError('التعليق طويل جدًا');

    final profile = await loadCurrentProfile();
    await _assertAllowedToPost(profile.uid);

    final postRef = _posts.doc(post.id);
    final commentRef = postRef.collection('comments').doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'authorUid': profile.uid,
      'authorName': profile.displayName,
      'authorPhotoUrl': profile.photoUrl,
      'authorRole': profile.role,
      'supportDisplay': profile.showAsSupport,
      'text': trimmed,
      'isDeleted': false,
      'isPinned': false,
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
    ));
  }

  Stream<List<CommunityComment>> streamComments(String postId, {int limit = 3}) async* {
    final cacheKey = 'community_comments_cache_${postId}_$limit';
    final cached = await _readCachedComments(cacheKey, postId);
    if (cached.isNotEmpty) yield cached;

    Query<Map<String, dynamic>> q = _posts
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false);
    if (limit > 0) q = q.limit(limit);
    yield* q.snapshots(includeMetadataChanges: true).map((snap) {
      final list = snap.docs
          .map((d) => CommunityComment.fromDoc(postId: postId, doc: d))
          .where((c) => !c.isDeleted && c.text.trim().isNotEmpty)
          .toList(growable: true);
      list.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      final out = List<CommunityComment>.unmodifiable(list);
      unawaited(_saveCachedComments(cacheKey, out));
      return out;
    });
  }

  Stream<List<String>> streamMyLikedPostIds(String uid) async* {
    final prefs = await SharedPreferences.getInstance();
    final key = 'community_liked_ids_$uid';
    final cached = prefs.getStringList(key) ?? const <String>[];
    if (cached.isNotEmpty) yield cached;

    yield* _db
        .collection('users')
        .doc(uid)
        .collection('communityLikes')
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          final ids = snap.docs.map((d) => d.id).toList(growable: false);
          unawaited(prefs.setStringList(key, ids));
          return ids;
        });
  }

  Future<List<CommunityPost>> getPostsByIds(List<String> ids) async {
    if (ids.isEmpty) return const <CommunityPost>[];
    final wanted = ids.take(80).toList(growable: false);
    final wantedSet = wanted.toSet();

    // كاش سريع للمفضلات حتى لا تبقى صفحة الإعجابات معلقة على طلبات كثيرة.
    final cachedBuckets = await Future.wait([
      _readCachedPosts('community_posts_cache_latest'),
      _readCachedPosts('community_posts_cache_likes'),
      _readCachedPosts('community_posts_cache_comments'),
      _readCachedPosts('community_posts_cache_trending'),
    ]);
    final cachedMap = <String, CommunityPost>{};
    for (final bucket in cachedBuckets) {
      for (final p in bucket) {
        if (wantedSet.contains(p.id)) cachedMap[p.id] = p;
      }
    }
    if (cachedMap.length == wantedSet.length) {
      return wanted.map((id) => cachedMap[id]).whereType<CommunityPost>().toList(growable: false);
    }

    final futures = wanted.map((id) => _posts.doc(id).get());
    final snaps = await Future.wait(futures);
    final fresh = snaps
        .where((s) => s.exists)
        .map(CommunityPost.fromDoc)
        .where((p) => !p.isDeleted && p.content.trim().isNotEmpty)
        .toList(growable: false);
    if (fresh.isNotEmpty) {
      for (final p in fresh) {
        cachedMap[p.id] = p;
      }
      return wanted.map((id) => cachedMap[id]).whereType<CommunityPost>().toList(growable: false);
    }
    return wanted.map((id) => cachedMap[id]).whereType<CommunityPost>().toList(growable: false);
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

    final commentRef = _posts.doc(post.id).collection('comments').doc(comment.id);
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

    final commentsRef = _posts.doc(post.id).collection('comments');
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
  }) async {
    try {
      final body = _snippet(commentText, fallback: 'علق على منشورك في مجتمع وازن.');

      await _safeSendCommunityNotification(
        toUid: post.authorUid,
        senderUid: sender.uid,
        senderName: sender.displayName,
        type: 'community_post_comment',
        title: '${sender.displayName} رد على منشورك',
        body: body,
        postId: post.id,
        commentId: commentId,
      );

      final latest = await _posts
          .doc(post.id)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .limit(40)
          .get();
      final participantUids = <String>{};
      for (final doc in latest.docs) {
        final data = doc.data();
        final uid = (data['authorUid'] ?? '').toString().trim();
        if (uid.isEmpty) continue;
        if (uid == sender.uid || uid == post.authorUid) continue;
        participantUids.add(uid);
        if (participantUids.length >= 8) break;
      }

      for (final uid in participantUids) {
        await _safeSendCommunityNotification(
          toUid: uid,
          senderUid: sender.uid,
          senderName: sender.displayName,
          type: 'community_thread_comment',
          title: 'تعليق جديد في منشور شاركت فيه',
          body: '${sender.displayName}: $body',
          postId: post.id,
          commentId: commentId,
        );
      }
    } catch (_) {
      // الإشعارات لا تمنع التعليق من النجاح.
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


  Future<List<CommunityPost>> _readCachedPosts(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return const <CommunityPost>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CommunityPost>[];
      return decoded
          .whereType<Map>()
          .map((m) => _postFromCache(Map<String, dynamic>.from(m)))
          .where((p) => !p.isDeleted && p.content.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <CommunityPost>[];
    }
  }

  Future<void> _saveCachedPosts(String key, List<CommunityPost> posts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final safe = posts.take(80).map(_postToCache).toList(growable: false);
      await prefs.setString(key, jsonEncode(safe));
    } catch (_) {}
  }

  Future<List<CommunityComment>> _readCachedComments(String key, String postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return const <CommunityComment>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CommunityComment>[];
      return decoded
          .whereType<Map>()
          .map((m) => _commentFromCache(postId, Map<String, dynamic>.from(m)))
          .where((c) => !c.isDeleted && c.text.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <CommunityComment>[];
    }
  }

  Future<void> _saveCachedComments(String key, List<CommunityComment> comments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(comments.take(30).map(_commentToCache).toList(growable: false)),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _postToCache(CommunityPost p) => {
        'id': p.id,
        'authorUid': p.authorUid,
        'authorName': p.authorName,
        'authorPhotoUrl': p.authorPhotoUrl,
        'authorRole': p.authorRole,
        'supportDisplay': p.supportDisplay,
        'category': p.category.firestoreValue,
        'content': p.content,
        'likesCount': p.likesCount,
        'commentsCount': p.commentsCount,
        'trendScore': p.trendScore,
        'createdAt': p.createdAt.toIso8601String(),
        'updatedAt': p.updatedAt?.toIso8601String(),
        'isDeleted': p.isDeleted,
        'recipeId': p.recipeId,
        'recipeTitle': p.recipeTitle,
      };

  CommunityPost _postFromCache(Map<String, dynamic> m) => CommunityPost(
        id: (m['id'] ?? '').toString(),
        authorUid: (m['authorUid'] ?? '').toString(),
        authorName: (m['authorName'] ?? 'مستخدم وازن').toString(),
        authorPhotoUrl: (m['authorPhotoUrl'] ?? '').toString(),
        authorRole: (m['authorRole'] ?? 'user').toString(),
        supportDisplay: m['supportDisplay'] == true,
        category: CommunityCategoryX.fromFirestore(m['category']),
        content: (m['content'] ?? '').toString(),
        likesCount: _asInt(m['likesCount']),
        commentsCount: _asInt(m['commentsCount']),
        trendScore: _asInt(m['trendScore']),
        createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
        updatedAt: DateTime.tryParse((m['updatedAt'] ?? '').toString()),
        isDeleted: m['isDeleted'] == true,
        recipeId: _nullableString(m['recipeId']),
        recipeTitle: _nullableString(m['recipeTitle']),
      );

  Map<String, dynamic> _commentToCache(CommunityComment c) => {
        'id': c.id,
        'authorUid': c.authorUid,
        'authorName': c.authorName,
        'authorPhotoUrl': c.authorPhotoUrl,
        'authorRole': c.authorRole,
        'supportDisplay': c.supportDisplay,
        'text': c.text,
        'createdAt': c.createdAt.toIso8601String(),
        'isDeleted': c.isDeleted,
        'isPinned': c.isPinned,
        'pinnedAt': c.pinnedAt?.toIso8601String(),
        'pinnedBy': c.pinnedBy,
      };

  CommunityComment _commentFromCache(String postId, Map<String, dynamic> m) => CommunityComment(
        id: (m['id'] ?? '').toString(),
        postId: postId,
        authorUid: (m['authorUid'] ?? '').toString(),
        authorName: (m['authorName'] ?? 'مستخدم وازن').toString(),
        authorPhotoUrl: (m['authorPhotoUrl'] ?? '').toString(),
        authorRole: (m['authorRole'] ?? 'user').toString(),
        supportDisplay: m['supportDisplay'] == true,
        text: (m['text'] ?? '').toString(),
        createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
        isDeleted: m['isDeleted'] == true,
        isPinned: m['isPinned'] == true,
        pinnedAt: DateTime.tryParse((m['pinnedAt'] ?? '').toString()),
        pinnedBy: _nullableString(m['pinnedBy']),
      );


  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String? _nullableString(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
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


extension _CommunitySortCacheKey on CommunitySort {
  String get firestoreCacheKey {
    switch (this) {
      case CommunitySort.latest:
        return 'latest';
      case CommunitySort.mostLiked:
        return 'likes';
      case CommunitySort.mostCommented:
        return 'comments';
      case CommunitySort.trending:
        return 'trending';
    }
  }
}

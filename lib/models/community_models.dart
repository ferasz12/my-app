import 'package:cloud_firestore/cloud_firestore.dart';

enum CommunityCategory { question, info, recipe, progress, experience }

extension CommunityCategoryX on CommunityCategory {
  String get firestoreValue {
    switch (this) {
      case CommunityCategory.question:
        return 'question';
      case CommunityCategory.info:
        return 'info';
      case CommunityCategory.recipe:
        return 'recipe';
      case CommunityCategory.progress:
        return 'progress';
      case CommunityCategory.experience:
        return 'experience';
    }
  }

  String get labelAr {
    switch (this) {
      case CommunityCategory.question:
        return 'سؤال';
      case CommunityCategory.info:
        return 'معلومة';
      case CommunityCategory.recipe:
        return 'وصفة';
      case CommunityCategory.progress:
        return 'تقدّم';
      case CommunityCategory.experience:
        return 'تجربة';
    }
  }

  static CommunityCategory fromFirestore(dynamic value) {
    final v = (value ?? '').toString().toLowerCase().trim();
    for (final c in CommunityCategory.values) {
      if (c.firestoreValue == v) return c;
    }
    return CommunityCategory.question;
  }
}

enum CommunitySort { latest, mostLiked, mostCommented, trending }

extension CommunitySortX on CommunitySort {
  String get labelAr {
    switch (this) {
      case CommunitySort.latest:
        return 'الأحدث';
      case CommunitySort.mostLiked:
        return 'الأكثر إعجابًا';
      case CommunitySort.mostCommented:
        return 'الأكثر تعليقًا';
      case CommunitySort.trending:
        return 'الأكثر انتشارًا';
    }
  }

  String get orderField {
    switch (this) {
      case CommunitySort.latest:
        return 'createdAt';
      case CommunitySort.mostLiked:
        return 'likesCount';
      case CommunitySort.mostCommented:
        return 'commentsCount';
      case CommunitySort.trending:
        return 'trendScore';
    }
  }
}

enum CommunityFeedView { all, mine, liked }

extension CommunityFeedViewX on CommunityFeedView {
  String get labelAr {
    switch (this) {
      case CommunityFeedView.all:
        return 'المجتمع';
      case CommunityFeedView.mine:
        return 'بوستاتي';
      case CommunityFeedView.liked:
        return 'إعجابي';
    }
  }
}

class CommunityAuthorProfile {
  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
  final String role;
  final bool showAsSupport;

  const CommunityAuthorProfile({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.role,
    required this.showAsSupport,
  });
}

class CommunityPost {
  final String id;
  final String authorUid;
  final String authorName;
  final String authorPhotoUrl;
  final String authorRole;
  final bool supportDisplay;
  final CommunityCategory category;
  final String content;
  final int likesCount;
  final int commentsCount;
  final int trendScore;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final String? recipeId;
  final String? recipeTitle;

  const CommunityPost({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.authorRole,
    required this.supportDisplay,
    required this.category,
    required this.content,
    required this.likesCount,
    required this.commentsCount,
    required this.trendScore,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    this.recipeId,
    this.recipeTitle,
  });

  factory CommunityPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final created = _firstDate([
      data['createdAt'],
      data['timestamp'],
      data['created_at'],
      data['postedAt'],
      data['date'],
      data['updatedAt'],
    ]);
    return CommunityPost(
      id: doc.id,
      authorUid: _firstString([
        data['authorUid'],
        data['userId'],
        data['uid'],
        data['authorId'],
      ]),
      authorName: _firstString([
        data['authorName'],
        data['displayName'],
        data['name'],
        data['username'],
      ], fallback: 'مستخدم وازن'),
      authorPhotoUrl: _firstString([
        data['authorPhotoUrl'],
        data['photoUrl'],
        data['photoURL'],
        data['profileImageUrl'],
      ]),
      authorRole: _firstString([
        data['authorRole'],
        data['role'],
      ], fallback: 'user').toLowerCase(),
      supportDisplay: data['supportDisplay'] == true ||
          data['showAsSupport'] == true ||
          data['isSupport'] == true,
      category: CommunityCategoryX.fromFirestore(
        data['category'] ?? data['type'] ?? data['postType'],
      ),
      content: _firstString([
        data['content'],
        data['text'],
        data['body'],
        data['message'],
      ]),
      likesCount: _firstInt([
        data['likesCount'],
        data['likeCount'],
        data['likes'],
      ]),
      commentsCount: _firstInt([
        data['commentsCount'],
        data['commentCount'],
        data['comments'],
        data['repliesCount'],
      ]),
      trendScore: _firstInt([
        data['trendScore'],
        data['score'],
      ]),
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _firstDate([data['updatedAt'], data['updated_at']]),
      isDeleted: data['isDeleted'] == true ||
          data['deleted'] == true ||
          data['deletedAt'] != null,
      recipeId: _nullableString(data['recipeId']),
      recipeTitle: _nullableString(data['recipeTitle']),
    );
  }
}

class CommunityComment {
  final String id;
  final String postId;

  /// The Firestore parent collection that actually owns this comment.
  /// New comments use communityPosts, while older app versions may have
  /// stored comments under posts. Keeping the source lets old comments stay
  /// fully interactive without moving or rewriting user data.
  final String sourceCollection;

  final String authorUid;
  final String authorName;
  final String authorUsername;
  final String authorPhotoUrl;
  final String authorRole;
  final bool supportDisplay;
  final String text;
  final DateTime createdAt;
  final bool hasKnownCreatedAt;
  final bool isDeleted;
  final bool isPinned;
  final DateTime? pinnedAt;
  final String? pinnedBy;

  /// Null means this is a top-level comment.
  final String? parentCommentId;

  /// All replies in the same thread share the root comment id.
  final String? rootCommentId;

  final String? replyToUid;
  final String? replyToName;
  final String? replyToUsername;

  const CommunityComment({
    required this.id,
    required this.postId,
    required this.sourceCollection,
    required this.authorUid,
    required this.authorName,
    required this.authorUsername,
    required this.authorPhotoUrl,
    required this.authorRole,
    required this.supportDisplay,
    required this.text,
    required this.createdAt,
    required this.hasKnownCreatedAt,
    required this.isDeleted,
    required this.isPinned,
    required this.pinnedAt,
    required this.pinnedBy,
    required this.parentCommentId,
    required this.rootCommentId,
    required this.replyToUid,
    required this.replyToName,
    required this.replyToUsername,
  });

  bool get isReply => (parentCommentId ?? '').trim().isNotEmpty;
  bool get isLegacySource => sourceCollection == 'posts';

  String get mentionLabel {
    final username = (replyToUsername ?? '').trim().replaceFirst('@', '');
    if (username.isNotEmpty) return '@$username';
    final name = (replyToName ?? '').trim();
    return name.isEmpty ? '' : '@$name';
  }

  factory CommunityComment.fromDoc({
    required String postId,
    required DocumentSnapshot<Map<String, dynamic>> doc,
    String sourceCollection = 'communityPosts',
  }) {
    final data = doc.data() ?? const <String, dynamic>{};

    // Older releases used more than one key for the same value. Read all
    // known aliases so existing users never lose comments after an update.
    final created = _firstDate([
      data['createdAt'],
      data['timestamp'],
      data['created_at'],
      data['postedAt'],
      data['date'],
      data['time'],
      data['updatedAt'],
    ]);

    final deletedAt = _firstDate([
      data['deletedAt'],
      data['deleted_at'],
    ]);

    return CommunityComment(
      id: doc.id,
      postId: postId,
      sourceCollection: sourceCollection,
      authorUid: _firstString([
        data['authorUid'],
        data['userId'],
        data['uid'],
        data['authorId'],
      ]),
      authorName: _firstString([
        data['authorName'],
        data['displayName'],
        data['name'],
        data['userName'],
        data['username'],
      ], fallback: 'مستخدم وازن'),
      authorUsername: _firstString([
        data['authorUsername'],
        data['username'],
        data['userName'],
        data['handle'],
      ]).replaceFirst('@', ''),
      authorPhotoUrl: _firstString([
        data['authorPhotoUrl'],
        data['photoUrl'],
        data['photoURL'],
        data['profileImageUrl'],
        data['avatarUrl'],
      ]),
      authorRole: _firstString([
        data['authorRole'],
        data['role'],
      ], fallback: 'user').toLowerCase(),
      supportDisplay: data['supportDisplay'] == true ||
          data['showAsSupport'] == true ||
          data['isSupport'] == true,
      text: _firstString([
        data['text'],
        data['content'],
        data['comment'],
        data['message'],
        data['body'],
      ]),
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0),
      hasKnownCreatedAt: created != null,
      isDeleted: data['isDeleted'] == true ||
          data['deleted'] == true ||
          deletedAt != null,
      isPinned: data['isPinned'] == true || data['pinned'] == true,
      pinnedAt: _firstDate([data['pinnedAt'], data['pinned_at']]),
      pinnedBy: _firstNullableString([
        data['pinnedBy'],
        data['pinned_by'],
      ]),
      parentCommentId: _firstNullableString([
        data['parentCommentId'],
        data['parentId'],
        data['replyToCommentId'],
        data['reply_to_comment_id'],
      ]),
      rootCommentId: _firstNullableString([
        data['rootCommentId'],
        data['threadRootId'],
        data['rootId'],
        data['root_comment_id'],
      ]),
      replyToUid: _firstNullableString([
        data['replyToUid'],
        data['replyToUserId'],
        data['reply_to_uid'],
      ]),
      replyToName: _firstNullableString([
        data['replyToName'],
        data['replyToDisplayName'],
        data['reply_to_name'],
      ]),
      replyToUsername: _firstNullableString([
        data['replyToUsername'],
        data['replyToUserName'],
        data['reply_to_username'],
      ]),
    );
  }
}


class CommunityReport {
  final String id;
  final String postId;
  final String postAuthorUid;
  final String postAuthorName;
  final String postAuthorPhotoUrl;
  final CommunityCategory postCategory;
  final String postContent;
  final String reporterUid;
  final String reporterName;
  final String reporterPhotoUrl;
  final String reason;
  final String details;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  const CommunityReport({
    required this.id,
    required this.postId,
    required this.postAuthorUid,
    required this.postAuthorName,
    required this.postAuthorPhotoUrl,
    required this.postCategory,
    required this.postContent,
    required this.reporterUid,
    required this.reporterName,
    required this.reporterPhotoUrl,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedBy,
    required this.reviewedAt,
  });

  bool get isOpen => status == 'open';

  String get statusLabelAr {
    switch (status) {
      case 'post_hidden':
        return 'تم إخفاء المنشور';
      case 'author_banned':
        return 'تم حظر المستخدم';
      case 'author_suspended':
        return 'تم تعليق المجتمع';
      case 'resolved':
        return 'تمت المعالجة';
      case 'rejected':
        return 'مرفوض';
      case 'open':
      default:
        return 'جديد';
    }
  }

  String get reasonLabelAr {
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
        return 'سبب آخر';
    }
  }

  factory CommunityReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CommunityReport(
      id: doc.id,
      postId: (data['postId'] ?? '').toString(),
      postAuthorUid: (data['postAuthorUid'] ?? '').toString(),
      postAuthorName: (data['postAuthorName'] ?? 'مستخدم وازن').toString(),
      postAuthorPhotoUrl: (data['postAuthorPhotoUrl'] ?? '').toString(),
      postCategory: CommunityCategoryX.fromFirestore(data['postCategory']),
      postContent: (data['postContent'] ?? '').toString(),
      reporterUid: (data['reporterUid'] ?? '').toString(),
      reporterName: (data['reporterName'] ?? 'مستخدم وازن').toString(),
      reporterPhotoUrl: (data['reporterPhotoUrl'] ?? '').toString(),
      reason: (data['reason'] ?? 'other').toString(),
      details: (data['details'] ?? '').toString(),
      status: (data['status'] ?? 'open').toString(),
      createdAt: _asDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _asDate(data['updatedAt']),
      reviewedBy: _nullableString(data['reviewedBy']),
      reviewedAt: _asDate(data['reviewedAt']),
    );
  }
}


String _firstString(List<dynamic> values, {String fallback = ''}) {
  for (final value in values) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

String? _firstNullableString(List<dynamic> values) {
  final value = _firstString(values);
  return value.isEmpty ? null : value;
}

DateTime? _firstDate(List<dynamic> values) {
  for (final value in values) {
    final parsed = _asDate(value);
    if (parsed != null) return parsed;
  }
  return null;
}

int _firstInt(List<dynamic> values) {
  for (final value in values) {
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is num) {
    final raw = v.toInt();
    // 10-digit values are normally Unix seconds; 13-digit values millis.
    final millis = raw.abs() < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
    final number = int.tryParse(v);
    if (number != null) {
      final millis = number.abs() < 100000000000 ? number * 1000 : number;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
  }
  return null;
}

String? _nullableString(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

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
  final String photoUrl;
  final String role;
  final bool showAsSupport;

  const CommunityAuthorProfile({
    required this.uid,
    required this.displayName,
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
    return CommunityPost(
      id: doc.id,
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'مستخدم وازن').toString(),
      authorPhotoUrl: (data['authorPhotoUrl'] ?? '').toString(),
      authorRole: (data['authorRole'] ?? 'user').toString().toLowerCase(),
      supportDisplay: data['supportDisplay'] == true,
      category: CommunityCategoryX.fromFirestore(data['category']),
      content: (data['content'] ?? '').toString(),
      likesCount: _asInt(data['likesCount']),
      commentsCount: _asInt(data['commentsCount']),
      trendScore: _asInt(data['trendScore']),
      createdAt: _asDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _asDate(data['updatedAt']),
      isDeleted: data['isDeleted'] == true,
      recipeId: _nullableString(data['recipeId']),
      recipeTitle: _nullableString(data['recipeTitle']),
    );
  }
}

class CommunityComment {
  final String id;
  final String postId;
  final String authorUid;
  final String authorName;
  final String authorPhotoUrl;
  final String authorRole;
  final bool supportDisplay;
  final String text;
  final DateTime createdAt;
  final bool isDeleted;
  final bool isPinned;
  final DateTime? pinnedAt;
  final String? pinnedBy;

  const CommunityComment({
    required this.id,
    required this.postId,
    required this.authorUid,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.authorRole,
    required this.supportDisplay,
    required this.text,
    required this.createdAt,
    required this.isDeleted,
    required this.isPinned,
    required this.pinnedAt,
    required this.pinnedBy,
  });

  factory CommunityComment.fromDoc({
    required String postId,
    required DocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CommunityComment(
      id: doc.id,
      postId: postId,
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'مستخدم وازن').toString(),
      authorPhotoUrl: (data['authorPhotoUrl'] ?? '').toString(),
      authorRole: (data['authorRole'] ?? 'user').toString().toLowerCase(),
      supportDisplay: data['supportDisplay'] == true,
      text: (data['text'] ?? '').toString(),
      createdAt: _asDate(data['createdAt']) ?? DateTime.now(),
      isDeleted: data['isDeleted'] == true,
      isPinned: data['isPinned'] == true,
      pinnedAt: _asDate(data['pinnedAt']),
      pinnedBy: _nullableString(data['pinnedBy']),
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

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String? _nullableString(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

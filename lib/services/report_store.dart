// lib/services/report_store.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// أنواع الأهداف للبلاغ (للتوافق مع البلاغات على المنشورات والرسائل)
class _TargetType {
  static const String post = 'post';
  static const String message = 'message';
}

/// نموذج البلاغ — متوافق مع الاستدعاءات الحالية (اسم PostReport أبقيناه للتوافق)
class PostReport {
  // ========== الحقول الأساسية (قديمة) ==========
  String id;
  String postId;          // للبلاغات على المنشورات (قد يكون فارغًا في بلاغات الرسائل)
  String postAuthor;      // ايميل/يوزر صاحب المنشور (أو الجهة المبلغ عنها)
  String postSnippet;     // مقتطف من نص المنشور (أو وصف مختصر)

  String reporterEmail;   // من قام بالإبلاغ
  String reason;          // السبب المختار
  String? details;        // تفاصيل إضافية (اختياري)
  String status;          // 'open' | 'actioned' | 'dismissed'
  DateTime createdAt;

  // ========== حقول إضافية لدعم بلاغات الرسائل ==========
  /// 'post' | 'message' — افتراضي 'post' للتوافق
  String targetType;

  /// لبلاغات الرسائل فقط
  String? chatId;           // معرف المحادثة
  String? messageId;        // معرف الرسالة
  String? offenderUid;      // صاحب الرسالة المخالِفة
  String? messageSnippet;   // مقتطف من نص الرسالة

  PostReport({
    required this.id,
    required this.postId,
    required this.postAuthor,
    required this.postSnippet,
    required this.reporterEmail,
    required this.reason,
    this.details,
    this.status = 'open',
    required this.createdAt,
    this.targetType = _TargetType.post,
    this.chatId,
    this.messageId,
    this.offenderUid,
    this.messageSnippet,
  });

  /// تهيئة من Firestore (يدعم الحقول القديمة والجديدة)
  factory PostReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final j = doc.data() ?? const <String, dynamic>{};

    DateTime _dt(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return PostReport(
      id: doc.id,
      postId: (j['postId'] ?? '').toString(),
      postAuthor: (j['postAuthor'] ?? j['post_author'] ?? j['author'] ?? '').toString(),
      postSnippet: (j['postSnippet'] ?? j['post_snippet'] ?? j['snippet'] ?? '').toString(),
      reporterEmail: (j['reporterEmail'] ?? j['reporter_email'] ?? j['reporterId'] ?? '').toString(),
      reason: (j['reason'] ?? '').toString(),
      details: (j['details'] as String?),
      status: (j['status'] ?? 'open').toString(),
      createdAt: _dt(j['createdAt']),
      targetType: (j['targetType'] ?? _TargetType.post).toString(),
      chatId: (j['chatId'] as String?),
      messageId: (j['messageId'] as String?),
      offenderUid: (j['offenderUid'] as String?),
      messageSnippet: (j['messageSnippet'] as String?),
    );
  }

  Map<String, dynamic> toFirestore({bool forCreate = false}) {
    return {
      // الأساسية (قديمة)
      'postId': postId,
      'postAuthor': postAuthor,
      'postSnippet': postSnippet,
      'reporterEmail': reporterEmail,
      'reason': reason,
      if (details != null) 'details': details,
      'status': status,
      'createdAt': forCreate ? Timestamp.now() : createdAt,

      // الجديدة (دعم الرسائل)
      'targetType': targetType,
      if (chatId != null) 'chatId': chatId,
      if (messageId != null) 'messageId': messageId,
      if (offenderUid != null) 'offenderUid': offenderUid,
      if (messageSnippet != null) 'messageSnippet': messageSnippet,
    };
  }

  /// منشئ راحة لبلاغ "رسالة"
  factory PostReport.message({
    required String chatId,
    required String messageId,
    required String offenderUid,
    required String messageText,
    required String reporterEmail,
    required String reason,
    String? details,
  }) {
    final snippet = messageText.length <= 140 ? messageText : messageText.substring(0, 140);
    return PostReport(
      id: '',
      postId: '', // ليس بلاغ منشور
      postAuthor: offenderUid,        // لعرض سريع في لوحة الإدارة
      postSnippet: snippet,           // مقتطف
      reporterEmail: reporterEmail,
      reason: reason,
      details: details,
      status: 'open',
      createdAt: DateTime.now(),
      targetType: _TargetType.message,
      chatId: chatId,
      messageId: messageId,
      offenderUid: offenderUid,
      messageSnippet: snippet,
    );
  }
}

class ReportStore {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('reports');

  /// (اختياري) توافق قديم
  static Future<void> init() async {}

  /// تيار حي لأحدث البلاغات مع فلترة اختيارية بالحالة ونوع الهدف
  static Stream<List<PostReport>> watchReports({String? status, String? targetType}) {
    Query<Map<String, dynamic>> q = _col.orderBy('createdAt', descending: true);
    if (status != null && status.isNotEmpty) {
      q = q.where('status', isEqualTo: status);
    }
    if (targetType != null && targetType.isNotEmpty) {
      q = q.where('targetType', isEqualTo: targetType);
    }
    return q.snapshots().map((snap) => snap.docs.map(PostReport.fromFirestore).toList());
  }

  /// قراءة كل البلاغات مرة واحدة (الأحدث أولاً)
  static Future<List<PostReport>> getAllReports({int limit = 200, String? targetType, String? status}) async {
    Query<Map<String, dynamic>> q = _col.orderBy('createdAt', descending: true).limit(limit);
    if (status != null && status.isNotEmpty) {
      q = q.where('status', isEqualTo: status);
    }
    if (targetType != null && targetType.isNotEmpty) {
      q = q.where('targetType', isEqualTo: targetType);
    }
    final snap = await q.get(const GetOptions(source: Source.serverAndCache));
    return snap.docs.map(PostReport.fromFirestore).toList();
  }

  /// إضافة/تعديل بلاغ:
  /// - report.id فارغ => ينشئ وثيقة جديدة ويعيد id
  /// - وإلا يعمل set(merge:true)
  static Future<String> addReport(PostReport report) async {
    // (اختياري) تأكيد تسجيل الدخول
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // يمكنك رمي استثناء أو السماح بلا تسجيل — حسب سياستك
      // throw Exception('Not signed in');
    }

    if (report.id.isEmpty) {
      final ref = await _col.add(report.toFirestore(forCreate: true));
      return ref.id;
    } else {
      await _col.doc(report.id).set(report.toFirestore(forCreate: true), SetOptions(merge: true));
      return report.id;
    }
  }

  /// دالة راحة: إنشاء بلاغ رسالة مباشرة (للاستخدام من شاشة الشات)
  static Future<String> addMessageReport({
    required String chatId,
    required String messageId,
    required String offenderUid,
    required String messageText,
    required String reporterEmail,
    required String reason,
    String? details,
  }) async {
    final r = PostReport.message(
      chatId: chatId,
      messageId: messageId,
      offenderUid: offenderUid,
      messageText: messageText,
      reporterEmail: reporterEmail,
      reason: reason,
      details: details,
    );
    return addReport(r);
  }

  /// تغيير حالة البلاغ
  static Future<void> updateReportStatus(String id, String status) async {
    await _col.doc(id).update({
      'status': status,
      'updatedAt': Timestamp.now(),
    });
  }

  /// حذف بلاغ
  static Future<void> deleteReportById(String id) async {
    await _col.doc(id).delete();
  }

  /// مسح كل البلاغات (اختبارات فقط)
  static Future<void> clearAll() async {
    // تحذير: يمسح أول 500 فقط — عدّل حسب حاجتك أو نفّذ paging
    final batch = _db.batch();
    final snap = await _col.limit(500).get();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  static Future<void> dispose() async {}
}

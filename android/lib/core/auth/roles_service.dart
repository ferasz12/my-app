// lib/core/auth/roles_service.dart
//
// خدمة موحّدة لإدارة الأدوار والصلاحيات ونقاط المستخدمين.
// ملاحظة مهمّة:
// - القواعد (firestore.rules) يُفضّل أن تعتمد أولاً على users/{uid}.role ثمّ على الـ custom claims.
// - جميع عمليات الكتابة هنا تستخدم set(..., merge:true) لتقليل أخطاء الوثائق غير الموجودة.
//
// متوافق مع الشاشات التالية:
// - لوحة المالك/الدعم: تعديل الدور، الحظر، تعليق نشر الوصفات، تعديل/تعيين النقاط، إرسال إشعار Inbox.
// - صفحة الإنجازات: تقرأ النقاط من points_total أو stats.points (وتشغيلياً نحدّث أيضاً points/pointsTotal كتوافق قديم).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AppRole { owner, admin, support, user }

class RolesService {
  RolesService._();
  static final RolesService _instance = RolesService._();
  factory RolesService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================
  // قراءة الدور
  // =========================

  /// يحوّل نص الدور إلى AppRole.
  AppRole _toRole(String? r) {
    switch ((r ?? 'user').toLowerCase()) {
      case 'owner':
        return AppRole.owner;
      case 'admin':
        return AppRole.admin;
      case 'support':
        return AppRole.support;
      default:
        return AppRole.user;
    }
  }

  /// يحوّل AppRole إلى نص للداتا بيس.
  String roleToString(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return 'owner';
      case AppRole.admin:
        return 'admin';
      case AppRole.support:
        return 'support';
      case AppRole.user:
      default:
        return 'user';
    }
  }

  /// يقرأ دور المستخدم الحالي من وثيقة users/{uid}.role (مباشرة من Firestore).
  Future<AppRole> currentUserRoleOnce() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return AppRole.user;
    final snap = await _db.doc('users/$uid').get();
    return _toRole((snap.data() ?? const {})['role']?.toString());
  }

  /// بثّ حي لدور المستخدم الحالي (يتحدّث تلقائياً عند تعديل الوثيقة).
  Stream<AppRole> currentUserRoleStream() async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      yield AppRole.user;
      return;
    }
    yield* _db.doc('users/$uid').snapshots().map(
          (s) => _toRole((s.data() ?? const {})['role']?.toString()),
        );
  }

  /// يقرأ دور أي مستخدم بالـ uid.
  Future<AppRole> getUserRole(String uid) async {
    final snap = await _db.doc('users/$uid').get();
    return _toRole((snap.data() ?? const {})['role']?.toString());
  }

  // =========================
  // تعديل الدور
  // =========================

  /// يضبط دور المستخدم الهدف — يكتب "role" فقط (merge).
  /// تأكد أن القواعد تسمح للمالك/الأدمن (أو الدعم إذا أردتها) بتغيير الدور.
  Future<void> setUserRole(String targetUid, AppRole role) async {
    await _db
        .doc('users/$targetUid')
        .set({'role': roleToString(role)}, SetOptions(merge: true));
  }

  // =========================
  // النقاط (توافق شامل)
  // =========================

  /// يزيد/ينقص نقاط المستخدم على مفاتيح متعددة لضمان التوافق:
  /// points_total (حديث) + stats.points (قديم) + points/pointsTotal (توافق قديم)
  Future<void> incrementUserPoints(String uid, int delta) async {
    if (delta == 0) return;
    final ref = _db.doc('users/$uid');

    // بدون Transaction لتفادي [cloud_firestore/internal] Internal errors
    await ref.set(
      {
        'points_total': FieldValue.increment(delta),
        'pointsTotal': FieldValue.increment(delta), // توافق قديم
        'points': FieldValue.increment(delta), // توافق قديم
        'stats': {
          'points': FieldValue.increment(delta),
        },
        'updatedAt': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// يعيّن النقاط مباشرة على كل الحقول المتوافقة.
  Future<void> setUserPoints(String uid, int points) async {
    await _db.doc('users/$uid').set({
      'points_total': points,
      'pointsTotal': points, // توافق قديم
      'points': points, // توافق قديم
      'stats': {'points': points},
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  /// قارئ موحّد للنقاط (نفس منطق صفحة الإنجازات).
  int readUserPoints(Map<String, dynamic>? data) {
    if (data == null) return 0;

    final pt = data['points_total'];
    if (pt is num) return pt.toInt();
    if (pt is String) return int.tryParse(pt) ?? 0;

    final stats = data['stats'];
    if (stats is Map) {
      final sp = stats['points'];
      if (sp is num) return sp.toInt();
      if (sp is String) return int.tryParse(sp) ?? 0;
    }

    final legacy1 = data['points'];
    if (legacy1 is num) return legacy1.toInt();
    if (legacy1 is String) return int.tryParse(legacy1) ?? 0;

    final legacy2 = data['pointsTotal'];
    if (legacy2 is num) return legacy2.toInt();
    if (legacy2 is String) return int.tryParse(legacy2) ?? 0;

    return 0;
  }

  // =========================
  // الحظر / التعليق
  // =========================

  /// حظر/فكّ حظر مستخدم.
  Future<void> setBanned(String uid, bool banned) async {
    await _db
        .doc('users/$uid')
        .set({'isBanned': banned}, SetOptions(merge: true));
  }

  /// تعليق/إلغاء تعليق نشر الوصفات حتى تاريخ معيّن (أرسل null لإلغاء التعليق).
  /// Firestore SDK سيحوّل DateTime إلى Timestamp تلقائياً.
  Future<void> setRecipesSuspendedUntil(String uid, DateTime? until) async {
    await _db.doc('users/$uid').set({
      'recipesSuspendedUntil': until, // null لإلغاء التعليق
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // =========================
  // الإشعارات (Inbox)
  // =========================

  /// إرسال إشعار إلى صندوق المستخدم:
  /// المسار المتوافق مع القواعد: notifications/{uid}/inbox/{notificationId}
  Future<void> sendInboxNotification({
    required String toUid,
    required String title,
    required String body,
    Map<String, dynamic>? extra, // اختياري لمعلومات إضافية
  }) async {
    await _db.collection('notifications/$toUid/inbox').add({
      'title': title,
      'body': body,
      'createdAt': Timestamp.now(),
      'read': false,
      if (extra != null) ...extra,
    });
  }

  // =========================
  // مساعدات إضافية اختيارية
  // =========================

  /// يتأكد من وجود وثيقة المستخدم قبل أي تعديلات (اختياري للاستخدام عند الحاجة).
  Future<void> ensureUserDoc(String uid) async {
    final ref = _db.doc('users/$uid');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'role': 'user',
        'createdAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }
  }
}

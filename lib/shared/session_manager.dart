// lib/shared/session_manager.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// يدير مفاتيح الجلسة بشكل موحّد حتى لا تختلط بيانات حسابين.
/// الفكرة: نخزّن currentUid (الأفضل) + currentEmail (كـ"مفتاح" أيضاً)،
/// ونستخدمهما لتسمية مفاتيح SharedPreferences.
///
/// ملاحظة: إذا كان email غير متاح (مثل بعض حالات Apple)، نخزّن uid بدلًا عنه
/// داخل currentEmail حتى تظل المفاتيح فريدة ولا تختلط.
class SessionManager {
  static const String kIsLoggedIn = 'isLoggedIn';
  static const String kCurrentEmail = 'currentEmail';
  static const String kCurrentUid = 'currentUid';

  /// مزامنة الشيرد مع المستخدم الحالي من FirebaseAuth.
  /// مهم جدًا عند تبديل الحسابات (حتى لو كان currentEmail موجود من حساب سابق).
  static Future<void> syncFromFirebaseUser(User user) async {
    final prefs = await SharedPreferences.getInstance();

    final uid = user.uid.trim();
    final email = (user.email ?? '').trim().toLowerCase();
    final emailKey = email.isNotEmpty ? email : uid;

    final oldUid = prefs.getString(kCurrentUid);
    final oldEmail = prefs.getString(kCurrentEmail);

    if (oldUid != uid) {
      await prefs.setString(kCurrentUid, uid);
    }
    if (oldEmail != emailKey) {
      // نخزّن email إن وجد، وإلا نخزّن uid كبديل آمن كمفتاح
      await prefs.setString(kCurrentEmail, emailKey);
    }

    await prefs.setBool(kIsLoggedIn, true);
  }

  /// مفاتيح التخزين الموصى بها: uid إن وجد، وإلا currentEmail (والذي قد يكون uid أيضًا).
  static Future<String> currentStorageKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kCurrentUid) ??
        prefs.getString(kCurrentEmail) ??
        'unknown_user';
  }

  static Future<void> clearSessionKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kIsLoggedIn, false);
    await prefs.remove(kCurrentEmail);
    await prefs.remove(kCurrentUid);
  }

  /// (اختياري) تنظيف كاش Firestore لمنع ظهور بيانات مستخدم قديم عند تبديل الحسابات.
  /// لو فشل لأي سبب لا نوقف التطبيق.
  static Future<void> clearFirestoreCacheSafe({Duration timeout = const Duration(seconds: 2)}) async {
    try {
      await FirebaseFirestore.instance.terminate().timeout(timeout);
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.clearPersistence().timeout(timeout);
    } catch (_) {}
  }

  /// تسجيل خروج "كامل" + مسح مفاتيح الجلسة.
///
/// ملاحظة: تنظيف كاش Firestore (terminate/clearPersistence) قد يأخذ وقتًا طويلًا
/// على بعض الأجهزة، لذلك جعلناه اختياري ويمكن تشغيله بدون حجب واجهة المستخدم.
static Future<void> fullSignOut({
  bool clearFirestoreCache = true,
  bool awaitFirestoreCache = true,
}) async {
  // 1) Sign-out (Firebase + Google) بمهلة حتى لا يعلق المستخدم في اللودر
  await Future.wait([
    _googleSignOutSafe(),
    _firebaseSignOutSafe(),
  ]);

  // 2) امسح مفاتيح الجلسة سريعًا
  await clearSessionKeys();

  // 3) تنظيف كاش Firestore (اختياري)
  if (clearFirestoreCache) {
    final f = clearFirestoreCacheSafe(timeout: const Duration(seconds: 2));
    if (awaitFirestoreCache) {
      await f;
    } else {
      // تشغيل بدون انتظار
      unawaited(f);
    }
  }
}

static Future<void> _googleSignOutSafe({Duration timeout = const Duration(seconds: 2)}) async {
  try {
    // google_sign_in v7+ singleton
    await GoogleSignIn.instance.signOut().timeout(timeout);
  } catch (_) {}
}

static Future<void> _firebaseSignOutSafe({Duration timeout = const Duration(seconds: 2)}) async {
  try {
    await FirebaseAuth.instance.signOut().timeout(timeout);
  } catch (_) {}
}

  /// هل تم تغيير الحساب (uid/emailKey) مقارنةً بما في prefs؟
  static Future<bool> didAccountChange(User user) async {
    final prefs = await SharedPreferences.getInstance();

    final uid = user.uid.trim();
    final email = (user.email ?? '').trim().toLowerCase();
    final emailKey = email.isNotEmpty ? email : uid;

    final oldUid = (prefs.getString(kCurrentUid) ?? '').trim();
    final oldEmail = (prefs.getString(kCurrentEmail) ?? '').trim().toLowerCase();

    if (oldUid.isNotEmpty && oldUid != uid) return true;
    if (oldEmail.isNotEmpty && oldEmail != emailKey) return true;
    return false;
  }
}

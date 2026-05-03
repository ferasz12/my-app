// lib/services/auth_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// مهم: نستخدم LocalAuthRepo لتوليد/تحديث AppUser + كتابة حقول lower في Firestore
import '../community/local_repos.dart';
import '../community/models.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// تهيئة بسيطة للويب
  static Future<void> init() async {
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
    }
  }

  // ------------------------------------------------------------
  // أدوات داخلية: إنشاء/تحديث وثيقة المستخدم المسموح بها بالقواعد
  // ------------------------------------------------------------

  /// ينشئ users/{uid} إن لم تكن موجودة (create مسموح) بحقول بسيطة مسموحة.
  static Future<void> _ensureBaseUserDoc(User user) async {
    final ref = FirebaseFirestore.instance.doc('users/${user.uid}');
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'email': user.email ?? '',
          'displayName': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'role': 'user', // مسموح عند الإنشاء
        });
      } else {
        // UPDATE: فقط الحقول غير الحساسة والمسموح بها في قواعدك
        tx.set(
          ref,
          {
            'email': user.email ?? '',
            'displayName': user.displayName ?? '',
            'photoUrl': user.photoURL ?? '',
            'updatedAt': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  /// يضمن وجود AppUser محلي ويعكسه إلى Firestore مع الحقول المساعدة للبحث.
  /// - displayNameOverride: لو مرّرنا اسمًا عند الإنشاء، نعلّم أنه "تعديل صريح".
  static Future<void> _ensureAppUserSynced({String? displayNameOverride}) async {
    final repo = LocalAuthRepo();
    try {
      final appUser = await repo.currentUser();

      if (displayNameOverride != null && displayNameOverride.trim().isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('username_explicit_${appUser.uid}', true);

        final updated = AppUser(
          uid: appUser.uid,
          username: displayNameOverride.trim(),
          email: appUser.email,
          gender: appUser.gender,
          createdAt: appUser.createdAt,
          followers: appUser.followers,
          following: appUser.following,
          bio: appUser.bio,
          profileImagePath: appUser.profileImagePath,
        );
        await repo.updateUser(updated);
      }
    } catch (_) {
      // نتجاهل بصمت
    }
  }

  // ------------------------------------------------------------
  // بريد التحقق
  // ------------------------------------------------------------
  static Future<void> _sendPlainVerification(User user) async {
    await user.sendEmailVerification();
  }

  // ------------------------------------------------------------
  // إنشاء حساب + إرسال تحقق + الذهاب لصفحة التحقق
  // ------------------------------------------------------------
  static Future<({UserCredential cred, bool isNewUser})> signUpAndVerify({
    required BuildContext context,
    required String email,
    required String password,
    String? displayName,
    bool useDeepLink = false, // غير مستخدم هنا (Plain link)
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // حدّث displayName (اختياري)
      if (displayName != null && displayName.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(displayName.trim());
      }

      final user = cred.user!;
      // أنشئ/حدّث وثيقة المستخدم المسموح بها بالقواعد
      await _ensureBaseUserDoc(user);

      // أرسل رسالة تحقق لو غير مفعّل
      if (!user.emailVerified) {
        await _sendPlainVerification(user);
      }

      // نزامن AppUser + الحقول lower (ولو فيه displayName نعتبره تعديل صريح)
      await _ensureAppUserSynced(displayNameOverride: displayName);

      // نوجّه المستخدم لصفحة التحقق
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/verifyEmail',
          arguments: {'email': email},
        );
      }

      return (cred: cred, isNewUser: cred.additionalUserInfo?.isNewUser ?? false);
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  // ------------------------------------------------------------
  // تسجيل دخول بالبريد/كلمة المرور
  // ------------------------------------------------------------
  static Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
    BuildContext? context,
    bool navigateIfUnverified = true,
    bool resendVerificationIfNeeded = true,
    bool useDeepLink = false, // غير مستخدم هنا (Plain link)
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = cred.user!;
      // ضمن وثيقة المستخدم + مزامنة AppUser
      await _ensureBaseUserDoc(user);
      await _ensureAppUserSynced();

      // لو البريد غير مفعّل، نرسل المستخدم لصفحة التحقق
      if (!user.emailVerified && context != null && navigateIfUnverified) {
        if (resendVerificationIfNeeded) {
          try { await _sendPlainVerification(user); } catch (_) {}
        }
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed(
            '/verifyEmail',
            arguments: {'email': user.email ?? email},
          );
        }
      }

      return cred;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  // ------------------------------------------------------------
  // تسجيل دخول Google (معطّل كما هو)
  // ------------------------------------------------------------
  static Future<({UserCredential cred, bool isNewUser})> signInWithGoogle({
    BuildContext? context,
    bool navigateIfUnverified = true,
    bool useDeepLink = false,
  }) async {
    throw FirebaseAuthException(
      code: 'google-signin-disabled',
      message: 'تسجيل دخول Google مُعطّل في هذا الإصدار من التطبيق.',
    );
  }

  // ------------------------------------------------------------
  // أدوات مساندة
  // ------------------------------------------------------------
  static Future<void> resendVerificationEmail({bool useDeepLink = false}) async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await _sendPlainVerification(user);
    }
  }

  static Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      return _auth.currentUser;
    }
    return null;
  }

  static Future<IdTokenResult?> refreshAndGetIdToken({bool forceRefresh = true}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.getIdTokenResult(forceRefresh);
    return user.getIdTokenResult();
  }

  static Future<void> reauthenticateWithPassword(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'لا يوجد مستخدم حالي');
    }
    final cred = EmailAuthProvider.credential(email: email.trim(), password: password);
    await user.reauthenticateWithCredential(cred);
  }

  static Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  // ------------------------------------------------------------
  // Getters/Streams
  // ------------------------------------------------------------
  static User? get currentUser => _auth.currentUser;
  static Stream<User?> authStateChanges() => _auth.authStateChanges();
  static Stream<User?> idTokenChanges() => _auth.idTokenChanges();
  static Stream<User?> userChanges() => _auth.userChanges();

  // ------------------------------------------------------------
  // أخطاء
  // ------------------------------------------------------------
  static Exception _mapAuthError(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    String msg;
    switch (code) {
      case 'invalid-email': msg = 'صيغة البريد الإلكتروني غير صحيحة.'; break;
      case 'email-already-in-use': msg = 'هذا البريد مستخدم مسبقًا.'; break;
      case 'weak-password': msg = 'كلمة المرور ضعيفة.'; break;
      case 'user-not-found':
      case 'wrong-password': msg = 'البريد أو كلمة المرور غير صحيحة.'; break;
      case 'user-disabled': msg = 'تم تعطيل هذا الحساب.'; break;
      case 'too-many-requests': msg = 'محاولات كثيرة، جرّب لاحقًا.'; break;
      case 'network-request-failed': msg = 'مشكلة في الاتصال. تأكد من الشبكة.'; break;
      case 'canceled': msg = 'تم الإلغاء.'; break;
      case 'operation-not-allowed': msg = 'مزود الدخول غير مفعّل في Firebase Console.'; break;
      case 'no-current-user': msg = 'لا يوجد مستخدم مسجّل دخول.'; break;
      case 'google-signin-disabled': msg = 'تسجيل دخول Google مُعطّل.'; break;
      default: msg = e.message ?? 'حدث خطأ غير متوقع.';
    }
    return FirebaseAuthException(code: code, message: msg);
  }
}

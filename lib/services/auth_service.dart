// lib/services/auth_service.dart
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/session_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth/recent_accounts_store.dart';

import '../data/legacy_user_repository.dart';

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
///
/// ✅ ملاحظة: كنا نستخدم Transaction سابقاً، لكنه قد يسبب تعليق على بعض الأجهزة
/// (خصوصاً عند بطء الشبكة/ AppCheck) ويوقف الديبَغر داخل كود Firestore.
/// هنا نستخدم Get ثم Set بشكل آمن، مع SetOptions(merge: true).
static Future<void> _ensureBaseUserDoc(User user) async {
  final ref = FirebaseFirestore.instance.doc('users/${user.uid}');
  final now = Timestamp.now();

  DocumentSnapshot<Map<String, dynamic>>? snap;
  try {
    // serverAndCache لتسريع الرجوع وعدم التعليق لو الشبكة ضعيفة
    snap = await ref.get(const GetOptions(source: Source.serverAndCache));
  } catch (_) {
    // إذا فشل القراءة لأي سبب، نكمل ونكتب merge (أفضل جهد)
    snap = null;
  }

  if (snap == null || !snap.exists) {
    // Create (مسموح في قواعدك)
    await ref.set({
      'email': user.email ?? '',
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'createdAt': now,
      'updatedAt': now,
      'role': 'user', // مسموح عند الإنشاء
    }, SetOptions(merge: true));
  } else {
    // Update: فقط الحقول غير الحساسة والمسموح بها في قواعدك
    await ref.set({
      'email': user.email ?? '',
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'updatedAt': now,
    }, SetOptions(merge: true));
  }
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

      // ✅ احفظ الحساب ضمن "الحسابات السابقة" (بدون كلمة مرور)
      try {
        await RecentAccountsStore.rememberUser(user);
      } catch (_) {}

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
          try {
            await _sendPlainVerification(user);
          } catch (_) {}
        }
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed(
            '/verifyEmail',
            arguments: {'email': user.email ?? email},
          );
        }
      }

      // ✅ احفظ الحساب ضمن "الحسابات السابقة" (بدون كلمة مرور)
      try {
        await RecentAccountsStore.rememberUser(user);
      } catch (_) {}

      return cred;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  
// ------------------------------------------------------------
// تسجيل دخول Google ✅ (محدّث + Timeouts لمنع التعليق)
// ------------------------------------------------------------
static Future<({UserCredential cred, bool isNewUser})> signInWithGoogle({
  BuildContext? context,
  bool navigateIfUnverified = true,
  bool useDeepLink = false,
}) async {
  try {
    UserCredential cred;

    if (kIsWeb) {
      // Web: Popup
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      provider.setCustomParameters({'prompt': 'select_account'});
      cred = await _auth.signInWithPopup(provider);
    } else {
      // Mobile/Desktop: google_sign_in (متوافق مع v7+)
      try {
        await GoogleSignIn.instance.initialize();
      } catch (_) {}

      // لتفادي الالتقاط بحساب سابق بدون عرض اختيار الحساب
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}

      try {


        // google_sign_in v7+: استخدم singleton instance (لا يوجد constructor)


        final GoogleSignInAccount googleUser = await GoogleSignIn.instance


            .authenticate(scopeHint: const ['email'])


            .timeout(const Duration(seconds: 45));


      


        // authentication قد تكون Future حسب إصدار الحزمة
        final dynamic authDyn = googleUser.authentication;
        final GoogleSignInAuthentication googleAuth = authDyn is Future
            ? await (authDyn as Future<GoogleSignInAuthentication>)
            : (authDyn as GoogleSignInAuthentication);

        final idToken = (googleAuth.idToken ?? '').trim();

        // Firebase يحتاج idToken لتسجيل الدخول
        if (idToken.isEmpty) {
          throw FirebaseAuthException(
            code: 'google-sign-in-failed',
            message:
                'تعذّر الحصول على idToken من Google. تأكد من إعدادات Google Sign-In (Client IDs / SHA) وحاول مرة أخرى.',
          );
        }

        final credential = GoogleAuthProvider.credential(idToken: idToken);

        cred = await _auth
            .signInWithCredential(credential)
            .timeout(const Duration(seconds: 25));
      } on GoogleSignInException catch (e) {
        final code = e.code.toString().toLowerCase();
        if (code.contains('canceled') || code.contains('cancelled')) {
          throw FirebaseAuthException(code: 'canceled', message: 'تم الإلغاء');
        }
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message: e.description ?? 'تعذّر تسجيل الدخول بـ Google',
        );
      }
    }

    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'تعذّر إنشاء/قراءة المستخدم');
    }

    final isNew = cred.additionalUserInfo?.isNewUser ?? false;

    // ✅ Best-effort + Timeout حتى لا يعلق الدخول بسبب Firestore/AppCheck/شبكة
    try {
      await _ensureBaseUserDoc(user).timeout(const Duration(seconds: 20));
    } catch (_) {}

    try {
      await const LegacyUserRepository()
          .ensureLegacyUserDocExists()
          .timeout(const Duration(seconds: 20));
    } catch (_) {}

    try {
      if (isNew) {
        await _ensureAppUserSynced(displayNameOverride: user.displayName)
            .timeout(const Duration(seconds: 20));
      } else {
        await _ensureAppUserSynced().timeout(const Duration(seconds: 20));
      }
    } catch (_) {}

    // ✅ احفظ الحساب ضمن "الحسابات السابقة" (بدون كلمة مرور)
    try {
      await RecentAccountsStore.rememberUser(user);
    } catch (_) {}

    return (cred: cred, isNewUser: isNew);
  } on FirebaseAuthException catch (e) {
    throw _mapAuthError(e);
  }
}

// ------------------------------------------------------------
// تسجيل دخول Apple  ✅ (محدث لإزالة التعليق)
  // ------------------------------------------------------------
  static Future<({UserCredential cred, bool isNewUser})> signInWithApple({
    BuildContext? context,
    bool navigateIfUnverified = true,
  }) async {
    try {
      final isApplePlatform =
          defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
      if (!isApplePlatform && !kIsWeb) {
        throw FirebaseAuthException(
          code: 'operation-not-allowed',
          message: 'تسجيل Apple متاح على iOS/macOS فقط.',
        );
      }

      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthProvider = OAuthProvider('apple.com');
      final oauthCred = oauthProvider.credential(
        idToken: apple.identityToken,
        accessToken: apple.authorizationCode,
      );

      final cred = await _auth.signInWithCredential(oauthCred);
      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'no-current-user', message: 'تعذّر إنشاء/قراءة المستخدم');
      }

      // حدّث الاسم لو كان فارغ (Apple يرجع الاسم غالبًا أول مرة)
      String? fullName;
      final gn = (apple.givenName ?? '').trim();
      final fn = (apple.familyName ?? '').trim();
      final combined = ('$gn $fn').trim();
      if (combined.isNotEmpty) fullName = combined;

      if ((user.displayName ?? '').trim().isEmpty && (fullName ?? '').isNotEmpty) {
        try {
          await user.updateDisplayName(fullName);
        } catch (_) {}
      }

      // ✅ Best-effort + Timeout حتى لا يعلق الدخول بسبب Firestore/AppCheck/شبكة
      try {
        await _ensureBaseUserDoc(user).timeout(const Duration(seconds: 20));
      } catch (_) {}

      try {
        await const LegacyUserRepository()
            .ensureLegacyUserDocExists()
            .timeout(const Duration(seconds: 20));
      } catch (_) {}

      try {
        if (cred.additionalUserInfo?.isNewUser == true) {
          await _ensureAppUserSynced(displayNameOverride: fullName ?? user.displayName)
              .timeout(const Duration(seconds: 20));
        } else {
          await _ensureAppUserSynced().timeout(const Duration(seconds: 20));
        }
      } catch (_) {}

      // ✅ احفظ الحساب ضمن "الحسابات السابقة" (بدون كلمة مرور)
      try {
        await RecentAccountsStore.rememberUser(user);
      } catch (_) {}

      return (cred: cred, isNewUser: cred.additionalUserInfo?.isNewUser ?? false);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw _mapAuthError(FirebaseAuthException(code: 'canceled', message: 'تم الإلغاء'));
      }
      throw _mapAuthError(FirebaseAuthException(code: 'apple-signin-failed', message: e.message));
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
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
    await SessionManager.fullSignOut();
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
      case 'invalid-email':
        msg = 'صيغة البريد الإلكتروني غير صحيحة.';
        break;
      case 'email-already-in-use':
        msg = 'هذا البريد مستخدم مسبقًا.';
        break;
      case 'weak-password':
        msg = 'كلمة المرور ضعيفة.';
        break;
      case 'user-not-found':
      case 'wrong-password':
        msg = 'البريد أو كلمة المرور غير صحيحة.';
        break;
      case 'user-disabled':
        msg = 'تم تعطيل هذا الحساب.';
        break;
      case 'too-many-requests':
        msg = 'محاولات كثيرة، جرّب لاحقًا.';
        break;
      case 'network-request-failed':
        msg = 'مشكلة في الاتصال. تأكد من الشبكة.';
        break;
      case 'canceled':
        msg = 'تم الإلغاء.';
        break;
      case 'operation-not-allowed':
        msg = 'مزود الدخول غير مفعّل في Firebase Console.';
        break;
      case 'no-current-user':
        msg = 'لا يوجد مستخدم مسجّل دخول.';
        break;
      case 'google-signin-disabled':
        msg = 'تسجيل دخول Google مُعطّل.';
        break;
      default:
        msg = e.message ?? 'حدث خطأ غير متوقع.';
    }
    return FirebaseAuthException(code: code, message: msg);
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_service.dart';

/// واجهة بسيطة لاستدعاء تسجيل الدخول الاجتماعي من الواجهة
/// مع Loader ورسائل خطأ مناسبة.
class SocialAuth {
  static Future<void> signInWithGoogle(BuildContext context) async {
    await _runWithLoader(
      context,
      title: 'جاري تسجيل الدخول بـ Google…',
      action: () => AuthService.signInWithGoogle(context: context),
    );
  }

  static Future<void> signInWithApple(BuildContext context) async {
    await _runWithLoader(
      context,
      title: 'جاري تسجيل الدخول بـ Apple…',
      action: () => AuthService.signInWithApple(context: context),
    );
  }

  static Future<void> _runWithLoader(
    BuildContext context, {
    required String title,
    required Future<dynamic> Function() action,
  }) async {
    // مهم جدًا: لا نعتمد على mounted بعد بدء عملية تسجيل الدخول.
    // لأن AuthGate قد يستبدل شاشة الترحيب فور نجاح تسجيل الدخول،
    // وبالتالي يصبح context غير mounted، وإذا اعتمدنا عليه لن نستطيع إغلاق الـ loader.
    // الحل: نحتفظ بـ NavigatorState (root) قبل أي await، ونستخدمه للإغلاق دائمًا.
    if (!context.mounted) return;
    final NavigatorState nav = Navigator.of(context, rootNavigator: true);

    // Loader فخم وبسيط
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    String? errorMsg;
    bool success = false;

    try {
      await action().timeout(const Duration(seconds: 60));
      // ✅ النجاح: أحيانًا تكون هذه الشاشة Route مستقل (مثلاً بعد تسجيل خروج من الإعدادات)
      // وبالتالي ما يكون AuthGate حاضر فوقها، فيبقى المستخدم هنا رغم أن Firebase سجّل الدخول.
      // نرجّع دائمًا لجذر التطبيق (/) حيث AuthGate موجود ويقرر الوجهة.
      success = true;
    } on TimeoutException {
      errorMsg = 'الاتصال بطيء أو غير متاح حالياً';
    } on FirebaseAuthException catch (e) {
      // AuthService يرجع رسالة عربية في e.message غالباً
      errorMsg = e.message ?? _fallbackAuthMessage(e);
    } catch (e) {
      errorMsg = 'حدث خطأ غير متوقع: $e';
    } finally {
      // ✅ إغلاق الـ loader حتى لو تغيّر الـ context بسبب AuthGate
      // (مشكلة Apple كانت أن شاشة الترحيب تُستبدل، فيبقى الـ loader للأبد)
      try {
        // تأخير خفيف لتفادي تعارض Pop أثناء تبديل الشجرة
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await nav.maybePop();
      } catch (_) {}
    }

    // ✅ لو نجح تسجيل الدخول: ارجع للجذر (AuthGate)
    // هذا يحل مشكلة: "أسجل دخول وما يتحول إلا إذا سكرت التطبيق وفتحته".
    if (success) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        nav.pushNamedAndRemoveUntil('/', (route) => false);
      } catch (_) {}
    }

    // عرض الخطأ (إن وجد) فقط لو ما زال السياق صالحًا
    if (errorMsg != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
    }
  }

  static String _fallbackAuthMessage(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'هذا البريد مسجّل مسبقاً بطريقة دخول مختلفة. جرّب تسجيل الدخول بالطريقة السابقة.';
      case 'popup-closed-by-user':
      case 'canceled':
        return 'تم الإلغاء.';
      case 'operation-not-allowed':
        return 'المزود غير مفعّل في Firebase Console.';
      case 'network-request-failed':
        return 'مشكلة في الاتصال. تأكد من الشبكة.';
      default:
        return 'تعذّر تسجيل الدخول.';
    }
  }
}

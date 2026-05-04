import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppReviewService {
  static const String appStoreId = '6757410841';
  static const String appStoreUrl =
      'https://apps.apple.com/sa/app/%D9%88%D8%A7%D8%B2%D9%86/id6757410841';
  static const String appReviewUrl =
      'https://apps.apple.com/sa/app/id$appStoreId?action=write-review';

  static const String _launchCountKey = 'wazen_review_launch_count';
  static const String _lastPromptMsKey = 'wazen_review_last_prompt_ms';
  static const String _userTappedRateKey = 'wazen_review_user_tapped_rate';

  // يظهر بعد عدة فتحات للتطبيق، ثم لا يزعج المستخدم إلا بعد فترة.
  static const int _minLaunchesBeforePrompt = 4;
  static const Duration _minGapBetweenPrompts = Duration(days: 10);

  static bool get _supportsReviewPrompt =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static String get shareMessage =>
      'جرّب تطبيق وازن 💚\nاحسب سعراتك وماكروزك وتابع أكلك ووزنك بسهولة:\n$appStoreUrl';

  static Future<void> maybeShowPeriodicPrompt(BuildContext context) async {
    if (!context.mounted || !_supportsReviewPrompt) return;

    // لا نعرض رسالة التقييم قبل ما يكون المستخدم داخل التطبيق فعليًا.
    if (FirebaseAuth.instance.currentUser == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_userTappedRateKey) ?? false) return;

    final launchCount = (prefs.getInt(_launchCountKey) ?? 0) + 1;
    await prefs.setInt(_launchCountKey, launchCount);
    if (launchCount < _minLaunchesBeforePrompt) return;

    final now = DateTime.now();
    final lastMs = prefs.getInt(_lastPromptMsKey) ?? 0;
    if (lastMs > 0) {
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (now.difference(lastPrompt) < _minGapBetweenPrompts) return;
    }

    if (!context.mounted) return;
    final shouldRate = await _showLightReviewDialog(context);
    await prefs.setInt(_lastPromptMsKey, now.millisecondsSinceEpoch);

    if (shouldRate == true) {
      await prefs.setBool(_userTappedRateKey, true);
      await requestInAppReviewOrOpenStore();
    }
  }

  static Future<bool?> _showLightReviewDialog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.favorite_rounded, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'رأيك يهمنا 💚',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          content: Text(
            'إذا وازن ساعدك في حساب أكلك ومتابعة هدفك، تقييمك البسيط يدعم التطبيق كثير.',
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('لاحقًا'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.star_rounded, size: 18),
              label: const Text('قيّم وازن'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> requestInAppReviewOrOpenStore() async {
    final inAppReview = InAppReview.instance;

    try {
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        return;
      }
    } catch (_) {}

    await openReviewPage();
  }

  static Future<void> openReviewPage() async {
    final reviewUri = Uri.parse(appReviewUrl);
    final storeUri = Uri.parse(appStoreUrl);

    try {
      final openedReview = await launchUrl(
        reviewUri,
        mode: LaunchMode.externalApplication,
      );
      if (openedReview) return;
    } catch (_) {}

    try {
      await InAppReview.instance.openStoreListing(appStoreId: appStoreId);
      return;
    } catch (_) {}

    await launchUrl(storeUri, mode: LaunchMode.externalApplication);
  }

  static Future<void> shareApp() async {
    await Share.share(shareMessage);
  }
}

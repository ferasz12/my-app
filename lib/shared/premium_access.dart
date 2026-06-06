// lib/shared/premium_access.dart
//
// مصدر واحد للتحقق من الاشتراك (Premium) بناءً على:
// - Firestore users/{uid}.subscription.expiry (إن وُجد وبشكل موثوق)
// - أو fallback محلي محفوظ في SharedPreferences (نفس مفاتيح صفحة الاشتراك)
//
// الهدف: فتح/قفل بعض المزايا فقط بدون قفل التطبيق بالكامل.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../settings/subscription_page.dart' show SubscriptionEntitlementService, SubscriptionPage;
import 'premium_feature.dart';
import 'package:flutter/material.dart';

class PremiumStatus {
  final bool isPremium;
  final DateTime? expiry;
  const PremiumStatus({required this.isPremium, required this.expiry});
}

class PremiumAccess {
  PremiumAccess._();

  /// ✅ هذه القائمة هي "المدفوعة".
  /// أي ميزة غير موجودة هنا تعتبر مجانية.
  static const Set<PremiumFeature> paidFeatures = <PremiumFeature>{
    PremiumFeature.aiPhoto,
    PremiumFeature.aiText,
    PremiumFeature.restaurants,
    PremiumFeature.coach,
    PremiumFeature.trackingPdf,
    PremiumFeature.virtualClubGuide,
    PremiumFeature.recipes,
    PremiumFeature.regimen,
    PremiumFeature.regimens,
    PremiumFeature.theme,
    PremiumFeature.notifications,
    PremiumFeature.cloudSync,
  };

  static bool isPaid(PremiumFeature f) => paidFeatures.contains(f);

  static final StreamController<PremiumStatus> _controller =
      StreamController<PremiumStatus>.broadcast();

  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  static String? _cacheKey;
  static DateTime? _localExpiryCache;
  static bool _localLoaded = false;

  /// استدعِها مرة واحدة (مثلاً من main) لتفعيل البث.
  static void ensureStarted() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _docSub?.cancel();
      _docSub = null;
      _localLoaded = false;
      _localExpiryCache = null;
      _cacheKey = null;

      if (user == null || user.isAnonymous) {
        _controller.add(const PremiumStatus(isPremium: false, expiry: null));
        return;
      }

      _docSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snap) async {
        final status = await _computeStatus(user, remoteData: snap.data());
        _controller.add(status);
      });

      // دفع حالة أولية بسرعة حتى قبل أول snapshot
      final initial = await _computeStatus(user, remoteData: null);
      _controller.add(initial);
    });
  }

  static Stream<PremiumStatus> stream() {
    ensureStarted();
    return _controller.stream.distinct((a, b) => a.isPremium == b.isPremium && a.expiry == b.expiry);
  }

  static Future<PremiumStatus> current() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const PremiumStatus(isPremium: false, expiry: null);
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      return _computeStatus(user, remoteData: doc.data());
    } catch (_) {
      return _computeStatus(user, remoteData: null);
    }
  }

  static Future<bool> hasAccess(PremiumFeature feature) async {
    if (!isPaid(feature)) return true; // مجانية
    final st = await current();
    return st.isPremium;
  }


  /// تحقق سريع عند الضغط على زر ميزة مدفوعة.
  /// يرجّع true إذا الميزة مجانية أو المستخدم مشترك، وإلا يفتح صفحة الاشتراك.
  static Future<bool> ensureSubscribed(
    BuildContext context, {
    required PremiumFeature feature,
    bool showSheet = true,
  }) async {
    final allowed = await hasAccess(feature);
    if (allowed) return true;

    if (!context.mounted) return false;

    if (showSheet) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.primary.withOpacity(.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(feature.icon, color: Theme.of(ctx).colorScheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${feature.titleAr} ميزة مدفوعة',
                              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(feature.subtitleAr, style: Theme.of(ctx).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await openPaywall(context);
                      },
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text('الاشتراك الآن'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('إغلاق'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      await openPaywall(context);
    }

    try {
      final refreshed = await current();
      return refreshed.isPremium;
    } catch (_) {
      return false;
    }
  }

  static Future<PremiumStatus> _computeStatus(User user, {Map<String, dynamic>? remoteData}) async {
    final now = DateTime.now();

    final remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(remoteData);
    final localExpiry = await _readLocalExpiry(user);

    DateTime? best;
    if (remoteExpiry != null) best = remoteExpiry;
    if (localExpiry != null) {
      if (best == null || localExpiry.isAfter(best)) best = localExpiry;
    }

    final ok = (best != null && best.isAfter(now));
    return PremiumStatus(isPremium: ok, expiry: best);
  }

  static Future<DateTime?> _readLocalExpiry(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = user.uid;
    final email = prefs.getString('currentEmail') ?? (user.email ?? 'unknown_user');

    final newKey = '$uid|$email';
    if (_localLoaded && _cacheKey == newKey) return _localExpiryCache;

    final expUid = uid.isNotEmpty ? prefs.getInt('subscriptionExpiry_uid_$uid') : null;
    final expEmail = prefs.getInt('subscriptionExpiry_$email');
    final bestMs = (expUid != null && (expEmail == null || expUid > expEmail)) ? expUid : expEmail;

    _cacheKey = newKey;
    _localExpiryCache = bestMs != null ? DateTime.fromMillisecondsSinceEpoch(bestMs) : null;
    _localLoaded = true;
    return _localExpiryCache;
  }

  /// افتح صفحة الاشتراك (Paywall) بشكل عادي (بدون إجبار).
  static Future<void> openPaywall(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionPage(force: false)),
    );

    // بعد الرجوع: حدّث الحالة
    try {
      await SubscriptionEntitlementService.refreshAndSyncForCurrentUser(allowRestore: true);
    } catch (_) {}
  }
}

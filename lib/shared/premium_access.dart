// lib/shared/premium_access.dart
// تحقق اشتراك سريع Local-first للصفحات التي تستورد premium_access مباشرة.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/subscription_page.dart' show SubscriptionEntitlementService, SubscriptionPage;
import 'premium_feature.dart';

class PremiumStatus {
  final bool isPremium;
  final DateTime? expiry;
  const PremiumStatus({required this.isPremium, required this.expiry});
}

class PremiumAccess {
  PremiumAccess._();

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
  };

  static bool isPaid(PremiumFeature f) => paidFeatures.contains(f);

  static final StreamController<PremiumStatus> _controller =
      StreamController<PremiumStatus>.broadcast();
  static StreamSubscription<User?>? _authSub;
  static String? _cacheKey;
  static DateTime? _localExpiryCache;
  static bool _localLoaded = false;
  static String? _remoteCacheKey;
  static DateTime? _remoteExpiryCache;
  static DateTime? _remoteReadAt;

  static void ensureStarted() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      _localLoaded = false;
      _localExpiryCache = null;
      _cacheKey = null;
      if (user == null || user.isAnonymous) {
        _controller.add(const PremiumStatus(isPremium: false, expiry: null));
        return;
      }
      final st = await current(allowRemote: false);
      _controller.add(st);
      unawaited(current(allowRemote: true).then(_controller.add).catchError((_) {}));
    });
  }

  static Stream<PremiumStatus> stream() {
    ensureStarted();
    return _controller.stream.distinct((a, b) => a.isPremium == b.isPremium && a.expiry == b.expiry);
  }

  static Future<PremiumStatus> current({bool allowRemote = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const PremiumStatus(isPremium: false, expiry: null);
    }

    final now = DateTime.now();
    final localExpiry = await _readLocalExpiry(user);
    if (localExpiry != null && localExpiry.isAfter(now)) {
      return PremiumStatus(isPremium: true, expiry: localExpiry);
    }

    final key = user.uid;
    if (_remoteCacheKey == key && _remoteReadAt != null && now.difference(_remoteReadAt!) < const Duration(minutes: 3)) {
      final best = _maxDate(localExpiry, _remoteExpiryCache);
      return PremiumStatus(isPremium: best != null && best.isAfter(now), expiry: best);
    }

    if (!allowRemote) {
      return PremiumStatus(isPremium: false, expiry: localExpiry);
    }

    DateTime? remoteExpiry;
    try {
      final cacheDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 90));
      remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(cacheDoc.data());
      if (remoteExpiry != null && remoteExpiry.isAfter(now)) {
        await _persistLocalExpiry(user, remoteExpiry);
        return PremiumStatus(isPremium: true, expiry: remoteExpiry);
      }
    } catch (_) {}

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(milliseconds: 320));
      remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(doc.data());
    } catch (_) {}

    _remoteCacheKey = key;
    _remoteExpiryCache = remoteExpiry;
    _remoteReadAt = now;
    if (remoteExpiry != null) {
      await _persistLocalExpiry(user, remoteExpiry);
    }

    final best = _maxDate(localExpiry, remoteExpiry);
    return PremiumStatus(isPremium: best != null && best.isAfter(now), expiry: best);
  }

  static Future<bool> hasAccess(PremiumFeature feature) async {
    if (!isPaid(feature)) return true;
    final st = await current(allowRemote: true);
    return st.isPremium;
  }

  static Future<bool> ensureSubscribed(
    BuildContext context, {
    required PremiumFeature feature,
    bool showSheet = true,
  }) async {
    if (!isPaid(feature)) return true;
    final st = await current(allowRemote: true);
    if (st.isPremium) return true;
    unawaited(current(allowRemote: true).catchError((_) => const PremiumStatus(isPremium: false, expiry: null)));

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
                  Icon(feature.icon, size: 42, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('${feature.titleAr} ضمن الباقة', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(feature.subtitleAr, textAlign: TextAlign.center),
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
    }
    return false;
  }

  static Future<void> openPaywall(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionPage(force: false)),
    );
    try {
      await SubscriptionEntitlementService.refreshAndSyncForCurrentUser(allowRestore: true);
    } catch (_) {}
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

  static Future<void> _persistLocalExpiry(User user, DateTime expiry) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = expiry.millisecondsSinceEpoch;
    await prefs.setInt('subscriptionExpiry_uid_${user.uid}', ms);
    final email = prefs.getString('currentEmail') ?? user.email;
    if (email != null && email.trim().isNotEmpty) {
      await prefs.setInt('subscriptionExpiry_${email.trim()}', ms);
    }
    _localExpiryCache = expiry;
    _localLoaded = true;
    _cacheKey = '${user.uid}|${email ?? ''}';
  }

  static DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/subscription_page.dart' show SubscriptionEntitlementService, SubscriptionPage;
import '../app/app_nav.dart';
import 'owner_feature_flags.dart';
import 'premium_feature.dart';

/// أدوات التحقق من الاشتراك لاستخدامها في أماكن مثل أزرار/أكشن معينة.
class PremiumAccess {
  PremiumAccess._();

  static Future<bool> hasActiveSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final now = DateTime.now();
    final localExpiry = await _readLocalExpiry(uid: user.uid, email: user.email);

    DateTime? remoteExpiry;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache));
      remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(snap.data());
    } catch (_) {
      // تجاهل
    }

    final effective = _maxDate(localExpiry, remoteExpiry);
    return effective != null && effective.isAfter(now);
  }

  static Future<bool> ensureSubscribed(
    BuildContext context, {
    required PremiumFeature feature,
    bool showSheet = true,
  }) async {
    final enabled = await OwnerFeatureFlagsService().isEnabled(feature);
    if (!enabled) {
      if (showSheet && context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (ctx) => _FeatureDisabledSheet(feature: feature),
        );
      }
      return false;
    }

    final active = await hasActiveSubscription();
    if (active) return true;

    if (!context.mounted) return false;

    if (showSheet) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => _PremiumLockedSheet(feature: feature),
      );
    }

    return false;
  }

  static Future<void> openPaywall(BuildContext context, {bool force = true}) async {
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SubscriptionPage(force: force),
      ),
    );
  }

  static Future<DateTime?> _readLocalExpiry({required String uid, String? email}) async {
    final prefs = await SharedPreferences.getInstance();

    final expUid = uid.isNotEmpty ? prefs.getInt('subscriptionExpiry_uid_$uid') : null;

    final String? effectiveEmail = (prefs.getString('currentEmail')?.trim().isNotEmpty ?? false)
        ? prefs.getString('currentEmail')
        : (email?.trim().isNotEmpty ?? false)
            ? email
            : null;
    final expEmail = effectiveEmail != null ? prefs.getInt('subscriptionExpiry_$effectiveEmail') : null;

    final int? bestMs;
    if (expUid == null) {
      bestMs = expEmail;
    } else if (expEmail == null) {
      bestMs = expUid;
    } else {
      bestMs = expUid > expEmail ? expUid : expEmail;
    }

    if (bestMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(bestMs);
  }

  static DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}



Future<void> _leaveLockedFeature(BuildContext context) async {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }

  final root = AppNav.key.currentState;
  if (root == null) return;
  try {
    root.pushNamedAndRemoveUntil('/home', (route) => false);
  } catch (_) {
    // ignore
  }
}

String _leaveLockedLabel(BuildContext context) {
  return Navigator.of(context).canPop() ? 'رجوع' : 'العودة للرئيسية';
}

/// بوابة ميزة مدفوعة — تعرض المحتوى بشكل تغبيش + بطاقة اشتراك عند عدم وجود اشتراك فعال.
class PremiumGate extends StatefulWidget {
  final PremiumFeature feature;
  final Widget child;
  final bool blurPreview;

  const PremiumGate({
    super.key,
    required this.feature,
    required this.child,
    this.blurPreview = true,
  });

  @override
  State<PremiumGate> createState() => _PremiumGateState();
}

class _PremiumGateState extends State<PremiumGate> {
  bool _loadedLocal = false;
  DateTime? _localExpiry;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        if (mounted) setState(() => _loadedLocal = true);
        return;
      }
      _localExpiry = await PremiumAccess._readLocalExpiry(uid: user.uid, email: user.email);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadedLocal = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return widget.child;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    return StreamBuilder<Map<PremiumFeature, bool>>(
      stream: OwnerFeatureFlagsService().watchFlags(),
      initialData: OwnerFeatureFlagsService.defaults,
      builder: (context, featureSnap) {
        final enabled = featureSnap.data?[widget.feature] ?? true;
        if (!enabled) {
          if (!widget.blurPreview) {
            return _FeatureDisabledFullScreen(feature: widget.feature);
          }
          return Stack(
            children: [
              widget.child,
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(color: Colors.black.withOpacity(.12)),
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: _FeatureDisabledCard(feature: widget.feature),
                ),
              ),
            ],
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(includeMetadataChanges: true),
          builder: (context, snap) {
            final now = DateTime.now();
            final remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(snap.data?.data());
            final effective = PremiumAccess._maxDate(remoteExpiry, _localExpiry);
            final active = effective != null && effective.isAfter(now);

            final checking = !_loadedLocal && !snap.hasData;
            if (checking) {
              return Stack(
                children: [
                  widget.child,
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(.08),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            if (active) return widget.child;

            if (!widget.blurPreview) {
              return _PremiumLockedFullScreen(feature: widget.feature);
            }

            return Stack(
              children: [
                widget.child,
                Positioned.fill(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(color: Colors.black.withOpacity(.12)),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: _PremiumLockedCard(feature: widget.feature),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PremiumLockedCard extends StatelessWidget {
  final PremiumFeature feature;

  const _PremiumLockedCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 10,
          shadowColor: Colors.black.withOpacity(.25),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: s.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(feature.icon, size: 34, color: s.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  '${feature.titleAr} ضمن الباقة',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(feature.subtitleAr, style: t.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => PremiumAccess.openPaywall(context, force: true),
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text('الاشتراك الآن'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => PremiumAccess.openPaywall(context, force: false),
                    child: const Text('عرض الباقات / استعادة المشتريات'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _leaveLockedFeature(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(_leaveLockedLabel(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumLockedFullScreen extends StatelessWidget {
  final PremiumFeature feature;
  const _PremiumLockedFullScreen({required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(feature.icon, size: 72, color: s.primary),
                  const SizedBox(height: 10),
                  Text(
                    '${feature.titleAr} ضمن الباقة',
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(feature.subtitleAr, style: t.bodyMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => PremiumAccess.openPaywall(context, force: true),
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text('الاشتراك الآن'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _leaveLockedFeature(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(_leaveLockedLabel(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumLockedSheet extends StatelessWidget {
  final PremiumFeature feature;
  const _PremiumLockedSheet({required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: s.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(feature.icon, color: s.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${feature.titleAr} ميزة مدفوعة',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(feature.subtitleAr, style: t.bodySmall),
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
                  Navigator.of(context).pop();
                  await PremiumAccess.openPaywall(context, force: true);
                },
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('الاشتراك الآن'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await PremiumAccess.openPaywall(context, force: false);
                },
                child: const Text('عرض الباقات / استعادة المشتريات'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('إغلاق'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureDisabledCard extends StatelessWidget {
  final PremiumFeature feature;
  const _FeatureDisabledCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 10,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: s.error.withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.lock_clock_outlined, size: 34, color: s.error),
                ),
                const SizedBox(height: 12),
                Text(
                  '${feature.titleAr} مقفلة حاليًا',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'هذه الميزة تم إيقافها مؤقتًا من لوحة الأونر داخل وازن.',
                  style: t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _leaveLockedFeature(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(_leaveLockedLabel(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureDisabledFullScreen extends StatelessWidget {
  final PremiumFeature feature;
  const _FeatureDisabledFullScreen({required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_clock_outlined, size: 72, color: s.error),
                  const SizedBox(height: 10),
                  Text(
                    '${feature.titleAr} مقفلة حاليًا',
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'هذه الميزة تم إيقافها مؤقتًا من لوحة الأونر داخل وازن.',
                    style: t.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => _leaveLockedFeature(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(_leaveLockedLabel(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureDisabledSheet extends StatelessWidget {
  final PremiumFeature feature;
  const _FeatureDisabledSheet({required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: s.error.withOpacity(.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.lock_clock_outlined, color: s.error),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${feature.titleAr} مقفلة حاليًا',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text('تم إيقاف هذه الميزة مؤقتًا من لوحة الأونر.', style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('إغلاق'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

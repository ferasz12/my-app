import 'dart:async';
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

  static final Map<String, DateTime?> _localExpiryMemory = <String, DateTime?>{};
  static final Set<String> _localExpiryMemoryReady = <String>{};
  static final Set<String> _remoteRefreshInFlight = <String>{};

  static bool localExpiryMemoryReadyForCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;
    return _localExpiryMemoryReady.contains(user.uid);
  }

  static DateTime? localExpirySyncForCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    return _localExpiryMemory[user.uid];
  }

  static Future<void> warmLocalSubscriptionCache() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await _readLocalExpiry(uid: user.uid, email: user.email);
    // تحديث هادئ من Firestore بالخلفية فقط، بدون تعطيل الواجهة.
    unawaited(refreshLocalFromRemoteQuietly());
  }

  static bool hasActiveSubscriptionSync() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;
    final expiry = _localExpiryMemory[user.uid];
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  static Future<bool> hasActiveSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final now = DateTime.now();

    // 1) أسرع مسار: الذاكرة.
    final mem = _localExpiryMemory[user.uid];
    if (mem != null && mem.isAfter(now)) {
      unawaited(refreshLocalFromRemoteQuietly());
      return true;
    }

    // 2) SharedPreferences فقط. لا ننتظر Firestore هنا.
    final localExpiry = await _readLocalExpiry(uid: user.uid, email: user.email);
    if (localExpiry != null && localExpiry.isAfter(now)) {
      unawaited(refreshLocalFromRemoteQuietly());
      return true;
    }

    // 3) إذا ما فيه كاش محلي، جرّب Firestore cache فقط لمدة قصيرة.
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 250));
      final remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(snap.data());
      if (remoteExpiry != null) {
        await _writeLocalExpiry(
          uid: user.uid,
          email: user.email,
          start: SubscriptionEntitlementService.readStartFromUserDoc(snap.data()),
          expiry: remoteExpiry,
          productId: SubscriptionEntitlementService.readProductIdFromUserDoc(snap.data()),
        );
        if (remoteExpiry.isAfter(now)) {
          unawaited(refreshLocalFromRemoteQuietly());
          return true;
        }
      }
    } catch (_) {}

    unawaited(refreshLocalFromRemoteQuietly());
    return false;
  }

  static Future<void> refreshLocalFromRemoteQuietly() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    if (_remoteRefreshInFlight.contains(user.uid)) return;
    _remoteRefreshInFlight.add(user.uid);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));
      final data = snap.data();
      final remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(data);
      if (remoteExpiry == null) return;
      await _writeLocalExpiry(
        uid: user.uid,
        email: user.email,
        start: SubscriptionEntitlementService.readStartFromUserDoc(data),
        expiry: remoteExpiry,
        productId: SubscriptionEntitlementService.readProductIdFromUserDoc(data),
      );
    } catch (_) {
      // تجاهل الشبكة؛ الكاش المحلي هو الأساس.
    } finally {
      _remoteRefreshInFlight.remove(user.uid);
    }
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
    await warmLocalSubscriptionCache();
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

    if (bestMs == null) {
      if (uid.isNotEmpty) {
        _localExpiryMemory[uid] = null;
        _localExpiryMemoryReady.add(uid);
      }
      return null;
    }

    final expiry = DateTime.fromMillisecondsSinceEpoch(bestMs);
    if (uid.isNotEmpty) {
      _localExpiryMemory[uid] = expiry;
      _localExpiryMemoryReady.add(uid);
    }
    return expiry;
  }

  static Future<void> _writeLocalExpiry({
    required String uid,
    String? email,
    DateTime? start,
    required DateTime expiry,
    String? productId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveEmail = (prefs.getString('currentEmail')?.trim().isNotEmpty ?? false)
        ? prefs.getString('currentEmail')!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : 'unknown_user';

    await prefs.setInt('subscriptionExpiry_$effectiveEmail', expiry.millisecondsSinceEpoch);
    if (start != null) {
      await prefs.setInt('subscriptionStart_$effectiveEmail', start.millisecondsSinceEpoch);
    }
    if (productId != null && productId.trim().isNotEmpty) {
      await prefs.setString('subscriptionProductId_$effectiveEmail', productId.trim());
    }

    if (uid.isNotEmpty) {
      await prefs.setInt('subscriptionExpiry_uid_$uid', expiry.millisecondsSinceEpoch);
      if (start != null) {
        await prefs.setInt('subscriptionStart_uid_$uid', start.millisecondsSinceEpoch);
      }
      if (productId != null && productId.trim().isNotEmpty) {
        await prefs.setString('subscriptionProductId_uid_$uid', productId.trim());
      }
      _localExpiryMemory[uid] = expiry;
      _localExpiryMemoryReady.add(uid);
    }
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
  Map<PremiumFeature, bool> _flags = OwnerFeatureFlagsService().cachedFlags;

  @override
  void initState() {
    super.initState();

    // قراءة فورية من الذاكرة إن كانت محملة عند تشغيل التطبيق أو من دخول سابق.
    _localExpiry = PremiumAccess.localExpirySyncForCurrentUser();
    _loadedLocal = PremiumAccess.localExpiryMemoryReadyForCurrentUser();

    _loadLocal();
    _loadFlagsQuietly();
    unawaited(_refreshAndReloadLocalQuietly());
  }

  Future<void> _refreshAndReloadLocalQuietly() async {
    await PremiumAccess.refreshLocalFromRemoteQuietly();
    await _loadLocal();
  }

  Future<void> _loadFlagsQuietly() async {
    try {
      final flags = await OwnerFeatureFlagsService().loadFlags();
      if (mounted) setState(() => _flags = flags);
    } catch (_) {}
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

    final enabled = _flags[widget.feature] ?? true;
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

    // Cache-first: لا ننتظر Firestore ولا StoreKit عند فتح صفحة مدفوعة.
    final now = DateTime.now();
    final active = _localExpiry != null && _localExpiry!.isAfter(now);
    if (active) return widget.child;

    // في أول لحظة قبل ما يخلص SharedPreferences، اعرض الصفحة بدل شاشة بيضاء/لودر طويل.
    if (!_loadedLocal) {
      return widget.child;
    }

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
  }
}

class _PremiumDecisionShell extends StatelessWidget {
  final PremiumFeature feature;
  const _PremiumDecisionShell({required this.feature});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    // واجهة صامتة جدًا أثناء التحقق حتى لا يظهر للمستخدم وميض اشتراك أو قفل.
    return Scaffold(
      backgroundColor: s.surface,
      body: const SizedBox.expand(),
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

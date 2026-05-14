// lib/settings/subscription_page.dart
//
// ✅ اشتراكات حقيقية عبر Apple/Google (التجربة 3 أيام من المتجر حسب الأهلية)
//
// المتطلبات المنفّذة هنا:
// 1) أول ما يسجّل المستخدم: لازم يبدأ اشتراك من المتجر.
//    (التجربة المجانية 3 أيام تُدار من المتجر Apple/Google حسب الأهلية).
// 2) بعد انتهاء التجربة/الاشتراك: يتقفل التطبيق بالكامل، وتظهر أقفال على العناصر.
//    صفحة الاشتراك فقط تبقى مفتوحة.
// 3) الكوبون يخصم فعليًا من السعر عبر شراء "منتج مخفّض" بسعر أقل (Product ID مختلف).
//    لا يمكن تغيير سعر نفس المنتج برمجيًا في iOS/Android.
// 4) إزالة تفعيل الاشتراك عبر باركود/رموز تفعيل من صفحة الاشتراك.
// 5) صفحة اشتراك أفخم + بدون تغيير IDs الأساسية:
//    vip_monthly / vip_yearly
//
// ملاحظة مهمة: تحديث حالة الاشتراك بدقة (خصوصًا iOS) يحتاج تحقق Receipt.
// هذا الملف يحتوي تحقق iOS عبر verifyReceipt (يتطلب App Shared Secret).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// Android-specific purchase params (offerToken / base plans)
import 'package:in_app_purchase_android/in_app_purchase_android.dart' as iap_android;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app/settings/privacy_page.dart';
import 'package:my_app/settings/terms_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../shared/friendly_errors.dart';

// =========================
// Gate (قفل التطبيق)
// =========================

/// لفّ أي شجرة (MainNavigation/Onboarding…) بهذا الـ Gate.
/// إذا ما فيه اشتراك نشط (يشمل الـ Trial من المتجر) ⇒ قفل كامل.
class SubscriptionEntitlementGate extends StatefulWidget {
  final Widget child;

  /// هل يفتح صفحة الاشتراك تلقائيًا عندما يكون التطبيق مقفول؟
  final bool autoOpenPaywall;

  /// هل تكون صفحة الاشتراك إجبارية (منع الرجوع) عندما تُفتح تلقائيًا؟
  final bool forcePaywall;

  const SubscriptionEntitlementGate({
    super.key,
    required this.child,
    this.autoOpenPaywall = true,
    // المطلوب: صفحة الاشتراك تظهر ويمكن إغلاقها، لكن يبقى التطبيق مقفولًا حتى الاشتراك.
    this.forcePaywall = false,
  });

  @override
  State<SubscriptionEntitlementGate> createState() => _SubscriptionEntitlementGateState();
}

class _SubscriptionEntitlementGateState extends State<SubscriptionEntitlementGate> {
  bool _paywallShownThisSession = false;
  bool _paywallRouteOpen = false;
  bool _lastLocked = false;
  DateTime? _localExpiry;
  String? _localProductId;
  bool _loadedLocal = false;
  bool _refreshStarted = false;
  bool _sanitizedRemoteFallback = false; // يمنع تفعيل اشتراك وهمي مكتوب سابقًا

  Timer? _expiryTimer;
  DateTime? _scheduledExpiry;
  bool _expiredDialogShownThisSession = false;

  // لمنع وميض رسالة الانتهاء عند بداية فتح التطبيق
  Timer? _expiryDialogDebounce;
  DateTime? _lastRemoteExpiry;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _expiryDialogDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      final email = prefs.getString('currentEmail') ?? (user?.email ?? 'unknown_user');

      final expUid = uid.isNotEmpty ? prefs.getInt('subscriptionExpiry_uid_$uid') : null;
      final expEmail = prefs.getInt('subscriptionExpiry_$email');
      final bestMs = (expUid != null && (expEmail == null || expUid > expEmail)) ? expUid : expEmail;

      final pidUid = uid.isNotEmpty ? prefs.getString('subscriptionProductId_uid_$uid') : null;
      final pidEmail = prefs.getString('subscriptionProductId_$email');
      final bestPid = (pidUid != null && pidUid.trim().isNotEmpty) ? pidUid : pidEmail;


      if (!mounted) return;
      setState(() {
        _localExpiry = bestMs != null ? DateTime.fromMillisecondsSinceEpoch(bestMs) : null;
        _localProductId = (bestPid != null && bestPid.trim().isNotEmpty) ? bestPid.trim() : null;
        _loadedLocal = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadedLocal = true);
    }
  }

  void _maybeOpenPaywall(BuildContext context, {required bool locked}) {
    if (!widget.autoOpenPaywall) return;

    // إذا عاد التطبيق نشطًا: نسمح بإعادة الفتح لاحقًا.
    if (!locked) {
      _lastLocked = false;
      return;
    }

    // locked == true
    if (!_lastLocked) {
      _lastLocked = true;
      // في وضع الإجباري: لا نمنع الفتح مرة أخرى.
      // في الوضع غير الإجباري: نفس السلوك السابق (مرة واحدة في الجلسة).
    }

    if (widget.forcePaywall) {
      // ✅ إجبارية: افتح صفحة الاشتراك دائمًا طالما التطبيق مقفول (بدون تكديس Routes).
      if (_paywallRouteOpen) return;
    } else {
      if (_paywallShownThisSession) return;
      _paywallShownThisSession = true;
    }

    _paywallRouteOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SubscriptionPage(force: widget.forcePaywall),
        ),
      )
          .then((_) async {
        _paywallRouteOpen = false;
        // بعد الرجوع: حدّث المحلي سريعًا
        await _loadLocal();
        if (mounted) setState(() {});
      });
    });
  }

  /// جدولة فحص عند/قبل وقت الانتهاء حتى يتقفل التطبيق حتى لو المستخدم فاتح.
  void _scheduleExpiryTimer(DateTime? effectiveExpiry) {
    // لا شيء نراقبه.
    if (effectiveExpiry == null) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _scheduledExpiry = null;
      return;
    }

    // لو نفس الانتهاء المجدول، لا نعيد الجدولة.
    if (_scheduledExpiry != null && _scheduledExpiry!.millisecondsSinceEpoch == effectiveExpiry.millisecondsSinceEpoch) {
      return;
    }

    _expiryTimer?.cancel();
    _scheduledExpiry = effectiveExpiry;

    final now = DateTime.now();
    final diff = effectiveExpiry.difference(now);
    if (diff.isNegative) {
      // انتهى بالفعل.
      _expiryTimer = null;
      return;
    }

    // لو بعيد جدًا (سنة)، نعمل إعادة تحقق دورية بدل تايمر طويل جدًا.
    final cap = diff > const Duration(hours: 6) ? const Duration(hours: 6) : diff + const Duration(seconds: 2);
    _expiryTimer = Timer(cap, () async {
      if (!mounted) return;
      //  لا نستدعي المتجر تلقائيًا عند انتهاء الوقت (حتى لا يعمل Restore تلقائي أو يكتب اشتراك غلط)
      await _loadLocal();
      if (mounted) setState(() {});
    });
}

    Future<void> _handleExpiryMessageIfNeeded({required bool active, required bool ready}) async {
    // أثناء التحقق الأولي: لا نعتبرها منتهية ولا نعرض رسائل.
    if (!ready) {
      _expiryDialogDebounce?.cancel();
      _expiryDialogDebounce = null;
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'entitlementWasActive_${user.uid}';
    final wasActive = prefs.getBool(key) ?? false;

    if (active) {
      // بمجرد ما يصير نشط (اشتراك أو Trial) نسجل ذلك.
      _expiryDialogDebounce?.cancel();
      _expiryDialogDebounce = null;
      await prefs.setBool(key, true);
      _expiredDialogShownThisSession = false;
      return;
    }

    // غير نشط الآن — إذا كان كان نشطًا سابقًا، نعرض رسالة مرة واحدة لكن بعد تثبيت الحالة.
    if (!wasActive || _expiredDialogShownThisSession) return;

    // لا نكرر إنشاء المؤقت كل rebuild.
    if (_expiryDialogDebounce != null) return;

    _expiryDialogDebounce = Timer(const Duration(seconds: 2), () async {
      _expiryDialogDebounce = null;
      if (!mounted) return;

      // تأكد مرة أخرى بعد مرور الوقت أن الحالة ما زالت غير نشطة.
      final now = DateTime.now();
      final effective = _maxDate(_lastRemoteExpiry, _localExpiry);
      final stillActive = effective != null && effective.isAfter(now);
      if (stillActive) return;

      final prefs2 = await SharedPreferences.getInstance();
      final wasActive2 = prefs2.getBool(key) ?? false;
      if (!wasActive2) return;

      _expiredDialogShownThisSession = true;
      await prefs2.setBool(key, false);

      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text((_localProductId ?? '').toLowerCase().contains('trial') ? 'انتهت فترتك التجريبية' : 'انتهى اشتراكك'),
              content: Text((_localProductId ?? '').toLowerCase().contains('trial')
                  ? 'لقد انتهت فترة التجربة المجانية. يرجى الاشتراك للاستمرار.'
                  : 'لقد انتهت صلاحية الاشتراك. يرجى الاشتراك للاستمرار.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('حسنًا'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const SubscriptionPage(force: true),
                      ),
                    );
                  },
                  child: const Text('اشترك الآن'),
                ),
              ],
            );
          },
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return widget.child;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        final data = snap.data?.data();

        //  إذا كان عندك بيانات اشتراك خاطئة قديمة مكتوبة بـ FALLBACK (بدون شراء حقيقي),
        // نلغيها مرة واحدة حتى لا يعتبرك التطبيق "مشترك" بالغلط.
        if (!_sanitizedRemoteFallback && data != null) {
          _sanitizedRemoteFallback = true;
          try {
            final subAny = data['subscription'];
            if (subAny is Map) {
              final sub = Map<String, dynamic>.from(subAny);
              final source = (sub['source'] ?? '').toString().toUpperCase();
              final isFallback = source.contains('FALLBACK') || source.contains('NO_APP_RECEIPT');
              final exp = SubscriptionEntitlementService.readExpiryFromUserDoc(data);
              final tooFarFuture = exp != null &&
                  exp.isAfter(DateTime.now().add(const Duration(days: 366 * 3))); // أكثر من 3 سنوات = غير منطقي
              if (sub['active'] == true && (isFallback || tooFarFuture)) {
                // لا ننتظر هنا (build)، نخليها بالخلفية.
                Future.microtask(() async {
                  try {
                    await ref.update({
                      'subscription.active': false,
                      'subscription.expiry': FieldValue.delete(),
                      'subscription.productId': FieldValue.delete(),
                      'subscription.source': 'CLIENT_CLEARED_INVALID',
                      'subscription.updatedAt': FieldValue.serverTimestamp(),
                    });
                  } catch (_) {}
                });
              }
            }
          } catch (_) {}
        }

        final remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(data);
        _lastRemoteExpiry = remoteExpiry;

        // ✅ أثناء الإقلاع: لا نقفل ولا نعرض رسالة انتهاء قبل ما يكون عندنا إشارة من (المحلي أو السحابة).
        final checking = !_loadedLocal || (_localExpiry == null && !snap.hasData);
        if (checking) {
          return _EntitlementCheckingOverlay(child: widget.child);
        }

        final now = DateTime.now();
        final effectiveExpiry = _maxDate(remoteExpiry, _localExpiry);
        final active = effectiveExpiry != null && effectiveExpiry.isAfter(now);

        // ✅ جدولة قفل عند الانتهاء
        _scheduleExpiryTimer(effectiveExpiry);
        // ✅ رسالة انتهاء الفترة التجريبية
        _handleExpiryMessageIfNeeded(active: active, ready: true);

        final locked = !active;
        _maybeOpenPaywall(context, locked: locked);

        if (!locked) return widget.child;

        //  مقفل: نعرض الشاشة خلف تغبيش + قائمة صغيرة للاشتراك
        return _LockedAppShell(
          child: widget.child,
          loading: !_loadedLocal,
          expiry: effectiveExpiry,
          onSubscribe: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const SubscriptionPage(force: true),
              ),
            );
          },
        );

      },
    );
  }

  DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

// =========================
// Paywall Block Screen (Official)
// =========================

class _PaywallBlockScreen extends StatelessWidget {
  final bool loading;
  final DateTime? expiry;
  final VoidCallback onSubscribe;

  const _PaywallBlockScreen({
    required this.loading,
    required this.expiry,
    required this.onSubscribe,
  });

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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 64, color: s.primary),
                  const SizedBox(height: 14),
                  Text('يلزم التفعيل للمتابعة', style: t.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'ابدأ تجربة مجانية 3 أيام أو اشترك بالخطة الشهرية أو السنوية.',
                    style: t.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  if (loading) ...[
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onSubscribe,
                      child: const Text('الذهاب لصفحة الاشتراك'),
                    ),
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


// =========================
// Locked Shell (Overlay)
// =========================



class _EntitlementCheckingOverlay extends StatelessWidget {
  final Widget child;

  const _EntitlementCheckingOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
            child: Container(
              color: s.surface.withOpacity(0.28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: s.surface.withOpacity(0.94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: s.outlineVariant.withOpacity(0.25)),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, 10),
                            color: Colors.black.withOpacity(0.10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            'جاري التحقق من الاشتراك…',
                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'لحظات فقط',
                            style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockedAppShell extends StatelessWidget {
  final Widget child;
  final VoidCallback onSubscribe;
  final DateTime? expiry;
  final bool loading;

  const _LockedAppShell({
    required this.child,
    required this.onSubscribe,
    required this.expiry,
    required this.loading,
  });

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    return '$day/$mon/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Stack(
      children: [
        // الخلفية (التطبيق) - مقفول بالكامل
        AbsorbPointer(absorbing: true, child: child),

        // Blur خفيف + غشاء لطيف (بدون أي أقفال بالخلف)
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    s.surface.withOpacity(0.10),
                    s.primary.withOpacity(0.10),
                    s.secondary.withOpacity(0.08),
                    Colors.black.withOpacity(0.22),
                  ],
                  stops: const [0.0, 0.45, 0.75, 1.0],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),

        // بطاقة وسطية فخمة (Glass)
        Positioned.fill(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            s.surface.withOpacity(0.90),
                            s.surface.withOpacity(0.74),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.20),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  s.primary.withOpacity(0.25),
                                  s.secondary.withOpacity(0.18),
                                ],
                              ),
                            ),
                            child: Icon(Icons.workspace_premium_rounded, color: s.primary, size: 30),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'الاشتراك مطلوب',
                            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'قبل استخدام التطبيق، يلزم الاشتراك.\nاختر باقة شهرية أو سنوية—وسيتم تفعيل تجربة 3 أيام مجانًا من المتجر (حسب الأهلية).',
                            style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          if (loading)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text('جاري التحقق…', style: t.bodySmall),
                              ],
                            )
                          else
                            Text(
                              'آخر صلاحية: ${_fmt(expiry)}',
                              style: t.bodySmall?.copyWith(color: s.onSurfaceVariant.withOpacity(0.9)),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: onSubscribe,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('الذهاب للاشتراك'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                backgroundColor: s.primary,
                                foregroundColor: s.onPrimary,
                                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'بعد تفعيل الاشتراك ستُفتح جميع الميزات تلقائيًا.',
                            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant.withOpacity(0.85)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =========================
// Locks overlay (paint)
// =========================

class _LocksOverlay extends StatefulWidget {
  final Rect excludeRect;
  const _LocksOverlay({required this.excludeRect});

  @override
  State<_LocksOverlay> createState() => _LocksOverlayState();
}

class _LocksOverlayState extends State<_LocksOverlay> {
  SemanticsHandle? _semanticsHandle;
  List<Rect> _tappableRects = const <Rect>[];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // ✅ نجبر بناء شجرة الـ Semantics حتى نقدر نحدد أماكن العناصر.
    _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
    _scheduleCollect();
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _scheduleCollect());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _semanticsHandle?.dispose();
    super.dispose();
  }

  void _scheduleCollect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _collectRects();
    });
  }

  void _collectRects() {
    final owner = RendererBinding.instance.pipelineOwner.semanticsOwner;
    final root = owner?.rootSemanticsNode;
    if (root == null) {
      // fallback: grid locks
      if (_tappableRects.isNotEmpty) setState(() => _tappableRects = const <Rect>[]);
      return;
    }

    final rects = <Rect>[];

    // ⚠️ ملاحظة توافق: واجهة SemanticsNode تختلف بين نسخ Flutter.
    // بعض الخصائص/الدوال (مثل hasAction / childrenInTraversalOrder) ليست موجودة في كل الإصدارات.
    // لذلك نستخدم dynamic مع محاولات متعددة ثم نرجع لبديل "شبكة الأقفال" إذا ما قدرنا نجمع أماكن العناصر.
    bool _nodeHasAction(SemanticsNode n, SemanticsAction a) {
      final dn = n as dynamic;
      // 1) Flutter جديد: hasAction
      try {
        final r = dn.hasAction(a);
        if (r is bool) return r;
      } catch (_) {}

      // 2) بعض الإصدارات: getSemanticsData().actions (bitmask)
      try {
        final data = dn.getSemanticsData();
        final actions = (data as dynamic).actions;
        if (actions is int) {
          final mask = 1 << a.index;
          return (actions & mask) != 0;
        }
        if (actions is Set<SemanticsAction>) {
          return actions.contains(a);
        }
      } catch (_) {}

      // 3) بعض الإصدارات: actions كـ bitmask أو Set
      try {
        final actions = dn.actions;
        if (actions is int) {
          final mask = 1 << a.index;
          return (actions & mask) != 0;
        }
        if (actions is Set<SemanticsAction>) {
          return actions.contains(a);
        }
      } catch (_) {}

      return false;
    }

    Iterable<SemanticsNode> _nodeChildren(SemanticsNode n) {
      final dn = n as dynamic;
      try {
        final kids = dn.childrenInTraversalOrder;
        if (kids is Iterable<SemanticsNode>) return kids;
      } catch (_) {}
      try {
        final kids = dn.children;
        if (kids is Iterable<SemanticsNode>) return kids;
      } catch (_) {}
      return const <SemanticsNode>[];
    }

    void walk(SemanticsNode n) {
      final hasTap = _nodeHasAction(n, SemanticsAction.tap) || _nodeHasAction(n, SemanticsAction.longPress);
      if (hasTap) {
        final r = n.rect;
        if (r.width >= 28 && r.height >= 28) {
          rects.add(r);
        }
      }
      for (final c in _nodeChildren(n)) {
        walk(c);
      }
    }

    walk(root);

    // تقليل العدد لمنع الثقل.
    // نأخذ عينة ثابتة.
    const maxRects = 90;
    List<Rect> sampled;
    if (rects.length <= maxRects) {
      sampled = rects;
    } else {
      final step = (rects.length / maxRects).ceil();
      sampled = <Rect>[];
      for (int i = 0; i < rects.length; i += step) {
        sampled.add(rects[i]);
        if (sampled.length >= maxRects) break;
      }
    }

    // لا نحدث state إذا ما تغيّر شيء لتقليل rebuild.
    if (!listEquals(sampled, _tappableRects)) {
      setState(() => _tappableRects = sampled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: CustomPaint(
        painter: _LocksPainter(
          tappableRects: _tappableRects,
          excludeRect: widget.excludeRect,
          color: s.onSurface.withOpacity(0.22),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LocksPainter extends CustomPainter {
  final List<Rect> tappableRects;
  final Rect excludeRect;
  final Color color;

  _LocksPainter({
    required this.tappableRects,
    required this.excludeRect,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final icon = Icons.lock_rounded;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    // إذا ما عندنا tappables (semantics غير متاحة) نرسم شبكة أقفال.
    if (tappableRects.isEmpty) {
      const spacing = 70.0;
      for (double y = 24; y < size.height; y += spacing) {
        for (double x = 24; x < size.width; x += spacing) {
          final p = Offset(x, y);
          if (excludeRect.contains(p)) continue;
          _paintLock(tp, canvas, p, 18);
        }
      }
      return;
    }

    for (final r in tappableRects) {
      final c = r.center;
      if (excludeRect.contains(c)) continue;
      // قص داخل الشاشة
      if (c.dx < 0 || c.dy < 0 || c.dx > size.width || c.dy > size.height) continue;
      _paintLock(tp, canvas, c, 18);
    }
  }

  void _paintLock(TextPainter tp, Canvas canvas, Offset center, double fontSize) {
    final icon = Icons.lock_rounded;
    tp.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: fontSize,
        color: color,
      ),
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LocksPainter oldDelegate) {
    return oldDelegate.tappableRects != tappableRects || oldDelegate.excludeRect != excludeRect || oldDelegate.color != color;
  }
}

// =========================
// Subscription Page (Paywall)
// =========================

enum _PaywallNoticeKind { success, info, warning, error }

class SubscriptionPage extends StatefulWidget {
  /// إذا true: يمنع الرجوع ويُعتبر "إجباري"
  final bool force;
  const SubscriptionPage({super.key, this.force = false});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  // IDs الأساسية (لا تغيّرها)
  static const String _kMonthlyId = 'vip_monthly1';
  static const String _kYearlyId = 'vip_yearly1';

  // ربط اشتراكات Apple بالمستخدم (App Account Token)
  static final Uuid _uuid = Uuid();
  String? _appAccountToken;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  bool _storeAvailable = false;
  bool _busy = false;

  bool _productsLoading = true;
  String? _productsError;
  List<String> _notFoundIds = const [];

  ProductDetails? _monthly;
  ProductDetails? _yearly;

  // Discount products (optional)
  ProductDetails? _monthlyDiscount;
  ProductDetails? _yearlyDiscount;
  int _activeCouponPct = 0;
  String? _activeCouponCode;
  String? _couponMsg;
  final TextEditingController _couponCtrl = TextEditingController();

  // Status
  DateTime? _start;
  DateTime? _expiry;
  String? _activeProductId;

  // UI (Notices + Processing overlay)
  _PaywallNoticeKind? _noticeKind;
  String? _noticeTitle;
  String? _noticeSubtitle;
  Timer? _noticeTimer;

  String _busyLabel = 'جاري المعالجة…';
  String? _busyHint;

  bool _restoreInFlight = false;
  Timer? _restoreTimeout;


  // لمنع تفعيل اشتراكات 'restored' تلقائياً عند فتح الصفحة (بدون شراء فعلي)
  DateTime? _purchaseInitiatedAt;
  DateTime? _restoreRequestedAt;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _userDocSub?.cancel();
    _noticeTimer?.cancel();
    _restoreTimeout?.cancel();
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadCachedStatus();
    await _ensureAppAccountToken();
    _startUserDocListener();
    await _initIAP();
    await _loadCouponFromPrefs();
  }

  Future<void> _loadCachedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      final email = prefs.getString('currentEmail') ?? (user?.email ?? 'unknown_user');

      final expUid = uid.isNotEmpty ? prefs.getInt('subscriptionExpiry_uid_$uid') : null;
      final expEmail = prefs.getInt('subscriptionExpiry_$email');
      final startUid = uid.isNotEmpty ? prefs.getInt('subscriptionStart_uid_$uid') : null;
      final startEmail = prefs.getInt('subscriptionStart_$email');

      final useUid = (expUid != null && (expEmail == null || expUid > expEmail));
      final bestMs = useUid ? expUid : expEmail;
      final bestStartMs = useUid ? startUid : startEmail;

      final pidUid = uid.isNotEmpty ? prefs.getString('subscriptionProductId_uid_$uid') : null;
      final pidEmail = prefs.getString('subscriptionProductId_$email');
      final pid = pidUid ?? pidEmail;


      setState(() {
        _start = bestStartMs != null ? DateTime.fromMillisecondsSinceEpoch(bestStartMs) : null;
        _expiry = bestMs != null ? DateTime.fromMillisecondsSinceEpoch(bestMs) : null;
        _activeProductId = pid;

      });
    } catch (_) {}
  }

  Future<void> _ensureAppAccountToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'appAccountToken_uid_${user.uid}';

      // 1) من الكاش
      final cached = prefs.getString(key);
      if (cached != null && cached.trim().isNotEmpty) {
        _appAccountToken = cached.trim();
        return;
      }

      // 2) من Firestore
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final data = snap.data();
      final remote = (data?['appAccountToken'] ?? '').toString().trim();
      if (remote.isNotEmpty) {
        _appAccountToken = remote;
        await prefs.setString(key, remote);
        return;
      }

      // 3) توليد UUID جديد
      final token = _uuid.v4();
      _appAccountToken = token;

      await ref.set({'appAccountToken': token}, SetOptions(merge: true));
      await prefs.setString(key, token);
    } catch (_) {
      // لا نكسر الصفحة
    }
  }



  void _startUserDocListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snap) {
        final data = snap.data();
        if (data == null) return;

        final remoteExpiry = SubscriptionEntitlementService.readExpiryFromUserDoc(data);
        final remoteStart = SubscriptionEntitlementService.readStartFromUserDoc(data);
        final remotePid = SubscriptionEntitlementService.readProductIdFromUserDoc(data);

        if (!mounted) return;
        setState(() {
          if (remoteStart != null) _start = remoteStart;
          if (remoteExpiry != null) _expiry = remoteExpiry;
          if ((remotePid ?? '').isNotEmpty) _activeProductId = remotePid;

        });
      },
      onError: (_) {},
    );
  }


  Future<void> _initIAP() async {
    if (mounted) {
      setState(() {
        _productsLoading = true;
        _productsError = null;
        _notFoundIds = const [];
      });
    }

    try {
      final available = await _iap.isAvailable();
      if (!mounted) return;

      setState(() => _storeAvailable = available);

      if (!available) {
        setState(() {
          _productsLoading = false;
          _productsError =
              'المتجر غير متاح حاليًا. تأكد من الاتصال بالإنترنت وتسجيل الدخول إلى App Store / ثم حاول مرة أخرى.';
        });
        return;
      }

      // base products
      final resp = await _iap.queryProductDetails({_kMonthlyId, _kYearlyId});
      if (!mounted) return;

      if (resp.error != null) {
        setState(() {
          _productsLoading = false;
          _productsError = 'تعذّر جلب الباقات من المتجر: ${resp.error}';
          _notFoundIds = resp.notFoundIDs;
        });
        return;
      }

      // إعادة تعيين قبل التحديث
      _monthly = null;
      _yearly = null;

      for (final p in resp.productDetails) {
        if (p.id == _kMonthlyId) _monthly = p;
        if (p.id == _kYearlyId) _yearly = p;
      }

      // إذا لم نجد أي باقة، غالبًا الـ IDs غير موجودة/غير مفعّلة في المتجر
      if (_monthly == null && _yearly == null) {
        setState(() {
          _productsLoading = false;
          _productsError =
              '''لم يتم العثور على باقات الاشتراك في المتجر. تأكد من تفعيل Product IDs التالية في App Store Connect  ثم أعد المحاولة:
• $_kMonthlyId
• $_kYearlyId''';
          _notFoundIds = resp.notFoundIDs;
        });
        return;
      }

      _sub?.cancel();
      _sub = _iap.purchaseStream.listen(_onPurchaseUpdated, onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ بالمتجر: $e')));
        }
      });

      setState(() {
        _productsLoading = false;
        _productsError = null;
        _notFoundIds = resp.notFoundIDs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _productsLoading = false;
        _productsError = 'حدث خطأ أثناء تهيئة المتجر: $e';
      });
    }
  }

  // -----------------
  // Coupon
  // -----------------

  static const Map<String, int> _localCoupons = {
    'wazen10': 10,
    'wazen15': 15,
    'wazen20': 20,
    'wazen25': 25,
    'wazen30': 30,
    // أمثلة إضافية شائعة (تأكد من وجود باقات الخصم في المتجر بنفس النسبة)
    'wazen35': 35,
    'wazen40': 40,
    'wazen45': 45,
    'wazen50': 50,
  };

  String _discountId(String baseId, int pct) => '${baseId}_$pct';

  Future<void> _loadCouponFromPrefs() async {
    // على iOS سيتم استخدام Offer Codes من App Store (Redeem Special Offer)
    // لذلك لا نعرض/نحمّل كوبونات داخلية هنا لتجنب اللبس.
    if (Platform.isIOS) return;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    final code = (prefs.getString('couponCode_$email') ?? '').trim();
    final pct = (prefs.getInt('couponPct_$email') ?? 0).clamp(0, 95);
    if (code.isNotEmpty && pct > 0) {
      _couponCtrl.text = code;
      _activeCouponCode = code;
      _activeCouponPct = pct;
      // نحاول تحميل منتجات الخصم
      await _loadDiscountProducts(pct);
    }
    if (mounted) setState(() {});
  }

  Future<void> _persistCoupon() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    if ((_activeCouponCode ?? '').trim().isEmpty || _activeCouponPct <= 0) {
      await prefs.remove('couponCode_$email');
      await prefs.remove('couponPct_$email');
      return;
    }
    await prefs.setString('couponCode_$email', _activeCouponCode!.trim());
    await prefs.setInt('couponPct_$email', _activeCouponPct);
  }

  Future<int?> _fetchCouponPctRemote(String code) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('coupons').doc(code).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      final active = data['active'];
      if (active is bool && active == false) return null;
      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) return null;

      final pct = data['pct'];
      if (pct is int) return pct;
      if (pct is num) return pct.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyCoupon() async {
    // iOS: الخصومات الحقيقية عبر Offer Codes داخل App Store
    if (Platform.isIOS) {
      await _presentOfferCodeRedemptionSheet();
      return;
    }
    if (!_storeAvailable) {
      setState(() => _couponMsg = 'المتجر غير متاح حاليًا');
      return;
    }

    final raw = _couponCtrl.text.trim();
    if (raw.isEmpty) {
      _clearCoupon();
      return;
    }

    final code = raw.toLowerCase();
    final displayCode = raw.toUpperCase();
    int? pct = _localCoupons[code] ?? _localCoupons[displayCode];
    pct ??= await _fetchCouponPctRemote(code);
    pct ??= await _fetchCouponPctRemote(displayCode);

    if (pct == null || pct <= 0 || pct >= 95) {
      setState(() {
        _activeCouponCode = null;
        _activeCouponPct = 0;
        _monthlyDiscount = null;
        _yearlyDiscount = null;
        _couponMsg = 'الكوبون غير صالح';
      });
      await _persistCoupon();
      return;
    }

    // حمّل منتجات الخصم (لا يمكن خصم سعر نفس المنتج)
    final ok = await _loadDiscountProducts(pct);
    if (!ok) {
      setState(() {
        _activeCouponCode = null;
        _activeCouponPct = 0;
        _monthlyDiscount = null;
        _yearlyDiscount = null;
        _couponMsg = 'هذا الكوبون يتطلب تفعيل باقات الخصم في المتجر مثل ${_kMonthlyId}_$pct و ${_kYearlyId}_$pct';
      });
      await _persistCoupon();
      return;
    }

    setState(() {
      _activeCouponCode = displayCode;
      _activeCouponPct = pct!;
      _couponMsg = 'تم تطبيق خصم $pct% — سيتم احتساب السعر المخفّض من المتجر.';
    });
    await _persistCoupon();
  }

  void _clearCoupon() {
    setState(() {
      _activeCouponCode = null;
      _activeCouponPct = 0;
      _monthlyDiscount = null;
      _yearlyDiscount = null;
      _couponMsg = null;
      _couponCtrl.text = '';
    });
    _persistCoupon();
  }

  Future<bool> _loadDiscountProducts(int pct) async {
    final ids = <String>{_discountId(_kMonthlyId, pct), _discountId(_kYearlyId, pct)};
    final resp = await _iap.queryProductDetails(ids);
    if (resp.error != null) return false;
    ProductDetails? m;
    ProductDetails? y;
    for (final p in resp.productDetails) {
      if (p.id == _discountId(_kMonthlyId, pct)) m = p;
      if (p.id == _discountId(_kYearlyId, pct)) y = p;
    }
    // نعتبره OK إذا وجدنا واحد على الأقل (شهري/سنوي)
    if (m == null && y == null) return false;
    setState(() {
      _monthlyDiscount = m;
      _yearlyDiscount = y;
    });
    return true;
  }

  
  // -----------------
  // Offer Codes (iOS)
  // -----------------
  //
  // لعمل خصم "حقيقي" على السعر داخل App Store:
  // 1) فعّل Offer Codes للاشتراك من App Store Connect.
  // 2) استخدم الزر بالأسفل لفتح صفحة النظام (Redeem Special Offer).
  //
  // ملاحظة: لا يمكن تغيير السعر برمجيًا. الخصم يتم تطبيقه من المتجر نفسه.

  static const MethodChannel _offerCodeChannel = MethodChannel('wazen_iap/offer_code');

  Future<void> _presentOfferCodeRedemptionSheet() async {
    if (!Platform.isIOS) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إدخال كود الخصم عبر المتجر متاح على iOS فقط.')),
      );
      return;
    }

    try {
      await _offerCodeChannel.invokeMethod('presentCodeRedemptionSheet');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم فتح صفحة إدخال كود العرض من App Store.')),
      );
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ميزة كود الخصم تحتاج تفعيل بسيط على iOS (AppDelegate). راجع التعليمات المرفقة.'),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FriendlyErrors.message(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح صفحة إدخال كود الخصم: $e')),
      );
    }
  }

// -----------------
  // Purchase
  // -----------------

  ProductDetails? _productForPlan(_Plan plan) {
    if (_activeCouponPct > 0) {
      return plan == _Plan.monthly ? (_monthlyDiscount ?? _monthly) : (_yearlyDiscount ?? _yearly);
    }
    return plan == _Plan.monthly ? _monthly : _yearly;
  }

  Future<void> _buyPlan(_Plan plan) async {
    if (_isActive) {
      _setNotice(
        _PaywallNoticeKind.info,
        'اشتراكك مفعل حاليًا',
        subtitle: 'إذا رغبت بتغيير الخطة، سيعالج المتجر ذلك تلقائيًا (حسب سياسات المتجر).',
        autoHide: const Duration(seconds: 6),
      );
    }

    _busyLabel = 'جاري فتح المتجر…';
    _busyHint = 'أكمل الدفع من App Store ';

    if (!_storeAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المتجر غير متاح حاليًا')));
      }
      return;
    }
    if (_productsLoading) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري تحميل الباقات… حاول بعد ثوانٍ')));
      }
      return;
    }
    if (_productsError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_productsError!)));
      }
      return;
    }

    final product = _productForPlan(plan);
    if (product == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('هذه الباقة غير متاحة حاليًا — أعد تحميل الباقات ثم جرّب مرة أخرى')));
      }
      return;
    }

    setState(() => _busy = true);
    _setNotice(_PaywallNoticeKind.info, 'جاري بدء عملية الاشتراك…', subtitle: 'قد تظهر نافذة المتجر الآن.');
    _purchaseInitiatedAt = DateTime.now();
    try {
      // ✅ Android subscriptions (new Google Play model) may require an offerToken.
      // The in_app_purchase_android implementation will pass the offerToken to Billing.
      final PurchaseParam param;
      if (defaultTargetPlatform == TargetPlatform.android) {
        String? offerToken;
        if (product is iap_android.GooglePlayProductDetails) {
          offerToken = product.offerToken;
        }
        param = iap_android.GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: offerToken,
        );
      } else {
        param = PurchaseParam(productDetails: product, applicationUserName: _appAccountToken ?? FirebaseAuth.instance.currentUser?.uid);
      }

      final started = await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر بدء عملية الشراء من المتجر')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر بدء الشراء: $e')));
        setState(() => _busy = false);
      }
    }
  }

Future<void> _restore() async {
  // UI فقط: نظهر تغبيش كامل وننتظر نتيجة الاستعادة بدل ما يختفي المؤشر فوراً.
  _busyLabel = 'جاري استعادة المشتريات…';
  _busyHint = 'قد تستغرق العملية عدة ثوانٍ';

  _restoreTimeout?.cancel();
  _restoreInFlight = true;
  _restoreRequestedAt = DateTime.now();

  if (mounted) {
    setState(() => _busy = true);
  }
  _setNotice(
    _PaywallNoticeKind.info,
    'جاري استعادة مشترياتك…',
    subtitle: 'إذا كنت مشتركًا سابقًا سيتم تفعيل اشتراكك تلقائيًا.',
    autoHide: const Duration(seconds: 6),
  );

  // إذا لم يصل أي restored خلال فترة معقولة نعرض رسالة واضحة.
  _restoreTimeout = Timer(const Duration(seconds: 10), () {
    if (!mounted) return;
    if (_restoreInFlight && !_isActive) {
      _restoreInFlight = false;
      setState(() => _busy = false);
      _setNotice(
        _PaywallNoticeKind.warning,
        'لم يتم العثور على مشتريات لاستعادتها',
        subtitle: 'تأكد أنك تستخدم نفس حساب المتجر الذي اشتركت منه سابقًا ثم جرّب مرة أخرى.',
        autoHide: const Duration(seconds: 8),
      );
    }
  });

  try {
    await _iap.restorePurchases();
    // ننتظر تحديثات stream — لا نطفئ busy هنا.
  } catch (e) {
    _restoreInFlight = false;
    _restoreTimeout?.cancel();
    if (mounted) {
      setState(() => _busy = false);
      _setNotice(_PaywallNoticeKind.error, 'تعذّرت الاستعادة', subtitle: '$e');
    }
  }
}

Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
for (final p in purchases) {
  if (p.status == PurchaseStatus.pending) {
    _busyLabel = 'بانتظار تأكيد المتجر…';
    _busyHint = 'لا تغلق التطبيق أثناء إتمام العملية';
    if (mounted) setState(() => _busy = true);
    _setNotice(
      _PaywallNoticeKind.info,
      'بانتظار تأكيد المتجر…',
      subtitle: 'أكمل العملية من نافذة المتجر ثم ارجع للتطبيق.',
      autoHide: const Duration(seconds: 6),
    );
    continue;
  }

  if (mounted) setState(() => _busy = false);

  if (p.status == PurchaseStatus.error) {
    _restoreInFlight = false;
    _restoreTimeout?.cancel();
    if (mounted) {
      _setNotice(_PaywallNoticeKind.error, 'فشلت العملية', subtitle: '${p.error}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل العملية: ${p.error}')));
    }
    continue;
  }
      if (p.status == PurchaseStatus.canceled) {
        _restoreInFlight = false;
        _restoreTimeout?.cancel();
        _setNotice(
          _PaywallNoticeKind.warning,
          'تم إلغاء العملية',
          subtitle: 'لم يتم إجراء أي تغيير على اشتراكك.',
          autoHide: const Duration(seconds: 6),
        );
        continue;
      }

      //  على iOS قد يصل حدث "restored" تلقائياً عند فتح صفحة الاشتراك بسبب مزامنة المتجر،
      // ولا نريد اعتباره اشتراكاً جديداً أو نكتب بيانات في Firestore إلا إذا المستخدم ضغط "اشترك" أو "استعادة".
      final now = DateTime.now();
      final purchaseInitiatedRecently =
          _purchaseInitiatedAt != null && now.difference(_purchaseInitiatedAt!).inMinutes < 5;
      final restoreRequestedRecently =
          _restoreRequestedAt != null && now.difference(_restoreRequestedAt!).inMinutes < 5;

      if (p.status == PurchaseStatus.restored && !(purchaseInitiatedRecently || restoreRequestedRecently)) {
        // تجاهل restored التلقائي (بدون إجراء من المستخدم).
        continue;
      }



      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        _purchaseInitiatedAt = null;
        _restoreRequestedAt = null;
        // ✅ حدّث الاشتراك (يشمل Trial) من الإيصال/المتجر
        final ent = await SubscriptionEntitlementService.refreshAndSyncForCurrentUser(fromPurchase: p);

        // ملاحظة: على بعض إصدارات Dart/Flutter قد لا تتم ترقية (promotion) المتغيرات القابلة للـ null
        // بالشكل المتوقع داخل شروط مركّبة. لذلك نفصل القيم هنا لضمان توافق تام.
        final expiry = ent?.expiry;
        final productId = ent?.productId;

if (expiry != null) {
  _restoreInFlight = false;
  _restoreTimeout?.cancel();

  if (!mounted) return;
  setState(() {
    _start = ent?.start;
    _expiry = expiry;
    _activeProductId = productId;
  });

  final isRestore = (p.status == PurchaseStatus.restored);
  final title = isRestore ? 'تمت استعادة اشتراكك بنجاح ✅' : 'تم تفعيل اشتراكك بنجاح ✅';
  final subtitle = 'الخطة: ${_planLabel(productId)} • ينتهي: ${_fmt(expiry)}';

  _setNotice(_PaywallNoticeKind.success, title, subtitle: subtitle, autoHide: const Duration(seconds: 6));

  // ✅ بعد نجاح التفعيل (بما في ذلك بدء Trial) نقفل صفحة الاشتراك تلقائيًا.
  // نعطي المستخدم لحظة قصيرة ليشوف رسالة النجاح.
  if (expiry.isAfter(DateTime.now())) {
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }
} else {
  _restoreInFlight = false;
  _restoreTimeout?.cancel();
  if (mounted) {
    _setNotice(
      _PaywallNoticeKind.error,
      'تمت العملية لكن لم يتم تفعيل الاشتراك',
      subtitle: 'جرّب "استعادة المشتريات" وتأكد من إعدادات Shared Secret في iOS.',
      autoHide: const Duration(seconds: 9),
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('تمت عملية الشراء، لكن لم نتمكن من تفعيل الاشتراك. جرّب "استعادة المشتريات" وتأكد من إعدادات Shared Secret في iOS.'),
    ));
  }
}
      }

      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  bool get _isActive => _expiry != null && _expiry!.isAfter(DateTime.now());

  void _setNotice(_PaywallNoticeKind kind, String title, {String? subtitle, Duration? autoHide}) {
    _noticeTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _noticeKind = kind;
      _noticeTitle = title;
      _noticeSubtitle = subtitle;
    });

    final d = autoHide ??
        (kind == _PaywallNoticeKind.error
            ? const Duration(seconds: 8)
            : (kind == _PaywallNoticeKind.warning ? const Duration(seconds: 7) : const Duration(seconds: 5)));

    _noticeTimer = Timer(d, () {
      if (!mounted) return;
      setState(() {
        _noticeKind = null;
        _noticeTitle = null;
        _noticeSubtitle = null;
      });
    });
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _noticeKind = null;
      _noticeTitle = null;
      _noticeSubtitle = null;
    });
  }



  // -----------------
  // UI
  // -----------------

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    return '$day/$mon/${d.year}';
  }

String _planLabel(String? pid) {
  final p = (pid ?? '').toLowerCase();
  if (p.contains('year') || p.contains('سنوي') || p.contains('yearly')) return 'سنوي';
  if (p.contains('month') || p.contains('شهري') || p.contains('monthly')) return 'شهري';
  return (pid == null || pid.trim().isEmpty) ? '—' : pid.trim();
}

  // روابط مهمة (مطابقة لمتطلبات Apple للاشتراكات)
  Future<void> _openExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح الرابط')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح الرابط')),
        );
      }
    }
  }

  void _openPrivacyPolicy() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage()));
  }

  void _openTermsOfUse() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsPage()));
  }


  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final topPad = MediaQuery.of(context).padding.top;

    final canPop = Navigator.of(context).canPop();

    final m = _productForPlan(_Plan.monthly);
    final y = _productForPlan(_Plan.yearly);

    final monthlyHasDiscount = _activeCouponPct > 0 && _monthlyDiscount != null;
    final yearlyHasDiscount = _activeCouponPct > 0 && _yearlyDiscount != null;

    // ملاحظة مهمّة:
    // - عند force=true كنا نمنع أي Pop بالكامل.
    // - لكن بعد نجاح الاشتراك نحتاج أن نسمح بإغلاق الصفحة تلقائيًا.
    // لذلك: نسمح بالخروج إذا كان الاشتراك نشطًا.
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          automaticallyImplyLeading: canPop,
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: s.surface.withOpacity(0.60)),
            ),
          ),
          centerTitle: true,
          title: const Text('اشتراك وازن'),
          leading: canPop
              ? const BackButton()
              : IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.primary.withOpacity(0.22),
                s.surface,
                s.surface,
              ],
            ),
          ),
          child: Stack(
            children: [
              const _PaywallBackgroundDecorations(),
              CustomScrollView(
                slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, topPad + 74, 16, 12),
                  child: _PaywallHeader(
                    active: _isActive,
                    start: _start,
                    expiry: _expiry,
                    activeProductId: _activeProductId,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: (_noticeTitle == null)
                        ? const SizedBox.shrink()
                        : _PaywallNoticeBanner(
                            key: ValueKey('${_noticeKind}_$_noticeTitle'),
                            kind: _noticeKind ?? _PaywallNoticeKind.info,
                            title: _noticeTitle!,
                            subtitle: _noticeSubtitle,
                            onClose: _clearNotice,
                          ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (!_productsLoading && (_productsError != null || !_storeAvailable)) ...[
                        _StoreStatusCardNew(
                          loading: _productsLoading,
                          storeAvailable: _storeAvailable,
                          message: _productsError,
                          notFoundIds: _notFoundIds,
                          onRetry: _busy ? null : _initIAP,
                        ),
                        const SizedBox(height: 12),
                      ],
_PlanCardNew(
                        icon: Icons.calendar_month_rounded,
                        title: 'الخطة الشهرية',
                        subtitle: 'اشتراك شهري يتجدد تلقائيًا\nيشمل تجربة مجانية 3 أيام من المتجر حسب الأهلية',
                        badge: 'مرن',
                        discountLabel: monthlyHasDiscount ? 'خصم $_activeCouponPct%' : null,
                        priceText: m?.price ?? '—',
                        oldPriceText: (_activeCouponPct > 0 && _monthly != null && _monthlyDiscount != null) ? _monthly!.price : null,
                        emphasize: false,
                        disabled: !_storeAvailable || _busy || _productsLoading || _productsError != null || m == null,
                        onPressed: () => _buyPlan(_Plan.monthly),
                      ),
                      const SizedBox(height: 14),
                      _PlanCardNew(
                        icon: Icons.event_available_rounded,
                        title: 'الخطة السنوية',
                        subtitle: 'اشتراك سنوي يتجدد تلقائيًا\nالأفضل لمن يريد الالتزام لفترة أطول',
                        badge: 'أفضل قيمة',
                        discountLabel: yearlyHasDiscount ? 'خصم $_activeCouponPct%' : null,
                        priceText: y?.price ?? '—',
                        oldPriceText: (_activeCouponPct > 0 && _yearly != null && _yearlyDiscount != null) ? _yearly!.price : null,
                        emphasize: true,
                        disabled: !_storeAvailable || _busy || _productsLoading || _productsError != null || y == null,
                        onPressed: () => _buyPlan(_Plan.yearly),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Platform.isIOS
                      ? _RedeemOfferCodeCardNew(
                          onRedeem: _busy ? null : _presentOfferCodeRedemptionSheet,
                          onRefreshStatus: _busy ? null : _restore,
                        )
                      : _CouponCardNew(
                          controller: _couponCtrl,
                          message: _couponMsg,
                          hasCoupon: _activeCouponPct > 0,
                          onApply: _busy ? null : _applyCoupon,
                          onClear: _busy ? null : _clearCoupon,
                        ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: _FeaturesStrip(),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LegalLinksCardNew(
                        onPrivacy: _openPrivacyPolicy,
                        onTerms: _openTermsOfUse,
                        onAppleEula: Platform.isIOS
                            ? () => _openExternalUrl('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')
                            : null,
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _busy ? null : _restore,
                        icon: const Icon(Icons.restore),
                        label: const Text('استعادة المشتريات'),
                      ),
                      const SizedBox(height: 10),
                      _FinePrintNew(
                        lines: [
                          '• التجربة المجانية، عند توفرها، تُدار من App Store أو Google Play حسب أهلية الحساب.',
                          '• بعد انتهاء التجربة أو الاشتراك، يتطلب استخدام المزايا المدفوعة وجود اشتراك نشط.',
                          '• يتم تجديد الاشتراك تلقائيًا ما لم يتم الإلغاء قبل نهاية الفترة.',
                          '• يمكن إدارة الاشتراك أو إلغاؤه من إعدادات الحساب في المتجر.',
                          if (_activeCouponPct > 0)
                            '• الكوبون يطبّق خصم فعلي عبر باقة مخفّضة في المتجر (Product ID مختلف).',
                          if (widget.force) '• لا يمكنك المتابعة بدون تفعيل (تجربة أو اشتراك).',
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
                ],
              ),
              if (_busy) _ProcessingOverlay(label: _busyLabel, hint: _busyHint),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Plan { monthly, yearly }

// =========================
// UI Components
// =========================

class _PaywallHeader extends StatelessWidget {
  final bool active;
  final DateTime? start;
  final DateTime? expiry;
  final String? activeProductId;

  const _PaywallHeader({
    required this.active,
    required this.start,
    required this.expiry,
    required this.activeProductId,
  });

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    return '$day/$mon/${d.year}';
  }

  String _planLabel(String? pid) {
    final p = (pid ?? '').toLowerCase();
    if (p.contains('year') || p.contains('سنوي') || p.contains('yearly')) return 'سنوي';
    if (p.contains('month') || p.contains('شهري') || p.contains('monthly')) return 'شهري';
    return (pid ?? '').trim().isEmpty ? '—' : pid!.trim();
  }

  String _totalDurationLabel(DateTime? st, DateTime? end) {
    if (st == null || end == null) return '—';
    final diff = end.difference(st);
    if (diff.inMinutes <= 0) return '—';
    if (diff.inDays >= 1) return '${diff.inDays} يوم';
    if (diff.inHours >= 1) return '${diff.inHours} ساعة';
    return '${diff.inMinutes} دقيقة';
  }

  String _remainingLabel(DateTime? end) {
    if (end == null) return '—';
    final now = DateTime.now();
    if (!end.isAfter(now)) return 'منتهي';
    final d = end.difference(now);
    if (d.inDays >= 1) return '${d.inDays} يوم';
    if (d.inHours >= 1) return '${d.inHours} ساعة';
    return '${d.inMinutes} دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final startText = _fmt(start);
    final expiryText = _fmt(expiry);
    final planText = _planLabel(activeProductId);
    final durationText = _totalDurationLabel(start, expiry);
    final remainingText = _remainingLabel(expiry);

    Widget stat({required String label, required String value}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: s.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            s.primary.withOpacity(0.22),
            s.secondary.withOpacity(0.14),
            s.surface.withOpacity(0.96),
          ],
        ),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 12)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [s.primary, s.secondary]),
            ),
            child: Icon(
              active ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined,
              color: s.onPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'اشتراكك مفعل' : 'فعّل تجربة وازن الكاملة',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                if (!active) ...[
                  Text(
                    'اختر الخطة المناسبة لك للوصول إلى أدوات التحليل، التتبع، الرجيمات، والمدرب الذكي في تجربة واحدة مرتبة.',
                    style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                  ),
                ] else ...[
                  Text(
                    'تفاصيل اشتراكك الحالي',
                    style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: stat(label: 'تاريخ الاشتراك', value: startText)),
                      const SizedBox(width: 10),
                      Expanded(child: stat(label: 'تاريخ الانتهاء', value: expiryText)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: stat(label: 'مدة الاشتراك', value: durationText)),
                      const SizedBox(width: 10),
                      Expanded(child: stat(label: 'المتبقي', value: remainingText)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _MiniChip(label: 'الخطة: $planText'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  const _MiniChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.outlineVariant.withOpacity(0.6)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _PaywallBackgroundDecorations extends StatelessWidget {
  const _PaywallBackgroundDecorations();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;

    Widget blob({
      required double size,
      required Alignment alignment,
      required List<Color> colors,
      double opacity = 0.24,
    }) {
      return Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.map((c) => c.withOpacity(opacity)).toList(),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        children: [
          blob(
            size: 520,
            alignment: const Alignment(-1.15, -1.05),
            colors: [s.primary, s.secondary],
            opacity: 0.22,
          ),
          blob(
            size: 420,
            alignment: const Alignment(1.25, -0.85),
            colors: [s.tertiary, s.primary],
            opacity: 0.18,
          ),
          blob(
            size: 520,
            alignment: const Alignment(1.10, 1.20),
            colors: [s.secondary, s.primary],
            opacity: 0.14,
          ),
        ],
      ),
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  final String label;
  final String? hint;

  const _ProcessingOverlay({required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Stack(
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: Colors.black.withOpacity(0.16),
              ),
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 22),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: s.surface.withOpacity(0.82),
                  border: Border.all(color: s.outlineVariant.withOpacity(0.6)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                      color: Colors.black.withOpacity(0.18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6)),
                    const SizedBox(height: 12),
                    Text(label, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    if (hint != null && hint!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(hint!, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaywallNoticeBanner extends StatelessWidget {
  final _PaywallNoticeKind kind;
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  const _PaywallNoticeBanner({
    super.key,
    required this.kind,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Color accent;
    IconData icon;
    switch (kind) {
      case _PaywallNoticeKind.success:
        accent = Colors.green;
        icon = Icons.check_circle_rounded;
        break;
      case _PaywallNoticeKind.warning:
        accent = Colors.orange;
        icon = Icons.info_rounded;
        break;
      case _PaywallNoticeKind.error:
        accent = Colors.red;
        icon = Icons.error_rounded;
        break;
      case _PaywallNoticeKind.info:
      default:
        accent = s.primary;
        icon = Icons.auto_awesome_rounded;
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: s.surface.withOpacity(0.78),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.14),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  splashRadius: 18,
                  tooltip: 'إخفاء',
                ),
            ],
          ),
        ),
      ),
    );
  }
}








class _PlanCardNew extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final String? discountLabel;
  final String priceText;
  final String? oldPriceText;
  final bool emphasize;
  final bool disabled;
  final VoidCallback onPressed;

  const _PlanCardNew({
    this.icon = Icons.workspace_premium_rounded,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.discountLabel,
    required this.priceText,
    this.oldPriceText,
    required this.emphasize,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final border = emphasize ? s.primary.withOpacity(0.80) : s.outlineVariant.withOpacity(0.55);
    final glow = emphasize ? s.primary.withOpacity(0.22) : Colors.black.withOpacity(0.10);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                s.surface.withOpacity(0.82),
                (emphasize ? s.primary.withOpacity(0.10) : s.secondary.withOpacity(0.06)),
                s.surface.withOpacity(0.70),
              ],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(color: glow, blurRadius: 26, offset: const Offset(0, 16)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [s.primary, s.secondary]),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                          color: s.primary.withOpacity(0.18),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: s.onPrimary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant, height: 1.2)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: emphasize ? s.primary : s.secondary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: t.bodySmall?.copyWith(color: s.onPrimary, fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (discountLabel != null && discountLabel!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: s.tertiary.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: s.tertiary.withOpacity(0.45)),
                          ),
                          child: Text(
                            discountLabel!,
                            style: t.bodySmall?.copyWith(color: s.onSurface, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(priceText, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  if (oldPriceText != null && oldPriceText!.trim().isNotEmpty)
                    Text(
                      oldPriceText!,
                      style: t.bodyMedium?.copyWith(
                        color: s.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const Spacer(),
                  if (emphasize)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: s.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: s.primary.withOpacity(0.25)),
                      ),
                      child: Text('أفضل قيمة', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: disabled ? null : onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: disabled ? s.surfaceVariant : (emphasize ? s.primary : s.secondary),
                    foregroundColor: disabled ? s.onSurfaceVariant.withOpacity(0.85) : s.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(disabled ? 'غير متاح الآن' : 'اختيار الخطة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RedeemOfferCodeCardNew extends StatelessWidget {
  final VoidCallback? onRedeem;
  final VoidCallback? onRefreshStatus;

  const _RedeemOfferCodeCardNew({
    required this.onRedeem,
    required this.onRefreshStatus,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.primary.withOpacity(0.10),
                  border: Border.all(color: s.primary.withOpacity(0.22)),
                ),
                child: Icon(Icons.confirmation_number_rounded, color: s.primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('كود خصم أو عرض خاص', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('مثال: WAZEN50', style: t.bodySmall?.copyWith(color: s.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'يمكنك استبدال أكواد الخصم والعروض الخاصة من صفحة App Store الرسمية. بعد الاستبدال، حدّث حالة الاشتراك للتأكد من تفعيل العرض.',
            style: t.bodyMedium?.copyWith(height: 1.45, color: s.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRedeem,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('إدخال الكود'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: onRefreshStatus,
                child: const Text('تحديث الحالة'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'على iPhone تتم معالجة أكواد العروض من Apple مباشرة، لذلك قد يظهر السعر النهائي داخل نافذة App Store قبل تأكيد الشراء.',
            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CouponCardNew extends StatelessWidget {
  final TextEditingController controller;
  final String? message;
  final bool hasCoupon;
  final VoidCallback? onApply;
  final VoidCallback? onClear;

  const _CouponCardNew({
    required this.controller,
    required this.message,
    required this.hasCoupon,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final infoColor = hasCoupon ? s.primary : s.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            s.surface,
            s.primary.withOpacity(0.04),
            s.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.primary.withOpacity(0.12),
                ),
                child: Icon(Icons.discount_rounded, color: s.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'كود خصم',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (hasCoupon)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('إزالة'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'أدخل كود الخصم لتفعيل السعر المخفّض من المتجر. مثال: WAZEN50',
            style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),

          // Input pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: s.surface.withOpacity(0.85),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: s.outlineVariant.withOpacity(0.60)),
            ),
            child: Row(
              children: [
                Icon(Icons.tag_rounded, color: s.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onApply?.call(),
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final up = newValue.text.toUpperCase();
                        return newValue.copyWith(
                          text: up,
                          selection: newValue.selection,
                          composing: TextRange.empty,
                        );
                      }),
                    ],
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                    decoration: InputDecoration(
                      hintText: 'WAZEN50',
                      hintStyle: t.titleSmall?.copyWith(
                        color: s.onSurfaceVariant.withOpacity(0.55),
                        letterSpacing: 1.6,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  child: const Text('تطبيق'),
                ),
              ],
            ),
          ),

          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: infoColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: infoColor.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(hasCoupon ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: infoColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message!,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaywallFeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PaywallFeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _PaywallFeatureGroup {
  final String title;
  final List<_PaywallFeatureItem> items;

  const _PaywallFeatureGroup({
    required this.title,
    required this.items,
  });
}

class _FeaturesStrip extends StatelessWidget {
  const _FeaturesStrip();

  static const _groups = <_PaywallFeatureGroup>[
    _PaywallFeatureGroup(
      title: 'تحليل الطعام',
      items: [
        _PaywallFeatureItem(
          icon: Icons.camera_alt_rounded,
          title: 'تحليل الطعام بالتصوير',
          subtitle: 'تقدير السعرات والماكروز من صورة الوجبة.',
        ),
        _PaywallFeatureItem(
          icon: Icons.edit_note_rounded,
          title: 'تحليل الطعام بالنص',
          subtitle: 'اكتب وصف الوجبة واحصل على تحليل منظم.',
        ),
        _PaywallFeatureItem(
          icon: Icons.restaurant_menu_rounded,
          title: 'الأطعمة الجاهزة والمطاعم',
          subtitle: 'اختيارات أسرع للأطعمة المتكررة والوجبات الجاهزة.',
        ),
      ],
    ),
    _PaywallFeatureGroup(
      title: 'التتبع والالتزام',
      items: [
        _PaywallFeatureItem(
          icon: Icons.picture_as_pdf_rounded,
          title: 'تقرير PDF للتقدم',
          subtitle: 'ملخص منظم للوزن، السعرات، الماء، والخطوات.',
        ),
        _PaywallFeatureItem(
          icon: Icons.track_changes_rounded,
          title: 'أنظمة رجيم متعددة',
          subtitle: 'الصيام، الكيتو، اللو كارب، وقليل الدهون.',
        ),
        _PaywallFeatureItem(
          icon: Icons.notifications_active_rounded,
          title: 'تنبيهات قابلة للتخصيص',
          subtitle: 'تذكيرات للماء، الوزن، الأكل، والتمرين.',
        ),
      ],
    ),
    _PaywallFeatureGroup(
      title: 'الإرشاد والمحتوى',
      items: [
        _PaywallFeatureItem(
          icon: Icons.smart_toy_rounded,
          title: 'مدرب وازن الذكي',
          subtitle: 'توجيهات يومية مبنية على بياناتك وسلوكك.',
        ),
        _PaywallFeatureItem(
          icon: Icons.fitness_center_rounded,
          title: 'النادي الافتراضي',
          subtitle: 'تمارين وفيديوهات مرتبة حسب العضلة.',
        ),
        _PaywallFeatureItem(
          icon: Icons.menu_book_rounded,
          title: 'الوصفات الصحية',
          subtitle: 'وصفات مع مكونات وخطوات وماكروز واضحة.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget featureTile(_PaywallFeatureItem item) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: s.surfaceVariant.withOpacity(0.22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: s.outlineVariant.withOpacity(0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.primary.withOpacity(0.10),
                border: Border.all(color: s.primary.withOpacity(0.22)),
              ),
              child: Icon(item.icon, color: s.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.primary.withOpacity(0.10),
                  border: Border.all(color: s.primary.withOpacity(0.22)),
                ),
                child: Icon(Icons.verified_rounded, color: s.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مميزات الاشتراك', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('كل أدوات وازن المتقدمة مرتبة حسب الاستخدام', style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (int g = 0; g < _groups.length; g++) ...[
            Text(
              _groups[g].title,
              style: t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: s.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _groups[g].items.length; i++) ...[
              featureTile(_groups[g].items[i]),
              if (i != _groups[g].items.length - 1) const SizedBox(height: 8),
            ],
            if (g != _groups.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _StoreStatusCardNew extends StatelessWidget {
  final bool loading;
  final bool storeAvailable;
  final String? message;
  final List<String> notFoundIds;
  final VoidCallback? onRetry;

  const _StoreStatusCardNew({
    required this.loading,
    required this.storeAvailable,
    required this.message,
    required this.notFoundIds,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    // ملاحظة: المستخدم طلب عدم إظهار حالة "جاري التحميل" عند فتح الصفحة.
    // لذلك نعرض هذه البطاقة فقط عند وجود مشكلة واضحة (المتجر غير متاح / خطأ).
    final show = !storeAvailable || (message != null && message!.trim().isNotEmpty);
    if (!show) return const SizedBox.shrink();

    final title = !storeAvailable ? 'المتجر غير متاح' : 'تعذّر تحميل الباقات';
    final msg = !storeAvailable
        ? 'تأكد من الاتصال بالإنترنت وتسجيل الدخول إلى App Store / Google Play ثم أعد المحاولة.'
        : (message?.trim().isNotEmpty == true ? message!.trim() : 'تحقق من إعدادات المتجر ثم أعد المحاولة.');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            !storeAvailable ? Icons.wifi_off_rounded : Icons.info_outline_rounded,
            color: !storeAvailable ? s.error : s.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(msg, style: t.bodySmall),
                if (notFoundIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Not Found IDs: ${notFoundIds.join(', ')}',
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLinksCardNew extends StatelessWidget {
  final VoidCallback onPrivacy;
  final VoidCallback onTerms;
  final VoidCallback? onAppleEula;

  const _LegalLinksCardNew({
    required this.onPrivacy,
    required this.onTerms,
    this.onAppleEula,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: s.primary),
              const SizedBox(width: 8),
              Text('الخصوصية والشروط', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'قبل الاشتراك، راجع سياسة الخصوصية والشروط والأحكام. بإتمام عملية الشراء أنت توافق عليها.',
            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant, height: 1.3),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onPrivacy,
                icon: const Icon(Icons.privacy_tip_outlined),
                label: const Text('سياسة الخصوصية'),
              ),
              OutlinedButton.icon(
                onPressed: onTerms,
                icon: const Icon(Icons.gavel_outlined),
                label: const Text('الشروط والأحكام'),
              ),
              if (onAppleEula != null)
                OutlinedButton.icon(
                  onPressed: onAppleEula,
                  icon: const Icon(Icons.link),
                  label: const Text('EULA (Apple)'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinePrintNew extends StatelessWidget {
  final List<String> lines;
  const _FinePrintNew({required this.lines});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

// =========================
// Service (Verify + Sync)
// =========================

class SubscriptionEntitlement {
  final DateTime? start;
  final DateTime? expiry;
  final String? productId;
  const SubscriptionEntitlement({required this.start, required this.expiry, required this.productId});
}

class SubscriptionEntitlementService {

  static DateTime? readExpiryFromUserDoc(Map<String, dynamic>? data) {
    final subscriptionExpiry = _readSubscriptionExpiry(data);
    final ownerGrantExpiry = _readOwnerGrantExpiry(data);
    return _maxDate(subscriptionExpiry, ownerGrantExpiry);
  }

  static DateTime? readStartFromUserDoc(Map<String, dynamic>? data) {
    final subscriptionExpiry = _readSubscriptionExpiry(data);
    final ownerGrantExpiry = _readOwnerGrantExpiry(data);

    if (_isSameMoment(ownerGrantExpiry, readExpiryFromUserDoc(data))) {
      return _readOwnerGrantStart(data) ?? ownerGrantExpiry;
    }

    if (_isSameMoment(subscriptionExpiry, readExpiryFromUserDoc(data))) {
      return _readSubscriptionStart(data) ?? subscriptionExpiry;
    }

    return _readOwnerGrantStart(data) ?? _readSubscriptionStart(data);
  }

  static String? readProductIdFromUserDoc(Map<String, dynamic>? data) {
    final ownerGrantExpiry = _readOwnerGrantExpiry(data);

    if (_isSameMoment(ownerGrantExpiry, readExpiryFromUserDoc(data))) {
      final grantAny = data?['ownerGrant'];
      final grant = (grantAny is Map) ? Map<String, dynamic>.from(grantAny) : null;
      final planKey = (grant?['planKey'] ?? '').toString().trim();
      if (planKey.isNotEmpty) return planKey;
      return 'owner_free';
    }

    final subAny = data?['subscription'];
    final sub = (subAny is Map) ? Map<String, dynamic>.from(subAny) : null;

    final source = (sub?['source'] ?? '').toString().toUpperCase();
    if (source.contains('FALLBACK') || source.contains('NO_APP_RECEIPT')) return null;

    final pid = sub?['productId'];
    return (pid is String && pid.trim().isNotEmpty) ? pid.trim() : null;
  }

  static DateTime? _readSubscriptionExpiry(Map<String, dynamic>? data) {
    final subAny = data?['subscription'];
    final sub = (subAny is Map) ? Map<String, dynamic>.from(subAny) : null;

    final source = (sub?['source'] ?? '').toString().toUpperCase();
    if (source.contains('FALLBACK') || source.contains('NO_APP_RECEIPT')) return null;

    return _coerceDate(sub?['expiry'], alt: sub?['expiryMillis']);
  }

  static DateTime? _readSubscriptionStart(Map<String, dynamic>? data) {
    final subAny = data?['subscription'];
    final sub = (subAny is Map) ? Map<String, dynamic>.from(subAny) : null;

    final source = (sub?['source'] ?? '').toString().toUpperCase();
    if (source.contains('FALLBACK') || source.contains('NO_APP_RECEIPT')) return null;

    return _coerceDate(sub?['start'], alt: sub?['startMillis']);
  }

  static DateTime? _readOwnerGrantExpiry(Map<String, dynamic>? data) {
    final grantAny = data?['ownerGrant'];
    final grant = (grantAny is Map) ? Map<String, dynamic>.from(grantAny) : null;
    return _coerceDate(grant?['expiry'], alt: grant?['expiryMillis']);
  }

  static DateTime? _readOwnerGrantStart(Map<String, dynamic>? data) {
    final grantAny = data?['ownerGrant'];
    final grant = (grantAny is Map) ? Map<String, dynamic>.from(grantAny) : null;
    return _coerceDate(grant?['start'], alt: grant?['startMillis']);
  }

  static DateTime? _coerceDate(dynamic value, {dynamic alt}) {
    final candidates = <dynamic>[value, alt];
    for (final candidate in candidates) {
      if (candidate is Timestamp) return candidate.toDate();
      if (candidate is int) return DateTime.fromMillisecondsSinceEpoch(candidate);
      if (candidate is num) return DateTime.fromMillisecondsSinceEpoch(candidate.toInt());
      if (candidate is String && candidate.trim().isNotEmpty) {
        final d = DateTime.tryParse(candidate.trim());
        if (d != null) return d;
      }
    }
    return null;
  }

  static DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static bool _isSameMoment(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
  }



  /// ✅ تحديث حالة الاشتراك من المتجر ثم مزامنتها مع Firestore.
  ///
  /// ملاحظة:
  /// - iOS/macOS: نحاول verifyReceipt، وإذا فشل لأي سبب نستخدم fallback محلي (يضمن فتح المزايا بدل ما "يعلق" المستخدم).
  /// - Android: بدون Backend لا يمكن استخراج expiry الحقيقي من Google Play بشكل آمن داخل التطبيق؛
  ///   لذلك نستخدم fallback محلي (تقريبي) لفتح المزايا فورًا، ويمكن لاحقًا استبداله بتحقق سيرفر.
  static Future<SubscriptionEntitlement?> refreshAndSyncForCurrentUser({PurchaseDetails? fromPurchase, bool allowRestore = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    final prefs = await SharedPreferences.getInstance();
    final uid = user.uid;
    final email = prefs.getString('currentEmail') ?? (user.email ?? 'unknown_user');
    final cached = _readLocalForUser(prefs, uid: uid, email: email);

    try {
      // 1) حاول استخدام عملية الشراء الحالية، وإلا استعد المشتريات للحصول على PurchaseDetails.
      final PurchaseDetails? purchase = fromPurchase ?? (allowRestore ? await _collectPurchaseViaRestore() : null);

      // إذا ما فيه أي PurchaseDetails (مثلًا المستخدم ما اشترى أصلًا) لا نمسح الكاش.
      if (purchase == null) return cached;

      final platform = defaultTargetPlatform;
      final pid = _getPurchaseProductId(purchase);

      // 2) Android: fallback محلي مباشر (يفتح المزايا فورًا)
      if (platform == TargetPlatform.android) {
        final ent = _approximateEntitlement(productId: pid, purchase: purchase, previousExpiry: cached.expiry);
        await _writeLocalForUser(prefs, uid: uid, email: email, start: ent.start, expiry: ent.expiry, productId: ent.productId);
        await _writeFirestore(user.uid, ent, source: 'ANDROID_DEVICE');
        return ent;
      }

      // 3) iOS/macOS: التحقق الرسمي عبر السيرفر (Firebase Callable Functions)
      if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
        final txId = (purchase.purchaseID ?? '').toString().trim();
        final ent = await _verifyAppleViaServer(transactionId: txId);

        // إذا فشل التحقق، لا نفتح المزايا بشكل تخميني — نرجع لآخر حالة معروفة.
        if (ent == null) return cached;

        await _writeLocalForUser(prefs, uid: uid, email: email, start: ent.start, expiry: ent.expiry, productId: ent.productId);

        // ✅ على iOS: السيرفر هو اللي يكتب Firestore ويستقبل الإشعارات (Notifications V2)
        return ent;
      }


      // منصات أخرى (غير مستخدمة في iOS فقط): fallback تقريبي
      final ent = _approximateEntitlement(productId: pid, purchase: purchase, previousExpiry: cached.expiry);
      await _writeLocalForUser(prefs, uid: uid, email: email, start: ent.start, expiry: ent.expiry, productId: ent.productId);
      await _writeFirestore(user.uid, ent, source: 'DEVICE_FALLBACK');
      return ent;
    } catch (_) {
      // لا نكسر التطبيق: رجّع آخر حالة معروفة.
      return cached;
    }
  }

  
  static SubscriptionEntitlement _readLocalForUser(SharedPreferences prefs, {required String uid, required String email}) {
    final expUid = uid.isNotEmpty ? prefs.getInt('subscriptionExpiry_uid_$uid') : null;
    final expEmail = prefs.getInt('subscriptionExpiry_$email');

    final startUid = uid.isNotEmpty ? prefs.getInt('subscriptionStart_uid_$uid') : null;
    final startEmail = prefs.getInt('subscriptionStart_$email');

    final pidUid = uid.isNotEmpty ? prefs.getString('subscriptionProductId_uid_$uid') : null;
    final pidEmail = prefs.getString('subscriptionProductId_$email');

    final useUid = (expUid != null && (expEmail == null || expUid > expEmail));
    final bestMs = useUid ? expUid : expEmail;
    final bestStartMs = useUid ? startUid : startEmail;

    final pid = (pidUid != null && pidUid.trim().isNotEmpty) ? pidUid : pidEmail;

    return SubscriptionEntitlement(
      start: bestStartMs != null ? DateTime.fromMillisecondsSinceEpoch(bestStartMs) : null,
      expiry: bestMs != null ? DateTime.fromMillisecondsSinceEpoch(bestMs) : null,
      productId: pid,
    );
  }


  static Future<void> _writeLocalForUser(
    SharedPreferences prefs, {
    required String uid,
    required String email,
    DateTime? start,
    DateTime? expiry,
    String? productId,
  }) async {
    // ✅ نكتب بنظامين لضمان التوافق: uid (الأفضل) + email (قديم)
    await _writeLocal(prefs, email, start: start, expiry: expiry, productId: productId);

    if (uid.isEmpty) return;
    final kExpUid = 'subscriptionExpiry_uid_$uid';
    final kPidUid = 'subscriptionProductId_uid_$uid';
    final kStartUid = 'subscriptionStart_uid_$uid';

    if (expiry == null) {
      await prefs.remove(kExpUid);
      await prefs.remove(kPidUid);
      await prefs.remove(kStartUid);
      return;
    }
    await prefs.setInt(kExpUid, expiry.millisecondsSinceEpoch);
    if (start != null) {
      await prefs.setInt(kStartUid, start.millisecondsSinceEpoch);
    } else {
      await prefs.remove(kStartUid);
    }
    if (productId != null && productId.trim().isNotEmpty) {
      await prefs.setString(kPidUid, productId);
    }
  }

static SubscriptionEntitlement _readLocal(SharedPreferences prefs, String email) {
    final startMs = prefs.getInt('subscriptionStart_$email');
    final expMs = prefs.getInt('subscriptionExpiry_$email');
    final pid = prefs.getString('subscriptionProductId_$email');
    return SubscriptionEntitlement(
      start: startMs != null ? DateTime.fromMillisecondsSinceEpoch(startMs) : null,
      expiry: expMs != null ? DateTime.fromMillisecondsSinceEpoch(expMs) : null,
      productId: pid,
    );
  }

  static Future<void> _writeLocal(SharedPreferences prefs, String email, {DateTime? start, DateTime? expiry, String? productId}) async {
    final kStart = 'subscriptionStart_$email';
    final kExp = 'subscriptionExpiry_$email';
    final kPid = 'subscriptionProductId_$email';
    if (expiry == null) {
      await prefs.remove(kStart);
      await prefs.remove(kExp);
      await prefs.remove(kPid);
      return;
    }
    await prefs.setInt(kExp, expiry.millisecondsSinceEpoch);
    if (start != null) {
      await prefs.setInt(kStart, start.millisecondsSinceEpoch);
    } else {
      await prefs.remove(kStart);
    }
    if (productId != null && productId.trim().isNotEmpty) {
      await prefs.setString(kPid, productId);
    }
  }

  static Future<void> _writeFirestore(String uid, SubscriptionEntitlement ent, {required String source}) async {
    //  لا تكتب اشتراك "Fallback" في Firestore أبداً. الكتابة تكون فقط عند شراء/استعادة حقيقية.
    final src = source.toUpperCase();
    if (src.contains('FALLBACK') || src.contains('NO_APP_RECEIPT')) {
      return;
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final expiry = ent.expiry;
    if (expiry == null) {
      await ref.set(
        {
          'subscription': {
            'active': false,
            'expiry': FieldValue.delete(),
            'productId': FieldValue.delete(),
            'start': FieldValue.delete(),
            'source': source,
            'updatedAt': FieldValue.serverTimestamp(),
          }
        },
        SetOptions(merge: true),
      );
      return;
    }
    await ref.set(
      {
        'subscription': {
          'active': expiry.isAfter(DateTime.now()),
          'expiry': Timestamp.fromDate(expiry),
          'start': ent.start != null ? Timestamp.fromDate(ent.start!) : FieldValue.delete(),
          'productId': ent.productId,
          'source': source,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      },
      SetOptions(merge: true),
    );
  }

  static Future<PurchaseDetails?> _collectPurchaseViaRestore() async {
    // نستمع قليلًا لمخرجات restorePurchases ثم نأخذ أول Purchase صالح.
    final iap = InAppPurchase.instance;
    PurchaseDetails? found;
    late final StreamSubscription<List<PurchaseDetails>> sub;
    final completer = Completer<void>();

    sub = iap.purchaseStream.listen(
      (list) {
        for (final p in list) {
          if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
            // نأخذ أول مشتريات يبدو أنه اشتراك من باقاتنا.
            final pid = _getPurchaseProductId(p) ?? '';
            if (pid.startsWith('vip_')) {
              found = p;
              if (!completer.isCompleted) completer.complete();
              break;
            }
          }
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );

    try {
      await iap.restorePurchases();
      await completer.future.timeout(const Duration(seconds: 12), onTimeout: () {});
    } catch (_) {
      // ignore
    } finally {
      await sub.cancel();
    }

    return found;
  }

  static String? _getPurchaseProductId(PurchaseDetails p) {
    // لتفادي اختلافات الإصدارات (productID / productId)
    try {
      final v = (p as dynamic).productID;
      if (v != null) return v.toString();
    } catch (_) {}
    try {
      final v = (p as dynamic).productId;
      if (v != null) return v.toString();
    } catch (_) {}
    return null;
  }

  static DateTime? _getPurchaseTime(PurchaseDetails p) {
    try {
      final v = (p as dynamic).transactionDate;
      if (v == null) return null;
      final ms = int.tryParse(v.toString());
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static SubscriptionEntitlement _approximateEntitlement({
    required String? productId,
    required PurchaseDetails purchase,
    required DateTime? previousExpiry,
  }) {
    final pid = (productId ?? '').trim();
    final now = DateTime.now();

    Duration? dur;
    if (pid.startsWith('vip_monthly')) dur = const Duration(days: 30);
    if (pid.startsWith('vip_yearly')) dur = const Duration(days: 365);

    if (dur == null) {
      return const SubscriptionEntitlement(start: null, expiry: null, productId: null);
    }

    // ✅ لو فيه اشتراك سابق فعال، نمدده؛ وإلا نبدأ من الآن.
    // (ملاحظة: على Android قد لا نستطيع الحصول على expiry الحقيقي بدون Backend،
    // فنجعل التجربة سلسة للمستخدم بدل ما تبقى الشاشة "مقفولة".)
    final base = (previousExpiry != null && previousExpiry.isAfter(now)) ? previousExpiry : now;

    return SubscriptionEntitlement(
      start: base,
      expiry: base.add(dur),
      productId: pid,
    );
  }

  
  // =========================
  // iOS: التحقق الرسمي عبر السيرفر
  // =========================

  static final FirebaseFunctions _appleFunctions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<SubscriptionEntitlement?> _verifyAppleViaServer({required String transactionId}) async {
    // ✅ هذا التحقق خاص بـ iOS/macOS فقط.
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.macOS) return null;

    if (transactionId.trim().isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    // جرّب أسماء الدوال (حسب ما هو منشور عندك)
    final functionNames = <String>['verifyApplePurchase', 'verifyAppleReceipt'];

    for (final name in functionNames) {
      try {
        final callable = _appleFunctions.httpsCallable(name);
        await callable.call(<String, dynamic>{
          'transactionId': transactionId.trim(),
        });
        // إذا نجحت واحدة نوقف
        break;
      } on FirebaseFunctionsException {
        // جرّب الاسم الثاني
        continue;
      } catch (_) {
        continue;
      }
    }

    // بعد التحقق، السيرفر يحدّث users/{uid}.subscription
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data();

      final expiry = readExpiryFromUserDoc(data);
      final start = readStartFromUserDoc(data);
      final pid = readProductIdFromUserDoc(data);

      if (expiry == null) {
        return const SubscriptionEntitlement(start: null, expiry: null, productId: null);
      }
      return SubscriptionEntitlement(start: start, expiry: expiry, productId: pid);
    } catch (_) {
      return null;
    }
  }
}
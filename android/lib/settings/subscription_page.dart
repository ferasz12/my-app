// lib/screens/subscription_page.dart
// Paywall حقيقي (شهري/سنوي) + in_app_purchase + استعادة + أكواد/باركود + تجديد سريع
// مزامنة مع Firestore تحت: users/{uid}/subscription

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// لو صفحة الباركود عندك في lib/screens/
import '../screens/barcode_scanner_page.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  // الحالة المحلية (اشتراك مخزن)
  DateTime? _start;
  DateTime? _expiry;
  String? _plan; // مثال: VIP30 / VIP365 / FREE30 / RENEW+30
  bool _loadingPrefs = true;

  // متجر التطبيقات
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _storeAvailable = false;
  bool _busy = false;

  // المعرّفات (عدّلها لتطابق منتجاتك في المتجرين)
  static const String _kMonthlyId = 'vip_monthly'; // ex: com.app.vip.monthly
  static const String _kYearlyId  = 'vip_yearly';  // ex: com.app.vip.yearly
  final Set<String> _kIds = {_kMonthlyId, _kYearlyId};

  // تفاصيل المنتجات
  ProductDetails? _monthly;
  ProductDetails? _yearly;

  // لمنع التسليم المكرر لشراء واحد
  Set<String> _processedTokens = {};

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _initAll() async {
    await _loadLocal();
    await _loadRemoteOverride(); // لو فيه حالة أحدث في السحابة نستخدمها
    await _initIAP();
  }

  // ==================== Local / Remote state ====================

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    final startMs = prefs.getInt('subscriptionStart_$email');
    final expiryMs = prefs.getInt('subscriptionExpiry_$email');
    final plan = prefs.getString('subscriptionPlan_$email');
    _processedTokens =
        (prefs.getStringList('iap_processed_tokens_$email') ?? []).toSet();

    setState(() {
      _start  = startMs  != null ? DateTime.fromMillisecondsSinceEpoch(startMs) : null;
      _expiry = expiryMs != null ? DateTime.fromMillisecondsSinceEpoch(expiryMs) : null;
      _plan   = plan;
      _loadingPrefs = false;
    });
  }

  Future<void> _saveLocal(DateTime start, DateTime expiry, String plan) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    await prefs.setInt('subscriptionStart_$email', start.millisecondsSinceEpoch);
    await prefs.setInt('subscriptionExpiry_$email', expiry.millisecondsSinceEpoch);
    await prefs.setString('subscriptionPlan_$email', plan);
    setState(() {
      _start = start;
      _expiry = expiry;
      _plan = plan;
    });
  }

  Future<void> _saveProcessedToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    _processedTokens.add(token);
    await prefs.setStringList('iap_processed_tokens_$email', _processedTokens.toList());
  }

  bool get _isActive => _expiry != null && _expiry!.isAfter(DateTime.now());

  // ========== Firestore Sync ==========
  Future<void> _saveToFirestore({
    required DateTime start,
    required DateTime expiry,
    required String plan,
    String? storeToken,
    String? source, // e.g. 'IAP_ANDROID', 'IAP_IOS', 'CODE'
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await ref.set({
        'subscription': {
          'plan': plan,
          'start': start.toUtc(),
          'expiry': expiry.toUtc(),
          'isActive': expiry.isAfter(DateTime.now().toUtc()),
          'storeToken': storeToken,
          'source': source ?? 'UNKNOWN',
          'updatedAt': Timestamp.now(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل مزامنة الاشتراك مع السحابة: $e')),
      );
    }
  }

  Future<void> _loadRemoteOverride() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final d = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      final sub = d.data()?['subscription'] as Map<String, dynamic>?;
      if (sub == null) return;

      final start = (sub['start'] as Timestamp?)?.toDate();
      final expiry = (sub['expiry'] as Timestamp?)?.toDate();
      final plan = sub['plan'] as String?;
      if (start != null && expiry != null && plan != null) {
        // لو بيانات السحابة أحدث من المحلي، خذها
        if (_expiry == null || expiry.isAfter(_expiry!)) {
          await _saveLocal(start, expiry, plan);
        }
      }
    } catch (_) {
      // تجاهل؛ نكمل عادي
    }
  }

  // يمنح/يمد الاشتراك لأيام معينة. لو الاشتراك شغّال يمدّ من تاريخ الانتهاء.
  Future<void> _activateDays(int days, {required String plan, String? storeToken, String? source}) async {
    final now = DateTime.now();
    final active = _expiry != null && _expiry!.isAfter(now);
    final start = active ? (_start ?? now) : now;
    final base = active ? _expiry! : now;
    final expiry = base.add(Duration(days: days));
    await _saveLocal(start, expiry, plan);
    await _saveToFirestore(start: start, expiry: expiry, plan: plan, storeToken: storeToken, source: source);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تفعيل/تمديد الاشتراك لمدة $days يومًا')),
    );
  }

  // ==================== IAP ====================
  Future<void> _initIAP() async {
    final available = await _iap.isAvailable();
    setState(() => _storeAvailable = available);
    if (!available) return;

    // استرجع المنتجات
    final resp = await _iap.queryProductDetails(_kIds);
    if (resp.error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب المنتجات: ${resp.error}')),
        );
      }
    }
    if (resp.notFoundIDs.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Products not found: ${resp.notFoundIDs.join(", ")}')),
      );
    }
    for (final p in resp.productDetails) {
      if (p.id == _kMonthlyId) _monthly = p;
      if (p.id == _kYearlyId)  _yearly  = p;
    }
    setState(() {});

    // استمع للتحديثات
    _sub = _iap.purchaseStream.listen(_handlePurchaseUpdates, onDone: () {
      _sub?.cancel();
    }, onError: (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ في الشراء: $e')),
        );
      }
    });
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() => _busy = true);
    final param = PurchaseParam(productDetails: product);
    try {
      await _iap.buyNonConsumable(purchaseParam: param);
      // ملاحظة: لو منتجاتك Subscriptions (تجديد تلقائي)، يبقى يشتغل،
      // لكن يُفضّل توصيل Cloud Function للتحقق من الإيصال لتحديد التاريخ الحقيقي للانتهاء.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر بدء عملية الشراء: $e')),
        );
      }
      setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر استعادة المشتريات: $e')),
      );
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> list) async {
    for (final p in list) {
      final token = p.verificationData.serverVerificationData; // يصلح كمعرّف فريد
      if (p.status == PurchaseStatus.pending) {
        setState(() => _busy = true);
      } else {
        setState(() => _busy = false);
        if (p.status == PurchaseStatus.error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل الشراء: ${p.error}')),
            );
          }
        } else if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
          // تفادي التسليم المكرر
          if (!_processedTokens.contains(token)) {
            await _deliverPurchase(p);
            await _saveProcessedToken(token);
          }
        }
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }
    }
  }

  Future<void> _deliverPurchase(PurchaseDetails p) async {
    // NOTE: بدون تحقق سيرفري، سنفترض 30/365 يوم حسب المنتج.
    // الأفضل: استدعِ Cloud Function تتحقق من الإيصال وترجع expiry الحقيقي.
    final id = p.productID;
    if (id == _kMonthlyId) {
      await _activateDays(
        30,
        plan: 'VIP30',
        storeToken: p.verificationData.serverVerificationData,
        source: _platformSource(),
      );
    } else if (id == _kYearlyId) {
      await _activateDays(
        365,
        plan: 'VIP365',
        storeToken: p.verificationData.serverVerificationData,
        source: _platformSource(),
      );
    }
  }

  String _platformSource() {
    // تقريبية — فقط للتوثيق
    if (Theme.of(context).platform == TargetPlatform.iOS) return 'IAP_IOS';
    if (Theme.of(context).platform == TargetPlatform.android) return 'IAP_ANDROID';
    return 'IAP';
  }

  // ==================== Codes / Barcode ====================

  // يحوّل كود مثل FREE30 أو FREE-45 إلى عدد الأيام
  int? _daysForCode(String raw) {
    final code = raw.trim().toUpperCase();
    if (code == 'FREE30') return 30;
    if (code == 'FREE90') return 90;
    if (code == 'FREE365' || code == 'FREE1Y') return 365;
    final m = RegExp(r'^FREE[-_]?(\d{1,4})$').firstMatch(code);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || code.isEmpty) return;

    final days = _daysForCode(code);
    if (days == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رمز غير صالح')),
      );
      return;
    }
    await _activateDays(days, plan: code.toUpperCase(), source: 'CODE');
  }

  Future<void> _enterCodeManually() async {
    final controller = TextEditingController();
    final s = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('أدخل رمز الاشتراك'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'مثال: FREE30 أو FREE-45'),
          textDirection: TextDirection.ltr,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: s.primary, foregroundColor: s.onPrimary),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final days = _daysForCode(controller.text);
    if (days == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رمز غير صالح')),
      );
      return;
    }
    await _activateDays(days, plan: controller.text.trim().toUpperCase(), source: 'CODE');
  }

  Future<void> _renewQuick(int days) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تجديد الاشتراك'),
        content: Text('متأكد تبغى تمدد $days يوم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm == true) {
      await _activateDays(days, plan: 'RENEW+$days', source: 'MANUAL');
    }
  }

  // ==================== UI Helpers ====================

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    final yr = d.year.toString();
    return '$day/$mon/$yr';
    // ممكن تستخدم intl لو تبي تنسيق أدق
  }

  String _remainingText() {
    if (_expiry == null) return 'لا يوجد اشتراك نشط';
    final diff = _expiry!.difference(DateTime.now());
    if (diff.isNegative) return 'انتهى الاشتراك';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return days > 0 ? 'باقي $days يوم و $hours ساعة' : 'باقي $hours ساعة';
  }

  double _progress() {
    if (_start == null || _expiry == null) return 0;
    final total = _expiry!.difference(_start!).inSeconds;
    if (total <= 0) return 1;
    final used = DateTime.now().difference(_start!).inSeconds.clamp(0, total);
    return used / total;
  }

  List<String> get _features => const [
        'مزامنة الأهداف وبيانات الماء والوزن بين جميع الأجهزة',
        'صفحة مجتمع للتحديات والإنجازات',
        'خطط غذائية وجداول تدريب قابلة للتخصيص',
        'ماسح باركود للأغذية مع قاعدة بيانات موسعة',
        'تذكيرات ذكية للماء والصيام والنشاط',
        'لوحات تحليلات وتتبّع تقدّم أسبوعي وشهري',
        'ثيمات متعددة (فاتح/داكن/أسود AMOLED) وخط أكبر',
      ];

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final monthlyPrice = _monthly?.price ?? '—';
    final yearlyPrice  = _yearly?.price  ?? '—';

    final double? mRaw = _monthly?.rawPrice;
    final double? yRaw = _yearly?.rawPrice;
    final String? curr = _yearly?.currencyCode ?? _monthly?.currencyCode;
    String? yearlyFoot;
    String? yearlyBadge;
    if (mRaw != null && yRaw != null && mRaw > 0) {
      final regularYear = mRaw * 12;
      final save = (regularYear - yRaw).clamp(0, regularYear);
      final savePct = regularYear > 0 ? ((save / regularYear) * 100).toStringAsFixed(0) : null;
      final perMonth = (yRaw / 12).toStringAsFixed(2);
      yearlyFoot = 'يعادل $perMonth ${curr ?? ''} / شهر';
      if (savePct != null) yearlyBadge = 'يوفّر %$savePct';
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('اشتراكي')),
        body: _loadingPrefs
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primaryContainer
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.workspace_premium_rounded, color: Theme.of(context).colorScheme.onPrimary),
                                const SizedBox(width: 8),
                                Text('اشتراك بريميوم',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      fontSize: 16, fontWeight: FontWeight.w600)),
                                const Spacer(),
                                Icon(Icons.stars_rounded, color: Theme.of(context).colorScheme.onPrimary),
                              ],
                            ),
                            const Spacer(),
                            Text('ابدأ مزاياك الكاملة',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text('باقة شهرية أو سنوية بخصم مميز • تجديد تلقائي • يمكن الإلغاء في أي وقت',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary.withOpacity(.95),
                                  fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _StatusCard(
                        start: _start, expiry: _expiry, plan: _plan,
                        progress: _progress(), remainingText: _remainingText(),
                      ),
                    ),
                  ),

                  // الباقات
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final isWide = c.maxWidth >= 820;
                          return Flex(
                            direction: isWide ? Axis.horizontal : Axis.vertical,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: isWide ? 1 : 0,
                                child: _PlanCard(
                                  title: 'الاشتراك الشهري',
                                  subtitle: 'يجدد كل شهر',
                                  price: monthlyPrice,
                                  features: _features,
                                  actionText: _storeAvailable ? 'اشترك الآن' : 'غير متاح',
                                  onPressed: (_storeAvailable && _monthly != null && !_busy)
                                      ? () => _buy(_monthly!)
                                      : null,
                                  highlight: false,
                                  badge: 'الأكثر شيوعًا',
                                  footNote: 'إلغاء في أي وقت',
                                ),
                              ),
                              SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 16),
                              Expanded(
                                flex: isWide ? 1 : 0,
                                child: _PlanCard(
                                  title: 'الاشتراك السنوي',
                                  subtitle: 'أفضل قيمة',
                                  price: yearlyPrice,
                                  features: _features,
                                  actionText: _storeAvailable ? 'اشترك سنويًا' : 'غير متاح',
                                  onPressed: (_storeAvailable && _yearly != null && !_busy)
                                      ? () => _buy(_yearly!)
                                      : null,
                                  highlight: true,
                                  badge: yearlyBadge ?? 'يوفّر أكثر',
                                  footNote: yearlyFoot,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // استعادة شراء
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _storeAvailable && !_busy ? _restore : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('استعادة المشتريات'),
                          ),
                          const SizedBox(width: 8),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: 8),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // تفعيل عبر باركود/رمز
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تفعيل مجاني عبر باركود أو رمز', style: t.titleMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _scanBarcode,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('مسح باركود'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _enterCodeManually,
                                  icon: const Icon(Icons.key),
                                  label: const Text('إدخال رمز'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // تجديد سريع
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تجديد سريع', style: t.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _RenewChip(label: '30 يوم', onTap: () => _renewQuick(30)),
                              _RenewChip(label: '90 يوم', onTap: () => _renewQuick(90)),
                              _RenewChip(label: '365 يوم', onTap: () => _renewQuick(365)),
                            ],
                          ),
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

// ==================== Widgets ====================

class _StatusCard extends StatelessWidget {
  final DateTime? start;
  final DateTime? expiry;
  final String? plan;
  final double progress;
  final String remainingText;

  const _StatusCard({
    required this.start,
    required this.expiry,
    required this.plan,
    required this.progress,
    required this.remainingText,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final active = expiry != null && expiry!.isAfter(DateTime.now());

    String _fmt(DateTime? d) {
      if (d == null) return '—';
      final day = d.day.toString().padLeft(2, '0');
      final mon = d.month.toString().padLeft(2, '0');
      final yr = d.year.toString();
      return '$day/$mon/$yr';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.outlineVariant.withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(active ? Icons.verified : Icons.report_gmailerrorred,
                  color: active ? s.primary : s.error),
              const SizedBox(width: 8),
              Text(active ? 'اشتراك مفعل' : 'لا يوجد اشتراك نشط',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (plan != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: s.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('الخطة: $plan', style: t.labelLarge),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _InfoTile(label: 'بداية', value: _fmt(start))),
              const SizedBox(width: 8),
              Expanded(child: _InfoTile(label: 'انتهاء', value: _fmt(expiry))),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress, minHeight: 10, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 6),
          Text(remainingText, style: t.bodySmall),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  final List<String> features;
  final String actionText;
  final String? footNote;
  final VoidCallback? onPressed;
  final bool highlight;
  final String? badge;

  const _PlanCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.features,
    required this.actionText,
    this.footNote,
    required this.onPressed,
    this.highlight = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final border = Border.all(
      color: highlight ? s.primary : s.outlineVariant,
      width: highlight ? 2 : 1.2,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1F24)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null)
            Align(
              alignment: AlignmentDirectional.topStart,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: highlight ? s.primary : s.secondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badge!, style: t.labelLarge?.copyWith(color: s.onPrimary)),
              ),
            ),
          Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text('شامل كل الميزات', style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          ...features.take(7).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: highlight ? s.primary : s.secondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: t.bodyMedium)),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: highlight ? s.primary : s.secondary,
              foregroundColor: s.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest.withOpacity(.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelLarge?.copyWith(color: s.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: t.titleMedium),
        ],
      ),
    );
  }
}

class _RenewChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _RenewChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: s.primary.withOpacity(.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.primary.withOpacity(.25)),
        ),
        child: Text(label, style: t.labelLarge?.copyWith(color: s.primary)),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/roles_service.dart';
import '../../settings/subscription_page.dart';
import '../../shared/owner_feature_flags.dart';
import '../../shared/premium_feature.dart';
import '../admin_support/admin_support_dashboard_page.dart';

class OwnerPage extends StatefulWidget {
  const OwnerPage({super.key});

  @override
  State<OwnerPage> createState() => _OwnerPageState();
}

class _OwnerPageState extends State<OwnerPage> with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _roles = RolesService();

  late final TabController _tab = TabController(length: 3, vsync: this);
  late final Future<AppRole> _roleFuture = _roles.currentUserRoleOnce();
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _savingRevenue = false;

  final _currency = NumberFormat.currency(locale: 'ar', symbol: 'ر.س', decimalDigits: 2);
  final _intFmt = NumberFormat.decimalPattern('ar');

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRole>(
      future: _roleFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data != AppRole.owner) {
          return Scaffold(
            appBar: AppBar(title: const Text('لوحة الأونر')),
            body: const Center(child: Text('هذه الصفحة خاصة بالأونر فقط')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('لوحة الأونر'),
            actions: [
              IconButton(
                tooltip: 'لوحة الإدارة الحالية',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminSupportDashboardPage()),
                  );
                },
                icon: const Icon(Icons.admin_panel_settings_outlined),
              ),
            ],
            bottom: TabBar(
              controller: _tab,
              tabs: const [
                Tab(icon: Icon(Icons.analytics_outlined), text: 'الإحصاءات'),
                Tab(icon: Icon(Icons.workspace_premium_outlined), text: 'اشتراك مجاني'),
                Tab(icon: Icon(Icons.toggle_on_outlined), text: 'الميزات'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              _buildOverviewTab(),
              _buildGrantTab(),
              _buildFeaturesTab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewTab() {
    final usersStream = _db.collection('users').limit(250).snapshots();
    final metricsStream = _db.collection('appConfig').doc('owner_metrics').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersStream,
      builder: (context, usersSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: metricsStream,
          builder: (context, metricsSnap) {
            if (!usersSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = usersSnap.data!.docs;
            final stats = _OwnerStats.fromDocs(docs);
            final metrics = metricsSnap.data?.data() ?? const <String, dynamic>{};
            final revenueTotalSar = _toDouble(metrics['revenueTotalSar']);

            return RefreshIndicator(
              onRefresh: () async {
                await _db.collection('users').get();
                await _db.collection('appConfig').doc('owner_metrics').get();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricCard(
                        title: 'المشتركون النشطون الآن',
                        value: _intFmt.format(stats.activeTotal),
                        icon: Icons.people_alt_outlined,
                      ),
                      _MetricCard(
                        title: 'اشتراكات شهرية',
                        value: _intFmt.format(stats.monthlyCount),
                        icon: Icons.calendar_view_month_outlined,
                      ),
                      _MetricCard(
                        title: 'اشتراكات سنوية',
                        value: _intFmt.format(stats.yearlyCount),
                        icon: Icons.calendar_month_outlined,
                      ),
                      _MetricCard(
                        title: 'اشتراكات أونر مجانية',
                        value: _intFmt.format(stats.ownerGrantCount),
                        icon: Icons.card_giftcard_outlined,
                      ),
                      _MetricCard(
                        title: 'الدخل التقديري الحالي',
                        value: _currency.format(stats.estimatedActiveRevenueSar),
                        icon: Icons.insights_outlined,
                        subtitle: 'مبني على المشتركين النشطين حاليًا',
                      ),
                      _MetricCard(
                        title: 'إجمالي الربح المسجل',
                        value: _currency.format(revenueTotalSar),
                        icon: Icons.payments_outlined,
                        subtitle: 'قيمة تحفظها أنت من لوحة الأونر',
                        trailing: IconButton(
                          tooltip: 'تعديل الربح الإجمالي',
                          onPressed: _savingRevenue ? null : () => _editRevenueTotal(context, current: revenueTotalSar),
                          icon: _savingRevenue
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.edit_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المشتركين حسب الباقة',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          if (stats.breakdown.isEmpty)
                            const Text('لا يوجد مشتركون نشطون حاليًا')
                          else
                            ...stats.breakdown.entries.map(
                              (entry) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.label_important_outline),
                                title: Text(entry.key),
                                trailing: Text(_intFmt.format(entry.value)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أحدث المشتركين النشطين',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          if (stats.latestActiveUsers.isEmpty)
                            const Text('لا يوجد مشتركون نشطون لعرضهم')
                          else
                            ...stats.latestActiveUsers.map(
                              (u) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(child: Text(u.initial)),
                                title: Text(u.displayName),
                                subtitle: Text('${u.email}\n${u.planLabel} • ينتهي ${u.expiryLabel}'),
                                isThreeLine: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGrantTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ابحث بالاسم أو الإيميل أو اليوزر',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('users').limit(250).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = snap.data!.docs
                  .map((d) => _OwnerUserRow.fromDoc(d))
                  .where((u) => u.matches(_search))
                  .toList()
                ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

              if (items.isEmpty) {
                return const Center(child: Text('لا يوجد مستخدمون مطابقون'));
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final user = items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(child: Text(user.initial)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 2),
                                    Text(user.email),
                                    if (user.username.isNotEmpty) Text('@${user.username}'),
                                  ],
                                ),
                              ),
                              _StatusChip(
                                label: user.planLabel,
                                color: user.isActive ? Colors.green : Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(user.statusLine),
                          if (user.ownerGrantExpiry != null) ...[
                            const SizedBox(height: 4),
                            Text('منحة الأونر تنتهي: ${user.ownerGrantExpiryLabel}'),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _showGrantDialog(context, user),
                                icon: const Icon(Icons.add_card_outlined),
                                label: const Text('منح اشتراك مجاني'),
                              ),
                              OutlinedButton.icon(
                                onPressed: user.hasOwnerGrant ? () => _revokeOwnerGrant(user) : null,
                                icon: const Icon(Icons.remove_circle_outline),
                                label: const Text('إلغاء منحة الأونر'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesTab() {
    return StreamBuilder<Map<PremiumFeature, bool>>(
      stream: OwnerFeatureFlagsService().watchFlags(),
      initialData: OwnerFeatureFlagsService.defaults,
      builder: (context, snap) {
        final flags = snap.data ?? OwnerFeatureFlagsService.defaults;
        final features = <PremiumFeature>[
          PremiumFeature.aiPhoto,
          PremiumFeature.aiText,
          PremiumFeature.restaurants,
          PremiumFeature.coach,
          PremiumFeature.trackingPdf,
          PremiumFeature.guide,
          PremiumFeature.virtualGym,
          PremiumFeature.virtualClubGuide,
          PremiumFeature.recipes,
          PremiumFeature.regimen,
          PremiumFeature.theme,
          PremiumFeature.notifications,
        ];

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: features.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'من هنا تقدر تقفل أو تفتح أي ميزة مدفوعة بشكل فوري على مستوى التطبيق كله. عند إقفال الميزة ستظهر للمستخدم أنها مقفلة من لوحة الأونر.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            }

            final feature = features[index - 1];
            final enabled = flags[feature] ?? true;
            return SwitchListTile.adaptive(
              value: enabled,
              secondary: Icon(feature.icon),
              title: Text(feature.titleAr),
              subtitle: Text(feature.subtitleAr),
              onChanged: (v) async {
                await OwnerFeatureFlagsService().setFlag(feature, v);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(v ? 'تم فتح ${feature.titleAr}' : 'تم إقفال ${feature.titleAr}')),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _editRevenueTotal(BuildContext context, {required double current}) async {
    final ctrl = TextEditingController(text: current == 0 ? '' : current.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تعديل إجمالي الربح المسجل'),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'المبلغ بالريال السعودي',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(double.tryParse(ctrl.text.trim()) ?? current),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();

    if (result == null) return;
    setState(() => _savingRevenue = true);
    try {
      await _db.collection('appConfig').doc('owner_metrics').set({
        'revenueTotalSar': result,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _savingRevenue = false);
    }
  }

  Future<void> _showGrantDialog(BuildContext context, _OwnerUserRow user) async {
    final ctrl = TextEditingController(text: '30');
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('منح اشتراك مجاني لـ ${user.displayName}'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'عدد الأيام',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctrl.text.trim()) ?? 0),
              child: const Text('منح الاشتراك'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();

    if (days == null || days <= 0) return;
    await _grantOwnerSubscription(user, days);
  }

  Future<void> _grantOwnerSubscription(_OwnerUserRow user, int days) async {
    final me = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final expiry = now.add(Duration(days: days));

    await _db.collection('users').doc(user.uid).set({
      'ownerGrant': {
        'active': true,
        'days': days,
        'planKey': 'owner_free_${days}d',
        'source': 'OWNER_GRANT',
        'grantedBy': me?.uid,
        'grantedAt': Timestamp.fromDate(now),
        'start': Timestamp.fromDate(now),
        'startMillis': now.millisecondsSinceEpoch,
        'expiry': Timestamp.fromDate(expiry),
        'expiryMillis': expiry.millisecondsSinceEpoch,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم منح ${user.displayName} اشتراكًا مجانيًا لمدة $days يوم')),
    );
  }

  Future<void> _revokeOwnerGrant(_OwnerUserRow user) async {
    await _db.collection('users').doc(user.uid).set({
      'ownerGrant': FieldValue.delete(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إلغاء منحة الأونر عن ${user.displayName}')),
    );
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = width > 1100 ? (width - 64) / 3 : (width > 700 ? (width - 52) / 2 : width - 32);

    return SizedBox(
      width: cardWidth,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _OwnerStats {
  final int activeTotal;
  final int monthlyCount;
  final int yearlyCount;
  final int ownerGrantCount;
  final double estimatedActiveRevenueSar;
  final Map<String, int> breakdown;
  final List<_OwnerUserSummary> latestActiveUsers;

  const _OwnerStats({
    required this.activeTotal,
    required this.monthlyCount,
    required this.yearlyCount,
    required this.ownerGrantCount,
    required this.estimatedActiveRevenueSar,
    required this.breakdown,
    required this.latestActiveUsers,
  });

  factory _OwnerStats.fromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();
    int activeTotal = 0;
    int monthlyCount = 0;
    int yearlyCount = 0;
    int ownerGrantCount = 0;
    final breakdown = <String, int>{};
    final activeUsers = <_OwnerUserSummary>[];

    for (final doc in docs) {
      final row = _OwnerUserRow.fromDoc(doc);
      if (!row.isActive) continue;
      activeTotal++;
      breakdown[row.planLabel] = (breakdown[row.planLabel] ?? 0) + 1;
      if (row.planType == _PlanType.monthly) monthlyCount++;
      if (row.planType == _PlanType.yearly) yearlyCount++;
      if (row.planType == _PlanType.ownerGrant) ownerGrantCount++;

      activeUsers.add(
        _OwnerUserSummary(
          displayName: row.displayName,
          email: row.email,
          planLabel: row.planLabel,
          expiryLabel: row.expiryLabel,
          expiry: row.effectiveExpiry ?? now,
        ),
      );
    }

    activeUsers.sort((a, b) => b.expiry.compareTo(a.expiry));

    return _OwnerStats(
      activeTotal: activeTotal,
      monthlyCount: monthlyCount,
      yearlyCount: yearlyCount,
      ownerGrantCount: ownerGrantCount,
      estimatedActiveRevenueSar: (monthlyCount * 18) + (yearlyCount * 194),
      breakdown: Map<String, int>.fromEntries(
        breakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      ),
      latestActiveUsers: activeUsers.take(8).toList(),
    );
  }
}

class _OwnerUserSummary {
  final String displayName;
  final String email;
  final String planLabel;
  final String expiryLabel;
  final DateTime expiry;

  const _OwnerUserSummary({
    required this.displayName,
    required this.email,
    required this.planLabel,
    required this.expiryLabel,
    required this.expiry,
  });

  String get initial {
    final s = displayName.trim();
    return s.isEmpty ? '?' : s.substring(0, 1);
  }
}

enum _PlanType { monthly, yearly, ownerGrant, other, none }

class _PlanInfo {
  final String label;
  final _PlanType type;
  const _PlanInfo(this.label, this.type);
}

class _OwnerUserRow {
  final String uid;
  final String displayName;
  final String email;
  final String username;
  final DateTime? subscriptionExpiry;
  final DateTime? ownerGrantExpiry;
  final DateTime? effectiveExpiry;
  final String planLabel;
  final _PlanType planType;

  const _OwnerUserRow({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.username,
    required this.subscriptionExpiry,
    required this.ownerGrantExpiry,
    required this.effectiveExpiry,
    required this.planLabel,
    required this.planType,
  });

  factory _OwnerUserRow.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final email = (data['email'] ?? '').toString().trim();
    final username = (data['username'] ?? '').toString().trim();
    final displayName = [
      (data['displayName'] ?? '').toString().trim(),
      (data['name'] ?? '').toString().trim(),
      [
        (data['firstName'] ?? '').toString().trim(),
        (data['lastName'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).join(' ').trim(),
      username,
      email.split('@').first,
      doc.id,
    ].firstWhere((e) => e.isNotEmpty, orElse: () => doc.id);

    final ownerGrant = (data['ownerGrant'] is Map)
        ? Map<String, dynamic>.from(data['ownerGrant'] as Map)
        : const <String, dynamic>{};
    final ownerGrantExpiry = _coerceDate(ownerGrant['expiry'], ownerGrant['expiryMillis']);

    DateTime? subscriptionOnlyExpiry;
    final sub = (data['subscription'] is Map)
        ? Map<String, dynamic>.from(data['subscription'] as Map)
        : const <String, dynamic>{};
    final source = (sub['source'] ?? '').toString().toUpperCase();
    if (!source.contains('FALLBACK') && !source.contains('NO_APP_RECEIPT')) {
      subscriptionOnlyExpiry = _coerceDate(sub['expiry'], sub['expiryMillis']);
    }

    final effectiveExpiry = _maxDate(subscriptionOnlyExpiry, ownerGrantExpiry);
    final activePlan = _resolvePlan(data, subscriptionOnlyExpiry, ownerGrantExpiry, effectiveExpiry);

    return _OwnerUserRow(
      uid: doc.id,
      displayName: displayName,
      email: email,
      username: username,
      subscriptionExpiry: subscriptionOnlyExpiry,
      ownerGrantExpiry: ownerGrantExpiry,
      effectiveExpiry: effectiveExpiry,
      planLabel: activePlan.label,
      planType: activePlan.type,
    );
  }

  bool matches(String q) {
    if (q.isEmpty) return true;
    final haystack = '$displayName $email $username $uid'.toLowerCase();
    return haystack.contains(q);
  }

  bool get isActive => effectiveExpiry != null && effectiveExpiry!.isAfter(DateTime.now());
  bool get hasOwnerGrant => ownerGrantExpiry != null;
  String get expiryLabel => _formatDate(effectiveExpiry);
  String get ownerGrantExpiryLabel => _formatDate(ownerGrantExpiry);
  String get statusLine => isActive ? 'الحالة: نشط حتى $expiryLabel' : 'الحالة: غير نشط';

  String get initial {
    final s = displayName.trim();
    return s.isEmpty ? '?' : s.substring(0, 1);
  }

  static _PlanInfo _resolvePlan(
    Map<String, dynamic> data,
    DateTime? subscriptionExpiry,
    DateTime? ownerGrantExpiry,
    DateTime? effectiveExpiry,
  ) {
    if (effectiveExpiry == null || !effectiveExpiry.isAfter(DateTime.now())) {
      return const _PlanInfo('غير مشترك', _PlanType.none);
    }

    if (_sameMoment(ownerGrantExpiry, effectiveExpiry)) {
      final ownerGrant = (data['ownerGrant'] is Map)
          ? Map<String, dynamic>.from(data['ownerGrant'] as Map)
          : const <String, dynamic>{};
      final days = ownerGrant['days'];
      final suffix = days is num ? ' (${days.toInt()} يوم)' : '';
      return _PlanInfo('اشتراك مجاني من الأونر$suffix', _PlanType.ownerGrant);
    }

    final sub = (data['subscription'] is Map)
        ? Map<String, dynamic>.from(data['subscription'] as Map)
        : const <String, dynamic>{};
    final pid = (sub['productId'] ?? '').toString().trim();
    if (pid.startsWith('vip_monthly')) return _PlanInfo(pid.isEmpty ? 'الباقة الشهرية' : pid, _PlanType.monthly);
    if (pid.startsWith('vip_yearly')) return _PlanInfo(pid.isEmpty ? 'الباقة السنوية' : pid, _PlanType.yearly);
    if (pid.isNotEmpty) return _PlanInfo(pid, _PlanType.other);
    return const _PlanInfo('اشتراك نشط', _PlanType.other);
  }

  static DateTime? _coerceDate(dynamic primary, dynamic secondary) {
    for (final value in [primary, secondary]) {
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      if (value is String && value.trim().isNotEmpty) {
        final d = DateTime.tryParse(value.trim());
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

  static bool _sameMoment(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('yyyy/MM/dd – HH:mm', 'en').format(date.toLocal());
  }
}

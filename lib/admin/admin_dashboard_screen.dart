// lib/screens/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// لو ما عندك Provider تجاهل الاستيراد
import '../shared/badges.dart';

// لوحتك القديمة (المؤشرات)
import '../community/local_repos.dart'; // LocalAuthRepo
import '../models/badge.dart';
import '../shared/user_badges_store.dart'; // getBadge(email)
import 'admin_repo.dart';

// ✅ البلاغات: المصدر الموحد
import '../services/report_store.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  bool _allowed = false;

  final _repo = AdminAnalyticsRepo();

  // --- حقول تبويب المؤشرات (كما كانت) ---
  final _ios = TextEditingController();
  final _android = TextEditingController();
  final _other = TextEditingController();
  final _subs = TextEditingController();
  final _revenue = TextEditingController(); // بالريال – نحوله لـ cents

  final _fmtInt = NumberFormat.decimalPattern('ar');
  final _fmtMoney =
      NumberFormat.currency(locale: 'ar', symbol: 'ر.س', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ios.dispose();
    _android.dispose();
    _other.dispose();
    _subs.dispose();
    _revenue.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final me = await LocalAuthRepo().currentUser();
    final badge = await getBadge(me.email);

    // السماح للمالك فقط (عدّل لو تبغى تضيف أدوار أخرى)
    _allowed = badge == BadgeType.owner;

    _loading = false;
    if (mounted) setState(() {});
  }

  Future<void> _apply(AdminTotals t) async {
    _ios.text = t.downloadsIos.toString();
    _android.text = t.downloadsAndroid.toString();
    _other.text = t.downloadsOther.toString();
    _subs.text = t.subscribers.toString();
    _revenue.text = (t.revenueCents / 100).toStringAsFixed(2);
  }

  // ============ تبويب المؤشرات (اللوحة القديمة كما هي) ============
  Widget _buildAnalyticsTab() {
    return StreamBuilder<AdminTotals>(
      stream: _repo.watchTotals(),
      builder: (context, snap) {
        final t = snap.data;
        if (t != null) _apply(t);
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TotalsGrid(t: t!, fmtInt: _fmtInt, fmtMoney: _fmtMoney),
            const SizedBox(height: 16),
            _EditPanel(
              ios: _ios,
              android: _android,
              other: _other,
              subs: _subs,
              revenue: _revenue,
              onSave: () async {
                await _repo.setDownloads(
                  ios: int.tryParse(_ios.text) ?? t.downloadsIos,
                  android: int.tryParse(_android.text) ?? t.downloadsAndroid,
                  other: int.tryParse(_other.text) ?? t.downloadsOther,
                );
                await _repo
                    .setSubscribers(int.tryParse(_subs.text) ?? t.subscribers);
                final cents = ((double.tryParse(_revenue.text) ??
                            (t.revenueCents / 100)) *
                        100)
                    .round();
                await _repo.setRevenueCents(cents);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم الحفظ')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              'آخر تحديث: ${DateFormat.yMMMd("ar").add_Hm().format(t.updatedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('لوحة المالك')),
        body: const Center(child: Text('هذه الصفحة للمالك فقط')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة المالك'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'المؤشرات'),
              Tab(text: 'بلاغات المجتمع'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AnalyticsTabProxy(),
            _ReportsTab(), // ✅ محدث
          ],
        ),
      ),
    );
  }
}

class _AnalyticsTabProxy extends StatelessWidget {
  const _AnalyticsTabProxy();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AdminDashboardScreenState>();
    return state!._buildAnalyticsTab();
  }
}

// ======================= Widgets المؤشرات =======================

class _TotalsGrid extends StatelessWidget {
  final AdminTotals t;
  final NumberFormat fmtInt;
  final NumberFormat fmtMoney;
  const _TotalsGrid(
      {required this.t, required this.fmtInt, required this.fmtMoney});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _MetricCard(
            title: 'التحميلات (iOS)',
            value: fmtInt.format(t.downloadsIos),
            icon: Icons.apple),
        _MetricCard(
            title: 'التحميلات (Android)',
            value: fmtInt.format(t.downloadsAndroid),
            icon: Icons.android),
        _MetricCard(
            title: 'تحميلات أخرى',
            value: fmtInt.format(t.downloadsOther),
            icon: Icons.download),
        _MetricCard(
            title: 'إجمالي التحميلات',
            value: fmtInt.format(t.downloadsTotal),
            icon: Icons.cloud_download),
        _MetricCard(
            title: 'عدد المشتركين',
            value: fmtInt.format(t.subscribers),
            icon: Icons.people),
        _MetricCard(
            title: 'إجمالي الأرباح',
            value: fmtMoney.format(t.revenueCents / 100),
            icon: Icons.attach_money),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _MetricCard(
      {required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.secondaryContainer,
              child: Icon(icon, color: cs.onSecondaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditPanel extends StatelessWidget {
  final TextEditingController ios, android, other, subs, revenue;
  final VoidCallback onSave;
  const _EditPanel({
    required this.ios,
    required this.android,
    required this.other,
    required this.subs,
    required this.revenue,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    Expanded input(String hint, TextEditingController c, {TextInputType? type}) {
      return Expanded(
        child: TextField(
          controller: c,
          keyboardType: type ?? TextInputType.number,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('تعديل سريع (محليًا إلى أن يتم ربط باكند/المتاجر):',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          input('iOS', ios),
          const SizedBox(width: 8),
          input('Android', android),
          const SizedBox(width: 8),
          input('أخرى', other),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          input('المشتركين', subs),
          const SizedBox(width: 8),
          input('الأرباح (ر.س)', revenue,
              type: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          ),
        ),
      ],
    );
  }
}

// ======================= تبويب البلاغات (ReportStore) =======================

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  String _statusFilter = 'all'; // all | open | actioned | dismissed

  List<PostReport> _applyFilter(List<PostReport> all) {
    if (_statusFilter == 'all') return all;
    return all.where((r) => r.status == _statusFilter).toList();
  }

  Future<void> _markActioned(PostReport r) async {
    await ReportStore.updateReportStatus(r.id, 'actioned');
  }

  Future<void> _markDismissed(PostReport r) async {
    await ReportStore.updateReportStatus(r.id, 'dismissed');
  }

  Future<void> _reopen(PostReport r) async {
    await ReportStore.updateReportStatus(r.id, 'open');
  }

  Future<void> _deleteReport(PostReport r) async {
    await ReportStore.deleteReportById(r.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        // فلترة
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _filterChip('الكل', 'all'),
                  _filterChip('جديدة', 'open'),
                  _filterChip('تم إجراء إجراء', 'actioned'),
                  _filterChip('مرفوضة', 'dismissed'),
                ],
              ),
              const Spacer(),
              // زر شكلي للتحديث اليدوي (Stream محدث تلقائيًا)
              IconButton(
                tooltip: 'تحديث',
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // القائمة
        Expanded(
          child: StreamBuilder<List<PostReport>>(
            stream: ReportStore.watchReports(), // ✅ لحظي
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('خطأ في قراءة البلاغات'));
              }
              final all = snap.data ?? const <PostReport>[];
              final list = _applyFilter(all);

              if (list.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 64),
                    Center(child: Text('لا توجد بلاغات')),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              _statusPill(context, r.status),
                              const Spacer(),
                              Text(
                                DateFormat('yyyy/MM/dd HH:mm')
                                    .format(r.createdAt.toLocal()),
                                style:
                                    tt.labelSmall?.copyWith(color: cs.outline),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Post info
                          Text('المنشور #${r.postId} • بواسطة ${r.postAuthor}',
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          if (r.postSnippet.trim().isNotEmpty)
                            Text(r.postSnippet, style: tt.bodyMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.flag, size: 16, color: cs.primary),
                              const SizedBox(width: 6),
                              Text('السبب: ${r.reason}',
                                  style: tt.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          if (r.details != null &&
                              r.details!.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('تفاصيل: ${r.details}', style: tt.bodySmall),
                          ],
                          if (r.reporterEmail.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('المبلّغ: ${r.reporterEmail}',
                                style:
                                    tt.bodySmall?.copyWith(color: cs.outline)),
                          ],
                          const SizedBox(height: 12),

                          // Actions
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (r.status != 'actioned')
                                FilledButton.icon(
                                  onPressed: () => _markActioned(r),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('تم إجراء إجراء'),
                                ),
                              if (r.status != 'dismissed')
                                FilledButton.tonalIcon(
                                  onPressed: () => _markDismissed(r),
                                  icon: const Icon(Icons.close),
                                  label: const Text('رفض البلاغ'),
                                ),
                              if (r.status != 'open')
                                OutlinedButton.icon(
                                  onPressed: () => _reopen(r),
                                  icon: const Icon(Icons.restart_alt),
                                  label: const Text('إعادة فتح'),
                                ),
                              OutlinedButton.icon(
                                onPressed: () => _deleteReport(r),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('حذف البلاغ'),
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

  Widget _filterChip(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final sel = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _statusFilter = value),
      selectedColor: cs.primaryContainer,
      backgroundColor: cs.surface,
      side: BorderSide(color: sel ? cs.primary : cs.outlineVariant),
      labelStyle: TextStyle(
        color: sel ? cs.onPrimaryContainer : cs.onSurface,
        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _statusPill(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String text;
    switch (status) {
      case 'open':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        text = 'جديد';
        break;
      case 'dismissed':
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        text = 'مرفوض';
        break;
      default:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        text = 'تم إجراء إجراء';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child:
          Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
    );
  }
}

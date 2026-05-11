// lib/water/water_pages.dart
import 'package:flutter/material.dart';
import 'water_store.dart';

Future<void> showWaterQuickAddSheet(BuildContext context) async {
  final cupSizes = <int>[200, 250, 300, 330, 500]; // مليلتر
  int selectedCup = 250;
  int cups = 1;
  final litersCtl = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('تسجيل الماء', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),

            // إدخال بالأكواب
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: selectedCup,
                    decoration: const InputDecoration(
                      labelText: 'حجم الكوب (مل)',
                      border: OutlineInputBorder(),
                    ),
                    items: cupSizes
                        .map((ml) => DropdownMenuItem(value: ml, child: Text('$ml مل')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) selectedCup = v;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '$cups',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد الأكواب',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      cups = (n == null || n <= 0) ? 1 : n;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.local_drink),
                label: const Text('إضافة كأكواب'),
                onPressed: () async {
                  final liters = (selectedCup * cups) / 1000.0;
                  await WaterStore.addLiters(liters);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تمت إضافة ${liters.toStringAsFixed(2)} لتر')),
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 8),
            // إدخال مباشر باللتر
            TextField(
              controller: litersCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'كمية باللتر (مثال: 0.5)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('إضافة باللتر'),
                onPressed: () async {
                  final v = double.tryParse(litersCtl.text.trim()) ?? 0;
                  if (v <= 0) return;
                  await WaterStore.addLiters(v);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تمت إضافة ${v.toStringAsFixed(2)} لتر')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class WaterHistoryPage extends StatefulWidget {
  const WaterHistoryPage({super.key});

  @override
  State<WaterHistoryPage> createState() => _WaterHistoryPageState();
}

class _WaterHistoryPageState extends State<WaterHistoryPage> {
  List<MapEntry<String, double>> data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await WaterStore.recent(days: 30);
      list.sort((a, b) => b.key.compareTo(a.key)); // الأجدد من فوق
      if (mounted) {
        setState(() {
          data = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _weekdayAr(int weekday) {
    switch (weekday) {
      case 1:
        return 'الإثنين';
      case 2:
        return 'الثلاثاء';
      case 3:
        return 'الأربعاء';
      case 4:
        return 'الخميس';
      case 5:
        return 'الجمعة';
      case 6:
        return 'السبت';
      case 7:
        return 'الأحد';
      default:
        return '';
    }
  }

  String _fmtDMY(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  DateTime? _tryParseDate(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  String _fmtLiters(double value, {int decimals = 2}) {
    if (value.isNaN || value.isInfinite) return '0';
    return value.toStringAsFixed(decimals);
  }

  double get _totalLiters {
    double total = 0;
    for (final e in data) {
      total += e.value;
    }
    return total;
  }

  double get _averageLiters => data.isEmpty ? 0 : _totalLiters / data.length;

  double get _bestLiters {
    if (data.isEmpty) return 0;
    double best = 0;
    for (final e in data) {
      if (e.value > best) best = e.value;
    }
    return best;
  }

  Widget _summaryHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.16),
            cs.secondaryContainer.withOpacity(0.35),
            cs.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.water_drop_rounded, color: cs.primary, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سجل الماء',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'آخر ${data.length} يوم محفوظ — الأحدث يظهر أولًا',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'الإجمالي',
                    value: _fmtLiters(_totalLiters),
                    unit: 'لتر',
                    icon: Icons.opacity_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryTile(
                    label: 'المتوسط',
                    value: _fmtLiters(_averageLiters),
                    unit: 'لتر',
                    icon: Icons.insights_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryTile(
                    label: 'الأعلى',
                    value: _fmtLiters(_bestLiters),
                    unit: 'لتر',
                    icon: Icons.emoji_events_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _summaryHeader(context),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.55), width: 0.8),
          ),
          child: Column(
            children: [
              Icon(Icons.water_drop_outlined, color: cs.primary, size: 42),
              const SizedBox(height: 10),
              Text(
                'لا يوجد سجل ماء حتى الآن',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'ابدأ بتسجيل الماء من الصفحة الرئيسية وسيظهر هنا مع اليوم والتاريخ.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('سجل الماء')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : data.isEmpty
                  ? _emptyState(context)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: data.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) return _summaryHeader(context);

                        final e = data[index - 1];
                        final dt = _tryParseDate(e.key);
                        final dayText = dt != null ? _weekdayAr(dt.weekday) : 'اليوم';
                        final dateText = dt != null ? _fmtDMY(dt) : e.key;
                        final liters = e.value;

                        return _WaterHistoryCard(
                          dayText: dayText,
                          dateText: dateText,
                          litersText: _fmtLiters(liters),
                          progress: (liters / kPlentyWaterThresholdLiters).clamp(0.0, 1.0),
                          primaryColor: cs.primary,
                          surfaceColor: cs.surface,
                          outlineColor: cs.outlineVariant.withOpacity(0.55),
                          textColor: theme.textTheme.bodyMedium?.color ?? cs.onSurface,
                          subTextColor: cs.onSurfaceVariant,
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45), width: 0.7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaterHistoryCard extends StatelessWidget {
  const _WaterHistoryCard({
    required this.dayText,
    required this.dateText,
    required this.litersText,
    required this.progress,
    required this.primaryColor,
    required this.surfaceColor,
    required this.outlineColor,
    required this.textColor,
    required this.subTextColor,
  });

  final String dayText;
  final String dateText;
  final String litersText;
  final double progress;
  final Color primaryColor;
  final Color surfaceColor;
  final Color outlineColor;
  final Color textColor;
  final Color subTextColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: outlineColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.water_drop_rounded, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: subTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: litersText,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(
                          text: ' لتر',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: subTextColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: primaryColor.withOpacity(0.10),
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

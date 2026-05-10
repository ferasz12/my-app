// lib/screens/calories_history_screen.dart
import 'package:flutter/material.dart';
import '../services/tracker_store.dart';

/// سجلّ السعرات (تصميم مُصغّر):
/// - بطاقة صغيرة بالعرض: اليوم + التاريخ + السعرات
/// - زر "عرض التفاصيل" يفتح صفحة تعرض الماكروز بنفس ايموجيات الصفحة الرئيسية
class CaloriesHistoryScreen extends StatefulWidget {
  const CaloriesHistoryScreen({super.key});

  @override
  State<CaloriesHistoryScreen> createState() => _CaloriesHistoryScreenState();
}

class _CaloriesHistoryScreenState extends State<CaloriesHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _backgroundRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // helper: yyyy-mm-dd (محلي)
  String _ymd(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _loadHistory({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      // قراءة محلية فقط وسريعة؛ السحابة تتزامن بالخلفية داخل TrackerStore.
      final data = await TrackerStore.getAllDays();

      // ترتيب من الأحدث إلى الأقدم
      data.sort((a, b) {
        final da = DateTime.tryParse((a['date'] ?? '') as String) ?? DateTime(2000);
        final db = DateTime.tryParse((b['date'] ?? '') as String) ?? DateTime(2000);
        return db.compareTo(da);
      });

      // ✅ لا نعرض "اليوم" لأن التثبيت يتم 11:59م
      final String today = _ymd(DateTime.now());
      final filtered = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final m in data) {
        final d = (m['date'] ?? '').toString();
        if (d.isEmpty || d == today) continue;
        if (seen.contains(d)) continue;
        seen.add(d);
        filtered.add(m);
      }

      if (!mounted) return;
      setState(() => _history = filtered);
    } catch (e) {
      debugPrint('Error loading calories history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء تحميل سجلّ السعرات')),
      );
    } finally {
      if (mounted && showLoader) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_backgroundRefreshing) return;
    setState(() => _backgroundRefreshing = true);
    try {
      // تحديث محلي فقط. لا نقرأ Firestore من سجل السعرات حتى تبقى الصفحة سريعة.
      await _loadHistory(showLoader: false);
    } finally {
      if (mounted) setState(() => _backgroundRefreshing = false);
    }
  }

  Future<void> _deleteDay(String date) async {
    try {
      await TrackerStore.clearDay(date);
      await _loadHistory(showLoader: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف يوم $date')));
    } catch (e) {
      debugPrint('Error deleting day $date: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حذف هذا اليوم')));
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

  Widget _infoNote(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تنبيه: يتم تثبيت السعرات اليومية تلقائيًا الساعة 11:59 م. أي تعديل أثناء اليوم ينعكس في السجل بعد نهاية اليوم.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('سجل السعرات')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _infoNote(context),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'لا يوجد سجل حتى الآن',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _history.length + 1, // +1 للملاحظة
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) return _infoNote(context);

                      final item = _history[index - 1];
                      final date = (item['date'] ?? '').toString();

                      final calories = (item['calories'] as num?)?.toDouble() ?? 0.0;
                      final protein = (item['protein'] as num?)?.toDouble() ?? 0.0;
                      final carbs = (item['carb'] as num?)?.toDouble() ?? 0.0;
                      final fat = (item['fat'] as num?)?.toDouble() ?? 0.0;

                      DateTime? dt;
                      try {
                        dt = DateTime.parse(date);
                      } catch (_) {}

                      final day = dt != null ? _weekdayAr(dt.weekday) : 'اليوم';
                      final dateText = dt != null ? _fmtDMY(dt) : date;

                      return _HistoryCompactCard(
                        dayText: day,
                        dateText: dateText,
                        calories: calories,
                        onDetails: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaloriesDayDetailsPage(
                                dayText: day,
                                dateText: dateText,
                                rawDate: date,
                                calories: calories,
                                protein: protein,
                                carbs: carbs,
                                fat: fat,
                                onDelete: () => _deleteDay(date),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

/// بطاقة صغيرة بالعرض
class _HistoryCompactCard extends StatelessWidget {
  const _HistoryCompactCard({
    required this.dayText,
    required this.dateText,
    required this.calories,
    required this.onDetails,
  });

  final String dayText;
  final String dateText;
  final double calories;
  final VoidCallback onDetails;

  String _fmt0(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // اليوم + التاريخ
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // السعرات + زر التفاصيل
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmt0(calories)} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    foregroundColor: cs.primary,
                  ),
                  child: const Text(
                    'عرض التفاصيل',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// صفحة تفاصيل ماكروز يوم محدد (بنفس ايموجيات الصفحة الرئيسية)
class CaloriesDayDetailsPage extends StatelessWidget {
  const CaloriesDayDetailsPage({
    super.key,
    required this.dayText,
    required this.dateText,
    required this.rawDate,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.onDelete,
  });

  final String dayText;
  final String dateText;
  final String rawDate;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final VoidCallback onDelete;

  String _fmtNum(double v, {int decimals = 0}) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(decimals);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget macroLine({
      required String label,
      required String emoji,
      required String value,
      required String unit,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
            Text(
              '$value $unit',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$dayText • $dateText'),
        actions: [
          IconButton(
            tooltip: 'حذف هذا اليوم',
            onPressed: () async {
              // تأكيد بسيط
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) {
                  return AlertDialog(
                    title: const Text('حذف اليوم؟'),
                    content: Text('تأكيد حذف سجل يوم $rawDate؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                    ],
                  );
                },
              );
              if (ok == true) {
                onDelete();
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفاصيل اليوم',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                macroLine(
                  label: 'السعرات',
                  emoji: '🔥',
                  value: _fmtNum(calories, decimals: 0),
                  unit: 'kcal',
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                macroLine(
                  label: 'البروتين',
                  emoji: '🥩',
                  value: _fmtNum(protein, decimals: 1),
                  unit: 'غ',
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                macroLine(
                  label: 'الكارب',
                  emoji: '🍞',
                  value: _fmtNum(carbs, decimals: 1),
                  unit: 'غ',
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                macroLine(
                  label: 'الدهون',
                  emoji: '🥑',
                  value: _fmtNum(fat, decimals: 1),
                  unit: 'غ',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

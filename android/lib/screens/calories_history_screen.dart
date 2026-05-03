
// lib/screens/calories_history_screen.dart
import 'package:flutter/material.dart';
import '../services/tracker_store.dart';

/// شاشة سجلّ السعرات بشكل مبسّط:
/// - كل يوم سطر واحد: اليوم + التاريخ + زر "عرض التفاصيل"
/// - عند الضغط: BottomSheet فيه السعرات + البروتين + الكارب + الدهون
class CaloriesHistoryScreen extends StatefulWidget {
  const CaloriesHistoryScreen({super.key});

  @override
  State<CaloriesHistoryScreen> createState() => _CaloriesHistoryScreenState();
}

class _CaloriesHistoryScreenState extends State<CaloriesHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // helper: yyyy-mm-dd (محلي)
  String _ymd(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      // ✅ استخدام الدالة الستاتيكية الموجودة في TrackerStore
      final data = await TrackerStore.getAllDays();

      // ترتيب من الأحدث إلى الأقدم (لو ما كان مرتّب)
      data.sort((a, b) {
        final da = DateTime.tryParse((a['date'] ?? '') as String) ?? DateTime(2000);
        final db = DateTime.tryParse((b['date'] ?? '') as String) ?? DateTime(2000);
        return db.compareTo(da);
      });

      // ✅ عدم إظهار يوم "اليوم" في السجل — لأنه يُثبَّت 11:59م
      final String today = _ymd(DateTime.now());
      final filtered = <Map<String, dynamic>>[];
      final seen = <String>{}; // لمنع أي تكرارات لنفس اليوم (احتياطًا)

      for (final m in data) {
        final d = (m['date'] ?? '').toString();
        if (d.isEmpty || d == today) continue; // تجاهل اليوم الحالي
        if (seen.contains(d)) continue;
        seen.add(d);
        filtered.add(m);
      }

      if (!mounted) return;
      setState(() {
        _history = filtered;
      });
    } catch (e) {
      debugPrint('Error loading calories history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء تحميل سجلّ السعرات'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    await _loadHistory();
  }

  Future<void> _deleteDay(String date) async {
    try {
      // ✅ الدالة الموجودة في TrackerStore لمسح يوم معيّن
      await TrackerStore.clearDay(date);
      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف يوم $date'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error deleting calories day: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر حذف هذا اليوم، حاول مرة أخرى'),
        ),
      );
    }
  }

  String _fmtDMY(DateTime d) {
    return '${d.day}/${d.month}/${d.year}';
  }

  String _weekdayAr(int weekday) {
    switch (weekday) {
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      case DateTime.monday:
        return 'الاثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      default:
        return '';
    }
  }

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
              'تنبيه: يتم تثبيت السعرات اليومية تلقائيًا الساعة 11:59 م. أي حذف/تعديل أثناء اليوم ينعكس في السجل بعد نهاية اليوم.',
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
      appBar: AppBar(
        title: const Text('سجل السعرات'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history_toggle_off,
                            size: 48,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لا يوجد سجلّ بعد',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'كل يوم تُسجّل فيه وجباتك راح يضاف هنا تلقائيًا.\n(يتم التثبيت 11:59 م)',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('تحديث'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        // أول عنصر: ملاحظة التثبيت
                        if (index == 0) {
                          return _infoNote(context);
                        }
                        final item = _history[index - 1];
                        final date = (item['date'] ?? '').toString();

                        final cal = (item['calories'] as num?)?.toDouble() ?? 0.0;
                        final p = (item['protein'] as num?)?.toDouble() ?? 0.0;
                        final c = (item['carb'] as num?)?.toDouble() ?? 0.0;
                        final f = (item['fat'] as num?)?.toDouble() ?? 0.0;

                        DateTime? dt;
                        try {
                          dt = DateTime.parse(date);
                        } catch (_) {}

                        final pretty = dt != null
                            ? '${_weekdayAr(dt.weekday)} • ${_fmtDMY(dt)}'
                            : date;

                        return _DayCard(
                          prettyDate: pretty,
                          rawDate: date,
                          calories: cal,
                          protein: p,
                          carbs: c,
                          fat: f,
                          onDelete: () => _deleteDay(date),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemCount: _history.length + 1, // +1 لملاحظة التثبيت
                    ),
                  ),
      ),
    );
  }
}

/// الكارد البسيطة لليوم في القائمة
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.prettyDate,
    required this.rawDate,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.onDelete,
  });

  final String prettyDate;
  final String rawDate;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // نفصل اليوم عن التاريخ من النص "الأربعاء • 12/9/2025"
    final parts = prettyDate.split('•');
    final String dayText = parts.isNotEmpty ? parts[0].trim() : prettyDate;
    final String dateText = parts.length > 1 ? parts[1].trim() : rawDate;

    void _showDetails() {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          Widget _buildStatRow(String label, String value, IconData icon) {
            return Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // رأس الـ bottom sheet: اليوم + التاريخ + حذف
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dayText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dateText • مثبّت 11:59م',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'حذف هذا اليوم',
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onDelete();
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildStatRow(
                  'السعرات',
                  '${calories.toStringAsFixed(0)} kcal',
                  Icons.local_fire_department,
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'البروتين',
                  '${protein.toStringAsFixed(0)} g',
                  Icons.fitness_center,
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'الكربوهيدرات',
                  '${carbs.toStringAsFixed(0)} g',
                  Icons.rice_bowl,
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'الدهون',
                  '${fat.toStringAsFixed(0)} g',
                  Icons.egg_alt,
                ),

                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.5),
          width: 0.7,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: cs.primary.withOpacity(0.08),
          child: Icon(
            Icons.calendar_today,
            color: cs.primary,
            size: 18,
          ),
        ),
        title: Text(
          dayText, // اليوم
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '$dateText • مثبّت 11:59م', // التاريخ + توضيح التثبيت
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: TextButton(
          onPressed: _showDetails,
          child: const Text('عرض التفاصيل'),
        ),
        onTap: _showDetails,
      ),
    );
  }
}

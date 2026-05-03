// =============================================================
// FILE: lib/fasting/fasting_history_page.dart
// صفحة مستقلة تعرض "سجل الرجيم" (اليوم، المدة، نسبة الإنجاز)
// =============================================================
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'fasting_service.dart';

class FastingHistoryPage extends StatelessWidget {
  const FastingHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FastingService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('سجل الرجيم')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: fs.history.isEmpty
            ? Center(
                child: Text('لا يوجد سجل بعد — ابدأ أول صيام وسيظهر هنا 👌',
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            : 
ListView.separated(
  itemCount: fs.history.length,
  separatorBuilder: (_, __) => const SizedBox(height: 10),
  itemBuilder: (_, i) {
    final s = fs.history[i];
    final h = (s.durationSec / 3600);
    final durationText = h >= 1
        ? '${h.toStringAsFixed(h % 1 == 0 ? 0 : 1)} ساعة'
        : '${(h * 60).round()} دقيقة';
    final pct = (s.percentDone * 100).round();

    // صياغة اليوم/التاريخ
    final parts = s.ymd.split('-');
    String prettyDate = s.ymd;
    try {
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      prettyDate = DateFormat.EEEE('ar').format(dt); // اسم اليوم بالعربي
    } catch (_) {}

    return _FastingDayCard(
      prettyDate: prettyDate,
      rawDate: s.ymd,
      durationText: durationText,
      percent: pct,
      startAt: s.startAt,
      endAt: s.actualEndAt ?? s.plannedEndAt,
      onDelete: () async {
        await context.read<FastingService>().deleteHistoryDay(s.ymd);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف اليوم من السجل')),
        );
      },
    );
  },
),

      ),
    );
  }
}


class _FastingDayCard extends StatelessWidget {
  const _FastingDayCard({
    required this.prettyDate,
    required this.rawDate,
    required this.durationText,
    required this.percent,
    required this.startAt,
    required this.endAt,
    required this.onDelete,
  });

  final String prettyDate;
  final String rawDate;
  final String durationText;
  final int percent;
  final DateTime startAt;
  final DateTime endAt;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    void _showDetails() {
      final dayText = prettyDate;
      final dateText = rawDate;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return Directionality(
            textDirection: ui.TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          
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
                            dateText,
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
                  const SizedBox(height: 12),
                  _buildStatRow(context, 'المدة', durationText, Icons.schedule),
                  const SizedBox(height: 8),
                  _buildStatRow(context, 'الالتزام', '$percent%', Icons.task_alt),
                  const SizedBox(height: 8),
                  _buildStatRow(context, 'البداية', DateFormat('hh:mm a').format(startAt), Icons.play_circle),
                  const SizedBox(height: 8),
                  _buildStatRow(context, 'النهاية', DateFormat('hh:mm a').format(endAt), Icons.stop_circle_outlined),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        title: Text(
          prettyDate,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          rawDate,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        trailing: TextButton(
          onPressed: _showDetails,
          child: const Text('عرض التفاصيل'),
        ),
        onTap: _showDetails,
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
      ),
      child: Row(
        children: [
          
          Icon(icon, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(value, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

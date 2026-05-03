// lib/schedule/full_schedule_page.dart
import 'package:flutter/material.dart';
import 'schedule_helper.dart';

class FullSchedulePage extends StatelessWidget {
  final String planName;
  final List<Map<String, String>> schedule;

  const FullSchedulePage({
    super.key,
    required this.planName,
    required this.schedule,
  });

  @override
  Widget build(BuildContext context) {
    // نعرض الأيام مرتبة حسب ترتيب الأسبوع العربي
    final sorted = List<Map<String, String>>.from(schedule);
    final order = WorkoutHelper.orderedArabicDays;
    sorted.sort((a, b) => order
        .indexOf(a['اليوم'] ?? '')
        .compareTo(order.indexOf(b['اليوم'] ?? '')));

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(planName),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  cs.primaryContainer.withOpacity(.65),
                  cs.surface,
                ],
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.calendar_month_rounded, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الجدول الكامل',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        'استعرض أيام الأسبوع والتمارين المرتبطة بكل يوم.',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(.75),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(.65),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: cs.outlineVariant.withOpacity(.55)),
                  ),
                  child: Text(
                    '${sorted.length} أيام',
                    style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...sorted.map((d) {
            final day = d['اليوم'] ?? '';
            final workout = d['التمرين'] ?? '';
            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.today_rounded,
                          color: cs.onSecondaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(day,
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text(
                            workout.isEmpty ? '—' : workout,
                            style: tt.bodyMedium?.copyWith(height: 1.25),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

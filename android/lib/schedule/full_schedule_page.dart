// lib/schedule/full_schedule_page.dart
import 'package:flutter/material.dart';
import 'schedule_helper.dart';

class FullSchedulePage extends StatelessWidget {
  final String planName;
  final List<Map<String, String>> schedule;
  const FullSchedulePage({super.key, required this.planName, required this.schedule});

  @override
  Widget build(BuildContext context) {
    // نعرض الأيام مرتبة حسب ترتيب الأسبوع العربي
    final sorted = List<Map<String, String>>.from(schedule);
    final order = WorkoutHelper.orderedArabicDays;
    sorted.sort((a, b) => order.indexOf(a['اليوم'] ?? '') .compareTo(order.indexOf(b['اليوم'] ?? '')));

    return Scaffold(
      appBar: AppBar(title: Text('📖 $planName')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final d = sorted[i];
          return ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(d['اليوم'] ?? ''),
            subtitle: Text(d['التمرين'] ?? ''),
          );
        },
      ),
    );
  }
}

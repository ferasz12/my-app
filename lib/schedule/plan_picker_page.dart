// lib/schedule/plan_picker_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'create_schedule_page.dart';
import 'selected_schedule_page.dart';
import 'workout_data.dart'; // ← المصدر الرسمي للجداول الجاهزة

/// ------ موديلات الجداول المخصّصة (لتخزينها محليًا) ------

class WorkoutItem {
  final String name;
  final int sets;
  final int reps;
  WorkoutItem({required this.name, required this.sets, required this.reps});

  Map<String, dynamic> toMap() => {'name': name, 'sets': sets, 'reps': reps};
  factory WorkoutItem.fromMap(Map<String, dynamic> m) => WorkoutItem(
        name: (m['name'] ?? '').toString(),
        sets: (m['sets'] ?? 0) as int,
        reps: (m['reps'] ?? 0) as int,
      );
}

class ScheduleDay {
  final String title;
  final List<WorkoutItem> items;
  ScheduleDay({required this.title, required this.items});

  Map<String, dynamic> toMap() =>
      {'title': title, 'items': items.map((e) => e.toMap()).toList()};

  factory ScheduleDay.fromMap(Map<String, dynamic> m) => ScheduleDay(
        title: (m['title'] ?? '').toString(),
        items: ((m['items'] ?? []) as List)
            .map((e) => WorkoutItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class TrainingSchedule {
  final String id;
  final String name;
  final List<ScheduleDay> days;

  TrainingSchedule({required this.id, required this.name, required this.days});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'days': days.map((d) => d.toMap()).toList(),
      };

  factory TrainingSchedule.fromMap(Map<String, dynamic> m) =>
      TrainingSchedule(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        days: ((m['days'] ?? []) as List)
            .map((e) => ScheduleDay.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// تخزين الجداول المخصّصة لكل مستخدم
class CustomScheduleStorage {
  static String _keyFor(String email) => 'custom_schedules_$email';

  static Future<List<TrainingSchedule>> loadAll(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(email));
    if (raw == null) return [];
    try {
      final list = (json.decode(raw) as List)
          .map((e) =>
              TrainingSchedule.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsert(String email, TrainingSchedule s) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadAll(email);
    final idx = list.indexWhere((e) => e.id == s.id);
    if (idx >= 0) {
      list[idx] = s;
    } else {
      list.add(s);
    }
    await prefs.setString(
      _keyFor(email),
      json.encode(list.map((e) => e.toMap()).toList()),
    );
  }

  static Future<void> delete(String email, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadAll(email);
    list.removeWhere((e) => e.id == id);
    await prefs.setString(
      _keyFor(email),
      json.encode(list.map((e) => e.toMap()).toList()),
    );
  }
}

/// ------ أدوات نص صغيرة ------
TextStyle _scaleStyle(BuildContext context, TextStyle? s, double factor,
    {FontWeight? weight, Color? color}) {
  final baseSize = s?.fontSize ?? 14.0;
  return (s ?? const TextStyle()).copyWith(
    fontSize: baseSize * factor,
    fontWeight: weight ?? s?.fontWeight,
    color: color ?? s?.color,
  );
}

/// =====================================
///             الصفحة
/// =====================================
class PlanPickerPage extends StatefulWidget {
  const PlanPickerPage({super.key});

  @override
  State<PlanPickerPage> createState() => _PlanPickerPageState();
}

class _PlanPickerPageState extends State<PlanPickerPage> {
  /// أسماء الجداول الجاهزة من workout_data.dart
  List<String> _preNames = [];

  /// الجداول المخصّصة من التخزين
  List<TrainingSchedule> _custom = [];

  bool _loading = true;

  String get _email => FirebaseAuth.instance.currentUser?.email ?? 'guest';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// قراءة الجداول الجاهزة + تحميل المخصصة
  Future<void> _load() async {
    setState(() => _loading = true);

    // 1) من workout_data.dart (خريطة خطط جاهزة)
    _preNames = WorkoutData.workoutPlans.keys.toList();

    // 2) المخصّصة من التخزين
    _custom = await CustomScheduleStorage.loadAll(_email);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// إنشاء جدول جديد باستخدام الـ named route "/createSchedule"
  Future<void> _goToCreate() async {
    final created = await Navigator.pushNamed(context, '/createSchedule');
    if (!mounted) return;
    if (created == true) {
      await _load(); // ← يعيد تحميل "جداولي"
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ الجدول')),
      );
    }
  }

  /// افتح جدول — إن كان جاهزًا نمرر الاسم فقط (والقراءة من workout_data)
  void _openPredefined(String planName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectedSchedulePage(
          planName: planName,
        ),
      ),
    );
  }

  void _openCustom(TrainingSchedule s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectedSchedulePage(
          planName: s.name,
          scheduleMap: s.toMap(), // ← للمخصّص
        ),
      ),
    );
  }

  Future<void> _delete(TrainingSchedule s) async {
    await CustomScheduleStorage.delete(_email, s.id);
    await _load();
  }

  // ----------------- Helpers لعرض معلومات مختصرة -----------------
  Map<String, dynamic>? _planMapByName(String name) {
    final raw = WorkoutData.workoutPlans[name];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// يدعم days كشكل List أو Map
  int _preDaysCount(String name) {
    final m = _planMapByName(name);
    if (m == null) return 0;
    final days = m['days'];
    if (days is List) return days.length;
    if (days is Map) return days.length;
    return 0;
  }

  /// تقدير عدد التمارين في اليوم الأول (يدعم الشكلين)
  int _preItemsPerDayApprox(String name) {
    final m = _planMapByName(name);
    if (m == null) return 0;
    final days = m['days'];
    if (days is List) {
      if (days.isEmpty) return 0;
      final first = days.first;
      if (first is Map && first['items'] is List) {
        return (first['items'] as List).length;
      }
      return 0;
    } else if (days is Map) {
      if (days.isEmpty) return 0;
      final firstValue = (days.values).first;
      if (firstValue is List) return firstValue.length;
      return 0;
    }
    return 0;
  }

  String _preGoalText(String name) {
    final m = _planMapByName(name);
    final goal = m?['goal']?.toString();
    return goal ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('الجداول'),
        actions: [
          IconButton(
            tooltip: 'إنشاء جدول',
            icon: const Icon(Icons.add),
            onPressed: _goToCreate,
          ),
        ],
      ),
      // إن رغبت بالاكتفاء بزر الشريط العلوي فقط، احذف الـ FAB أدناه.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToCreate,
        icon: const Icon(Icons.add),
        label: const Text('إنشاء جدول'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _HeaderCard(
                    onCreate: _goToCreate,
                  ),
                  const SizedBox(height: 14),

                  // ======= الجاهزة من workout_data.dart =======
                  Text('جداول جاهزة',
                      style: _scaleStyle(context, tt.titleMedium, 1.1,
                          weight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ..._preNames.map(
                    (name) => _PredefinedTile(
                      name: name,
                      daysCount: _preDaysCount(name),
                      approxItemsPerDay: _preItemsPerDayApprox(name),
                      goalText: _preGoalText(name),
                      onTap: () => _openPredefined(name),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ======= المخصّصة (محفوظة محليًا) =======
                  Row(
                    children: [
                      Text('جداولي',
                          style: _scaleStyle(context, tt.titleMedium, 1.1,
                              weight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text('${_custom.length}',
                            style: tt.labelSmall?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_custom.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'ما عندك جداول مخصّصة حتى الآن. اضغط "إنشاء جدول".',
                        style: tt.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ..._custom.map(
                    (s) => _CustomTile(
                      schedule: s,
                      onOpen: () => _openCustom(s),
                      onDelete: () => _delete(s),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    ),
    );
  }
}

/// ====== بطاقة لعرض جدول جاهز (من workout_data.dart) ======
class _PredefinedTile extends StatelessWidget {
  const _PredefinedTile({
    required this.name,
    required this.daysCount,
    required this.approxItemsPerDay,
    required this.goalText,
    required this.onTap,
  });

  final String name;
  final int daysCount;
  final int approxItemsPerDay;
  final String goalText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isUniversal = goalText.trim().isEmpty ||
        goalText.trim() == 'مناسب لجميع الأهداف' ||
        goalText.trim() == 'عام';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                cs.primaryContainer.withOpacity(.55),
                cs.surface,
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(Icons.fitness_center, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniPill(
                          icon: Icons.calendar_month,
                          text: '$daysCount أيام',
                        ),
                        _MiniPill(
                          icon: Icons.bolt,
                          text: '$approxItemsPerDay / يوم',
                        ),
                        if (isUniversal)
                          const _MiniPill(
                            icon: Icons.verified_rounded,
                            text: 'مناسب للجميع',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_left, color: cs.onSurface.withOpacity(.55)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomTile extends StatelessWidget {
  const _CustomTile({
    required this.schedule,
    required this.onOpen,
    required this.onDelete,
  });

  final TrainingSchedule schedule;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final approx = schedule.days.isNotEmpty ? schedule.days.first.items.length : 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(Icons.edit_calendar, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.name.isEmpty ? 'جدول مخصّص' : schedule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniPill(
                          icon: Icons.calendar_month,
                          text: '${schedule.days.length} أيام',
                        ),
                        _MiniPill(
                          icon: Icons.bolt,
                          text: '$approx / يوم',
                        ),
                        const _MiniPill(
                          icon: Icons.star_rounded,
                          text: 'مخصّص',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'حذف',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: cs.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withOpacity(.72)),
          const SizedBox(width: 6),
          Text(
            text,
            style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primaryContainer.withOpacity(.70),
            cs.surface,
          ],
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.calendar_today_rounded, color: cs.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جدولك الرياضي',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  'اختر جدول جاهز أو أنشئ جدولك الخاص — مناسب لجميع الأهداف.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(.75),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }
}

// lib/screens/training_schedule_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../schedule/workout_data.dart';
import '../schedule/workout_sessions_page.dart';
import '../schedule/selected_schedule_page.dart';
import '../schedule/custom_schedule_storage.dart';
import '../schedule/schedule_helper.dart';

class TrainingSchedulePage extends StatefulWidget {
  const TrainingSchedulePage({super.key});

  @override
  State<TrainingSchedulePage> createState() => _TrainingSchedulePageState();
}

class _TrainingSchedulePageState extends State<TrainingSchedulePage> {
  String? selectedPlan;
  List<Map<String, dynamic>> _customPlans = [];
  bool _loading = true;

  // مفاتيح التخزين
  String _keySelectedPlan(String email) => 'selectedWorkoutPlan_$email';

  Future<String> _resolveEmail() async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail != null && userEmail.trim().isNotEmpty) {
      return userEmail.trim().toLowerCase();
    }
    final prefs = await SharedPreferences.getInstance();
    final alt = prefs.getString('user_email');
    return (alt != null && alt.trim().isNotEmpty)
        ? alt.trim().toLowerCase()
        : 'guest';
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail();

    selectedPlan = prefs.getString(_keySelectedPlan(email));
    _customPlans = await CustomScheduleStorage.loadAll(email);

    setState(() => _loading = false);
  }

  Future<void> _confirmSchedule(String planName) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail();
    await prefs.setString(_keySelectedPlan(email), planName);
    if (!mounted) return;

    setState(() => selectedPlan = planName);

    // بعد التأكيد: نفتح صفحة الجدول مباشرة
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectedSchedulePage(planName: planName),
      ),
    );
  }

  Future<void> _cancelPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail();
    await prefs.remove(_keySelectedPlan(email));
    if (!mounted) return;
    setState(() => selectedPlan = null);
  }

  void _openSessions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutSessionsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = WorkoutData.workoutPlans; // الجداول الجاهزة
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.of(context).size.width;
    final cross = w >= 900 ? 4 : (w >= 600 ? 3 : 2);
    final narrow = w < 380;

    return Scaffold(
      appBar: AppBar(title: const Text("جدولي الرياضي")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // ===== أعلى الصفحة: حالة الجدول المختار + الجلسات =====
                    if (selectedPlan != null)
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const CircleAvatar(child: Icon(Icons.check)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('الجدول الحالي',
                                        style: t.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                      selectedPlan!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _openSessions,
                                    icon: const Icon(Icons.history, size: 18),
                                    label: Text(narrow
                                        ? 'الجلسات'
                                        : 'جلسات التمارين'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SelectedSchedulePage(
                                              planName: selectedPlan!),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.visibility),
                                    label: const Text('عرض'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _cancelPlan,
                                    icon: const Icon(Icons.delete_forever),
                                    label: const Text('إلغاء'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: s.errorContainer,
                                      foregroundColor: s.onErrorContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ===== زر/بطاقة إنشاء جدول جديد =====
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final name =
                              await Navigator.pushNamed(context, '/createSchedule');
                          if (name is String && name.isNotEmpty) {
                            if (!mounted) return;
                            // اختَر الجدول مباشرة بعد الإنشاء
                            await _confirmSchedule(name);
                          } else {
                            _loadAll(); // قد يكون المستخدم عاد بدون إنشاء
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: const [
                              CircleAvatar(child: Icon(Icons.add)),
                              SizedBox(width: 12),
                              Expanded(child: Text('إنشاء جدولي بنفسي')),
                              Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ===== قسم جداولي المخصصة =====
                    if (_customPlans.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'جداولي المخصصة',
                          style: (narrow ? t.titleSmall : t.titleMedium)
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (_customPlans.isNotEmpty) const SizedBox(height: 6),
                    if (_customPlans.isNotEmpty)
                      _PlansGrid(
                        crossAxisCount: cross,
                        items: _customPlans
                            .map((e) => _PlanCardData(
                                  name: (e['name'] ?? '').toString(),
                                  subtitle: 'مخصص',
                                  onUse: () => _confirmSchedule(
                                      (e['name'] ?? '').toString()),
                                  onDelete: () async {
                                    final n = (e['name'] ?? '').toString();
                                    final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('حذف الجدول؟'),
                                            content: Text('سيتم حذف "$n".'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child: const Text('إلغاء')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  child: const Text('حذف')),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (ok) {
                                      final email = await _resolveEmail();
                                      await CustomScheduleStorage.delete(
                                          email, n);
                                      _loadAll();
                                    }
                                  },
                                ))
                            .toList(),
                      ),

                    if (_customPlans.isNotEmpty) const SizedBox(height: 16),

                    // ===== قسم الجداول الجاهزة =====
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "جداول جاهزة",
                        style: (narrow ? t.titleSmall : t.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: _PlansGrid(
                        crossAxisCount: cross,
                        items: plans.keys
                            .map((name) => _PlanCardData(
                                  name: name,
                                  subtitle: (plans[name]?['goal'] ?? '')
                                      .toString(),
                                  onUse: () => _confirmSchedule(name),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PlanCardData {
  final String name;
  final String subtitle;
  final VoidCallback onUse;
  final VoidCallback? onDelete;
  _PlanCardData({
    required this.name,
    required this.subtitle,
    required this.onUse,
    this.onDelete,
  });
}

class _PlansGrid extends StatelessWidget {
  final int crossAxisCount;
  final List<_PlanCardData> items;
  const _PlansGrid({super.key, required this.crossAxisCount, required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.4,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_note),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        it.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(it.subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: it.onUse,
                        child: const Text('استخدام الجدول'),
                      ),
                    ),
                    if (it.onDelete != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: it.onDelete,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
    );
  }
}

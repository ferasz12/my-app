// lib/schedule/create_schedule_page.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plan_picker_page.dart' show WorkoutItem, ScheduleDay, TrainingSchedule; // للنماذج
import 'schedule_storage.dart'; // ✅ للحفظ بصيغة تقرأها الصفحة الرئيسية
import 'workout_data.dart';     // ✅ للحقن الفوري داخل الخريطة العامة

class CreateSchedulePage extends StatefulWidget {
  const CreateSchedulePage({super.key, this.editing});

  final TrainingSchedule? editing;

  @override
  State<CreateSchedulePage> createState() => _CreateSchedulePageState();
}

class _CreateSchedulePageState extends State<CreateSchedulePage> {
  ColorScheme get cs => Theme.of(context).colorScheme;
  TextTheme get tt => Theme.of(context).textTheme;

  final _nameCtrl = TextEditingController();
  final List<ScheduleDay> _days = [];

  String get _email => FirebaseAuth.instance.currentUser?.email ?? 'guest';

  /// أيام الأسبوع العربية (اختيار سريع)
  static const _arabicWeekDays = <String>[
    'الأحد','الإثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت',
  ];

  bool _hasDay(String title) => _days.any((d) => d.title == title);

  void _addDayWithTitle(String title) {
    if (_hasDay(title)) return;
    setState(() {
      _days.add(ScheduleDay(title: title, items: <WorkoutItem>[]));
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _nameCtrl.text = widget.editing!.name;
      _days.addAll(widget.editing!.days);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // --------- حفظ متوافق قديمًا (يبقى) ---------
  Future<void> _upsertLegacyCustomSchedule(String email, TrainingSchedule s) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'custom_schedules_$email';

    List<Map<String, dynamic>> list = [];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        list = (json.decode(raw) as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        list = [];
      }
    }

    final map = s.toMap();
    // دمج حسب id أو الاسم (لتجنب التكرار عند التعديل)
    final idx = list.indexWhere((e) =>
        (('${e['id'] ?? ''}' == s.id) && s.id.isNotEmpty) ||
        (('${e['name'] ?? ''}').toLowerCase() == s.name.toLowerCase()));

    if (idx >= 0) {
      list[idx] = map;
    } else {
      list.add(map);
    }

    await prefs.setString(key, json.encode(list));
  }

  /// تحويل TrainingSchedule إلى الشكل الذي تتوقعه الصفحة الرئيسية (WorkoutData):
  /// { 'goal':'', 'days': { 'الأحد': [ {name,sets,reps}, ... ] , ... }, 'isCustom':true }
  Map<String, dynamic> _toWorkoutDataMap(TrainingSchedule s) {
    final Map<String, dynamic> daysMap = {};
    for (final d in s.days) {
      daysMap[d.title] = d.items.map((it) => {
        'name': it.name,
        'sets': it.sets,
        'reps': it.reps,
      }).toList();
    }
    return {
      'goal': '',
      'days': daysMap,
      'isCustom': true,
    };
  }

  /// إضافة يوم كامل عبر BottomSheet
  void _addDay() async {
    final titleCtrl = TextEditingController();
    final items = <WorkoutItem>[];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setM) {
            Future<void> addItem() async {
              final n = TextEditingController();
              final s = TextEditingController();
              final r = TextEditingController();
              final ok = await showDialog<bool>(
                context: ctx,
                builder: (_) => AlertDialog(
                  title: const Text('تمرين جديد'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
          Container(
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
                  child: Icon(Icons.playlist_add_rounded, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أنشئ جدولك الخاص',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اكتب اسم الجدول، اختر الأيام، ثم أضف التمارين لكل يوم.',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(.75),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

                      TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
                      const SizedBox(height: 8),
                      TextField(controller: s, decoration: const InputDecoration(labelText: 'الجموع (Sets)'), keyboardType: TextInputType.number),
                      const SizedBox(height: 8),
                      TextField(controller: r, decoration: const InputDecoration(labelText: 'التكرارات (Reps)'), keyboardType: TextInputType.number),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('إضافة')),
                  ],
                ),
              );
              if (ok == true) {
                final it = WorkoutItem(
                  name: n.text.trim().isEmpty ? 'تمرين' : n.text.trim(),
                  sets: int.tryParse(s.text) ?? 3,
                  reps: int.tryParse(r.text) ?? 10,
                );
                setM(() => items.add(it));
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'عنوان اليوم (مثال: يوم 1 — صدر/باي)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة تمرين'),
                  ),
                ),
                const SizedBox(height: 8),
                ...items.map((e) => ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(e.name),
                      subtitle: Text('Sets ${e.sets} • Reps ${e.reps}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setM(() => items.remove(e)),
                      ),
                    )),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty || items.isEmpty) {
                        Navigator.pop(ctx);
                        return;
                      }
                      _days.add(ScheduleDay(title: titleCtrl.text.trim(), items: List.of(items)));
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ اليوم'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    setState(() {});
  }

  /// ✅ إضافة تمرين داخل يوم موجود
  Future<void> _addExerciseToDay(ScheduleDay day) async {
    final n = TextEditingController();
    final s = TextEditingController();
    final r = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('إضافة تمرين — ${day.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: 'اسم التمرين')),
            const SizedBox(height: 8),
            TextField(controller: s, decoration: const InputDecoration(labelText: 'الجموع (Sets)'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: r, decoration: const InputDecoration(labelText: 'التكرارات (Reps)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('إضافة')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        day.items.add(WorkoutItem(
          name: n.text.trim().isEmpty ? 'تمرين' : n.text.trim(),
          sets: int.tryParse(s.text) ?? 3,
          reps: int.tryParse(r.text) ?? 10,
        ));
      });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().isEmpty ? 'جدول بدون اسم' : _nameCtrl.text.trim();
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف يومًا واحدًا على الأقل')),
      );
      return;
    }

    final id = widget.editing?.id ?? 'c_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final schedule = TrainingSchedule(id: id, name: name, days: List.of(_days));

    // 1) حفظ متوافق قديمًا (يبقى)
    await _upsertLegacyCustomSchedule(_email, schedule);

    // 2) ✅ حفظ بالشكل الذي تقرأه الصفحة الرئيسية + الحقن الفوري
    final wd = _toWorkoutDataMap(schedule);
    await ScheduleStorage.saveCustomPlan(wd);                 // يكتب في التخزين الذي تقرأه الصفحة الرئيسية
    WorkoutData.workoutPlans[name] = Map<String, dynamic>.from(wd); // حقن فوري ليظهر فورًا

    if (!mounted) return;
    Navigator.pop(context, true); // ← لصفحات سابقة (PlanPicker/التبويب) تعيد التحميل
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
      appBar: AppBar(title: Text(widget.editing == null ? 'إنشاء جدول' : 'تعديل الجدول')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('اسم الجدول', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.title),
              hintText: 'مثال: 3-Day Split أو جدول 3 أيام',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('الأيام', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addDay,
                icon: const Icon(Icons.add),
                label: const Text('إضافة يوم'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ==== اختيار سريع لأيام الأسبوع ====
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _arabicWeekDays.map((d) {
              final selected = _hasDay(d);
              return FilterChip(
                label: Text(d),
                selected: selected,
                onSelected: (val) {
                  if (val) {
                    _addDayWithTitle(d);
                  } else {
                    setState(() {
                      _days.removeWhere((e) => e.title == d);
                    });
                  }
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          if (_days.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(.5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text('لا توجد أيام بعد — اختر من الشيبس أعلاه أو اضغط "إضافة يوم".', style: tt.bodyMedium),
            ),

          ..._days.map((d) => Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ExpansionTile(
                    title: Text(d.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    children: [
                      if (d.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text('لا توجد تمارين بعد لهذا اليوم', style: tt.bodySmall),
                          ),
                        ),

                      // قائمة التمارين مع زر حذف لكل عنصر
                      ...d.items.map((e) => ListTile(
                            leading: const Icon(Icons.fitness_center),
                            title: Text(e.name),
                            subtitle: Text('Sets ${e.sets} • Reps ${e.reps}'),
                            trailing: IconButton(
                              tooltip: 'حذف التمرين',
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  d.items.remove(e);
                                });
                              },
                            ),
                          )),

                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _addExerciseToDay(d), // ✅ إضافة تمرين لليوم
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة تمرين لهذا اليوم'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              )),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ الجدول'),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

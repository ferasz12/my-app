// lib/schedule/selected_schedule_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

// مصدر الجداول الجاهزة (يُتوقع احتواؤه على workoutPlans)
import 'workout_data.dart';

/// ====== نماذج خفيفة للعرض ======
class _WorkoutItem {
  final String name;
  final int sets;
  final int reps;
  _WorkoutItem({required this.name, required this.sets, required this.reps});
}

class _ScheduleDay {
  final String title;
  final List<_WorkoutItem> items;
  _ScheduleDay({required this.title, required this.items});
}

class _TrainingSchedule {
  final String id;
  final String name;
  final List<_ScheduleDay> days;
  _TrainingSchedule({required this.id, required this.name, required this.days});
}

/// ====== صفحة عرض الجدول المختار (جاهز أو مخصّص) ======
class SelectedSchedulePage extends StatelessWidget {
  const SelectedSchedulePage({
    super.key,
    required this.planName,    // للجداول الجاهزة: الاسم كما في workout_data.dart
    this.scheduleMap,          // للجداول المخصّصة: الخريطة الناتجة من toMap()
  });

  final String planName;
  final Map<String, dynamic>? scheduleMap;

  // نفس المفتاح المستخدم في TrainingSchedulePage
  String _keySelectedPlan(String email) => 'selectedWorkoutPlan_$email';

  Future<void> _saveAsSelected(BuildContext context, String plan) async {
    final prefs = await SharedPreferences.getInstance();
    final email =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ??
            'guest';
    await prefs.setString(_keySelectedPlan(email), plan);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم اعتماد "$plan" كجدولك الحالي')),
      );
    }
  }

  // ====== أدوات تحويل مرنة ======
  static const _arDays = <String>{
    'الأحد','الاحد','الاثنين','الثلاثاء','الأربعاء','الاربعاء','الخميس','الجمعة','السبت'
  };
  static const _enDays = <String>{
    'sunday','monday','tuesday','wednesday','thursday','friday','saturday'
  };

  bool _looksLikeDayKey(String k) {
    final low = k.toLowerCase().trim();
    return _arDays.contains(k) ||
        _enDays.contains(low) ||
        RegExp(r'^(day|اليوم)\s*\d+$', caseSensitive: false).hasMatch(low);
  }

  int _toInt(dynamic v, {int def = 0}) {
    if (v is int) return v;
    if (v is double) return v.round();
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return def;
    final n = int.tryParse(s);
    return n ?? def;
  }

  String _firstNonEmpty(Map m, List<String> keys, {String def = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return def;
  }

  _WorkoutItem _parseItem(dynamic any) {
    // عنصر نصي فقط
    if (any is String) {
      return _WorkoutItem(name: any.trim(), sets: 0, reps: 0);
    }
    if (any is Map) {
      final map = Map<String, dynamic>.from(any as Map);
      final name = _firstNonEmpty(
        map,
        ['name','title','exercise','workout','label','اسم','التمرين'],
        def: 'تمرين',
      );
      final sets = _toInt(map['sets'] ?? map['set'] ?? map['جموع'] ?? map['setsCount'] ?? map['groups'] ?? 0);
      final reps = _toInt(map['reps'] ?? map['rep'] ?? map['تكرارات'] ?? map['repsCount'] ?? map['repeat'] ?? 0);
      return _WorkoutItem(name: name, sets: sets, reps: reps);
    }
    // fallback
    return _WorkoutItem(name: any?.toString() ?? 'تمرين', sets: 0, reps: 0);
  }

  _ScheduleDay _parseDayFromMapEntry(String title, dynamic itemsValue) {
    final itemsList = <_WorkoutItem>[];

    if (itemsValue is List) {
      for (final it in itemsValue) {
        itemsList.add(_parseItem(it));
      }
    } else if (itemsValue is Map) {
      final m = Map<String, dynamic>.from(itemsValue);
      final inner = m['items'] ?? m['exercises'] ?? m['workouts'] ?? m['تمارين'];
      if (inner is List) {
        for (final it in inner) {
          itemsList.add(_parseItem(it));
        }
      } else {
        for (final v in m.values) {
          if (v is List) {
            for (final it in v) {
              itemsList.add(_parseItem(it));
            }
          } else if (v != null) {
            itemsList.add(_parseItem(v));
          }
        }
      }
    } else if (itemsValue != null) {
      itemsList.add(_parseItem(itemsValue));
    }

    return _ScheduleDay(title: title, items: itemsList);
  }

  List<_ScheduleDay> _parseDaysFlexible(Map<String, dynamic> raw) {
    // 1) days موجودة
    if (raw['days'] != null) {
      final d = raw['days'];
      if (d is List) {
        // شكل: days: [ {title, items/exercises/workouts: [...]}, ... ]
        return d.map<_ScheduleDay>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final title = _firstNonEmpty(m, ['title','day','dayName','اليوم','name'], def: 'يوم');
          final itemsVal = m['items'] ?? m['exercises'] ?? m['workouts'] ?? m['تمارين'] ?? m['list'];
          return _parseDayFromMapEntry(title, itemsVal ?? m);
        }).toList();
      } else if (d is Map) {
        // شكل: days: { 'الأحد': [..], 'الاثنين':[...]} أو { 'الأحد': {'items':[...]} }
        final dm = Map<String, dynamic>.from(d);
        final out = <_ScheduleDay>[];
        dm.forEach((key, value) {
          out.add(_parseDayFromMapEntry(key.toString(), value));
        });
        return out;
      }
    }

    // 2) بدون days: نعتبر المفاتيح نفسها أيام إذا تشبه اسم يوم
    final out = <_ScheduleDay>[];
    raw.forEach((key, value) {
      final k = key.toString();
      if (k == 'id' || k == 'name' || k == 'title') return;
      if (_looksLikeDayKey(k)) {
        out.add(_parseDayFromMapEntry(k, value));
      }
    });

    // 3) fallback: يوم واحد بعنوان اسم الجدول لو لقيّنا قائمة تمارين عامة
    if (out.isEmpty) {
      final itemsVal = raw['items'] ?? raw['exercises'] ?? raw['workouts'] ?? raw['تمارين'] ?? raw['list'];
      if (itemsVal != null) {
        out.add(_parseDayFromMapEntry('اليوم 1', itemsVal));
      }
    }

    return out;
  }

  /// تحويل من خريطة (مخصّص أو جاهز)
  _TrainingSchedule _fromMap(Map<String, dynamic> m, String fallbackName) {
    final id = (m['id'] ?? 'sche_$fallbackName').toString();
    final name = (m['name'] ?? fallbackName).toString();
    final days = _parseDaysFlexible(m);
    return _TrainingSchedule(id: id, name: name, days: days);
  }

  /// قراءة الجدول الجاهز من workout_data.dart
  _TrainingSchedule? _loadFromWorkoutDataByName(String name) {
    try {
      final raw = WorkoutData.workoutPlans[name]; // ← توقّع Map/ List/ أي
      if (raw == null) return null;

      if (raw is Map) {
        return _fromMap(Map<String, dynamic>.from(raw as Map), name);
      }
      if (raw is List) {
        final fake = <String, dynamic>{'name': name, 'days': raw};
        return _fromMap(fake, name);
      }
      // أي شكل آخر: نحاول اعتباره عنصر واحد
      final fallback = <String, dynamic>{'name': name, 'items': raw.toString()};
      return _fromMap(fallback, name);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // مصدر البيانات: مخصّص من الـ Map أو جاهز بالاسم
    final _TrainingSchedule? schedule = scheduleMap != null
        ? _fromMap(scheduleMap!, planName)
        : _loadFromWorkoutDataByName(planName);

    if (schedule == null || schedule.days.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('الجدول')),
        body: const Center(
          child: Text('لم يتم العثور على بيانات هذا الجدول'),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(schedule.name.isEmpty ? planName : schedule.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // هيدر
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.onPrimaryContainer.withOpacity(.12),
                  child: Icon(Icons.fitness_center, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    schedule.name.isEmpty ? planName : schedule.name,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${schedule.days.length} أيام',
                    style: tt.labelLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // الأيام + التمارين
          ...schedule.days.map(
            (d) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                title: Text(
                  d.title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [
                  if (d.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text('لا توجد تمارين مسجّلة لهذا اليوم',
                          style: tt.bodySmall, textAlign: TextAlign.center),
                    ),
                  ...d.items.map(
                    (e) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceVariant.withOpacity(.20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.sports_gymnastics),
                        title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: (e.sets > 0 || e.reps > 0)
                            ? Text('Sets ${e.sets} • Reps ${e.reps}')
                            : const Text('—'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // اعتماد الجدول
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await _saveAsSelected(context, schedule.name.isEmpty ? planName : schedule.name);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('استخدام هذا الجدول'),
            ),
          ),
        ],
      ),
    );
  }
}

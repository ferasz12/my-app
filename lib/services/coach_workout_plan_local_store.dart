// lib/services/coach_workout_plan_local_store.dart
// يحفظ جداول التمارين التي ينشئها مدرب وازن محليًا فقط بدون Firestore.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../schedule/custom_schedule_storage.dart';
import '../schedule/schedule_storage.dart';
import '../schedule/workout_data.dart';
import 'ask_wazen_coach_api.dart';

class CoachWorkoutPlanLocalStore {
  CoachWorkoutPlanLocalStore._();

  static Future<String> _resolveEmail(SharedPreferences prefs) async {
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    final candidates = <String?>[
      authEmail,
      prefs.getString('currentEmail'),
      prefs.getString('email'),
      prefs.getString('userEmail'),
      prefs.getString('user_email'),
    ];
    return (candidates.firstWhere(
          (e) => e != null && e.trim().isNotEmpty,
          orElse: () => 'unknown_user',
        )!)
        .trim();
  }

  static List<String> _emailKeyVariants(String email) {
    final out = <String>{email.trim()};
    if (email.trim().isNotEmpty) out.add(email.trim().toLowerCase());
    return out.where((e) => e.isNotEmpty).toList();
  }

  static String _legacyKey(String email) => 'custom_schedules_$email';
  static String _selectedWorkoutKey(String email) => 'selectedWorkoutPlan_$email';

  static Map<String, dynamic> _daysAsWorkoutDataMap(CoachWorkoutPlan plan) {
    final daysMap = <String, dynamic>{};
    for (final day in plan.days) {
      daysMap[day.title] = day.items.map((item) => item.toMap()).toList();
    }
    return daysMap;
  }

  static List<Map<String, dynamic>> _decodeLegacyList(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      // ignore
    }
    return <Map<String, dynamic>>[];
  }

  static Map<String, dynamic> _toPlanPickerMap(CoachWorkoutPlan plan, String id) {
    return <String, dynamic>{
      'id': id,
      'name': plan.name,
      'goal': plan.goal,
      'summary': plan.summary,
      'days': plan.days.map((d) => d.toMap()).toList(),
      'createdByCoach': true,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> _toScheduleStorageMap(CoachWorkoutPlan plan) {
    return <String, dynamic>{
      'name': plan.name,
      'goal': plan.goal,
      'summary': plan.summary,
      'days': _daysAsWorkoutDataMap(plan),
      'isCustom': true,
      'createdByCoach': true,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  static Future<void> saveAndSelect(CoachWorkoutPlan plan) async {
    if (plan.name.trim().isEmpty || plan.days.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final legacyKeys = _emailKeyVariants(email).map(_legacyKey).toList();
    final legacyId = plan.id.trim().isNotEmpty
        ? plan.id.trim()
        : 'coach_${DateTime.now().millisecondsSinceEpoch}';

    final pickerPlan = _toPlanPickerMap(plan, legacyId);

    // 1) التخزين الذي تقرأه صفحة الجداول مباشرة: custom_schedules_$email.
    // نكتب بنسختين من مفتاح الإيميل لأن بعض صفحات الجداول تستخدم الإيميل كما هو
    // وبعض الخدمات القديمة تستخدمه lowercase.
    for (final key in legacyKeys) {
      final legacyList = _decodeLegacyList(prefs.getString(key));
      legacyList.removeWhere((e) {
        final id = (e['id'] ?? '').toString();
        final name = (e['name'] ?? '').toString().toLowerCase();
        return id == legacyId || name == plan.name.toLowerCase();
      });
      legacyList.add(pickerPlan);
      await prefs.setString(key, jsonEncode(legacyList));
    }

    // 2) نفس التخزين عبر CustomScheduleStorage للتوافق مع صفحة إنشاء الجداول.
    for (final variant in _emailKeyVariants(email)) {
      try {
        await CustomScheduleStorage.upsert(variant, pickerPlan);
      } catch (_) {
        // ignore
      }
    }

    // 3) التخزين الأحدث المستخدم في ScheduleStorage.
    await ScheduleStorage.saveCustomPlan(_toScheduleStorageMap(plan));
    await ScheduleStorage.saveSelectedPlan(plan.name);
    for (final variant in _emailKeyVariants(email)) {
      await prefs.setString(_selectedWorkoutKey(variant), plan.name);
    }

    // 4) تحديث الذاكرة الحالية حتى يظهر فورًا بدون إعادة تشغيل.
    WorkoutData.workoutPlans[plan.name] = <String, dynamic>{
      'name': plan.name,
      'goal': plan.goal,
      'summary': plan.summary,
      'days': _daysAsWorkoutDataMap(plan),
      'isCustom': true,
      'createdByCoach': true,
    };
  }

  static Future<List<String>> saveAndSelectAll(List<CoachWorkoutPlan> plans) async {
    final names = <String>[];
    for (final plan in plans) {
      if (plan.name.trim().isEmpty || plan.days.isEmpty) continue;
      await saveAndSelect(plan);
      names.add(plan.name);
    }
    return names;
  }
}

// lib/services/ask_wazen_report.dart
//
// "اسأل وازن" يحتاج إرسال ملخص واضح لبيانات المستخدم.
// هذا الملف يبني تقرير JSON من نفس مفاتيح SharedPreferences المستخدمة داخل التطبيق
// (السعرات/الماكروز، الماء، النشاط، الوزن، الصيام، الهدف...)

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/user_profile_source.dart' show getCurrentUserView;

class AskWazenReportBuilder {
  static String _ymd(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;

  static double _toD(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  static int _toI(dynamic v) =>
      (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

  static Map<String, dynamic> _jsonMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final x = json.decode(raw);
      return x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static List<dynamic> _jsonList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final x = json.decode(raw);
      return x is List ? x : const [];
    } catch (_) {
      return const [];
    }
  }

  /// يبني تقرير لآخر [days] يوم (افتراضي 7)
  /// مناسب للإرسال للسيرفر/الذكاء الاصطناعي.
  static Future<Map<String, dynamic>> build({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final fbUser = FirebaseAuth.instance.currentUser;

    final email = prefs.getString('currentEmail') ?? fbUser?.email ?? 'unknown_user';
    final today = DateTime.now();
    final todayYmd = _ymd(today);

    // الاسم الظاهر (نفس مصدر المجتمع/البروفايل)
    String displayName = '';
    try {
      if (fbUser != null) {
        final v = await getCurrentUserView();
        displayName = v.displayName.trim();
      }
    } catch (_) {}
    displayName = displayName.isNotEmpty
        ? displayName
        : (prefs.getString('displayName_$email') ??
            prefs.getString('name_$email') ??
            prefs.getString('fullName_$email') ??
            (fbUser?.displayName ?? ''))
            .toString()
            .trim();

    // بيانات أساسية (من مفاتيح الأهداف/البيانات)
    final gender = (prefs.getString('gender_$email') ?? '').toString();
    final age = prefs.getInt('age_$email') ?? 0;
    final heightCm = _toD(prefs.getDouble('height_$email') ?? 0);
    final currentWeightKg = _toD(prefs.getDouble('current_weight_$email') ??
        prefs.getDouble('weight_$email') ??
        prefs.getDouble('goal_current_$email') ??
        0);

    final goal = (prefs.getString('goal_$email') ?? '').toString();
    final goalDifficulty = (prefs.getString('goal_difficulty_$email') ?? '').toString();
    final goalTargetWeight = _toD(prefs.getDouble('goal_target_$email') ?? 0);
    final goalWeeklyChange = _toD(prefs.getDouble('goal_weekly_$email') ?? 0);
    final goalNote = (prefs.getString('goal_note_$email') ?? '').toString();

    final targetCalories = _toD(prefs.getDouble('caloriesNeeded_$email') ?? 0);
    final targetProtein = _toD(prefs.getDouble('protein_$email') ?? 0);
    final targetCarbs = _toD(prefs.getDouble('carbs_$email') ?? 0);
    final targetFat = _toD(prefs.getDouble('fat_$email') ?? 0);
    final stepsTarget = prefs.getInt('stepsTarget_$email') ?? 0;

    // لقطة الأهداف اليومية (تُكتب من HomeScreen)
    final dailyTargets = _jsonMap(prefs.getString('dailyNutritionHistory_$email'));

    // وزن (سجل محلي: weight_log_$email = List<Map>{date, kg})
    final weightLog = _jsonList(prefs.getString('weight_log_$email'))
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    double weightAt(String ymd) {
      for (final m in weightLog) {
        final d = (m['date'] ?? m['ymd'] ?? '').toString();
        if (d == ymd) return _toD(m['kg'] ?? m['weight'] ?? m['weightKg']);
      }
      return 0.0;
    }

    // صيام (سجل عالمي في هذا التطبيق)
    final fastingHistory = _jsonList(prefs.getString('fasting.history'))
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    Map<String, dynamic> fastingFor(String ymd) {
      final sessions = fastingHistory.where((e) => (e['ymd'] ?? '').toString() == ymd).toList();
      if (sessions.isEmpty) return {'sessions': 0, 'hours': 0.0};
      int cnt = sessions.length;
      int totalSec = 0;
      double avgDone = 0;
      for (final s in sessions) {
        totalSec += _toI(s['durationSec']);
        avgDone += _toD(s['percentDone']);
      }
      avgDone = cnt == 0 ? 0 : (avgDone / cnt);
      return {
        'sessions': cnt,
        'hours': (totalSec / 3600.0),
        'avg_completion': avgDone,
      };
    }

    // أيام التقرير
    final daysOut = <Map<String, dynamic>>[];
    for (int i = 0; i < days; i++) {
      final day = today.subtract(Duration(days: i));
      final ymd = _ymd(day);

      // أهداف اليوم
      final t = (dailyTargets[ymd] is Map)
          ? Map<String, dynamic>.from(dailyTargets[ymd] as Map)
          : <String, dynamic>{};

      // استهلاك اليوم
      final totals = _jsonMap(prefs.getString('kcal_daytotals_${email}_$ymd'));

      // ماء اليوم (Liters)
      final waterStr = prefs.getString('water_total_${email}_$ymd');
      final waterLiters = waterStr != null ? double.tryParse(waterStr) ?? 0.0 : 0.0;

      // نشاط اليوم (steps/burned)
      final activity = _jsonMap(prefs.getString('activity_${ymd}_$email'));

      final w = weightAt(ymd);
      final fasting = fastingFor(ymd);

      daysOut.add({
        'date': ymd,
        'target': {
          'calories': _toD(t['calories']),
          'protein': _toD(t['protein']),
          'carbs': _toD(t['carbs']),
          'fat': _toD(t['fat']),
        },
        'consumed': {
          'calories': _toD(totals['k']),
          'protein': _toD(totals['p']),
          'carbs': _toD(totals['c']),
          'fat': _toD(totals['f']),
        },
        'water_liters': waterLiters,
        'activity': {
          'steps': _toI(activity['steps']),
          'burned_kcal': _toI(activity['burned']),
        },
        'weight_kg': w,
        'fasting': fasting,
      });
    }

    // ملخص سريع (يساعد الذكاء الاصطناعي بدون حسابات معقدة)
    double avg(String keyK, {required bool consumed}) {
      double sum = 0;
      int n = 0;
      for (final d in daysOut) {
        final m = (consumed ? d['consumed'] : d['target']) as Map<String, dynamic>;
        final v = _toD(m[keyK]);
        if (v > 0) {
          sum += v;
          n++;
        }
      }
      return n == 0 ? 0 : (sum / n);
    }

    int underProteinDays = 0;
    for (final d in daysOut) {
      final tp = _toD((d['target'] as Map)['protein']);
      final cp = _toD((d['consumed'] as Map)['protein']);
      if (tp > 0 && cp < tp * 0.85) underProteinDays++;
    }

    return {
      'schema': 1,
      'ymd': todayYmd,
      'user': {
        'uid': fbUser?.uid,
        'email': email,
        'name': displayName,
      },
      'profile': {
        'gender': gender,
        'age': age,
        'height_cm': heightCm,
        'current_weight_kg': currentWeightKg,
        'steps_target': stepsTarget,
      },
      'goal': {
        'name': goal,
        'difficulty': goalDifficulty,
        'target_weight_kg': goalTargetWeight,
        'weekly_change_kg': goalWeeklyChange,
        'note': goalNote,
      },
      'targets': {
        'calories': targetCalories,
        'protein': targetProtein,
        'carbs': targetCarbs,
        'fat': targetFat,
      },
      'window_days': days,
      'days': daysOut,
      'derived': {
        'avg_target_calories': avg('calories', consumed: false),
        'avg_consumed_calories': avg('calories', consumed: true),
        'avg_target_protein': avg('protein', consumed: false),
        'avg_consumed_protein': avg('protein', consumed: true),
        'under_protein_days': underProteinDays,
      },
    };
  }
}

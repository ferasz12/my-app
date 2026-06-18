// lib/services/ask_wazen_report.dart
//
// "اسأل وازن" يحتاج إرسال ملخص واضح لبيانات المستخدم.
// هذا الملف يبني تقرير JSON من نفس مفاتيح SharedPreferences المستخدمة داخل التطبيق
// (السعرات/الماكروز، الماء، النشاط، الوزن، الصيام، الهدف...)

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/session_manager.dart';
import '../shared/user_profile_source.dart' show getCurrentUserView;
import '../shared/wazen_profile_prefs.dart';
import '../core/data/wazen_identity_store.dart';

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

  static String _cleanMealSlotName(dynamic raw) {
    return (raw ?? '')
        .toString()
        .replaceAll(RegExp(r'[🍳🍽️🌙🥗🍱☕️☕🥣]'), '')
        .trim();
  }

  static String _foodName(dynamic item) {
    if (item is! Map) return '';
    return (item['name'] ??
            item['meal_name'] ??
            item['title'] ??
            item['foodName'] ??
            item['label'] ??
            '')
        .toString()
        .trim();
  }

  static Map<String, dynamic> _summarizeMeals(List<dynamic> rawMeals) {
    final slots = <Map<String, dynamic>>[];
    final allItems = <Map<String, dynamic>>[];

    for (final meal in rawMeals) {
      if (meal is! Map) continue;
      final slotName = _cleanMealSlotName(meal['name'] ?? meal['title'] ?? 'وجبة');
      final rawItems = meal['items'];
      final items = rawItems is List ? rawItems : const [];
      final slotItems = <Map<String, dynamic>>[];

      if (items.isEmpty) {
        final name = _foodName(meal);
        final cal = _toD(meal['cal'] ?? meal['calories'] ?? meal['kcal'] ?? meal['k']);
        final protein = _toD(meal['protein'] ?? meal['p']);
        final carbs = _toD(meal['carb'] ?? meal['carbs'] ?? meal['c']);
        final fat = _toD(meal['fat'] ?? meal['f']);
        if (name.isNotEmpty && (cal > 0 || protein > 0 || carbs > 0 || fat > 0)) {
          final one = <String, dynamic>{
            'slot': slotName.isEmpty ? 'وجبة' : slotName,
            'name': name,
            'calories': cal,
            'protein': protein,
            'carbs': carbs,
            'fat': fat,
          };
          slotItems.add(one);
          allItems.add(one);
        }
      }

      for (final item in items) {
        if (item is! Map) continue;
        final name = _foodName(item);
        if (name.isEmpty) continue;
        final one = <String, dynamic>{
          'slot': slotName.isEmpty ? 'وجبة' : slotName,
          'name': name,
          'calories': _toD(item['cal'] ?? item['calories'] ?? item['kcal'] ?? item['k']),
          'protein': _toD(item['protein'] ?? item['p']),
          'carbs': _toD(item['carb'] ?? item['carbs'] ?? item['c']),
          'fat': _toD(item['fat'] ?? item['f']),
        };
        slotItems.add(one);
        allItems.add(one);
      }

      if (slotItems.isNotEmpty) {
        slots.add({
          'name': slotName.isEmpty ? 'وجبة' : slotName,
          'items_count': slotItems.length,
          'items': slotItems.take(8).toList(),
        });
      }
    }

    return {
      'total_items': allItems.length,
      'first_item': allItems.isNotEmpty ? allItems.first : null,
      'last_item': allItems.isNotEmpty ? allItems.last : null,
      'slots_count': slots.length,
      'slots': slots,
      'items_flat': allItems.take(20).toList(),
    };
  }


  static Map<String, dynamic> _totalsFromMealsSummary(Map<String, dynamic> mealsSummary) {
    final items = mealsSummary['items_flat'];
    if (items is! List) return <String, dynamic>{};
    double k = 0, p = 0, c = 0, f = 0;
    for (final item in items) {
      if (item is! Map) continue;
      k += _toD(item['calories']);
      p += _toD(item['protein']);
      c += _toD(item['carbs']);
      f += _toD(item['fat']);
    }
    return {'k': k, 'p': p, 'c': c, 'f': f};
  }

  static Map<String, dynamic> _readTotalsForDay(
    SharedPreferences prefs, {
    required String email,
    required String storageKey,
    required List<String> aliases,
    required String ymd,
  }) {
    final userKeys = <String>{email, storageKey, ...aliases}
      ..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
    final keys = <String>{
      for (final alias in userKeys) 'kcal_daytotals_${alias}_$ymd',
    }..removeWhere((e) => e.contains('unknown_user'));

    for (final key in keys) {
      final totals = _jsonMap(prefs.getString(key));
      if (_toD(totals['k']) > 0 || _toD(totals['p']) > 0 || _toD(totals['c']) > 0 || _toD(totals['f']) > 0) {
        return totals;
      }
    }

    for (final key in <String>{
      for (final alias in userKeys) 'intake_entries_${alias}_$ymd',
      for (final alias in userKeys) 'kcal_entries_${alias}_$ymd',
    }) {
      final raw = prefs.getString(key);
      final list = _jsonList(raw);
      double k = 0, p = 0, c = 0, f = 0;
      for (final item in list) {
        if (item is! Map) continue;
        k += _toD(item['k'] ?? item['cal'] ?? item['calories']);
        p += _toD(item['p'] ?? item['protein']);
        c += _toD(item['c'] ?? item['carb'] ?? item['carbs']);
        f += _toD(item['f'] ?? item['fat']);
      }
      if (k > 0 || p > 0 || c > 0 || f > 0) return {'k': k, 'p': p, 'c': c, 'f': f};
    }

    return <String, dynamic>{};
  }

  static List<dynamic> _readMealsForDay(
    SharedPreferences prefs, {
    required String email,
    required String storageKey,
    required List<String> aliases,
    required String ymd,
    required bool isToday,
  }) {
    final userKeys = <String>{email, storageKey, ...aliases}
      ..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
    for (final alias in userKeys) {
      final raw = prefs.getString('meals_${alias}_$ymd') ??
          prefs.getString('intake_entries_${alias}_$ymd') ??
          prefs.getString('kcal_entries_${alias}_$ymd') ??
          (isToday ? prefs.getString('meals_$alias') : null);
      final list = _jsonList(raw);
      if (list.isNotEmpty) return list;
    }
    return const [];
  }

  /// يبني تقرير لآخر [days] يوم (افتراضي 7)
  /// مناسب للإرسال للسيرفر/الذكاء الاصطناعي.
  static Future<Map<String, dynamic>> build({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final fbUser = FirebaseAuth.instance.currentUser;

    if (fbUser != null) {
      await WazenIdentityStore.syncFromFirebaseUser(fbUser, prefs: prefs, migrate: true);
    }
    final aliases = await WazenProfilePrefs.aliases(prefs, user: fbUser, migrate: false);
    final profileKey = WazenProfilePrefs.latestAlias(prefs, aliases);
    final email = (fbUser?.email ?? prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ?? prefs.getString('currentEmail') ?? 'unknown_user').trim();
    final storageKey = await SessionManager.currentStorageKey();
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
        : (WazenProfilePrefs.readString(
              prefs,
              const ['displayName_', 'name_', 'fullName_'],
              aliases,
              preferred: profileKey,
            ) ??
            (fbUser?.displayName ?? ''))
            .toString()
            .trim();

    // بيانات أساسية (من مفاتيح الأهداف/البيانات) — قراءة موحدة من كل aliases.
    final gender = (WazenProfilePrefs.readString(prefs, const ['gender_'], aliases, preferred: profileKey) ?? '').toString();
    final age = WazenProfilePrefs.readInt(prefs, const ['age_'], aliases, preferred: profileKey) ?? 0;
    final heightCm = _toD(WazenProfilePrefs.readDouble(prefs, const ['height_', 'height_cm_', 'heightCm_'], aliases, preferred: profileKey) ?? 0);
    final currentWeightKg = _toD(WazenProfilePrefs.readDouble(
          prefs,
          const ['current_weight_', 'weight_', 'weightKg_', 'currentWeight_', 'user_weight_', 'goal_current_'],
          aliases,
          preferred: profileKey,
        ) ??
        0);

    final goal = (WazenProfilePrefs.readString(prefs, const ['goal_', 'user_goal_'], aliases, preferred: profileKey) ?? '').toString();
    final goalDifficulty = (WazenProfilePrefs.readString(prefs, const ['goal_difficulty_'], aliases, preferred: profileKey) ?? '').toString();
    final goalTargetWeight = _toD(WazenProfilePrefs.readDouble(
          prefs,
          const ['goal_target_', 'targetWeight_', 'target_weight_', 'goalWeight_', 'targetWeightKg_'],
          aliases,
          preferred: profileKey,
        ) ??
        0);
    final goalWeeklyChange = _toD(WazenProfilePrefs.readDouble(prefs, const ['goal_weekly_'], aliases, preferred: profileKey) ?? 0);
    final goalNote = (WazenProfilePrefs.readString(prefs, const ['goal_note_'], aliases, preferred: profileKey) ?? '').toString();

    final targetCalories = _toD(WazenProfilePrefs.readDouble(prefs, const ['caloriesNeeded_'], aliases, preferred: profileKey) ?? 0);
    final targetProtein = _toD(WazenProfilePrefs.readDouble(prefs, const ['protein_'], aliases, preferred: profileKey) ?? 0);
    final targetCarbs = _toD(WazenProfilePrefs.readDouble(prefs, const ['carbs_', 'carb_'], aliases, preferred: profileKey) ?? 0);
    final targetFat = _toD(WazenProfilePrefs.readDouble(prefs, const ['fat_'], aliases, preferred: profileKey) ?? 0);
    final stepsTarget = WazenProfilePrefs.readInt(prefs, const ['stepsTarget_'], aliases, preferred: profileKey) ?? 0;

    // لقطة الأهداف اليومية (تُكتب من HomeScreen)
    final dailyTargets = _jsonMap(WazenProfilePrefs.readString(
      prefs,
      const ['dailyNutritionHistory_'],
      aliases,
      preferred: profileKey,
    ));

    // وزن (سجل محلي: weight_log_$alias = List<Map>{date, kg})
    final weightLog = <Map<String, dynamic>>[];
    for (final alias in WazenProfilePrefs.orderedAliases(aliases, preferred: profileKey)) {
      weightLog.addAll(
        _jsonList(prefs.getString('weight_log_$alias'))
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
    }
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

      // استهلاك اليوم من نفس سجل السعرات، مع دعم مفاتيح البريد ومفتاح التخزين.
      var totals = _readTotalsForDay(
        prefs,
        email: email,
        storageKey: storageKey,
        aliases: aliases,
        ymd: ymd,
      );

      // وجبات اليوم: تساعد المدرب يعرف هل هذه أول/ثاني وجبة وما الذي أُكل فعليًا.
      final mealsRaw = _readMealsForDay(
        prefs,
        email: email,
        storageKey: storageKey,
        aliases: aliases,
        ymd: ymd,
        isToday: i == 0,
      );
      final mealsSummary = _summarizeMeals(mealsRaw);
      if (_toD(totals['k']) == 0 && _toD(totals['p']) == 0 && _toD(totals['c']) == 0 && _toD(totals['f']) == 0) {
        totals = _totalsFromMealsSummary(mealsSummary);
      }

      // ماء اليوم (Liters)
      double waterLiters = 0.0;
      for (final alias in WazenProfilePrefs.orderedAliases(aliases, preferred: profileKey)) {
        final waterStr = prefs.getString('water_total_${alias}_$ymd');
        final parsed = waterStr != null ? double.tryParse(waterStr) ?? 0.0 : 0.0;
        if (parsed > 0) {
          waterLiters = parsed;
          break;
        }
      }

      // نشاط اليوم (steps/burned)
      var activity = <String, dynamic>{};
      for (final alias in WazenProfilePrefs.orderedAliases(aliases, preferred: profileKey)) {
        activity = _jsonMap(prefs.getString('activity_${ymd}_$alias'));
        if (_toI(activity['steps']) > 0 || _toI(activity['burned']) > 0) break;
      }

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
        'meals': mealsSummary,
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

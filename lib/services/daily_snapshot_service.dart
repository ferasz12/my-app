import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/wazen_profile_prefs.dart';

class DailySnapshotService {
  static Future<void> ensureTodaySnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final aliases = await WazenProfilePrefs.aliases(
      prefs,
      user: FirebaseAuth.instance.currentUser,
    );
    if (aliases.isEmpty) return;

    final profileKey = WazenProfilePrefs.latestAlias(prefs, aliases);

    // تاريخ اليوم (محلي)
    final today = DateTime.now().toIso8601String().split('T').first;
    final last = WazenProfilePrefs.readString(
      prefs,
      const ['lastSnapshotDate_'],
      aliases,
      preferred: profileKey,
    );
    if (last == today) return; // تم إنشاؤها اليوم

    // اقرأ الأهداف الحالية من نفس مفاتيح بياناتي/الهوم/التتبع.
    final calories = WazenProfilePrefs.readDouble(
          prefs,
          const ['caloriesNeeded_'],
          aliases,
          preferred: profileKey,
        ) ??
        2000;
    final protein = WazenProfilePrefs.readDouble(
          prefs,
          const ['protein_'],
          aliases,
          preferred: profileKey,
        ) ??
        100;
    final carbs = WazenProfilePrefs.readDouble(
          prefs,
          const ['carbs_', 'carb_'],
          aliases,
          preferred: profileKey,
        ) ??
        250;
    final fat = WazenProfilePrefs.readDouble(
          prefs,
          const ['fat_'],
          aliases,
          preferred: profileKey,
        ) ??
        60;

    final rawHistory = WazenProfilePrefs.readString(
      prefs,
      const ['dailyNutritionHistory_'],
      aliases,
      preferred: profileKey,
    );
    Map<String, dynamic> history = {};
    if (rawHistory != null) {
      try {
        history = json.decode(rawHistory) as Map<String, dynamic>;
      } catch (_) {
        history = {};
      }
    }

    history[today] ??= {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
    };

    await WazenProfilePrefs.writeAll(
      prefs,
      aliases,
      (alias) => 'dailyNutritionHistory_$alias',
      json.encode(history),
    );
    await WazenProfilePrefs.writeAll(
      prefs,
      aliases,
      (alias) => 'lastSnapshotDate_$alias',
      today,
    );

    // (اختياري) صفّر مجاميع اليوم حتى ما ترحّل من أمس
    for (final alias in aliases) {
      await prefs.remove('consumed_cal_$alias');
      await prefs.remove('consumed_pro_$alias');
      await prefs.remove('consumed_carb_$alias');
      await prefs.remove('consumed_fat_$alias');
    }
  }
}

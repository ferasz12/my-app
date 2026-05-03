import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DailySnapshotService {
  static Future<void> ensureTodaySnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail');
    if (email == null) return;

    // تاريخ اليوم (محلي)
    final today = DateTime.now().toIso8601String().split('T').first;
    final last = prefs.getString('lastSnapshotDate_$email');
    if (last == today) return; // تم إنشاؤها اليوم

    // اقرأ الأهداف الحالية (قد تكون من الأمس، وهذا المقصود: نثبت أهداف اليوم)
    final calories = prefs.getDouble('caloriesNeeded_$email') ?? 2000;
    final protein  = prefs.getDouble('protein_$email') ?? 100;
    final carbs    = prefs.getDouble('carbs_$email') ?? 250;
    final fat      = prefs.getDouble('fat_$email') ?? 60;

    // سجل الأيام
    final rawHistory = prefs.getString('dailyNutritionHistory_$email');
    Map<String, dynamic> history = {};
    if (rawHistory != null) {
      try { history = json.decode(rawHistory); } catch (_) { history = {}; }
    }

    // أنشئ إدخال اليوم إذا غير موجود
    history[today] ??= {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
    };

    await prefs.setString('dailyNutritionHistory_$email', json.encode(history));
    await prefs.setString('lastSnapshotDate_$email', today);

    // (اختياري) صفّر مجاميع اليوم حتى ما ترحّل من أمس
    await prefs.remove('consumed_cal_$email'); // إن كنت تستخدم مفتاحًا لليوم كله
    await prefs.remove('consumed_pro_$email');
    await prefs.remove('consumed_carb_$email');
    await prefs.remove('consumed_fat_$email');
  }
}
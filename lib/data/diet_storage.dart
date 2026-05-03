// lib/data/diet_storage.dart
import 'package:shared_preferences/shared_preferences.dart';

class DietStorage {
  static String _dateKey(DateTime d) {
    // YYYY-MM-DD
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// اجلب مفتاح اليوم بصيغة السجل المعتمدة
  static String todayKey() => _dateKey(DateTime.now());

  /// أضف/ادمج القيم مع اليوم (يستخدم setDouble)
  static Future<void> addToDay({
    required DateTime day,
    double calories = 0,
    double protein = 0,
    double carb = 0,
    double fat = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dateKey(day);

    final oldCals = prefs.getDouble('dietCalories_$key') ?? 0.0;
    final oldProt = prefs.getDouble('dietProtein_$key') ?? 0.0;
    final oldCarb = prefs.getDouble('dietCarb_$key') ?? 0.0;
    final oldFat = prefs.getDouble('dietFat_$key') ?? 0.0;

    await prefs.setDouble('dietCalories_$key', oldCals + calories);
    await prefs.setDouble('dietProtein_$key', oldProt + protein);
    await prefs.setDouble('dietCarb_$key', oldCarb + carb);
    await prefs.setDouble('dietFat_$key', oldFat + fat);
  }

  /// نفس السابقة لكن لليوم الحالي
  static Future<void> addToToday({
    double calories = 0,
    double protein = 0,
    double carb = 0,
    double fat = 0,
  }) {
    return addToDay(
      day: DateTime.now(),
      calories: calories,
      protein: protein,
      carb: carb,
      fat: fat,
    );
  }

  /// قراءة يوم واحد
  static Future<Map<String, double>> readDay(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dateKey(day);
    return {
      'calories': prefs.getDouble('dietCalories_$key') ?? 0.0,
      'protein': prefs.getDouble('dietProtein_$key') ?? 0.0,
      'carb': prefs.getDouble('dietCarb_$key') ?? 0.0,
      'fat': prefs.getDouble('dietFat_$key') ?? 0.0,
    };
  }

  /// جلب كل الأيام الموجودة في التخزين
  static Future<List<String>> listAllDays() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final days = <String>{};
    for (final k in keys) {
      if (k.startsWith('dietCalories_')) {
        days.add(k.replaceFirst('dietCalories_', ''));
      }
    }
    final list = days.toList();
    list.sort((a, b) => b.compareTo(a)); // أحدث أولاً
    return list;
  }

  /// حذف يوم معيّن
  static Future<void> removeDay(String dayKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dietCalories_$dayKey');
    await prefs.remove('dietProtein_$dayKey');
    await prefs.remove('dietCarb_$dayKey');
    await prefs.remove('dietFat_$dayKey');
  }

  /// حذف الكل (بحذر)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final k in keys) {
      if (k.startsWith('dietCalories_') ||
          k.startsWith('dietProtein_') ||
          k.startsWith('dietCarb_') ||
          k.startsWith('dietFat_')) {
        await prefs.remove(k);
      }
    }
  }
}

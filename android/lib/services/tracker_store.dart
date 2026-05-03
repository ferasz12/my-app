// lib/services/tracker_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TrackerStore {
  /// تنسيق التاريخ: YYYY-MM-DD
  static String _todayKey() {
    final now = DateTime.now();
    return _keyForDate(now);
  }

  static String _keyForDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return 'diet_$y-$m-$day'; // مثال: diet_2025-08-22
  }

  /// إضافة استهلاك لليوم (تجميع فوق الموجود)
  static Future<void> addIntake({
    required double cal,
    required double protein,
    required double carb,
    required double fat,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _todayKey();
    final raw = prefs.getString(key);
    double c = 0, p = 0, cb = 0, f = 0;

    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      c = (m['calories'] as num?)?.toDouble() ?? 0;
      p = (m['protein'] as num?)?.toDouble() ?? 0;
      cb = (m['carb'] as num?)?.toDouble() ?? 0;
      f = (m['fat'] as num?)?.toDouble() ?? 0;
    }

    final newMap = {
      'date': key.replaceFirst('diet_', ''), // خزن التاريخ للعرض لاحقًا
      'calories': c + cal,
      'protein': p + protein,
      'carb': cb + carb,
      'fat': f + fat,
    };

    await prefs.setString(key, jsonEncode(newMap));
  }

  /// قراءة يوم محدد
  static Future<Map<String, dynamic>> getDay(DateTime d) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForDate(d);
    final raw = prefs.getString(key);
    if (raw == null) {
      return {
        'date': key.replaceFirst('diet_', ''),
        'calories': 0.0,
        'protein': 0.0,
        'carb': 0.0,
        'fat': 0.0,
      };
    }
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      'date': (m['date'] ?? key.replaceFirst('diet_', '')).toString(),
      'calories': (m['calories'] as num?)?.toDouble() ?? 0.0,
      'protein': (m['protein'] as num?)?.toDouble() ?? 0.0,
      'carb': (m['carb'] as num?)?.toDouble() ?? 0.0,
      'fat': (m['fat'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// جميع الأيام المخزنة بصيغة [{date, calories, protein, carb, fat}, ...] مرتبة من الأحدث
  static Future<List<Map<String, dynamic>>> getAllDays() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('diet_')).toList();

    final list = <Map<String, dynamic>>[];
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      list.add({
        'date': (m['date'] ?? k.replaceFirst('diet_', '')).toString(),
        'calories': (m['calories'] as num?)?.toDouble() ?? 0.0,
        'protein': (m['protein'] as num?)?.toDouble() ?? 0.0,
        'carb': (m['carb'] as num?)?.toDouble() ?? 0.0,
        'fat': (m['fat'] as num?)?.toDouble() ?? 0.0,
      });
    }

    // ترتيب الأحدث -> الأقدم حسب نص التاريخ YYYY-MM-DD
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  /// مسح يوم (اختياري للاستخدام من شاشة السجل)
  static Future<void> clearDay(String yyyymmdd) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('diet_$yyyymmdd');
  }

  /// إعادة ضبط اليوم الحالي (اختياري)
  static Future<void> resetToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_todayKey());
  }
}

// lib/water/water_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const double kPlentyWaterThresholdLiters = 2.0; // معيار "شرب كثير" لليوم

class WaterStore {
  static String _today() => DateTime.now().toIso8601String().split('T').first;

  static Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('currentEmail') ?? 'unknown_user';
    // إن ما عندك currentEmail، غيّرها لـ uid المستخدم عندك.
  }

  /// إجمالي لتر اليوم
  static Future<double> todayLiters() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final key = 'water_${_today()}_$email';
    return (prefs.getDouble(key) ?? 0.0);
  }

  /// إضافة باللتر (تتجمع لنفس اليوم)
  static Future<void> addLiters(double liters) async {
    if (liters <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = _today();

    // خزّن قيمة اليوم المباشرة
    final key = 'water_${date}_$email';
    final current = prefs.getDouble(key) ?? 0.0;
    final total = current + liters;
    await prefs.setDouble(key, total);

    // حدّث سجل الشهر/السنة كسلسلة JSON: { "yyyy-MM-dd": double, ... }
    final logKey = 'water_log_$email';
    final raw = prefs.getString(logKey);
    final Map<String, dynamic> map =
        raw == null ? <String, dynamic>{} : jsonDecode(raw);
    map[date] = (map[date] ?? 0) + liters;
    await prefs.setString(logKey, jsonEncode(map));
  }

  /// إرجاع آخر [days] يوم: قائمة مرتبة من الأقدم إلى الأحدث
  static Future<List<MapEntry<String, double>>> recent({int days = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final raw = prefs.getString('water_log_$email');
    final map = <String, double>{};
    if (raw != null) {
      final m = (jsonDecode(raw) as Map<String, dynamic>);
      for (final e in m.entries) {
        map[e.key] = (e.value as num).toDouble();
      }
    }
    // نُرجع فقط آخر N يوم بترتيب التاريخ
    final keys = map.keys.toList()..sort();
    final start = keys.length > days ? keys.length - days : 0;
    final picked = keys.sublist(start);
    return picked.map((k) => MapEntry(k, map[k] ?? 0.0)).toList();
  }

  /// هل اليوم وصل "شرب كثير"
  static Future<bool> isTodayPlenty() async {
    final v = await todayLiters();
    return v >= kPlentyWaterThresholdLiters;
  }
}

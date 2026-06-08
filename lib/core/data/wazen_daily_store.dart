// lib/core/data/wazen_daily_store.dart
// طبقة موحدة لقراءة/كتابة بيانات اليوم محليًا بدون خلط بين email و UID.
// canonical local key = UID، مع mirror للإيميل حتى لا تنكسر بيانات المستخدمين الحاليين.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'wazen_identity_store.dart';

// Helper is top-level because WazenDailyTotals is outside WazenDailyStore.
// Keeping it private to this library avoids leaking parsing utilities elsewhere.
double _toD(dynamic v) {
  if (v is num) return v.toDouble();
  if (v == null) return 0.0;
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
}

class WazenDailyTotals {
  const WazenDailyTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  Map<String, dynamic> toMap() => {
        'k': calories,
        'p': protein,
        'c': carbs,
        'f': fat,
      };

  static WazenDailyTotals fromMap(Map<String, dynamic> map) => WazenDailyTotals(
        calories: _toD(map['k'] ?? map['calories']),
        protein: _toD(map['p'] ?? map['protein']),
        carbs: _toD(map['c'] ?? map['carb'] ?? map['carbs']),
        fat: _toD(map['f'] ?? map['fat']),
      );
}

class WazenDailyStore {
  WazenDailyStore._();

  static String ymd([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }


  static int _toI(dynamic v) {
    if (v is num) return v.toInt();
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static Future<WazenDailyTotals> readTotals(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    for (final a in id.aliases) {
      final raw = _decodeMap(prefs.getString('kcal_daytotals_${a}_$date'));
      if (raw.isNotEmpty) return WazenDailyTotals.fromMap(raw);
    }
    return WazenDailyTotals(
      calories: prefs.getDouble('dietCalories_$date') ?? 0.0,
      protein: prefs.getDouble('dietProtein_$date') ?? 0.0,
      carbs: prefs.getDouble('dietCarb_$date') ?? 0.0,
      fat: prefs.getDouble('dietFat_$date') ?? 0.0,
    );
  }

  static Future<void> writeTotals(String date, WazenDailyTotals totals) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    final raw = jsonEncode(totals.toMap());
    await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'kcal_daytotals_${a}_$date', raw);
    await prefs.setDouble('dietCalories_$date', totals.calories);
    await prefs.setDouble('dietProtein_$date', totals.protein);
    await prefs.setDouble('dietCarb_$date', totals.carbs);
    await prefs.setDouble('dietFat_$date', totals.fat);
  }

  static Future<Map<String, int>> readActivity(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    for (final a in id.aliases) {
      final m = _decodeMap(prefs.getString('activity_${date}_$a'));
      if (m.isNotEmpty) {
        return {'steps': _toI(m['steps']), 'burned': _toI(m['burned'])};
      }
    }
    return {'steps': 0, 'burned': 0};
  }

  static Future<void> writeActivity(String date, {required int steps, required int burned}) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    final raw = jsonEncode({'steps': steps < 0 ? 0 : steps, 'burned': burned < 0 ? 0 : burned});
    await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'activity_${date}_$a', raw);
  }

  static Future<double> readWaterLiters(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    for (final a in id.aliases) {
      final direct = prefs.getDouble('water_${date}_$a');
      if (direct != null && direct > 0) return direct;
      final raw = double.tryParse(prefs.getString('water_total_${a}_$date') ?? '');
      if (raw != null && raw > 0) return raw;
    }
    return 0.0;
  }

  static Future<void> writeWaterLiters(String date, double liters) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    final value = liters < 0 ? 0.0 : liters;
    await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'water_${date}_$a', value);
    await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'water_total_${a}_$date', value.toString());
  }

  static Future<List<Map<String, dynamic>>> readMeals(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    for (final a in id.aliases) {
      final specific = _decodeList(prefs.getString('meals_${a}_$date'));
      if (specific.isNotEmpty) return specific;
      if (date == ymd()) {
        final current = _decodeList(prefs.getString('meals_$a'));
        if (current.isNotEmpty) return current;
      }
    }
    return <Map<String, dynamic>>[];
  }

  static Future<void> writeMeals(String date, List<Map<String, dynamic>> meals) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity();
    final raw = jsonEncode(meals);
    await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'meals_${a}_$date', raw);
    if (date == ymd()) {
      await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'meals_$a', raw);
    }
  }
}

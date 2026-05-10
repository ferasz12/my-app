// lib/water/water_store.dart
// محلي وسريع: لا توجد مزامنة Firestore أثناء اليوم.
// يتم رفع الماء ضمن لقطة نهاية اليوم عبر DailyCloudBackupService.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/end_of_day_cloud_backup_service.dart';

const double kPlentyWaterThresholdLiters = 2.0;

class WaterStore {
  static String _today() => DateTime.now().toIso8601String().split('T').first;

  static Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'unknown_user')
        .trim();
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final m = jsonDecode(raw);
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> _cacheDay({
    required SharedPreferences prefs,
    required String email,
    required String ymd,
    required double liters,
  }) async {
    await prefs.setDouble('water_${ymd}_$email', liters);
    await prefs.setString('water_total_${email}_$ymd', liters.toStringAsFixed(6));

    final logKey = 'water_log_$email';
    final map = _decodeMap(prefs.getString(logKey));
    map[ymd] = liters;
    await prefs.setString(logKey, jsonEncode(map));
    unawaited(DailyCloudBackupService.instance.markDirty().catchError((_) {}));
  }

  static Future<double> todayLiters() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = _today();
    final local = prefs.getDouble('water_${date}_$email');
    if (local != null) return local;
    final byTotal = double.tryParse(prefs.getString('water_total_${email}_$date') ?? '');
    return byTotal ?? 0.0;
  }

  static Future<void> addLiters(double liters) async {
    if (liters <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = _today();
    final current = await todayLiters();
    final total = current + liters;
    await _cacheDay(prefs: prefs, email: email, ymd: date, liters: total);
  }

  /// لا توجد مزامنة أثناء اليوم. تركنا التوقيع حتى لا ينكسر أي ملف يستدعيها.
  static Future<void> syncFromCloud({int limit = 60, bool force = false}) async {}

  static Future<List<MapEntry<String, double>>> recent({int days = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final raw = prefs.getString('water_log_$email');
    final map = <String, double>{};

    if (raw != null) {
      final m = _decodeMap(raw);
      for (final e in m.entries) {
        final v = e.value;
        map[e.key] = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
      }
    }

    final keys = map.keys.toList()..sort();
    final start = keys.length > days ? keys.length - days : 0;
    final picked = keys.sublist(start);
    return picked.map((k) => MapEntry(k, map[k] ?? 0.0)).toList();
  }

  static Future<bool> isTodayPlenty() async {
    final v = await todayLiters();
    return v >= kPlentyWaterThresholdLiters;
  }
}

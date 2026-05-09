// lib/water/water_store.dart
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_repository.dart';

const double kPlentyWaterThresholdLiters = 2.0; // معيار "شرب كثير" لليوم

class WaterStore {
  static bool _cloudSyncInProgress = false;
  static DateTime? _lastCloudSyncAt;
  static String _today() => DateTime.now().toIso8601String().split('T').first;

  static Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
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
  }

  /// إجمالي لتر اليوم. إذا انحذف التطبيق، يحاول يرجّعه من Firestore.
  static Future<double> todayLiters() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = _today();
    final key = 'water_${date}_$email';
    final local = prefs.getDouble(key);
    if (local != null && local > 0) return local;

    // لا نوقف الواجهة بانتظار السحابة. نرجع المحلي فورًا ونزامن بالخلفية.
    syncFromCloud(limit: 7);
    return local ?? 0.0;
  }

  /// إضافة باللتر (تتجمع لنفس اليوم) + مزامنة سحابية.
  static Future<void> addLiters(double liters) async {
    if (liters <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = _today();

    final current = await todayLiters();
    final total = current + liters;
    await _cacheDay(prefs: prefs, email: email, ymd: date, liters: total);

    unawaited(AppRepository.writeWaterLiters(ymd: date, liters: total).catchError((_) {}));
  }

  /// مزامنة سجل الماء من Firestore إلى الجهاز بعد إعادة التثبيت.
  /// افتراضيًا تعمل بالخلفية بدون تعليق الواجهة.
  static Future<void> syncFromCloud({int limit = 60, bool force = false}) async {
    if (!force) {
      _scheduleCloudSync(limit: limit);
      return;
    }
    await _syncFromCloudNow(limit: limit, force: true);
  }

  static void _scheduleCloudSync({int limit = 60}) {
    final now = DateTime.now();
    if (_cloudSyncInProgress) return;
    final last = _lastCloudSyncAt;
    if (last != null && now.difference(last) < const Duration(minutes: 5)) return;
    unawaited(_syncFromCloudNow(limit: limit).catchError((_) {}));
  }

  static Future<void> _syncFromCloudNow({int limit = 60, bool force = false}) async {
    if (_cloudSyncInProgress) return;
    final now = DateTime.now();
    final last = _lastCloudSyncAt;
    if (!force && last != null && now.difference(last) < const Duration(minutes: 5)) return;

    _cloudSyncInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await _email();
      final days = await AppRepository.readDays(limit: (limit.clamp(7, 120)).toInt());
      for (final d in days) {
        final ymd = (d['date'] ?? '').toString();
        if (ymd.isEmpty) continue;
        final water = d['water'];
        final liters = water is Map && water['liters'] is num
            ? (water['liters'] as num).toDouble()
            : 0.0;
        if (liters > 0) {
          await _cacheDay(prefs: prefs, email: email, ymd: ymd, liters: liters);
        }
      }
      _lastCloudSyncAt = DateTime.now();
    } catch (_) {
    } finally {
      _cloudSyncInProgress = false;
    }
  }

  /// إرجاع آخر [days] يوم: قائمة مرتبة من الأقدم إلى الأحدث
  static Future<List<MapEntry<String, double>>> recent({int days = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();

    // رجّع المحلي فورًا، وخلّ السحابة تتزامن بالخلفية.
    syncFromCloud(limit: days + 30);

    final raw = prefs.getString('water_log_$email');
    final map = <String, double>{};
    if (raw != null) {
      final m = _decodeMap(raw);
      for (final e in m.entries) {
        final v = e.value;
        map[e.key] = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
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

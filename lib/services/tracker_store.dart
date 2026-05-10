// lib/services/tracker_store.dart
// سريع ومحلي: لا يقرأ ولا يكتب Firestore أثناء اليوم.
// يتم رفع لقطة اليوم للسحابة عبر DailyCloudBackupService في نهاية اليوم.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'end_of_day_cloud_backup_service.dart';

class TrackerStore {
  static String _todayKey() => _keyForDate(DateTime.now());

  static String _keyForDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return 'diet_$y-$m-$day';
  }

  static String _ymd(DateTime d) => _keyForDate(d).replaceFirst('diet_', '');

  static Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'unknown_user')
        .trim();
  }

  static double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return null;
  }

  static Future<void> _cacheDay({
    required SharedPreferences prefs,
    required String email,
    required String ymd,
    required double cal,
    required double protein,
    required double carb,
    required double fat,
    List<Map<String, dynamic>>? entries,
  }) async {
    final map = {
      'date': ymd,
      'calories': cal,
      'protein': protein,
      'carb': carb,
      'fat': fat,
    };

    await prefs.setString('diet_$ymd', jsonEncode(map));
    await prefs.setString(
      'kcal_daytotals_${email}_$ymd',
      jsonEncode({'k': cal, 'p': protein, 'c': carb, 'f': fat}),
    );
    if (entries != null) {
      await prefs.setString('intake_entries_${email}_$ymd', jsonEncode(entries));
    }

    unawaited(DailyCloudBackupService.instance.markDirty().catchError((_) {}));
  }

  static Map<String, dynamic> _dayMapFromTotals({
    required String ymd,
    required Map<String, dynamic> totals,
  }) {
    return {
      'date': ymd,
      'calories': _toD(totals['k'] ?? totals['calories']),
      'protein': _toD(totals['p'] ?? totals['protein']),
      'carb': _toD(totals['c'] ?? totals['carb'] ?? totals['carbs']),
      'fat': _toD(totals['f'] ?? totals['fat']),
    };
  }

  /// يكتب مجاميع يوم كامل كقيمة نهائية، وليس تجميعًا فوق القديم.
  /// هذا مهم عند حذف وجبة: السجل يصير مطابقًا للوجبات الموجودة فعليًا.
  static Future<void> setDayTotals({
    String? ymd,
    required double cal,
    required double protein,
    required double carb,
    required double fat,
    List<Map<String, dynamic>>? entries,
    bool mirrorCloud = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = ymd ?? _ymd(DateTime.now());

    await _cacheDay(
      prefs: prefs,
      email: email,
      ymd: date,
      cal: cal,
      protein: protein,
      carb: carb,
      fat: fat,
      entries: entries,
    );
  }

  /// إضافة استهلاك لليوم للتوافق مع الكود القديم.
  static Future<void> addIntake({
    required double cal,
    required double protein,
    required double carb,
    required double fat,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final key = _todayKey();
    final raw = prefs.getString(key);
    double c = 0, p = 0, cb = 0, f = 0;

    if (raw != null) {
      final m = _decodeMap(raw) ?? <String, dynamic>{};
      c = _toD(m['calories']);
      p = _toD(m['protein']);
      cb = _toD(m['carb']);
      f = _toD(m['fat']);
    }

    final date = key.replaceFirst('diet_', '');
    await _cacheDay(
      prefs: prefs,
      email: email,
      ymd: date,
      cal: c + cal,
      protein: p + protein,
      carb: cb + carb,
      fat: f + fat,
    );
  }

  /// لا تعمل مزامنة أثناء اليوم حتى لا يعلق التطبيق.
  /// الرفع للسحابة يتم نهاية اليوم فقط.
  static Future<void> syncFromCloud({int limit = 60, bool force = false}) async {}

  /// قراءة يوم محدد من المحلي فقط.
  static Future<Map<String, dynamic>> getDay(DateTime d) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final key = _keyForDate(d);
    final ymd = key.replaceFirst('diet_', '');

    final totals = _decodeMap(prefs.getString('kcal_daytotals_${email}_$ymd'));
    if (totals != null) return _dayMapFromTotals(ymd: ymd, totals: totals);

    final raw = prefs.getString(key);
    if (raw != null) {
      final m = _decodeMap(raw) ?? <String, dynamic>{};
      return {
        'date': (m['date'] ?? ymd).toString(),
        'calories': _toD(m['calories']),
        'protein': _toD(m['protein']),
        'carb': _toD(m['carb']),
        'fat': _toD(m['fat']),
      };
    }

    return {
      'date': ymd,
      'calories': 0.0,
      'protein': 0.0,
      'carb': 0.0,
      'fat': 0.0,
    };
  }

  /// جميع الأيام المحلية المخزنة، بدون أي قراءة Firestore.
  static Future<List<Map<String, dynamic>>> getAllDays() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();

    final byDate = <String, Map<String, dynamic>>{};

    final totalsPrefix = 'kcal_daytotals_${email}_';
    for (final k in prefs.getKeys().where((x) => x.startsWith(totalsPrefix))) {
      final ymd = k.substring(totalsPrefix.length);
      final totals = _decodeMap(prefs.getString(k));
      if (totals == null) continue;
      byDate[ymd] = _dayMapFromTotals(ymd: ymd, totals: totals);
    }

    final keys = prefs.getKeys().where((k) => k.startsWith('diet_')).toList();
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      final m = _decodeMap(raw);
      if (m == null) continue;
      final ymd = (m['date'] ?? k.replaceFirst('diet_', '')).toString();
      byDate.putIfAbsent(ymd, () => {
            'date': ymd,
            'calories': _toD(m['calories']),
            'protein': _toD(m['protein']),
            'carb': _toD(m['carb']),
            'fat': _toD(m['fat']),
          });
    }

    final list = byDate.values.where((m) {
      return _toD(m['calories']) > 0 ||
          _toD(m['protein']) > 0 ||
          _toD(m['carb']) > 0 ||
          _toD(m['fat']) > 0;
    }).toList();
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  static Future<void> clearDay(String yyyymmdd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    await prefs.remove('diet_$yyyymmdd');
    await prefs.remove('kcal_daytotals_${email}_$yyyymmdd');
    await prefs.remove('intake_entries_${email}_$yyyymmdd');
    await prefs.setBool('eod_cloud_backup_done_${email}_$yyyymmdd', false);
    unawaited(DailyCloudBackupService.instance.markDirty().catchError((_) {}));
  }

  static Future<void> resetToday() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final ymd = _ymd(DateTime.now());
    await prefs.remove(_todayKey());
    await prefs.remove('kcal_daytotals_${email}_$ymd');
    await prefs.remove('intake_entries_${email}_$ymd');
    await prefs.setBool('eod_cloud_backup_done_${email}_$ymd', false);
    unawaited(DailyCloudBackupService.instance.markDirty().catchError((_) {}));
  }
}

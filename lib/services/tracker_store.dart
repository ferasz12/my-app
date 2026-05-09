// lib/services/tracker_store.dart
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_repository.dart';

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

  static String _ymd(DateTime d) => _keyForDate(d).replaceFirst('diet_', '');

  static Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            'unknown_user')
        .trim();
  }

  static double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null) return null;
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

    if (mirrorCloud) {
      try {
        await AppRepository.writeEntriesAndTotals(
          ymd: date,
          entries: entries ?? const <Map<String, dynamic>>[],
          totals: {'k': cal, 'p': protein, 'c': carb, 'f': fat},
        );
      } catch (_) {}
    }
  }

  /// إضافة استهلاك لليوم (تجميع فوق الموجود)
  /// أبقيناها للتوافق مع الكود القديم، لكن الحفظ النهائي في الهوم يستخدم setDayTotals.
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

  /// مزامنة أيام السجل من Firestore إلى SharedPreferences بعد إعادة تثبيت التطبيق.
  static Future<void> syncFromCloud({int limit = 370}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await _email();
      final days = await AppRepository.readDays(limit: limit);
      for (final d in days) {
        final ymd = (d['date'] ?? '').toString();
        if (ymd.isEmpty) continue;
        final intake = d['intake'];
        final totals = intake is Map ? (intake['totals'] as Map?) : null;
        final entriesRaw = intake is Map ? intake['entries'] : null;
        final entries = entriesRaw is List
            ? entriesRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        if (totals is Map) {
          final cal = _toD(totals['k']);
          final protein = _toD(totals['p']);
          final carb = _toD(totals['c']);
          final fat = _toD(totals['f']);
          final hasIntake = cal > 0 || protein > 0 || carb > 0 || fat > 0 || entries.isNotEmpty;
          if (!hasIntake) continue;
          await _cacheDay(
            prefs: prefs,
            email: email,
            ymd: ymd,
            cal: cal,
            protein: protein,
            carb: carb,
            fat: fat,
            entries: entries,
          );
        }
      }
    } catch (_) {}
  }

  /// قراءة يوم محدد
  static Future<Map<String, dynamic>> getDay(DateTime d) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final key = _keyForDate(d);
    final ymd = key.replaceFirst('diet_', '');

    // 1) الحديث: مجاميع الهوم النهائية
    final totals = _decodeMap(prefs.getString('kcal_daytotals_${email}_$ymd'));
    if (totals != null) return _dayMapFromTotals(ymd: ymd, totals: totals);

    // 2) القديم: diet_yyyy-mm-dd
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

    // 3) السحابة بعد إعادة تثبيت التطبيق
    try {
      final remote = await AppRepository.readDay(ymd);
      final intake = remote?['intake'];
      final rt = intake is Map ? intake['totals'] : null;
      if (rt is Map) {
        final map = _dayMapFromTotals(ymd: ymd, totals: Map<String, dynamic>.from(rt));
        await _cacheDay(
          prefs: prefs,
          email: email,
          ymd: ymd,
          cal: _toD(map['calories']),
          protein: _toD(map['protein']),
          carb: _toD(map['carb']),
          fat: _toD(map['fat']),
        );
        return map;
      }
    } catch (_) {}

    return {
      'date': ymd,
      'calories': 0.0,
      'protein': 0.0,
      'carb': 0.0,
      'fat': 0.0,
    };
  }

  /// جميع الأيام المخزنة بصيغة [{date, calories, protein, carb, fat}, ...] مرتبة من الأحدث
  static Future<List<Map<String, dynamic>>> getAllDays() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();

    // أولًا حاول ترجع بيانات السحابة وتخزنها محليًا؛ لو فشلت، المحلي يكمل عادي.
    await syncFromCloud();

    final byDate = <String, Map<String, dynamic>>{};

    // 1) اقرأ المجاميع النهائية الحديثة kcal_daytotals_email_yyyy-mm-dd
    final totalsPrefix = 'kcal_daytotals_${email}_';
    for (final k in prefs.getKeys().where((x) => x.startsWith(totalsPrefix))) {
      final ymd = k.substring(totalsPrefix.length);
      final totals = _decodeMap(prefs.getString(k));
      if (totals == null) continue;
      byDate[ymd] = _dayMapFromTotals(ymd: ymd, totals: totals);
    }

    // 2) اقرأ diet_ القديم كـ fallback فقط إذا ما فيه قيمة أحدث لنفس اليوم
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

  /// مسح يوم (اختياري للاستخدام من شاشة السجل)
  static Future<void> clearDay(String yyyymmdd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    await prefs.remove('diet_$yyyymmdd');
    await prefs.remove('kcal_daytotals_${email}_$yyyymmdd');
    await prefs.remove('intake_entries_${email}_$yyyymmdd');
    try {
      await AppRepository.clearDayIntake(ymd: yyyymmdd);
    } catch (_) {}
  }

  /// إعادة ضبط اليوم الحالي (اختياري)
  static Future<void> resetToday() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final ymd = _ymd(DateTime.now());
    await prefs.remove(_todayKey());
    await prefs.remove('kcal_daytotals_${email}_$ymd');
    await prefs.remove('intake_entries_${email}_$ymd');
  }
}

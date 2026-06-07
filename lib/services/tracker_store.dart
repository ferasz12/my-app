// lib/services/tracker_store.dart
// سريع ومحلي: لا يقرأ ولا يكتب Firestore أثناء اليوم.
// الحفظ محلي فقط؛ تم تعطيل أي رفع سحابي تلقائي.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }



  /// قراءة وجبات/عناصر يوم محدد من التخزين المحلي.
  static Future<List<Map<String, dynamic>>> getDayEntries(String yyyymmdd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final raw = prefs.getString('intake_entries_${email}_$yyyymmdd');
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <Map<String, dynamic>>[];
      return list.whereType<Map>().map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e);
        final k = _toD(m['k'] ?? m['cal'] ?? m['calories'] ?? m['kcal']);
        final p = _toD(m['p'] ?? m['protein'] ?? m['protein_g']);
        final c = _toD(m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carbs_g']);
        final f = _toD(m['f'] ?? m['fat'] ?? m['fat_g']);
        return <String, dynamic>{
          ...m,
          'name': (m['name'] ?? m['label'] ?? 'وجبة').toString(),
          'k': k,
          'p': p,
          'c': c,
          'f': f,
          'cal': k,
          'protein': p,
          'carb': c,
          'fat': f,
        };
      }).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Map<String, dynamic> _normalizeEntryForDay(Map<String, dynamic> item) {
    final p = _toD(item['p'] ?? item['protein'] ?? item['protein_g']);
    final c = _toD(item['c'] ?? item['carb'] ?? item['carbs'] ?? item['carbs_g']);
    final f = _toD(item['f'] ?? item['fat'] ?? item['fat_g']);
    double k = _toD(item['k'] ?? item['cal'] ?? item['calories'] ?? item['kcal'] ?? item['calories_kcal']);
    if (k <= 0 && (p > 0 || c > 0 || f > 0)) {
      k = (p * 4 + c * 4 + f * 9).roundToDouble();
    }
    final nameRaw = (item['name'] ?? item['label'] ?? item['food_name'] ?? 'وجبة').toString().trim();
    return <String, dynamic>{
      ...item,
      'name': nameRaw.isEmpty ? 'وجبة' : nameRaw,
      'k': k,
      'p': p,
      'c': c,
      'f': f,
      'cal': k,
      'protein': p,
      'carb': c,
      'fat': f,
      'addedAt': item['addedAt'] ?? DateTime.now().toIso8601String(),
    };
  }

  /// إضافة وجبات إلى يوم سابق أو محدد، مع إعادة حساب مجاميع ذلك اليوم.
  static Future<void> appendEntriesToDay({
    required String ymd,
    required List<Map<String, dynamic>> entries,
  }) async {
    if (entries.isEmpty) return;

    final existing = await getDayEntries(ymd);
    final current = await getDay(DateTime.tryParse(ymd) ?? DateTime.now());

    // إذا كان اليوم محفوظًا كمجاميع فقط بدون تفاصيل، نحافظ على القديم كعنصر واحد.
    if (existing.isEmpty) {
      final oldK = _toD(current['calories']);
      final oldP = _toD(current['protein']);
      final oldC = _toD(current['carb'] ?? current['carbs']);
      final oldF = _toD(current['fat']);
      if (oldK > 0 || oldP > 0 || oldC > 0 || oldF > 0) {
        existing.add(<String, dynamic>{
          'name': 'سجل سابق',
          'k': oldK,
          'p': oldP,
          'c': oldC,
          'f': oldF,
          'cal': oldK,
          'protein': oldP,
          'carb': oldC,
          'fat': oldF,
        });
      }
    }

    final all = <Map<String, dynamic>>[
      ...existing.map(_normalizeEntryForDay),
      ...entries.map(_normalizeEntryForDay),
    ];

    double k = 0, p = 0, c = 0, f = 0;
    for (final e in all) {
      k += _toD(e['k'] ?? e['cal']);
      p += _toD(e['p'] ?? e['protein']);
      c += _toD(e['c'] ?? e['carb'] ?? e['carbs']);
      f += _toD(e['f'] ?? e['fat']);
    }

    await setDayTotals(
      ymd: ymd,
      cal: k,
      protein: p,
      carb: c,
      fat: f,
      entries: all,
    );
  }

  /// حذف عنصر واحد من يوم محدد ثم إعادة حساب المجاميع.
  static Future<void> removeEntryFromDay({
    required String ymd,
    required int index,
  }) async {
    final entries = await getDayEntries(ymd);
    if (index < 0 || index >= entries.length) return;
    entries.removeAt(index);

    double k = 0, p = 0, c = 0, f = 0;
    final normalized = entries.map(_normalizeEntryForDay).toList();
    for (final e in normalized) {
      k += _toD(e['k'] ?? e['cal']);
      p += _toD(e['p'] ?? e['protein']);
      c += _toD(e['c'] ?? e['carb'] ?? e['carbs']);
      f += _toD(e['f'] ?? e['fat']);
    }

    await setDayTotals(
      ymd: ymd,
      cal: k,
      protein: p,
      carb: c,
      fat: f,
      entries: normalized,
    );
  }

  static Future<void> resetToday() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final ymd = _ymd(DateTime.now());
    await prefs.remove(_todayKey());
    await prefs.remove('kcal_daytotals_${email}_$ymd');
    await prefs.remove('intake_entries_${email}_$ymd');
    await prefs.setBool('eod_cloud_backup_done_${email}_$ymd', false);
  }
}

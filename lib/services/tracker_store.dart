// lib/services/tracker_store.dart
// سريع ومحلي: لا يقرأ ولا يكتب Firestore أثناء اليوم.
// يتم رفع لقطة اليوم للسحابة عبر DailyCloudBackupService في نهاية اليوم.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/wazen_identity_store.dart';
import '../shared/session_manager.dart';
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

  static const String _deletedDaysKey = 'wazen_deleted_calorie_days';

  static Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'unknown_user')
        .trim();
  }

  static Future<List<String>> _knownAliases(SharedPreferences prefs) async {
    final user = FirebaseAuth.instance.currentUser;
    final identity = await WazenIdentityStore.currentIdentity(user: user, migrate: false);
    String sessionKey = '';
    try {
      sessionKey = await SessionManager.currentStorageKey();
    } catch (_) {}

    final aliases = <String>{
      identity.storageKey,
      identity.emailKey,
      ...identity.aliases,
      prefs.getString('currentEmail') ?? '',
      prefs.getString('currentUid') ?? '',
      user?.uid ?? '',
      user?.email?.trim().toLowerCase() ?? '',
      sessionKey,
      'unknown_user',
    }..removeWhere((e) => e.trim().isEmpty);

    return aliases.toList(growable: false);
  }

  static Set<String> _deletedDays(SharedPreferences prefs) {
    return (prefs.getStringList(_deletedDaysKey) ?? const <String>[])
        .map(normalizeYmd)
        .where(_looksLikeYmd)
        .toSet();
  }

  static bool _looksLikeYmd(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim());
  }

  static Future<void> _markDayDeleted(SharedPreferences prefs, String ymd) async {
    final date = normalizeYmd(ymd);
    final set = _deletedDays(prefs)..add(date);
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    await prefs.setStringList(_deletedDaysKey, list);
    await prefs.setString('wazen_deleted_calorie_day_at_$date', DateTime.now().toIso8601String());
  }

  static Future<void> _unmarkDayDeleted(SharedPreferences prefs, String ymd) async {
    final date = normalizeYmd(ymd);
    final set = _deletedDays(prefs);
    if (set.remove(date)) {
      final list = set.toList()..sort((a, b) => b.compareTo(a));
      await prefs.setStringList(_deletedDaysKey, list);
    }
    await prefs.remove('wazen_deleted_calorie_day_at_$date');
  }

  static Future<void> _deleteCloudDayPermanently(String ymd) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final date = normalizeYmd(ymd);
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(user.uid);
    final batch = db.batch();

    batch.delete(userRef.collection('days').doc(date));
    batch.set(
      userRef,
      {
        'cloudDeletedCalorieDays': FieldValue.arrayUnion([date]),
        'cloudSync': {
          'deletedDaysUpdatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit().timeout(const Duration(seconds: 8));
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
    await _unmarkDayDeleted(prefs, ymd);

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
    if (totals != null) {
      return {
        ..._dayMapFromTotals(ymd: ymd, totals: totals),
        'locked': prefs.getBool('kcal_day_locked_${email}_$ymd') ?? false,
      };
    }

    final raw = prefs.getString(key);
    if (raw != null) {
      final m = _decodeMap(raw) ?? <String, dynamic>{};
      return {
        'date': (m['date'] ?? ymd).toString(),
        'calories': _toD(m['calories']),
        'protein': _toD(m['protein']),
        'carb': _toD(m['carb']),
        'fat': _toD(m['fat']),
        'locked': prefs.getBool('kcal_day_locked_${email}_$ymd') ?? false,
      };
    }

    return {
      'date': ymd,
      'calories': 0.0,
      'protein': 0.0,
      'carb': 0.0,
      'fat': 0.0,
      'locked': prefs.getBool('kcal_day_locked_${email}_$ymd') ?? false,
    };
  }

  static List<Map<String, dynamic>> _decodeListOfMaps(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static String normalizeYmd(String value) {
    final raw = value.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final d = DateTime.tryParse(raw);
    if (d == null) return _ymd(DateTime.now());
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<List<Map<String, dynamic>>> getDayEntries(String ymd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = normalizeYmd(ymd);
    return _decodeListOfMaps(prefs.getString('intake_entries_${email}_$date'));
  }

  static Future<bool> isDayLocked(String ymd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = normalizeYmd(ymd);
    return prefs.getBool('kcal_day_locked_${email}_$date') ?? false;
  }

  static Future<void> setDayLocked(String ymd, bool locked) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = normalizeYmd(ymd);
    await prefs.setBool('kcal_day_locked_${email}_$date', locked);
  }

  static Future<Map<String, dynamic>> addEntryToDay({
    required String ymd,
    required String name,
    required double cal,
    required double protein,
    required double carb,
    required double fat,
    String source = 'manual',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = normalizeYmd(ymd);
    final entriesKey = 'intake_entries_${email}_$date';
    final entries = _decodeListOfMaps(prefs.getString(entriesKey));

    // إذا كان اليوم محفوظًا بالمجاميع فقط بدون تفاصيل وجبات، نحافظ على المجاميع القديمة
    // كعنصر سابق حتى لا تضيع عند إضافة وجبة جديدة ليوم قديم.
    if (entries.isEmpty) {
      final existingTotals = _decodeMap(prefs.getString('kcal_daytotals_${email}_$date'));
      final existingDiet = _decodeMap(prefs.getString('diet_$date'));
      final oldK = _toD(existingTotals?['k'] ?? existingDiet?['calories']);
      final oldP = _toD(existingTotals?['p'] ?? existingDiet?['protein']);
      final oldC = _toD(existingTotals?['c'] ?? existingDiet?['carb'] ?? existingDiet?['carbs']);
      final oldF = _toD(existingTotals?['f'] ?? existingDiet?['fat']);
      if (oldK > 0 || oldP > 0 || oldC > 0 || oldF > 0) {
        entries.add({
          'name': 'الوجبات السابقة',
          'k': oldK,
          'p': oldP,
          'c': oldC,
          'f': oldF,
          'source': 'previous_total',
          'lockedBaseline': true,
        });
      }
    }

    final safeName = name.trim().isEmpty ? 'وجبة' : name.trim();
    final safeCal = cal.isFinite && cal > 0 ? cal : 0.0;
    final safeP = protein.isFinite && protein > 0 ? protein : 0.0;
    final safeC = carb.isFinite && carb > 0 ? carb : 0.0;
    final safeF = fat.isFinite && fat > 0 ? fat : 0.0;

    entries.add({
      'name': safeName,
      'k': safeCal,
      'p': safeP,
      'c': safeC,
      'f': safeF,
      'source': source,
      'addedAt': DateTime.now().toIso8601String(),
    });

    double k = 0, p = 0, c = 0, f = 0;
    for (final e in entries) {
      k += _toD(e['k'] ?? e['cal'] ?? e['calories']);
      p += _toD(e['p'] ?? e['protein']);
      c += _toD(e['c'] ?? e['carb'] ?? e['carbs']);
      f += _toD(e['f'] ?? e['fat']);
    }

    await _cacheDay(
      prefs: prefs,
      email: email,
      ymd: date,
      cal: k,
      protein: p,
      carb: c,
      fat: f,
      entries: entries,
    );
    await prefs.setBool('eod_cloud_backup_done_${email}_$date', false);

    return {
      'date': date,
      'calories': k,
      'protein': p,
      'carb': c,
      'fat': f,
      'entries': entries,
      'locked': prefs.getBool('kcal_day_locked_${email}_$date') ?? false,
    };
  }

  static Future<Map<String, dynamic>> recomputeDayFromEntries(String ymd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();
    final date = normalizeYmd(ymd);
    final entries = _decodeListOfMaps(prefs.getString('intake_entries_${email}_$date'));
    double k = 0, p = 0, c = 0, f = 0;
    for (final e in entries) {
      k += _toD(e['k'] ?? e['cal'] ?? e['calories']);
      p += _toD(e['p'] ?? e['protein']);
      c += _toD(e['c'] ?? e['carb'] ?? e['carbs']);
      f += _toD(e['f'] ?? e['fat']);
    }
    await _cacheDay(
      prefs: prefs,
      email: email,
      ymd: date,
      cal: k,
      protein: p,
      carb: c,
      fat: f,
      entries: entries,
    );
    return {
      'date': date,
      'calories': k,
      'protein': p,
      'carb': c,
      'fat': f,
      'entries': entries,
      'locked': prefs.getBool('kcal_day_locked_${email}_$date') ?? false,
    };
  }

  /// جميع الأيام المحلية المخزنة، بدون أي قراءة Firestore.
  static Future<List<Map<String, dynamic>>> getAllDays() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _email();

    final deleted = _deletedDays(prefs);
    final byDate = <String, Map<String, dynamic>>{};

    final totalsPrefix = 'kcal_daytotals_${email}_';
    for (final k in prefs.getKeys().where((x) => x.startsWith(totalsPrefix))) {
      final ymd = k.substring(totalsPrefix.length);
      if (deleted.contains(ymd)) continue;
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
      if (deleted.contains(ymd)) continue;
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
    final date = normalizeYmd(yyyymmdd);
    final aliases = await _knownAliases(prefs);

    // احذف كل نسخ اليوم المحلية، سواء كانت بالمفتاح الجديد UID أو البريد أو المفاتيح القديمة.
    await prefs.remove('diet_$date');
    await prefs.remove('dietCalories_$date');
    await prefs.remove('dietProtein_$date');
    await prefs.remove('dietCarb_$date');
    await prefs.remove('dietFat_$date');

    for (final a in aliases) {
      await prefs.remove('kcal_daytotals_${a}_$date');
      await prefs.remove('intake_entries_${a}_$date');
      await prefs.remove('kcal_day_locked_${a}_$date');
      await prefs.remove('meals_${a}_$date');
      await prefs.remove('activity_${date}_$a');
      await prefs.remove('water_${date}_$a');
      await prefs.remove('water_total_${a}_$date');
      await prefs.remove('water_ml_${date}_$a');
      await prefs.setBool('eod_cloud_backup_done_${a}_$date', false);
      await prefs.setBool('eod_cloud_dirty_${a}_$date', false);
    }

    // Tombstone محلي: يمنع الاسترجاع اليدوي من إرجاع اليوم المحذوف مرة ثانية.
    await _markDayDeleted(prefs, date);

    // حذف فعلي من Firestore + حفظ علامة حذف سحابية لتفهم الأجهزة الثانية أن هذا اليوم محذوف.
    // إذا فشل الاتصال، سيبقى الـ tombstone المحلي، وستحاول المزامنة اليدوية القادمة حذف اليوم من السحابة.
    try {
      await _deleteCloudDayPermanently(date);
    } catch (_) {}

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

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;


import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:health/health.dart';

// PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ المصدر الموحّد لاستهلاك اليوم (كما في الصفحة الرئيسية)
import '../services/tracker_store.dart';
import '../shared/weight_live_bus.dart';
import '../shared/macro_targets_controller.dart';
import '../core/data/wazen_identity_store.dart';
import '../core/data/wazen_daily_store.dart';
import '../notifications/app_notifications.dart';


// ==== Global helpers for insights ====
double _toD(v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

num? _prefNum(SharedPreferences prefs, String key) {
  final v = prefs.get(key);
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    final normalized = v
        .trim()
        .replaceAll('٫', '.')
        .replaceAll('،', '.')
        .replaceAll(',', '.');
    return num.tryParse(normalized);
  }
  return null;
}

double? _prefDouble(SharedPreferences prefs, String key) =>
    _prefNum(prefs, key)?.toDouble();

int? _prefInt(SharedPreferences prefs, String key) =>
    _prefNum(prefs, key)?.round();

List<String> _safePrefStringList(SharedPreferences prefs, String key) {
  final value = prefs.get(key);
  if (value == null) return <String>[];
  if (value is List<String>) return value;
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return <String>[raw];
  }
  return <String>[];
}

int _asSafeInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.round();
  if (value is String) return num.tryParse(value.trim())?.round() ?? fallback;
  return fallback;
}

double _asSafeDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim().replaceAll(',', '.')) ?? fallback;
  return fallback;
}

class _MealLogItem {
  final String slot;
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const _MealLogItem({
    required this.slot,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

String _cleanMealSlot(dynamic raw) {
  final value = (raw ?? '').toString().replaceAll(RegExp(r'[🍳🍽️🌙🥗🍱☕️☕🥣]'), '').trim();
  return value.isEmpty ? 'وجبة' : value;
}

String _foodLogItemName(Map<dynamic, dynamic> map) {
  final raw = map['name'] ??
      map['meal_name'] ??
      map['title'] ??
      map['foodName'] ??
      map['label'] ??
      map['arabicName'] ??
      map['englishName'] ??
      '';
  final value = raw.toString().trim();
  return value.isEmpty ? 'عنصر غذائي' : value;
}

double _foodLogCal(Map<dynamic, dynamic> map) {
  final raw = map['k'] ??
      map['cal'] ??
      map['kcal'] ??
      map['calories'] ??
      map['caloriesKcal'] ??
      (map['energy'] is Map ? (map['energy'] as Map)['kcal'] : map['energy']);
  var calories = _toD(raw);
  if (calories <= 0) {
    calories = _toD(map['p'] ?? map['protein'] ?? map['protein_g']) * 4 +
        _toD(map['c'] ?? map['carb'] ?? map['carbs'] ?? map['carb_g']) * 4 +
        _toD(map['f'] ?? map['fat'] ?? map['fat_g']) * 9;
  }
  return calories;
}

_MealLogItem _mealLogItemFromMap(Map<dynamic, dynamic> map, {required String slot}) {
  return _MealLogItem(
    slot: _cleanMealSlot(slot),
    name: _foodLogItemName(map),
    calories: _foodLogCal(map),
    protein: _toD(map['p'] ?? map['protein'] ?? map['protein_g']),
    carbs: _toD(map['c'] ?? map['carb'] ?? map['carbs'] ?? map['carb_g']),
    fat: _toD(map['f'] ?? map['fat'] ?? map['fat_g']),
  );
}

List<_MealLogItem> _extractMealLogItems(dynamic data, {String slot = 'وجبة'}) {
  final out = <_MealLogItem>[];

  void walk(dynamic node, String currentSlot) {
    if (node == null) return;
    if (node is String) {
      try {
        walk(jsonDecode(node), currentSlot);
      } catch (_) {}
      return;
    }
    if (node is List) {
      for (final item in node) {
        walk(item, currentSlot);
      }
      return;
    }
    if (node is! Map) return;

    final map = Map<dynamic, dynamic>.from(node as Map);
    final nextSlot = _cleanMealSlot(map['slot'] ?? map['mealSlot'] ?? map['mealType'] ?? map['name'] ?? map['title'] ?? currentSlot);
    final nested = map['items'] ?? map['foods'] ?? map['entries'] ?? map['meals'];
    if (nested is List && nested.isNotEmpty) {
      for (final item in nested) {
        walk(item, nextSlot);
      }
      return;
    }

    final hasNutrition = _foodLogCal(map) > 0 ||
        _toD(map['p'] ?? map['protein'] ?? map['protein_g']) > 0 ||
        _toD(map['c'] ?? map['carb'] ?? map['carbs'] ?? map['carb_g']) > 0 ||
        _toD(map['f'] ?? map['fat'] ?? map['fat_g']) > 0;
    if (hasNutrition) {
      out.add(_mealLogItemFromMap(map, slot: currentSlot));
    }
  }

  walk(data, slot);
  return out;
}

Map<String, double> _sumMealLogItems(List<_MealLogItem> items) {
  double cal = 0, p = 0, c = 0, f = 0;
  for (final item in items) {
    cal += item.calories;
    p += item.protein;
    c += item.carbs;
    f += item.fat;
  }
  return {'cal': cal, 'p': p, 'c': c, 'f': f};
}


/// Sum possible nutrient maps/lists (k/cal, p, c, f)
Map<String, double> sumFromIterable(Iterable items) {
  double cal = 0, p = 0, c = 0, f = 0;
  for (final it in items) {
    if (it is String) {
      try {
        final m = jsonDecode(it);
        cal += _toD(m['k'] ?? m['cal']);
        p += _toD(m['p'] ?? m['protein']);
        c += _toD(m['c'] ?? m['carb']);
        f += _toD(m['f'] ?? m['fat']);
      } catch (_) {}
    } else if (it is Map) {
      cal += _toD(it['k'] ?? it['cal']);
      p += _toD(it['p'] ?? it['protein']);
      c += _toD(it['c'] ?? it['carb']);
      f += _toD(it['f'] ?? it['fat']);
    }
  }
  return {'cal': cal, 'protein': p, 'carb': c, 'fat': f};
}

/// ========= Helpers =========
String _todayKey() => DateTime.now().toIso8601String().split('T').first;

/// يحوّل أي تمثيل للتاريخ إلى مفتاح yyyy-MM-dd (يدعم ISO/epoch وبعض الصيغ الشائعة).
String? _normalizeYmd(dynamic value) {
  if (value == null) return null;

  DateTime? dt;
  if (value is int) {
    dt = DateTime.fromMillisecondsSinceEpoch(value);
  } else if (value is double) {
    dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
  } else {
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    // ISO أو ISO مع مسافة بدل T
    dt = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.replaceFirst(' ', 'T'));

    // صيغ شائعة
    if (dt == null) {
      final fmts = <DateFormat>[
        DateFormat('yyyy/MM/dd'),
        DateFormat('dd/MM/yyyy'),
        DateFormat('d/M/yyyy'),
        DateFormat('dd-MM-yyyy'),
        DateFormat('d-M-yyyy'),
        DateFormat('yyyy-MM-dd'),
      ];
      for (final f in fmts) {
        try {
          dt = f.parseStrict(raw);
          break;
        } catch (_) {}
      }
    }
  }

  if (dt == null) return null;
  final d0 = DateTime(dt.year, dt.month, dt.day);
  return DateFormat('yyyy-MM-dd').format(d0);
}


Future<String?> _currentEmail() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('currentEmail');
}

Future<List<String>> _currentProfileAliases() async {
  final prefs = await SharedPreferences.getInstance();
  final id = await WazenIdentityStore.currentIdentity(migrate: false);
  final aliases = <String>{
    prefs.getString('currentEmail') ?? '',
    prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ?? '',
    prefs.getString(WazenIdentityStore.kCurrentUid) ?? '',
    prefs.getString(WazenIdentityStore.kCurrentStorageKey) ?? '',
    id.storageKey,
    id.uid,
    id.email,
    id.emailKey,
    ...id.aliases,
  }..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
  return aliases.toList(growable: false);
}

String _latestProfileAlias(SharedPreferences prefs, List<String> aliases) {
  if (aliases.isEmpty) return 'unknown_user';
  var best = aliases.first;
  var bestStamp = -1;
  for (final alias in aliases) {
    final stamp = math.max(
      prefs.getInt('profileUpdatedAt_$alias') ?? 0,
      prefs.getInt('macrosUpdatedAt_$alias') ?? 0,
    );
    if (stamp > bestStamp) {
      bestStamp = stamp;
      best = alias;
    }
  }
  return best;
}

List<String> _orderedAliases(List<String> aliases, String preferred) {
  return <String>[
    if (preferred.trim().isNotEmpty && preferred != 'unknown_user') preferred,
    ...aliases,
  ].where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList();
}

double? _prefDoubleAnyAlias(
  SharedPreferences prefs,
  List<String> prefixes,
  List<String> aliases, {
  String preferred = '',
}) {
  for (final alias in _orderedAliases(aliases, preferred)) {
    for (final prefix in prefixes) {
      final v = _prefDouble(prefs, '$prefix$alias');
      if (v != null) return v;
    }
  }
  return null;
}

int? _prefIntAnyAlias(
  SharedPreferences prefs,
  String prefix,
  List<String> aliases, {
  String preferred = '',
}) {
  for (final alias in _orderedAliases(aliases, preferred)) {
    final v = _prefInt(prefs, '$prefix$alias');
    if (v != null) return v;
  }
  return null;
}

String? _prefStringAnyAlias(
  SharedPreferences prefs,
  String prefix,
  List<String> aliases, {
  String preferred = '',
}) {
  for (final alias in _orderedAliases(aliases, preferred)) {
    final v = _readStringFlexible(prefs, '$prefix$alias');
    if (v != null && v.trim().isNotEmpty) return v;
  }
  return null;
}

Future<String?> _currentGoal() async {
  final prefs = await SharedPreferences.getInstance();
  final aliases = await _currentProfileAliases();
  final profileKey = _latestProfileAlias(prefs, aliases);
  final byAlias = _prefStringAnyAlias(prefs, 'goal_', aliases, preferred: profileKey) ??
      _prefStringAnyAlias(prefs, 'user_goal_', aliases, preferred: profileKey);
  if (byAlias != null && byAlias.trim().isNotEmpty) return byAlias.trim();

  return prefs.getString('goal') ??
      prefs.getString('user_goal') ??
      prefs.getString('plan_goal') ??
      prefs.getString('target_goal');
}


/// ✅ غلاف بسيط يحافظ على النداءات الموجودة في هذا الملف
class DailyTrackerStore {
  static Future<void> addIntake({
    required double cal,
    required double protein,
    required double carb,
    required double fat,
  }) {
    return TrackerStore.addIntake(
      cal: cal,
      protein: protein,
      carb: carb,
      fat: fat,
    );
  }
}

/// قراءة مجاميع يوم محدد (متوافقة مع صيغ متعددة قديمة/حديثة).
Future<Map<String, double>> _readTotalsForDate(
  SharedPreferences prefs,
  String email,
  String ymd,
) async {
  double toD(v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  // 1) المفاتيح الأساسية المستخدمة في صفحة الهوم
  try {
    final totalsKey = 'kcal_daytotals_${email}_$ymd';
    final rawTotals = prefs.getString(totalsKey);
    if (rawTotals != null) {
      final m = jsonDecode(rawTotals);
      if (m is Map) {
        final k = toD(m['k'] ?? m['cal'] ?? m['calories']);
        final p = toD(m['p'] ?? m['protein']);
        final c = toD(m['c'] ?? m['carb'] ?? m['carbs']);
        final f = toD(m['f'] ?? m['fat']);
        if (k > 0 || p > 0 || c > 0 || f > 0) {
          return {'cal': k, 'p': p, 'c': c, 'f': f};
        }
      }
    }
  } catch (_) {}

  // 2) نفس fallback تبع الهوم: قائمة intake_entries تجمع k أو cal وباقي الماكروز
  try {
    final entriesKey = 'intake_entries_${email}_$ymd';
    final raw = prefs.getString(entriesKey);
    if (raw != null) {
      final list = jsonDecode(raw);
      if (list is List) {
        double k=0, p=0, c=0, f=0;
        for (final e in list) {
          if (e is Map) {
            final kk = e['k'] ?? e['cal'] ?? e['calories'] ?? e['kcal'];
            k += toD(kk);
            p += toD(e['p'] ?? e['protein'] ?? e['protein_g']);
            c += toD(e['c'] ?? e['carb'] ?? e['carbs'] ?? e['carb_g']);
            f += toD(e['f'] ?? e['fat'] ?? e['fat_g']);
          }
        }
        if (k > 0 || p > 0 || c > 0 || f > 0) {
          return {'cal': k, 'p': p, 'c': c, 'f': f};
        }
      }
    }
  } catch (_) {}

  // 3) فallback موسّع (كما كان) يدعم مفاتيح أخرى محتملة
  double _calFrom(Map m) {
    final k = m['k'] ?? m['cal'] ?? m['kcal'] ?? m['calories'] ?? (m['energy'] is Map ? m['energy']['kcal'] : m['energy']);
    final p = m['p'] ?? m['protein'] ?? m['protein_g'];
    final c = m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g'];
    final f = m['f'] ?? m['fat'] ?? m['fat_g'];
    double cal = toD(k ?? 0);
    if (cal == 0) cal = toD(p)*4 + toD(c)*4 + toD(f)*9;
    return cal;
  }
  Map<String, double> sumFromIterable(Iterable items) {
    double cal = 0, p = 0, c = 0, f = 0;
    for (final it in items) {
      try {
        Map m;
        if (it is String) { m = Map<String, dynamic>.from(jsonDecode(it)); }
        else if (it is Map) { m = Map<String, dynamic>.from(it); }
        else { continue; }
        cal += _calFrom(m);
        p   += toD(m['p'] ?? m['protein'] ?? m['protein_g']);
        c   += toD(m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g']);
        f   += toD(m['f'] ?? m['fat'] ?? m['fat_g']);
      } catch (_) {}
    }
    return {'cal': cal, 'p': p, 'c': c, 'f': f};
  }

  final entryListKeys = <String>[
    'intake_entries_${email}_$ymd',
    'kcal_entries_${email}_$ymd',
    'intakes_${email}_$ymd',
    'meals_${email}_$ymd',
    'food_log_${email}_$ymd',
    'food_log_${ymd}_$email',
  ];
  for (final k in entryListKeys) {
    final raw = prefs.getString(k);
    if (raw == null) continue;
    try {
      final data = jsonDecode(raw);
      final mealItems = _extractMealLogItems(data);
      if (mealItems.isNotEmpty) {
        final s = _sumMealLogItems(mealItems);
        if (s.values.any((v) => v > 0)) return s;
      }
      if (data is List) {
        final s = sumFromIterable(data);
        if (s.values.any((v)=> v>0)) return s;
      } else if (data is Map) {
        if (data['items'] is List) {
          final s = sumFromIterable(data['items']);
          if (s.values.any((v)=> v>0)) return s;
        } else {
          final m = Map<String, dynamic>.from(data);
          final cal = _calFrom(m);
          final p = toD(m['p'] ?? m['protein'] ?? m['protein_g']);
          final c = toD(m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g']);
          final f = toD(m['f'] ?? m['fat'] ?? m['fat_g']);
          if (cal>0 || p>0 || c>0 || f>0) return {'cal': cal, 'p': p, 'c': c, 'f': f};
        }
      }
    } catch (_) {}
  }

  // 4) طبقة وازن اليومية الموحدة: نفس مصدر صفحة سجل السعرات بعد التوحيد.
  try {
    final unified = await WazenDailyStore.readTotals(ymd);
    if (unified.calories > 0 || unified.protein > 0 || unified.carbs > 0 || unified.fat > 0) {
      return {
        'cal': unified.calories,
        'p': unified.protein,
        'c': unified.carbs,
        'f': unified.fat,
      };
    }
  } catch (_) {}

  // 5) مفاتيح قديمة منفصلة بدون هوية مستخدم.
  final legacyCal = _prefDouble(prefs, 'dietCalories_$ymd') ?? 0.0;
  final legacyP = _prefDouble(prefs, 'dietProtein_$ymd') ?? 0.0;
  final legacyC = _prefDouble(prefs, 'dietCarb_$ymd') ?? 0.0;
  final legacyF = _prefDouble(prefs, 'dietFat_$ymd') ?? 0.0;
  if (legacyCal > 0 || legacyP > 0 || legacyC > 0 || legacyF > 0) {
    return {'cal': legacyCal, 'p': legacyP, 'c': legacyC, 'f': legacyF};
  }

  return {'cal': 0, 'p': 0, 'c': 0, 'f': 0};
}

List<_MealLogItem> _readMealItemsForDate(
  SharedPreferences prefs, {
  required List<String> aliases,
  required String ymd,
  required bool isToday,
}) {
  final out = <_MealLogItem>[];
  final seen = <String>{};

  void addFromRaw(String? raw, String sourceSlot) {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      for (final item in _extractMealLogItems(decoded, slot: sourceSlot)) {
        final signature = '${item.slot}|${item.name}|${item.calories.toStringAsFixed(1)}|${item.protein.toStringAsFixed(1)}|${item.carbs.toStringAsFixed(1)}|${item.fat.toStringAsFixed(1)}';
        if (seen.add(signature)) out.add(item);
      }
    } catch (_) {}
  }

  void addFromStringList(List<String>? list, String sourceSlot) {
    if (list == null || list.isEmpty) return;
    for (final raw in list) {
      addFromRaw(raw, sourceSlot);
    }
  }

  for (final alias in aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user')) {
    addFromRaw(prefs.getString('intake_entries_${alias}_$ymd'), 'سجل السعرات');
    addFromRaw(prefs.getString('meals_${alias}_$ymd'), 'وجبة');
    addFromRaw(prefs.getString('kcal_entries_${alias}_$ymd'), 'سجل السعرات');
    addFromRaw(prefs.getString('intakes_${alias}_$ymd'), 'سجل السعرات');
    addFromRaw(prefs.getString('food_log_${alias}_$ymd'), 'سجل السعرات');
    addFromRaw(prefs.getString('food_log_${ymd}_$alias'), 'سجل السعرات');
    addFromStringList(_safePrefStringList(prefs, 'intake_entries_${alias}_$ymd'), 'سجل السعرات');
    addFromStringList(_safePrefStringList(prefs, 'meals_${alias}_$ymd'), 'وجبة');
    if (isToday) {
      addFromRaw(prefs.getString('meals_$alias'), 'وجبة');
      addFromStringList(_safePrefStringList(prefs, 'meals_$alias'), 'وجبة');
    }
  }

  if (out.isEmpty) {
    addFromRaw(prefs.getString('diet_$ymd'), 'إجمالي اليوم');
  }
  return out;
}


/// ====== نموذج معلومات المستخدم للتقرير ======
class _UserProfile {
  final String email;
  final String fullName;
  final String goal;
  final String? gender; // "ذكر"/"أنثى" أو null
  final double? heightCm;
  final double? weightKg;
  final int? age;
  _UserProfile({
    required this.email,
    required this.fullName,
    required this.goal,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.age,
  });

  double? get bmi {
    if (heightCm == null || weightKg == null) return null;
    final h = heightCm! / 100.0;
    if (h <= 0) return null;
    return weightKg! / (h * h);
  }

  String get bmiClass {
    final b = bmi;
    if (b == null) return 'غير متوفر';
    if (b < 18.5) return 'نحافة';
    if (b < 25) return 'طبيعي';
    if (b < 30) return 'زيادة وزن';
    return 'سمنة';
  }

  double? get bmr {
    // Mifflin–St Jeor (تقريبي إذا توفر العمر/الجنس/الطول/الوزن)
    if (heightCm == null || weightKg == null || age == null || gender == null) {
      return null;
    }
    final w = weightKg!;
    final h = heightCm!;
    final a = age!;
    if (gender == 'أنثى' || gender?.toLowerCase() == 'female') {
      return (10 * w) + (6.25 * h) - (5 * a) - 161;
    }
    return (10 * w) + (6.25 * h) - (5 * a) + 5; // ذكر
  }
}


String? _readStringFlexible(SharedPreferences prefs, String key) {
  final v = prefs.get(key);
  if (v == null) return null;
  if (v is String) return v;
  // Convert non-strings safely (bool/num) to string
  return v.toString();
}


String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}

String _joinNameParts(String? first, String? last) {
  final f = (first ?? '').trim();
  final l = (last ?? '').trim();
  return [f, l].where((e) => e.isNotEmpty).join(' ').trim();
}

/// محاولة استخراج الاسم من وثيقة المستخدم في Firestore مع دعم عدة مفاتيح شائعة
String _extractFullNameFromUserDoc(Map<String, dynamic> data) {
  String? pick(String key) {
    final v = _asString(data[key]);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  // مباشر
  final direct = pick('fullName') ??
      pick('name') ??
      pick('displayName') ??
      pick('userName') ??
      pick('username');

  if (direct != null) return direct;

  // profile
  final profile = (data['profile'] is Map) ? Map<String, dynamic>.from(data['profile'] as Map) : null;
  if (profile != null) {
    final p = _asString(profile['fullName']) ??
        _asString(profile['name']) ??
        _asString(profile['displayName']) ??
        _asString(profile['userName']);
    if (p != null && p.trim().isNotEmpty) return p.trim();

    final pf = _asString(profile['firstName']);
    final pl = _asString(profile['lastName']);
    final joined = _joinNameParts(pf, pl);
    if (joined.isNotEmpty) return joined;
  }

  // metrics
  final metrics = (data['metrics'] is Map) ? Map<String, dynamic>.from(data['metrics'] as Map) : null;
  if (metrics != null) {
    final mname = _asString(metrics['fullName']) ??
        _asString(metrics['name']) ??
        _asString(metrics['displayName']);
    if (mname != null && mname.trim().isNotEmpty) return mname.trim();

    final mf = _asString(metrics['firstName']);
    final ml = _asString(metrics['lastName']);
    final joined = _joinNameParts(mf, ml);
    if (joined.isNotEmpty) return joined;
  }

  // في حال تخزين الاسم كـ first/last على الجذر
  final f = _asString(data['firstName']);
  final l = _asString(data['lastName']);
  final joined = _joinNameParts(f, l);
  if (joined.isNotEmpty) return joined;

  return '';
}

Map<String, dynamic> _nestedMap(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

int _trackingTimestampToMs(dynamic value) {
  if (value == null) return 0;
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

double? _firstDoubleInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(
          value.trim().replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.'),
        );
        if (parsed != null) return parsed;
      }
    }
  }
  return null;
}

int? _firstIntInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  final value = _firstDoubleInMaps(maps, keys);
  return value == null ? null : value.round();
}

String? _firstStringInMaps(
  List<Map<String, dynamic>> maps,
  List<String> keys,
) {
  for (final map in maps) {
    for (final key in keys) {
      final value = _asString(map[key]);
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
  }
  return null;
}

int _cloudProfileStamp(Map<String, dynamic> data) {
  final metrics = _nestedMap(data, 'metrics');
  final profile = _nestedMap(data, 'profile');
  final values = <int>[
    _trackingTimestampToMs(data['profileUpdatedAtMs']),
    _trackingTimestampToMs(data['updatedAtMs']),
    _trackingTimestampToMs(data['updatedAt']),
    _trackingTimestampToMs(metrics['updatedAtMs']),
    _trackingTimestampToMs(metrics['updatedAt']),
    _trackingTimestampToMs(profile['updatedAtMs']),
    _trackingTimestampToMs(profile['updatedAt']),
  ];
  return values.fold<int>(0, (a, b) => a > b ? a : b);
}

Future<Map<String, dynamic>?> _readCurrentUserDocForTracking(
  WazenIdentity identity,
) async {
  // صفحة التتبع تعتمد على البيانات المحلية فقط حتى تفتح فورًا بدون انتظار السحابة.
  return null;
}


Future<void> _cacheResolvedProfileForTracking({
  required SharedPreferences prefs,
  required Iterable<String> aliases,
  String? fullName,
  String? gender,
  int? age,
  double? heightCm,
  double? weightKg,
  String? goal,
  int? stamp,
}) async {
  final safeAliases = aliases
      .where((e) => e.trim().isNotEmpty && e != 'unknown_user')
      .toSet()
      .toList(growable: false);
  if (safeAliases.isEmpty) return;

  for (final alias in safeAliases) {
    if ((fullName ?? '').trim().isNotEmpty) {
      final name = fullName!.trim();
      await prefs.setString('fullName_$alias', name);
      final parts = name.split(RegExp(r'\s+'));
      await prefs.setString('firstName_$alias', parts.isNotEmpty ? parts.first : '');
      await prefs.setString('lastName_$alias', parts.length > 1 ? parts.sublist(1).join(' ') : '');
    }
    if ((gender ?? '').trim().isNotEmpty) {
      await prefs.setString('gender_$alias', gender!.trim());
    }
    if (age != null && age > 0) await prefs.setInt('age_$alias', age);
    if (heightCm != null && heightCm > 0) {
      await prefs.setDouble('height_$alias', heightCm);
      await prefs.setDouble('height_cm_$alias', heightCm);
      await prefs.setDouble('heightCm_$alias', heightCm);
    }
    if (weightKg != null && weightKg > 0) {
      await prefs.setDouble('weight_$alias', weightKg);
      await prefs.setDouble('current_weight_$alias', weightKg);
      await prefs.setDouble('currentWeight_$alias', weightKg);
      await prefs.setDouble('weightKg_$alias', weightKg);
      await prefs.setDouble('user_weight_$alias', weightKg);
    }
    if ((goal ?? '').trim().isNotEmpty) {
      final resolvedGoal = goal!.trim();
      await prefs.setString('goal_$alias', resolvedGoal);
      await prefs.setString('user_goal_$alias', resolvedGoal);
    }
    if (stamp != null && stamp > 0) {
      final current = prefs.getInt('profileUpdatedAt_$alias') ?? 0;
      if (stamp >= current) await prefs.setInt('profileUpdatedAt_$alias', stamp);
    }
  }
}

Future<_UserProfile> _loadUserProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final user = FirebaseAuth.instance.currentUser;
  final identity = user != null
      ? await WazenIdentityStore.currentIdentity(user: user, migrate: false)
      : await WazenIdentityStore.currentIdentity(migrate: false);
  await WazenIdentityStore.mirrorKnownLocalKeys(prefs, identity);

  final aliases = await _currentProfileAliases();
  final profileKey = _latestProfileAlias(prefs, aliases);
  final orderedAliases = _orderedAliases(aliases, profileKey);
  final profileStamp = prefs.getInt('profileUpdatedAt_$profileKey') ?? 0;
  final macroStamp = prefs.getInt('macrosUpdatedAt_$profileKey') ?? 0;
  final localStamp = profileStamp > macroStamp ? profileStamp : macroStamp;

  final localFullName = _prefStringAnyAlias(prefs, 'fullName_', aliases, preferred: profileKey) ??
      _joinNameParts(
        _prefStringAnyAlias(prefs, 'firstName_', aliases, preferred: profileKey) ??
            _prefStringAnyAlias(prefs, 'name_', aliases, preferred: profileKey),
        _prefStringAnyAlias(prefs, 'lastName_', aliases, preferred: profileKey),
      );
  final localGoal = _prefStringAnyAlias(prefs, 'goal_', aliases, preferred: profileKey) ??
      _prefStringAnyAlias(prefs, 'user_goal_', aliases, preferred: profileKey) ??
      prefs.getString('goal') ??
      prefs.getString('user_goal') ??
      'نمط حياة صحي';
  final localGender = _prefStringAnyAlias(prefs, 'gender_', aliases, preferred: profileKey);
  final localAge = _prefIntAnyAlias(prefs, 'age_', aliases, preferred: profileKey);
  final localHeight = _prefDoubleAnyAlias(
    prefs,
    const ['height_', 'height_cm_', 'heightCm_'],
    aliases,
    preferred: profileKey,
  );
  final localWeight = _prefDoubleAnyAlias(
    prefs,
    const ['current_weight_', 'weight_', 'weightKg_', 'currentWeight_', 'user_weight_', 'goal_current_'],
    aliases,
    preferred: profileKey,
  );

  Map<String, dynamic>? cloudData;
  try {
    cloudData = await _readCurrentUserDocForTracking(identity);
  } catch (_) {
    cloudData = null;
  }

  String? cloudFullName;
  String? cloudGoal;
  String? cloudGender;
  int? cloudAge;
  double? cloudHeight;
  double? cloudWeight;
  int cloudStamp = 0;

  if (cloudData != null) {
    final metrics = _nestedMap(cloudData, 'metrics');
    final profile = _nestedMap(cloudData, 'profile');
    final basic = _nestedMap(cloudData, 'basic');
    final lifestyle = _nestedMap(cloudData, 'lifestyle');
    final maps = <Map<String, dynamic>>[cloudData, metrics, profile, basic, lifestyle];

    cloudStamp = _cloudProfileStamp(cloudData);
    cloudFullName = _extractFullNameFromUserDoc(cloudData).trim();
    if (cloudFullName.isEmpty) cloudFullName = null;
    cloudGoal = _firstStringInMaps(maps, const ['goal', 'goalType', 'userGoal', 'planGoal']);
    cloudGender = _firstStringInMaps(maps, const ['gender', 'sex']);
    cloudAge = _firstIntInMaps(maps, const ['age']);
    cloudHeight = _firstDoubleInMaps(maps, const ['heightCm', 'height', 'height_cm']);
    cloudWeight = _firstDoubleInMaps(
      maps,
      const ['currentWeightKg', 'weightKg', 'weight', 'currentWeight', 'current_weight', 'user_weight'],
    );
  }

  final preferCloud = cloudStamp > 0 && (localStamp == 0 || cloudStamp >= localStamp);

  T? pick<T>(T? local, T? cloud) {
    if (preferCloud) return cloud ?? local;
    return local ?? cloud;
  }

  final fullName = pick<String>(
        localFullName.trim().isNotEmpty ? localFullName.trim() : (user?.displayName ?? '').trim(),
        cloudFullName,
      ) ??
      '';
  final goal = pick<String>(localGoal.trim().isNotEmpty ? localGoal.trim() : null, cloudGoal) ??
      'نمط حياة صحي';
  final gender = pick<String>(
    (localGender ?? '').trim().isNotEmpty ? localGender!.trim() : null,
    cloudGender,
  );
  final age = pick<int>(localAge, cloudAge);
  final height = pick<double>(localHeight, cloudHeight);
  final weight = pick<double>(localWeight, cloudWeight);

  final displayEmail = (identity.email.isNotEmpty
          ? identity.email
          : (prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ??
              prefs.getString('currentEmail') ??
              user?.email ??
              identity.emailKey))
      .trim();

  await _cacheResolvedProfileForTracking(
    prefs: prefs,
    aliases: orderedAliases,
    fullName: fullName,
    gender: gender,
    age: age,
    heightCm: height,
    weightKg: weight,
    goal: goal,
    stamp: (localStamp > cloudStamp ? localStamp : cloudStamp),
  );

  return _UserProfile(
    email: displayEmail.isNotEmpty ? displayEmail : 'unknown_user',
    fullName: fullName,
    goal: goal,
    gender: gender,
    heightCm: height,
    weightKg: weight,
    age: age,
  );
}




/// ========= Screen =========
class WeightTrackingPage extends StatefulWidget {
  const WeightTrackingPage({super.key});
  @override
  State<WeightTrackingPage> createState() => _WeightTrackingPageState();
}


// ===== Helpers: data holders for charting/PDF (moved to top-level) =====


// ===== Helpers: data holders for charting/PDF =====
class _Series {
  final List<DateTime> dates;

  // التغذية
  final List<double> calories;
  final List<double> protein;
  final List<double> carb;
  final List<double> fat;

  // الترطيب (بالمل)
  final List<double> waterMl;

  // النشاط
  final List<int> steps;
  final List<int> burned;

  // الوزن
  final List<double?> weights;

  const _Series({
    required this.dates,
    required this.calories,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.waterMl,
    required this.steps,
    required this.burned,
    required this.weights,
  });
}

class _PdfSeriesBundle {
  final _Series week;
  final _Series month;
  final _Series year;
  final Map<String, List<_MealLogItem>> weekMealItems;

  const _PdfSeriesBundle({
    required this.week,
    required this.month,
    required this.year,
    required this.weekMealItems,
  });
}

class _Grouped {
  final List<String> labelsText;
  final List<double> values;
  final List<DateTime> labelsDates;
  const _Grouped({
    required this.labelsText,
    required this.values,
    required this.labelsDates,
  });
}

class _GroupedByDate {
  final List<DateTime> labels;
  final List<double> values;
  const _GroupedByDate({
    required this.labels,
    required this.values,
  });
}

class _Agg {
  final DateTime label;
  final double sum;
  final int count;
  const _Agg(this.label, this.sum, this.count);
  _Agg add(double v) => _Agg(label, sum + v, count + 1);
}
// ===== End helpers =====

  
class _WeightTrackingPageState extends State<WeightTrackingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;
  bool _isExportingPdf = false;

  // كاش استرجاع بيانات الأيام من السحابة لهذه التبويبة.
  // كان موجود في تبويبة سجل السعرات فقط، لذلك صار الخطأ عند البناء.
  bool _cloudDailyRestoreDone = false;
  List<Map<String, dynamic>> _cachedRemoteDays = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _initUserNameSync();
  }

  

  Future<void> _initUserNameSync() async {
    // ابدأ بالقيمة الحالية إن وجدت
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      setState(() => _displayName = user.displayName!.trim());
    }

    // اقرأ من التخزين المحلي كـ fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (user?.email ?? await _currentEmail() ?? '').trim();
      if (email.isNotEmpty) {
        final stored = (prefs.getString('fullName_$email') ?? '').trim();
        final first = (prefs.getString('firstName_$email') ?? '').trim();
        final last = (prefs.getString('lastName_$email') ?? '').trim();
        final local = stored.isNotEmpty ? stored : _joinNameParts(first, last);
        if (local.isNotEmpty && mounted) {
          setState(() => _displayName = local);
        }
      }
    } catch (_) {}

    // لا توجد قراءة Firestore هنا: صفحة التتبع يجب أن تفتح من التخزين المحلي مباشرة.
  }
@override
  void dispose() {
    _userNameSub?.cancel();
    _tick?.cancel();
    _tab.dispose();
    super.dispose();
  }

  // ====== زر تصدير PDF (مُحسَّن مع بيانات المستخدم) ======
  Future<void> _exportTrackingPdf(BuildContext context) async {
    if (!mounted || _isExportingPdf) return;
    _isExportingPdf = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      final now = DateTime.now();

      // لا نجمع 7 + 30 + 365 يوم بثلاث دورات بطيئة.
      // نجمع Snapshot محلي واحد سريع، ثم نشتق منه الأسبوع/الشهر/السنة.
      final profileFuture = _loadUserProfile();
      final bundleFuture = _collectPdfSeriesBundle();
      final weightPointsFuture = _loadAllWeightPointsForReport();
      final fontFuture = rootBundle.load('assets/Tajawal-Regular.ttf');

      final profile = await profileFuture;
      final bundle = await bundleFuture;
      final week = bundle.week;
      final month = bundle.month;
      final year = bundle.year;
      final weekMealItems = bundle.weekMealItems;
      final allWeightPoints = await weightPointsFuture;

      final tajawal = pw.Font.ttf(await fontFuture);

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: tajawal, bold: tajawal),
      );

      // ====== صفحة غلاف ======
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('تقرير التتبّع الصحي — تطبيق وازن',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo800,
                      )),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'تاريخ التوليد: ${DateFormat('yyyy/MM/dd HH:mm').format(now)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(8),
                      color: PdfColors.grey200,
                    ),
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _kv('الاسم', profile.fullName.isEmpty ? 'غير محدد' : profile.fullName),
                        _kv('البريد', profile.email),
                        _kv('الهدف', profile.goal),
                        _kv('الجنس', profile.gender ?? 'غير محدد'),
                        _kv('الطول', profile.heightCm != null ? '${profile.heightCm!.toStringAsFixed(0)} سم' : 'غير محدد'),
                        _kv('الوزن الحالي', profile.weightKg != null ? '${profile.weightKg!.toStringAsFixed(1)} كجم' : 'غير محدد'),
                        _kv('العمر', profile.age?.toString() ?? 'غير محدد'),
                        _kv('BMI', profile.bmi != null ? '${profile.bmi!.toStringAsFixed(1)} (${profile.bmiClass})' : 'غير متوفر'),
                        _kv('BMR تقديري', profile.bmr != null ? '${profile.bmr!.toStringAsFixed(0)} سعرة/يوم' : 'غير متوفر'),
          
        ],
                    ),
                  ),
                  pw.Spacer(),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('© وازن — تقرير آلي للاستخدام الشخصي.',
                        style: const pw.TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      pw.Widget header(String title) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 18.0, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6.0),
              pw.Divider(),
            ],
          );

      // أسبوعي
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('التتبّع — أسبوعي'),
                  _sectionTitle('الأكل (سعرات) — آخر 7 أيام'),
                  _bars(
                    values: week.calories,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                  ),
                  _statsTable(
                    columns: ['اليوم', 'سعرات', 'بروتين', 'كارب', 'دهون', 'وجبات'],
                    rows: List.generate(
                        week.dates.length,
                        (i) => [
                              DateFormat('yyyy/MM/dd').format(week.dates[i]),
                              week.calories[i].toStringAsFixed(0),
                              week.protein[i].toStringAsFixed(0),
                              week.carb[i].toStringAsFixed(0),
                              week.fat[i].toStringAsFixed(0),
                              (weekMealItems[DateFormat('yyyy-MM-dd').format(week.dates[i])]?.length ?? 0).toString(),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الماكروز — بروتين/كارب/دهون (آخر 7 أيام)'),
                  _twoBarsSideBySide(
                    leftTitle: 'بروتين (جم)',
                    left: week.protein,
                    rightTitle: 'كارب (جم)',
                    right: week.carb,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                  ),
                  pw.SizedBox(height: 6.0),
                  pw.Text('دهون (جم)',
                      style: pw.TextStyle(
                          fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
                  _bars(
                    values: week.fat,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                    color: PdfColors.grey700,
                  ),
                  _statsTable(
                    columns: ['اليوم', 'بروتين', 'كارب', 'دهون'],
                    rows: List.generate(
                        week.dates.length,
                        (i) => [
                              DateFormat('yyyy/MM/dd').format(week.dates[i]),
                              week.protein[i].toStringAsFixed(0),
                              week.carb[i].toStringAsFixed(0),
                              week.fat[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الترطيب — ماء (مل)'),
                  _bars(
                    values: week.waterMl,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                    color: PdfColors.teal600,
                  ),
                  _statsTable(
                    columns: ['اليوم', 'ماء (مل)'],
                    rows: List.generate(
                        week.dates.length,
                        (i) => [
                              DateFormat('yyyy/MM/dd').format(week.dates[i]),
                              week.waterMl[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),

                  _sectionTitle('النشاط — خطوات ومحروق'),
                  _twoBarsSideBySide(
                    leftTitle: 'خطوات',
                    left: week.steps.map((e) => e.toDouble()).toList(),
                    rightTitle: 'محروق',
                    right: week.burned.map((e) => e.toDouble()).toList(),
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الوزن — قراءات الأسبوع'),
                  _bars(
                    values: week.weights.map<double>((e) => (e ?? 0.0)).toList(),
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                    color: PdfColors.grey700,
                  ),
                  _weightSummaryTable(week),
                ],
              ),
            ),
          ),
        ),
      );

      // شهري (متوسطات أسبوعية)
      final monthWeeks = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.calories,
      );
      final monthSteps = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.steps.map((e) => e.toDouble()).toList(),
      );
      final monthBurned = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.burned.map((e) => e.toDouble()).toList(),
      );
      final monthWeights = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.weights.map<double>((e) => (e ?? 0.0)).toList(),
      );

      final monthProtein = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.protein,
      );
      final monthCarb = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.carb,
      );
      final monthFat = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.fat,
      );
      final monthWater = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.waterMl,
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('التتبّع — شهري'),
                  _sectionTitle('الأكل (سعرات) — متوسطات أسبوعية خلال الشهر'),
                  _bars(
                      values: monthWeeks.values,
                      labelBuilder: (i) => 'أسبوع ${i + 1}'),
                  _statsTable(
                    columns: ['أسبوع', 'متوسط السعرات'],
                    rows: List.generate(
                        monthWeeks.values.length,
                        (i) => [
                              'أسبوع ${i + 1}',
                              monthWeeks.values[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الماكروز — متوسط أسبوعي خلال الشهر'),
                  _twoBarsSideBySide(
                    leftTitle: 'بروتين (جم)',
                    left: monthProtein.values,
                    rightTitle: 'كارب (جم)',
                    right: monthCarb.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                  ),
                  pw.SizedBox(height: 6.0),
                  pw.Text('دهون (جم)',
                      style: pw.TextStyle(
                          fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
                  _bars(
                    values: monthFat.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                    color: PdfColors.grey700,
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الترطيب — ماء (مل) (متوسط أسبوعي)'),
                  _bars(
                    values: monthWater.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                    color: PdfColors.teal600,
                  ),
                  pw.SizedBox(height: 10.0),

                  _sectionTitle('النشاط — خطوات/محروق (متوسط أسبوعي)'),
                  _twoBarsSideBySide(
                    leftTitle: 'خطوات',
                    left: monthSteps.values,
                    rightTitle: 'محروق',
                    right: monthBurned.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الوزن — متوسطات أسبوعية'),
                  _bars(
                    values: monthWeights.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                    color: PdfColors.grey700,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // سنوي (متوسط شهري)
      final byMonthCalories =
          _groupByMonthAverage(month.dates, year.dates, year.calories);
      final byMonthSteps = _groupByMonthAverage(month.dates, year.dates,
          year.steps.map((e) => e.toDouble()).toList());
      final byMonthBurned = _groupByMonthAverage(month.dates, year.dates,
          year.burned.map((e) => e.toDouble()).toList());
      final byMonthWeights = _groupByMonthAverage(month.dates, year.dates,
          year.weights.map<double>((e) => (e ?? 0.0)).toList());

      final byMonthProtein =
          _groupByMonthAverage(month.dates, year.dates, year.protein);
      final byMonthCarb =
          _groupByMonthAverage(month.dates, year.dates, year.carb);
      final byMonthFat =
          _groupByMonthAverage(month.dates, year.dates, year.fat);
      final byMonthWater =
          _groupByMonthAverage(month.dates, year.dates, year.waterMl);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('التتبّع — سنوي'),
                  _sectionTitle('الأكل (سعرات) — متوسط شهري'),
                  _bars(
                    values: byMonthCalories.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthCalories.labels[i]),
                  ),
                  pw.SizedBox(height: 8.0),
                  _sectionTitle('الماكروز — متوسط شهري'),
                  _twoBarsSideBySide(
                    leftTitle: 'بروتين (جم)',
                    left: byMonthProtein.values,
                    rightTitle: 'كارب (جم)',
                    right: byMonthCarb.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthProtein.labels[i]),
                  ),
                  pw.SizedBox(height: 6.0),
                  pw.Text('دهون (جم)',
                      style: pw.TextStyle(
                          fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
                  _bars(
                    values: byMonthFat.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthFat.labels[i]),
                    color: PdfColors.grey700,
                  ),
                  pw.SizedBox(height: 8.0),
                  _sectionTitle('الترطيب — ماء (مل) (متوسط شهري)'),
                  _bars(
                    values: byMonthWater.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthWater.labels[i]),
                    color: PdfColors.teal600,
                  ),
                  pw.SizedBox(height: 8.0),

                  _sectionTitle('النشاط — خطوات/محروق (متوسط شهري)'),
                  _twoBarsSideBySide(
                    leftTitle: 'خطوات',
                    left: byMonthSteps.values,
                    rightTitle: 'محروق',
                    right: byMonthBurned.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthSteps.labels[i]),
                  ),
                  pw.SizedBox(height: 8.0),
                  _sectionTitle('الوزن — متوسط شهري'),
                  _bars(
                    values: byMonthWeights.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthWeights.labels[i]),
                    color: PdfColors.grey700,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      
// ====== صفحة "ملفّي الصحي" — ملخص شخصي ======
final prefsPdf = await SharedPreferences.getInstance();
final pdfAliases = await _currentProfileAliases();
final pdfProfileKey = _latestProfileAlias(prefsPdf, pdfAliases);
final tCalPdf = _prefDoubleAnyAlias(
      prefsPdf,
      const ['caloriesNeeded_'],
      pdfAliases,
      preferred: pdfProfileKey,
    ) ??
    2000.0;

final wkCals = week.calories.where((e) => e > 0).toList();
final wkAvgCal = wkCals.isNotEmpty ? wkCals.reduce((a,b)=>a+b)/wkCals.length : 0.0;
int onTargetDays = 0;
for (final v in wkCals) {
  if (tCalPdf > 0 && v >= tCalPdf*0.85 && v <= tCalPdf*1.15) onTargetDays++;
}
final adherence = wkCals.isEmpty ? 0.0 : (onTargetDays / wkCals.length * 100.0);

doc.addPage(
  pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (ctx) => pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ملفّي الصحي — ملخص',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo800,
                )),
            pw.SizedBox(height: 10),
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('الاسم')),
                    pw.Text(profile.fullName.isNotEmpty ? profile.fullName : '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('العمر')),
                    pw.Text(profile.age?.toString() ?? '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('الطول (سم)')),
                    pw.Text(profile.heightCm?.toStringAsFixed(0) ?? '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('الوزن الحالي (كجم)')),
                    pw.Text(profile.weightKg?.toStringAsFixed(1) ?? '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('BMI')),
                    pw.Text(
                      ((profile.bmi)!=null)
                        ? '${profile.bmi!.toStringAsFixed(1)} (${profile.bmiClass})'
                        : '—',
                    ),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('BMR (تقريبي)')),
                    pw.Text(profile.bmr?.toStringAsFixed(0) ?? '—'),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text('ملخص هذا الأسبوع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المؤشر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('القيمة')),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('هدف السعرات (يومي)')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(tCalPdf.toStringAsFixed(0))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('متوسط السعرات المُثبتة')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(wkAvgCal.toStringAsFixed(0))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('أيام ضمن الهدف (±15%)')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${onTargetDays}/${wkCals.length} (${adherence.toStringAsFixed(0)}%)')),
                ]),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);

// ====== صفحة سجل الوزن الكامل ======
if (allWeightPoints.isNotEmpty) {
  final firstWeight = allWeightPoints.first.kg;
  final lastWeight = allWeightPoints.last.kg;
  final change = lastWeight - firstWeight;
  final minWeight = allWeightPoints.map((e) => e.kg).reduce(math.min);
  final maxWeight = allWeightPoints.map((e) => e.kg).reduce(math.max);
  final avgWeight = allWeightPoints.map((e) => e.kg).reduce((a, b) => a + b) /
      allWeightPoints.length;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              header('سجل الوزن الكامل'),
              pw.Text(
                'هذه الصفحة تعرض جميع قراءات الوزن المسجلة في وازن، بينما واجهة التطبيق تعرض آخر 4 قراءات فقط حتى يبقى الرسم ثابتًا وواضحًا.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              _statsTable(
                columns: ['عدد القراءات', 'أول قراءة', 'آخر قراءة', 'التغيّر', 'أدنى', 'أعلى', 'متوسط'],
                rows: [
                  [
                    allWeightPoints.length.toString(),
                    '${firstWeight.toStringAsFixed(1)} كجم',
                    '${lastWeight.toStringAsFixed(1)} كجم',
                    '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} كجم',
                    '${minWeight.toStringAsFixed(1)} كجم',
                    '${maxWeight.toStringAsFixed(1)} كجم',
                    '${avgWeight.toStringAsFixed(1)} كجم',
                  ],
                ],
              ),
              pw.SizedBox(height: 12),
              _sectionTitle('رسم جميع قراءات الوزن'),
              _weightPdfBars(allWeightPoints),
              pw.SizedBox(height: 12),
              _sectionTitle('كل القراءات المسجلة'),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('الوزن', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('التغيّر عن السابق', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...List.generate(allWeightPoints.length, (i) {
                    final point = allWeightPoints[i];
                    final diff = i == 0 ? null : point.kg - allWeightPoints[i - 1].kg;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(DateFormat('yyyy/MM/dd').format(point.t)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${point.kg.toStringAsFixed(1)} كجم'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(diff == null ? '—' : '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} كجم'),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final dir = await getApplicationDocumentsDirectory();
      final name = 'tracking_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';
      final file = File('${dir.path}/$name');
      // اترك الواجهة تتنفس قبل مرحلة حفظ الملف، بدون تغيير شكل التقرير.
      await Future<void>.delayed(Duration.zero);
      final bytes = await doc.save();
      await file.writeAsBytes(bytes, flush: false);
      if (mounted) {
        if (navigator.canPop()) navigator.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء الملف: $name')),
        );
        unawaited(OpenFile.open(file.path).then((_) {}).catchError((_) {}));
      }
    } catch (e) {
      if (mounted) {
        if (navigator.canPop()) navigator.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير PDF: $e')),
        );
      }
    } finally {
      _isExportingPdf = false;
    }
  }

// تجهيز بيانات PDF محليًا بدورة واحدة بدل 7 + 30 + 365 يوم.
// هذا يحافظ على شكل التقرير الحالي لكنه يزيل سبب التعليق الطويل عند الضغط.
  Future<_PdfSeriesBundle> _collectPdfSeriesBundle() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    final aliases = await _currentProfileAliases();
    final profileKey = _latestProfileAlias(prefs, aliases);
    final analysisKeys = <String>[
      email,
      ..._orderedAliases(aliases, profileKey),
    ].where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = List<DateTime>.generate(
      365,
      (i) => today.subtract(Duration(days: 364 - i)),
      growable: false,
    );
    final ymds = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toList(growable: false);
    final ymdSet = ymds.toSet();

    final nutrition = <String, Map<String, double>>{};
    final waterLiters = <String, double>{};
    final activity = <String, Map<String, int>>{};
    final weights = <String, double>{};

    double score(Map<String, double> m) =>
        (m['cal'] ?? 0) + (m['p'] ?? 0) + (m['c'] ?? 0) + (m['f'] ?? 0);

    void putNutrition(String ymd, Map<String, double> value) {
      if (!ymdSet.contains(ymd)) return;
      if (score(value) <= 0) return;
      final old = nutrition[ymd];
      if (old == null || score(value) >= score(old)) {
        nutrition[ymd] = value;
      }
    }

    Map<String, double>? totalsFromRaw(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        final mealItems = _extractMealLogItems(decoded);
        if (mealItems.isNotEmpty) {
          final s = _sumMealLogItems(mealItems);
          return {
            'cal': s['cal'] ?? 0.0,
            'p': s['p'] ?? 0.0,
            'c': s['c'] ?? 0.0,
            'f': s['f'] ?? 0.0,
          };
        }
        if (decoded is List) {
          final s = sumFromIterable(decoded);
          return {
            'cal': s['cal'] ?? 0.0,
            'p': s['protein'] ?? 0.0,
            'c': s['carb'] ?? 0.0,
            'f': s['fat'] ?? 0.0,
          };
        }
        if (decoded is Map) {
          final m = Map<dynamic, dynamic>.from(decoded);
          if (m['items'] is List) {
            final s = sumFromIterable(m['items'] as List);
            return {
              'cal': s['cal'] ?? 0.0,
              'p': s['protein'] ?? 0.0,
              'c': s['carb'] ?? 0.0,
              'f': s['fat'] ?? 0.0,
            };
          }
          final cal = _foodLogCal(m);
          final p = _toD(m['p'] ?? m['protein'] ?? m['protein_g']);
          final c = _toD(m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g']);
          final f = _toD(m['f'] ?? m['fat'] ?? m['fat_g']);
          return {'cal': cal, 'p': p, 'c': c, 'f': f};
        }
      } catch (_) {}
      return null;
    }

    void readNutritionFor(String alias, String ymd) {
      final totalsRaw = prefs.getString('kcal_daytotals_${alias}_$ymd');
      final totals = totalsFromRaw(totalsRaw);
      if (totals != null) putNutrition(ymd, totals);

      const prefixes = <String>[
        'intake_entries_',
        'kcal_entries_',
        'intakes_',
        'meals_',
        'food_log_',
      ];
      for (final prefix in prefixes) {
        final byAlias = totalsFromRaw(prefs.getString('$prefix${alias}_$ymd'));
        if (byAlias != null) putNutrition(ymd, byAlias);
      }
      final reversedFoodLog = totalsFromRaw(prefs.getString('food_log_${ymd}_$alias'));
      if (reversedFoodLog != null) putNutrition(ymd, reversedFoodLog);
    }

    for (final alias in analysisKeys) {
      // الوزن
      final weightLogRaw = prefs.getString('weight_log_$alias');
      if (weightLogRaw != null) {
        try {
          final decoded = jsonDecode(weightLogRaw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final ymd = _normalizeYmd(item['date']);
              final kg = _toD(item['kg'] ?? item['weight'] ?? item['weightKg']);
              if (ymd != null && ymdSet.contains(ymd) && kg > 0) {
                weights[ymd] = kg;
              }
            }
          }
        } catch (_) {}
      }

      final historyList = _safePrefStringList(prefs, 'weightHistory_$alias');
      for (final item in historyList) {
        try {
          final m = jsonDecode(item) as Map<String, dynamic>;
          final ymd = _normalizeYmd(m['date']);
          final kg = _toD(m['weight'] ?? m['kg'] ?? m['weightKg']);
          if (ymd != null && ymdSet.contains(ymd) && kg > 0) {
            weights.putIfAbsent(ymd, () => kg);
          }
        } catch (_) {}
      }

      // الماء
      final waterLogRaw = prefs.getString('water_log_$alias');
      if (waterLogRaw != null) {
        try {
          final m = jsonDecode(waterLogRaw) as Map<String, dynamic>;
          for (final e in m.entries) {
            final ymd = _normalizeYmd(e.key);
            final v = _toD(e.value);
            if (ymd != null && ymdSet.contains(ymd) && v > 0) {
              waterLiters[ymd] = v;
            }
          }
        } catch (_) {}
      }

      // التغذية
      for (final ymd in ymds) {
        readNutritionFor(alias, ymd);

        final waterByLiter = _prefDouble(prefs, 'water_${ymd}_$alias');
        if (waterByLiter != null && waterByLiter > 0) waterLiters[ymd] = waterByLiter;

        final waterMl = _prefDouble(prefs, 'waterMl_${ymd}_$alias') ??
            _prefDouble(prefs, 'water_ml_${ymd}_$alias');
        if (waterMl != null && waterMl > 0) waterLiters[ymd] = waterMl / 1000.0;

        int s = 0;
        int b = 0;
        final activityRaw = prefs.getString('activity_${ymd}_$alias');
        if (activityRaw != null) {
          try {
            final a = jsonDecode(activityRaw) as Map<String, dynamic>;
            s = _asSafeInt(a['steps']);
            b = _asSafeInt(a['burned'] ?? a['activeBurned']);
          } catch (_) {}
        }
        if (s <= 0) s = _prefInt(prefs, 'steps_${ymd}_$alias') ?? 0;
        if (b <= 0) b = _prefInt(prefs, 'active_burned_${ymd}_$alias') ?? 0;
        if (s > 0 || b > 0) {
          final old = activity[ymd];
          if (old == null || (s + b) >= ((old['steps'] ?? 0) + (old['burned'] ?? 0))) {
            activity[ymd] = {'steps': s, 'burned': b};
          }
        }
      }
    }

    // مفاتيح قديمة بدون هوية مستخدم
    for (final ymd in ymds) {
      final legacyDiet = totalsFromRaw(prefs.getString('diet_$ymd'));
      if (legacyDiet != null) putNutrition(ymd, legacyDiet);
    }

    // fallback خفيف لآخر 30 يوم فقط من TrackerStore.
    // نتجنب _readTotalsForDate هنا لأنها تدخل في fallbacks كثيرة وتبطئ PDF عند المستخدمين بدون سجل طويل.
    for (final ymd in ymds.skip(335)) {
      final current = nutrition[ymd];
      if (current != null && score(current) > 0) continue;
      try {
        final day = DateTime.parse(ymd);
        final trackerDay = await TrackerStore.getDay(day);
        final totals = <String, double>{
          'cal': _asSafeDouble(trackerDay['calories']),
          'p': _asSafeDouble(trackerDay['protein']),
          'c': _asSafeDouble(trackerDay['carb'] ?? trackerDay['carbs']),
          'f': _asSafeDouble(trackerDay['fat']),
        };
        putNutrition(ymd, totals);
      } catch (_) {}
    }

    final currentWeight = _prefDoubleAnyAlias(
      prefs,
      const ['current_weight_', 'weight_', 'weightKg_', 'currentWeight_', 'user_weight_'],
      analysisKeys,
      preferred: profileKey,
    );
    if (currentWeight != null && currentWeight > 0) {
      weights[DateFormat('yyyy-MM-dd').format(today)] = currentWeight;
    }

    _Series makeSeries(int daysBack) {
      final start = 365 - daysBack;
      final d = dates.sublist(start);
      final calories = <double>[];
      final protein = <double>[];
      final carbs = <double>[];
      final fat = <double>[];
      final waterMl = <double>[];
      final steps = <int>[];
      final burned = <int>[];
      final seriesWeights = <double?>[];

      for (final day in d) {
        final ymd = DateFormat('yyyy-MM-dd').format(day);
        final totals = nutrition[ymd] ?? const {'cal': 0.0, 'p': 0.0, 'c': 0.0, 'f': 0.0};
        calories.add(totals['cal'] ?? 0.0);
        protein.add(totals['p'] ?? 0.0);
        carbs.add(totals['c'] ?? 0.0);
        fat.add(totals['f'] ?? 0.0);
        waterMl.add((waterLiters[ymd] ?? 0.0) * 1000.0);
        steps.add(activity[ymd]?['steps'] ?? 0);
        burned.add(activity[ymd]?['burned'] ?? 0);
        seriesWeights.add(weights[ymd]);
      }

      return _Series(
        dates: d,
        calories: calories,
        protein: protein,
        carb: carbs,
        fat: fat,
        waterMl: waterMl,
        steps: steps,
        burned: burned,
        weights: seriesWeights,
      );
    }

    final week = makeSeries(7);
    return _PdfSeriesBundle(
      week: week,
      month: makeSeries(30),
      year: makeSeries(365),
      weekMealItems: await _collectMealItemsForDates(week.dates),
    );
  }

// جمع بيانات يومية لعدد أيام للخلف (أقدم -> أحدث)
  Future<_Series> _collectSeries({required int daysBack}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    final aliases = await _currentProfileAliases();
    final profileKey = _latestProfileAlias(prefs, aliases);
    final analysisKeys = <String>[
      email,
      ..._orderedAliases(aliases, profileKey),
    ].where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList();

    // قراءة محلية فقط: لا مزامنة سحابية أثناء فتح صفحة التتبع أو تصدير التقرير.
    final remoteDays = <Map<String, dynamic>>[];

    // -------------------------
    // 1) الأوزان (حديث + قديم)
    // -------------------------
    final weightMap = <String, double>{};

    // الحديث والقديم: اقرأ الوزن من كل مفاتيح المستخدم المحتملة.
    for (final userKey in analysisKeys) {
      final weightLogRaw = prefs.getString('weight_log_$userKey');
      if (weightLogRaw != null) {
        try {
          final decoded = jsonDecode(weightLogRaw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final d = item['date']?.toString();
                final kg = _toD(item['kg'] ?? item['weight'] ?? item['weightKg']);
                if (d != null && kg > 0) weightMap[d] = kg;
              }
            }
          }
        } catch (_) {}
      }
      final historyList = _safePrefStringList(prefs, 'weightHistory_$userKey');
      if (historyList.isNotEmpty) {
        for (final item in historyList) {
          try {
            final m = jsonDecode(item) as Map<String, dynamic>;
            final d = m['date']?.toString();
            final kg = (m['weight'] as num?)?.toDouble();
            if (d != null && kg != null) weightMap.putIfAbsent(d, () => kg);
          } catch (_) {}
        }
      }
    }

    // لو اليوم له وزن حالي ولم يكن في الخريطة
    final current = _prefDoubleAnyAlias(
      prefs,
      const ['current_weight_', 'weight_', 'weightKg_', 'currentWeight_', 'user_weight_'],
      analysisKeys,
      preferred: profileKey,
    );
    final todayYmd =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toIso8601String()
            .split('T')
            .first;
    if (current != null && current > 0) {
      // وزن صفحة بياناتي هو المصدر الأحدث لليوم، لذلك يغطي أي قراءة قديمة لنفس اليوم.
      weightMap[todayYmd] = current;
    }

    // الوزن السحابي من users/{uid}/days/{ymd}/tracking.weightKg
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final tracking = d['tracking'];
      final kg = tracking is Map && tracking['weightKg'] is num
          ? (tracking['weightKg'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && kg > 0) {
        weightMap.putIfAbsent(ymd, () => kg);
      }
    }

    // -------------------------
    // 2) الماء (ليتر) -> (مل)
    // -------------------------
    final waterLitersMap = <String, double>{};
    for (final userKey in analysisKeys) {
      final waterLogRaw = prefs.getString('water_log_$userKey');
      if (waterLogRaw != null) {
        try {
          final m = jsonDecode(waterLogRaw) as Map<String, dynamic>;
          for (final e in m.entries) {
            final v = _toD(e.value);
            if (v > 0) waterLitersMap[e.key] = v;
          }
        } catch (_) {}
      }
    }
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final water = d['water'];
      final liters = water is Map && water['liters'] is num
          ? (water['liters'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && liters > 0) {
        waterLitersMap.putIfAbsent(ymd, () => liters);
      }
    }

    // -------------------------
    // 3) بناء السلاسل اليومية
    // -------------------------
    final now = DateTime.now();
    final dates = <DateTime>[];
    final calories = <double>[];
    final proteins = <double>[];
    final carbs = <double>[];
    final fats = <double>[];
    final waterMl = <double>[];
    final steps = <int>[];
    final burned = <int>[];
    final weights = <double?>[];

    for (int i = daysBack - 1; i >= 0; i--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = day.toIso8601String().split('T').first;

      // التغذية (سعرات/ماكروز) — نفس مصدر سجل السعرات الحقيقي.
      double cal = 0.0, p = 0.0, c = 0.0, f = 0.0;

      try {
        final trackerDay = await TrackerStore.getDay(day);
        cal = _asSafeDouble(trackerDay['calories']);
        p = _asSafeDouble(trackerDay['protein']);
        c = _asSafeDouble(trackerDay['carb'] ?? trackerDay['carbs']);
        f = _asSafeDouble(trackerDay['fat']);
      } catch (_) {}

      for (final userKey in analysisKeys) {
        if (cal > 0 || p > 0 || c > 0 || f > 0) break;
        try {
          final totals = await _readTotalsForDate(prefs, userKey, key);
          cal = (totals['cal'] ?? 0.0);
          p = (totals['p'] ?? 0.0);
          c = (totals['c'] ?? 0.0);
          f = (totals['f'] ?? 0.0);
          if (cal > 0 || p > 0 || c > 0 || f > 0) break;
        } catch (_) {}
      }

      // fallback: diet_YYYY-MM-DD (قد يكون بدون email)
      if (cal == 0.0 && p == 0.0 && c == 0.0 && f == 0.0) {
        final raw = prefs.getString('diet_$key');
        if (raw != null) {
          try {
            final m = jsonDecode(raw) as Map<String, dynamic>;
            cal = (m['calories'] as num?)?.toDouble() ?? 0.0;
            p = (m['protein'] as num?)?.toDouble() ?? 0.0;
            c = (m['carb'] as num?)?.toDouble() ?? 0.0;
            f = (m['fat'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }
      }

      // النشاط (خطوات/محروق) — نفس مفاتيح صحتي وApple Health.
      int s = 0, b = 0;
      for (final userKey in analysisKeys) {
        final aRaw = prefs.getString('activity_${key}_$userKey');
        if (aRaw != null) {
          try {
            final a = jsonDecode(aRaw) as Map<String, dynamic>;
            s = _asSafeInt(a['steps']);
            b = _asSafeInt(a['burned'] ?? a['activeBurned']);
          } catch (_) {}
        }
        if (s <= 0) s = _prefInt(prefs, 'steps_${key}_$userKey') ?? s;
        if (b <= 0) b = _prefInt(prefs, 'active_burned_${key}_$userKey') ?? b;
        if (s > 0 || b > 0) break;
      }

      // الماء (الهدف في التطبيق بالمل، التخزين باللتر)
      double liters = waterLitersMap[key] ?? 0.0;
      for (final userKey in analysisKeys) {
        liters = _prefDouble(prefs, 'water_${key}_$userKey') ?? liters;
        final legacyMl = _prefInt(prefs, 'waterMl_${key}_$userKey') ??
            _prefInt(prefs, 'water_ml_${key}_$userKey');
        if (legacyMl != null && legacyMl > 0) {
          liters = legacyMl / 1000.0;
          break;
        }
        final legacyMlD = _prefDouble(prefs, 'waterMl_${key}_$userKey') ??
            _prefDouble(prefs, 'water_ml_${key}_$userKey');
        if (legacyMlD != null && legacyMlD > 0) {
          liters = legacyMlD / 1000.0;
          break;
        }
        if (liters > 0) break;
      }

      final w = weightMap[key];

      dates.add(day);
      calories.add(cal);
      proteins.add(p);
      carbs.add(c);
      fats.add(f);
      waterMl.add(liters * 1000.0);
      steps.add(s);
      burned.add(b);
      weights.add(w);
    }

    return _Series(
      dates: dates,
      calories: calories,
      protein: proteins,
      carb: carbs,
      fat: fats,
      waterMl: waterMl,
      steps: steps,
      burned: burned,
      weights: weights,
    );
  }

  Future<Map<String, List<_MealLogItem>>> _collectMealItemsForDates(
    List<DateTime> dates,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    final aliases = <String>{
      email,
      ...await _currentProfileAliases(),
    }..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final result = <String, List<_MealLogItem>>{};
    for (final date in dates) {
      final ymd = DateFormat('yyyy-MM-dd').format(date);
      var items = _readMealItemsForDate(
        prefs,
        aliases: aliases.toList(growable: false),
        ymd: ymd,
        isToday: ymd == today,
      );
      if (items.isEmpty) {
        try {
          final trackerEntries = await TrackerStore.getDayEntries(ymd);
          items = _extractMealLogItems(trackerEntries, slot: 'سجل السعرات');
        } catch (_) {}
      }
      if (items.isNotEmpty) result[ymd] = items;
    }
    return result;
  }

  _Grouped _groupAverage({
    required int weekSize,
    required List<DateTime> dates,
    required List<double> values,
  }) {
    final out = <double>[];
    final labels = <String>[];
    for (int i = 0; i < values.length; i += weekSize) {
      final end = math.min(i + weekSize, values.length);
      final slice = values.sublist(i, end);
      final double avg = slice.isEmpty
          ? 0.0
          : slice.reduce((a, b) => a + b) / slice.length.toDouble();

      out.add(avg);
      labels.add('أسبوع ${labels.length + 1}');
    }
    return _Grouped(labelsText: labels, values: out, labelsDates: []);
  }

  _GroupedByDate _groupByMonthAverage(
    List<DateTime> monthDates,
    List<DateTime> yearDates,
    List<double> yearValues,
  ) {
    final map = <String, _Agg>{}; // yyyy-MM -> (sum,count,DateTime label)
    for (int i = 0; i < yearDates.length; i++) {
      final d = yearDates[i];
      final key = DateFormat('yyyy-MM').format(d);
      map.putIfAbsent(key, () => _Agg(d, 0, 0));
      map[key] = map[key]!.add(yearValues[i]);
    }
    final keys = map.keys.toList()..sort();
    final labels = <DateTime>[];
    final values = <double>[];
    for (final k in keys) {
      final a = map[k]!;
      labels.add(DateTime(a.label.year, a.label.month, 1));
      values.add(a.sum / math.max(a.count, 1));
    }
    final start = values.length > 12 ? values.length - 12 : 0;
    return _GroupedByDate(
        labels: labels.sublist(start), values: values.sublist(start));
  }

  // عناصر PDF صغيرة
  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.SizedBox(width: 120, child: pw.Text('$k:')),
            pw.Expanded(child: pw.Text(v)),
          ],
        ),
      );

  pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4.0),
        child: pw.Text(t,
            style:
                pw.TextStyle(fontSize: 14.0, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _statsTable(
      {required List<String> columns, required List<List<String>> rows}) {
    final colWidths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < columns.length; i++) {
      colWidths[i] = const pw.FlexColumnWidth();
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: colWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: columns
              .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.all(6.0),
                    child: pw.Text(c),
                  ))
              .toList(),
        ),
        ...rows.map((r) => pw.TableRow(
              children: r
                  .map((c) => pw.Padding(
                        padding: const pw.EdgeInsets.all(6.0),
                        child: pw.Text(c),
                      ))
                  .toList(),
            )),
      ],
    );
  }

  pw.Widget _weightSummaryTable(_Series s) {
    final vals = s.weights.whereType<double>().toList();
    if (vals.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6.0),
        child: pw.Text('لا توجد قراءات وزن في هذه الفترة'),
      );
    }
    final min = vals.reduce(math.min);
    final max = vals.reduce(math.max);
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return _statsTable(
      columns: ['أدنى', 'أعلى', 'متوسط'],
      rows: [
        [
          min.toStringAsFixed(1),
          max.toStringAsFixed(1),
          avg.toStringAsFixed(1)
        ],
      ],
    );
  }

  pw.Widget _weightPdfBars(List<_WeightPoint> pts) {
    if (pts.isEmpty) {
      return pw.Text('لا توجد قراءات وزن مسجلة');
    }
    final values = pts.map((e) => e.kg).toList();
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final range = math.max(maxVal - minVal, 1.0);
    final step = math.max(1, (pts.length / 8).ceil());

    return pw.Container(
      height: 120,
      padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: List.generate(pts.length, (i) {
          final p = pts[i];
          final h = 26.0 + ((p.kg - minVal) / range) * 62.0;
          final showLabel = i == 0 || i == pts.length - 1 || i % step == 0;
          return pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 1),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  if (showLabel)
                    pw.Text(
                      p.kg.toStringAsFixed(1),
                      style: const pw.TextStyle(fontSize: 6),
                    ),
                  pw.Container(
                    height: h,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.teal600,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                  if (showLabel)
                    pw.Text(
                      DateFormat('MM/dd').format(p.t),
                      style: const pw.TextStyle(fontSize: 5),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }


  pw.Widget _bars({
    required List<double> values,
    required String Function(int) labelBuilder,
    PdfColor color = PdfColors.teal600,
  }) {
    final double maxVal = values.fold<double>(0.0, (p, n) => p > n ? p : n);

    final bars = <pw.Widget>[];
    for (int i = 0; i < values.length; i++) {
      final double h = maxVal == 0.0 ? 1.0 : (values[i] / maxVal) * 60.0;
      bars.add(
        pw.Column(
          children: [
            pw.Stack(children: [
  pw.Container(
    width: 14.0,
    height: h,
    decoration: pw.BoxDecoration(
      color: color,
      borderRadius: pw.BorderRadius.circular(4),
    ),
  ),
  pw.Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: pw.Center(child: pw.Text(values[i].toStringAsFixed(0), style: const pw.TextStyle(fontSize: 8))),
  ),
]),
pw.SizedBox(height: 4.0),
pw.Text(labelBuilder(i), style: const pw.TextStyle(fontSize: 8.0)),

          ],
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6.0),
      child: pw.SizedBox(
        height: 90.0,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: bars,
        ),
      ),
    );
  }

  pw.Widget _twoBarsSideBySide({
    required String leftTitle,
    required List<double> left,
    required String rightTitle,
    required List<double> right,
    required String Function(int) labelBuilder,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(leftTitle,
            style:
                pw.TextStyle(fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
        _bars(
            values: left, labelBuilder: labelBuilder, color: PdfColors.indigo),
        pw.SizedBox(height: 6.0),
        pw.Text(rightTitle,
            style:
                pw.TextStyle(fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
        _bars(
            values: right,
            labelBuilder: labelBuilder,
            color: PdfColors.deepOrange),
      ],
    );
  }

  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('التتبّع'),
            if (_displayName.trim().isNotEmpty)
              Text(
                _displayName,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(.65)),
              ),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surfaceVariant
                    : cs.surfaceVariant.withOpacity(.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? .46 : .25)),
              ),
              child: TabBar(
                controller: _tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: isDark
                      ? Color.alphaBlend(cs.primary.withOpacity(.13), cs.surface)
                      : cs.surface,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? .16 : .06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                labelColor: isDark ? cs.primary : cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                tabs: const [
                  Tab(text: 'الماكروز'),
                  Tab(text: 'الوزن'),
                  Tab(text: 'النشاط'),
                  Tab(text: 'صحتي'),
                  Tab(text: 'تحليلات'),
                ],
              ),
            ),
          ),
        ),
        
        actions: [
          IconButton(
            tooltip: 'تصدير PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              final ok = await PremiumAccess.ensureSubscribed(context, feature: PremiumFeature.trackingPdf);
              if (ok) {
                await _exportTrackingPdf(context);
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CaloriesHistoryScreen(),
          _WeightTab(),
          _ActivityTab(),
          _HealthVitalsTab(),
          _InsightsTab(),
        ],
      ),
    );
  }
BarChartGroupData _bar(int x, double used, double target, {required Color color}) {
    final percent = target <= 0 ? 0.0 : (used / target * 100);
    final clamped = percent.clamp(0.0, 200.0).toDouble(); // حتى 200%
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: clamped,
          width: 18.0,
          color: color.withOpacity(.9),
          borderRadius: BorderRadius.circular(6.0),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 200,
            color: color.withOpacity(.18),
          ),
        )
      ],
    );
  }

  Future<void> _quickAddDialog(BuildContext context) async {
    final c = TextEditingController();
    final p = TextEditingController();
    final k = TextEditingController();
    final f = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة يدوية لليوم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _numField(c, 'سعرات (سعرة)'),
            _numField(p, 'بروتين (غم)'),
            _numField(k, 'كارب (غم)'),
            _numField(f, 'دهون (غم)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cal = double.tryParse(c.text) ?? 0;
              final pro = double.tryParse(p.text) ?? 0;
              final crb = double.tryParse(k.text) ?? 0;
              final fat = double.tryParse(f.text) ?? 0;
              await DailyTrackerStore.addIntake(
                cal: cal,
                protein: pro,
                carb: crb,
                fat: fat,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// تحليلات ذكية حسب الهدف
String _smartAnalysis(
  String goal,
  double uCal,
  double uP,
  double uC,
  double uF,
  double tCal,
  double tP,
  double tC,
  double tF,
) {
  double rP = tP == 0 ? 0 : uP / tP;
  double rC = tC == 0 ? 0 : uC / tC;
  double rF = tF == 0 ? 0 : uF / tF;
  double rCal = tCal == 0 ? 0 : uCal / tCal;

  String highFat = rF > 1.1 ? 'الدهون مرتفعة اليوم. ' : '';
  String highCarb = rC > 1.1 ? 'الكارب مرتفع اليوم. ' : '';
  String lowProtein = rP < 0.7 ? 'البروتين منخفض. ' : '';
  String okCal = (rCal >= 0.9 && rCal <= 1.1) ? 'السعرات قريبة من هدفك. ' : '';
  String lowCal = rCal < 0.85 ? 'السعرات أقل بكثير من هدفك. ' : '';
  String highCalTxt = rCal > 1.15 ? 'تجاوزت هدف السعرات اليوم. ' : '';

  switch (goal) {
    case 'إنقاص الوزن':
    case 'خفض الدهون':
      if (rF > 1.0 && rC > 1.0) {
        return 'هدفك إنقاص/خفض الدهون: $highFat$highCarbخفّف الدهون والسكريات، وارفع البروتين . $okCal';
      }
      if (rF > 1.0) {
        return 'هدفك إنقاص/خفض الدهون: $highFatاختر مصادر بروتين خفيفة وقلّل الزيوت. $okCal';
      }
      if (rC > 1.2) {
        return 'هدفك إنقاص/خفض الدهون: $highCarbقلّل النشويات المكررة وزيد الألياف والخضار. $okCal';
      }
      if (rP < 0.8) {
        return 'هدفك إنقاص/خفض الدهون: $lowProteinزيد من البروتين للحفاظ على الكتلة العضلية.';
      }
      return 'جيد! توزيعتك تدعم الهدف — استمر على توازن بروتين أعلى ودهون/كارب مضبوطة. $okCal';

    case 'زيادة الوزن':
      if (rCal < 0.95) {
        return 'لهدف زيادة الوزن: $lowCal زد حصصك تدريجيًا خاصة الكارب والبروتين.';
      }
      if (rP < 0.9) {
        return 'لهدف زيادة الوزن: $lowProteinاحرص على بروتين كافٍ مع كل وجبة.';
      }
      if (rC < 0.9) {
        return 'لهدف زيادة الوزن: الكارب أقل من المطلوب — زِيد الأرز/الخبز الكامل/الشوفان.';
      }
      return 'ممتاز! تقدّم مناسب للزيادة — حافظ على فائض سعرات متوازن وبروتين كافٍ.';

    case 'بناء العضلات':
      if (rP < 1.0) {
        return 'هدفك بناء العضلات: $lowProteinحاول الوصول لهدف البروتين اليومي.';
      }
      if (rCal < 0.95) {
        return 'هدفك بناء العضلات: $lowCal زيد السعرات قليلا مع توزيع كارب جيد حول التمرين.';
      }
      return 'رائع! بروتينك جيد وتقريبًا عند هدف السعرات — استمر ووزّع الكارب حول التمرين.';

    case 'الصيام المتقطع':
      if (rP < 0.8) {
        return 'الصيام المتقطع: $lowProteinاحرص على بروتين كاف داخل نافذة الأكل.';
      }
      if (rCal > 1.2) {
        return 'الصيام المتقطع: $highCalTxtراقب حجم الوجبات داخل النافذة.';
      }
      return 'جيد! التزم بمواعيد النافذة ووجبات متوازنة مع بروتين جيد.';

    case 'نمط حياة صحي':
    case 'تحسين الصحة العامة':
      if (rF > 1.2) {
        return 'نمط صحي: $highFatقلّل المقليات واختر دهون صحية بكميات معتدلة.';
      }
      if (rC > 1.2) return 'نمط صحي: $highCarbفضّل الحبوب الكاملة والخضار.';
      return 'توزيع متوازن — استمر على اعتدال السعرات وجودة الاختيارات.';

    case 'خفض ضغط الدم':
      return 'خفض الضغط: راقب الصوديوم واشرب ماء كفاية. ${highFat.isNotEmpty ? highFat : ''}${highCarb.isNotEmpty ? highCarb : ''} ركّز على البوتاسيوم (موز/أفوكادو/سبانخ).';

    case 'زيادة النشاط اليومي':
      return 'زيادة النشاط: اجعل الكارب معتدلًا قبل النشاط والبروتين موزعًا خلال اليوم. ${okCal.isNotEmpty ? okCal : ''}';

    case 'ضبط مستوى السكر':
    case 'اتباع رجيم نباتي':
      if (rC > 1.2) {
        return 'السكر/النباتي: $highCarbانتبه للتوزيع عبر اليوم واختر كارب منخفض المؤشر.';
      }
      if (rP < 0.8) {
        return 'السكر/النباتي: $lowProteinأضف مصادر بروتين نباتي (عدس/حمص/توفو).';
      }
      return 'جيد! حافظ على كارب معقّد وألياف عالية وبروتين كافٍ.';
  }
  return 'توزيعك اليومي جيد عمومًا — راقب البروتين واعتدل في الدهون والكارب، واضبط السعرات حسب هدفك.';
}

class _MacroTile {
  final String label;
  final double used, target;
  final IconData icon;
  final Color color;
  _MacroTile(this.label, this.used, this.target, this.icon, this.color);

  Widget buildBar() {
    final remaining = (target - used).clamp(0.0, target).toDouble();
    final percent =
        target == 0 ? 0.0 : (used / target).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text('$label - المتبقي: ${remaining.toStringAsFixed(0)}'),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: color.withOpacity(.18),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10.0,
          ),
        ),
      ]),
    );
  }
} // 👈 قفل الكلاس

class _AnalysisCard extends StatelessWidget {
  final String text;
  const _AnalysisCard({required this.text});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.indigo.withOpacity(.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _CaloriesHistoryScreen extends StatefulWidget {
  const _CaloriesHistoryScreen();
  @override
  State<_CaloriesHistoryScreen> createState() => _CaloriesHistoryScreenState();
}


class _CaloriesHistoryScreenState extends State<_CaloriesHistoryScreen> with WidgetsBindingObserver {
  StreamSubscription? _macrosSub;
  VoidCallback? _targetsListener;
  SharedPreferences? _prefsRef;
  String? _emailRef;

  // أهداف اليوم من صفحة بياناتي
  double? _tCal, _tP, _tC, _tF;
  // الالتزام العام
  double _adherence = 0;
  int _okCalDays = 0, _okPDays = 0;
  // عرض/إخفاء السلاسل
  bool _showCal = true, _showP = true, _showC = true, _showF = true;
  // Heatmap & Highlights & Micro-goals
  List<Map<String, dynamic>> _heat = []; // [{date, score, cal, p, c, f}]
  Map<String, dynamic>? _bestDay;
  Map<String, dynamic>? _worstDay;
  Set<String> _microEnabled = {}; // {'cal_ok','protein_ok','logging_ok'}
  Map<String, double> _microProgress = {}; // id -> 0..1


  // آخر 7/14/30 يوم (بدون اليوم الجاري حتى يُثبَّت)
  int _days = 7;
  List<Map<String, dynamic>> _series = []; // [{date:'yyyy-mm-dd', cal:..., p:..., c:..., f:...}]
  String? _goal;

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;
  bool _cloudDailyRestoreDone = false;
  List<Map<String, dynamic>> _cachedRemoteDays = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    _load();
    _macrosSub = MacrosLiveBus.listen(_load);
    _targetsListener = () => _load();
    MacroTargetsController.revision.addListener(_targetsListener!);
  }

    @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _macrosSub?.cancel();
    if (_targetsListener != null) {
      MacroTargetsController.revision.removeListener(_targetsListener!);
    }
    _userNameSub?.cancel();
    super.dispose();
  }
Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    _goal = await _currentGoal();
    _prefsRef = prefs; _emailRef = email;
    await _loadMicroEnabled(prefs, email);
    
    // تحميل الأهداف من صفحة بياناتي
    if (email != null) {
      _tCal = _prefDouble(prefs, 'caloriesNeeded_${email}');
      _tP   = _prefDouble(prefs, 'protein_${email}');
      _tC   = _prefDouble(prefs, 'carbs_${email}');
      _tF   = _prefDouble(prefs, 'fat_${email}');
    }
final now = DateTime.now();
    final list = <Map<String, dynamic>>[];

    for (int i = _days-1; i >= 0; i--) { // يشمل اليوم الحالي
      final d = now.subtract(Duration(days: i)).toIso8601String().split('T').first;
      if (email == null) continue;
      final totals = await _readTotalsForDate(prefs, email, d);
      final cal = (totals['cal'] ?? 0).toDouble();
      final p  = (totals['p']   ?? 0).toDouble();
      final c  = (totals['c']   ?? 0).toDouble();
      final f  = (totals['f']   ?? 0).toDouble();
      if (cal>0 || p>0 || c>0 || f>0) {
        list.add({'date': d, 'cal': cal, 'p': p, 'c': c, 'f': f});
      } else {
        list.add({'date': d, 'cal': 0, 'p': 0, 'c': 0, 'f': 0});
      }
    }
    if (!mounted) return;
    setState(() => _series = list);
    _computeAdherence();
    _computeWeeklyHeatmap();
    _computeBestWorst();
    _computeMicroProgress();
  }

  // ألوان ثابتة متوافقة مع أسلوبك السابق (يمكن تعديلها لاحقًا لو أردت)
  Color get _calColor => Theme.of(context).colorScheme.primary;
  Color get _pColor   => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFA8B4C7) : Colors.indigo;  // بروتين
  Color get _cColor   => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFC9B896) : Colors.orange;  // كارب
  Color get _fColor   => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFC7A7A7) : Colors.redAccent; // دهون

  
  void _computeAdherence() {
    final daysWith = _series.where((e)=> ((e['cal'] as num?)?.toDouble() ?? 0) > 0).toList();
    final tCal = _tCal ?? (daysWith.isEmpty ? 2000.0 : daysWith.map((e)=> (e['cal'] as num).toDouble()).reduce((a,b)=>a+b)/daysWith.length);
    final tP   = _tP ?? (tCal * 0.30 / 4);
    final tC   = _tC ?? (tCal * 0.40 / 4);
    final tF   = _tF ?? (tCal * 0.30 / 9);
    int okCal=0, okP=0; double sum=0; int n=0;
    for (final d in _series) {
      final cal = (d['cal'] as num).toDouble();
      final p   = (d['p'] as num).toDouble();
      final c   = (d['c'] as num).toDouble();
      final f   = (d['f'] as num).toDouble();
      if (cal<=0 && p<=0 && c<=0 && f<=0) continue;
      double s=0;
      if (tCal>0 && (cal>=tCal*0.9 && cal<=tCal*1.1)) { s+=40; okCal++; }
      if (p>=tP*0.9) { s+=25; okP++; }
      if (tC>0 && (c>=tC*0.8 && c<=tC*1.2)) s+=15;
      if (tF>0 && (f>=tF*0.8 && f<=tF*1.2)) s+=15;
      if (cal>0) s+=5;
      sum+=s; n++;
    }
    setState(() { _adherence = n==0?0:(sum/n).clamp(0,100); _okCalDays=okCal; _okPDays=okP; });
  }

  Widget _adherenceHero(ColorScheme cs, TextTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(width: 90, height: 90, child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 90, height: 90, child: CircularProgressIndicator(
              value: _adherence/100.0, strokeWidth: 10, backgroundColor: cs.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${_adherence.toStringAsFixed(0)}%', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const Text('التزام', style: TextStyle(fontSize: 12)),
            ]),
          ])),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children:[const Text('🔥', style: TextStyle(fontSize: 18)), const SizedBox(width:6), Text('ضمن السعرات: $_okCalDays يوم', style: t.bodyMedium)]),
            const SizedBox(height: 6),
            Row(children:[const Text('🥩', style: TextStyle(fontSize: 18)), const SizedBox(width:6), Text('البروتين مُتحقق: $_okPDays يوم', style: t.bodyMedium)]),
            const SizedBox(height: 8),
            Text('حسّن الالتزام برفع البروتين وتثبيت السعرات حول الهدف اليومي.', style: t.bodySmall?.copyWith(color: cs.onSurface.withOpacity(.7))),
          ])),
        ],
      ),
    );
  }

  // رسم موحّد (سعرات + ماكروز ×تحويل سعرات) مع إمكانية إظهار/إخفاء السلاسل
  Widget _combinedMacroChart(List<double> kcal, List<double> p, List<double> c, List<double> f) {
    final protKcal = p.map((e)=> e*4).toList();
    final carbKcal = c.map((e)=> e*4).toList();
    final fatKcal  = f.map((e)=> e*9).toList();
    final n = _series.length;
    List<FlSpot> spots(List<double> arr)=> arr.asMap().entries.map((e)=> FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = [...kcal, ...protKcal, ...carbKcal, ...fatKcal].fold<double>(0, (m,v)=> v>m?v:m) * 1.15;
    final cs = Theme.of(context).colorScheme; final t = Theme.of(context).textTheme;
    Widget legend(Color c, String label)=> Container(
      padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
      decoration: BoxDecoration(color: cs.surface, border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width:10, height:10, decoration: BoxDecoration(color:c, shape: BoxShape.circle)), const SizedBox(width:6), Text(label, style: t.labelMedium)]),
    );
    return Container(
      height: 260,
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: Offset(0,4))]),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الرسم اليومي للماكروز والسعرات', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Expanded(child: LineChart(LineChartData(
            minY: 0, maxY: maxY <= 0 ? 1 : maxY,
            lineTouchData: LineTouchData(enabled: true),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, interval: math.max(1, n~/6).toDouble(),
                getTitlesWidget: (v,meta){ final i=v.toInt(); if(i<0||i>=n) return const SizedBox.shrink(); final d=_series[i]['date'] as String; return Text(d.substring(5), style: const TextStyle(fontSize: 10)); },
              )),
            ),
            gridData: FlGridData(show: true, horizontalInterval: (maxY/4).clamp(1, 999999)),
            borderData: FlBorderData(show: true, border: const Border(top: BorderSide.none, right: BorderSide.none, left: BorderSide(width:.8), bottom: BorderSide(width:.8))),
            lineBarsData: [
              if (_showCal) LineChartBarData(spots: spots(kcal), isCurved: true, barWidth: 2.5, color: _calColor, dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_calColor.withOpacity(.25), _calColor.withOpacity(0)]))),
              if (_showP)   LineChartBarData(spots: spots(protKcal), isCurved: true, barWidth: 2.3, color: _pColor,   dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_pColor.withOpacity(.18), _pColor.withOpacity(0)]))),
              if (_showC)   LineChartBarData(spots: spots(carbKcal), isCurved: true, barWidth: 2.3, color: _cColor,   dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_cColor.withOpacity(.18), _cColor.withOpacity(0)]))),
              if (_showF)   LineChartBarData(spots: spots(fatKcal),  isCurved: true, barWidth: 2.3, color: _fColor,   dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_fColor.withOpacity(.18), _fColor.withOpacity(0)]))),
            ],
          ))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            legend(_calColor, '🔥 السعرات (سعرة)'),
            legend(_pColor, '🥩 البروتين'),
            legend(_cColor, '🍞 الكارب'),
            legend(_fColor, '🧈 الدهون'),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilterChip(label: const Text('🔥 السعرات'), selected: _showCal, onSelected: (v)=> setState(()=> _showCal=v)),
            FilterChip(label: const Text('🥩 البروتين'), selected: _showP, onSelected: (v)=> setState(()=> _showP=v)),
            FilterChip(label: const Text('🍞 الكارب'), selected: _showC, onSelected: (v)=> setState(()=> _showC=v)),
            FilterChip(label: const Text('🧈 الدهون'), selected: _showF, onSelected: (v)=> setState(()=> _showF=v)),
          ]),
        ],
      ),
    ),
  );
  }

  void _computeWeeklyHeatmap() {
    // نستخدم آخر 28 يوماً (4 أسابيع) بعدد أيام المدى المختار إن كان أكبر
    final n = _series.length;
    final take = n < 28 ? n : 28;
    final days = _series.sublist(n - take, n);
    final tCal = _tCal ?? (days.where((e)=> e['cal']>0).isEmpty ? 2000.0 : days.map((e)=> (e['cal'] as num).toDouble()).reduce((a,b)=>a+b)/days.length);
    _heat = days.map((d){
      final cal = (d['cal'] as num).toDouble();
      final p = (d['p'] as num).toDouble();
      final c = (d['c'] as num).toDouble();
      final f = (d['f'] as num).toDouble();
      // درجة الالتزام يوميًا بناء على السعرات ±10%
      double score = 0;
      if (tCal>0 && cal>0) {
        final dev = (cal - tCal).abs()/tCal;
        score = (1.0 - dev).clamp(0.0, 1.0);
        if (dev <= 0.10) score = 1.0; // ضمن الهدف
      }
      return {'date': d['date'], 'score': score, 'cal': cal, 'p': p, 'c': c, 'f': f};
    }).toList();
  }

  void _computeBestWorst() {
    if (_series.isEmpty) { _bestDay=null; _worstDay=null; return; }
    final tCal = _tCal ?? 2000.0;
    double dayScore(Map<String,dynamic> d){
      final cal = (d['cal'] as num).toDouble();
      final p = (d['p'] as num).toDouble();
      final c = (d['c'] as num).toDouble();
      final f = (d['f'] as num).toDouble();
      double s=0;
      if (tCal>0 && cal>0 && (cal>=tCal*0.9 && cal<=tCal*1.1)) s+=40;
      // بروتين أقوى وزنًا
      final tP = _tP ?? (tCal*0.30/4);
      if (tP>0 && p>=tP*0.9) s+=35;
      final tC = _tC ?? (tCal*0.40/4);
      if (tC>0 && (c>=tC*0.8 && c<=tC*1.2)) s+=15;
      final tF = _tF ?? (tCal*0.30/9);
      if (tF>0 && (f>=tF*0.8 && f<=tF*1.2)) s+=10;
      return s;
    }
    Map<String,dynamic>? best; double bScore=-1;
    Map<String,dynamic>? worst; double wScore=1e9;
    for (final d in _series){
      final sc = dayScore(d.cast<String,dynamic>());
      if (sc> bScore){ bScore=sc; best=d; }
      if (sc< wScore){ wScore=sc; worst=d; }
    }
    _bestDay = best?.cast<String,dynamic>();
    _worstDay = worst?.cast<String,dynamic>();
  }

  Future<void> _loadMicroEnabled(SharedPreferences prefs, String? email) async {
    final raw = prefs.getString('microgoals_enabled_${email ?? 'unknown'}');
    if (raw != null) {
      try {
        _microEnabled = Set<String>.from((jsonDecode(raw) as List).map((e)=> e.toString()));
      } catch (_) {}
    } else {
      _microEnabled = {'cal_ok','protein_ok','logging_ok'}; // افتراضيًا فعّالة
    }
  }

  Future<void> _saveMicroEnabled(SharedPreferences prefs, String? email) async {
    await prefs.setString('microgoals_enabled_${email ?? 'unknown'}', jsonEncode(_microEnabled.toList()));
  }

  void _computeMicroProgress() {
    final n = _series.length;
    if (n==0) { _microProgress = {}; return; }
    final tCal = _tCal ?? 2000.0;
    final tP   = _tP ?? (tCal*0.30/4);
    int okCal=0, okP=0, okLog=0;
    for (final d in _series) {
      final cal = (d['cal'] as num).toDouble();
      final p   = (d['p'] as num).toDouble();
      if (cal>0) okLog++;
      if (tCal>0 && cal>=tCal*0.9 && cal<=tCal*1.1) okCal++;
      if (tP>0 && p>=tP*0.9) okP++;
    }
    _microProgress = {
      'cal_ok': okCal / n,
      'protein_ok': okP / n,
      'logging_ok': okLog / n,
    };
  }

  Widget _weeklyHeatmap(ColorScheme cs, TextTheme t) {
    // grid 4 أسابيع × 7 أيام
    final cols = 4; final rows = 7;
    final items = _heat; // آخر 28 يوم
    Color colorFor(double s) {
      // 0→سطح، 1→primary
      return Color.lerp(cs.surfaceVariant, cs.primary, s.clamp(0,1))!;
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('التزام السعرات آخر ٤ أسابيع', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // أسماء الأيام
          Column(
            children: const [
              SizedBox(height: 20, width: 20),
              Text('س', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ح', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ن', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ث', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ر', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('خ', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ج', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 8),
          for (int c=0;c<cols;c++)
            Column(children: [
              Text('الأسبوع ${c+1}', style: t.labelSmall),
              const SizedBox(height: 4),
              for (int r=0;r<rows;r++)
                Builder(builder: (_) {
                  final idx = c*rows + r;
                  if (idx >= items.length) return const SizedBox(height: 20, width: 20);
                  final s = items[idx];
                  final val = (s['score'] as num).toDouble();
                  final d   = s['date'] as String;
                  return Tooltip(
                    message: '$d\n${val>=1? 'ضمن الهدف' : 'انحراف ${(100 - (val*100)).toStringAsFixed(0)}%'}',
                    child: Container(
                      width: 20, height: 20,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: colorFor(val),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
            ]),
        ]),
      ]),
    );
  }

  Widget _bestWorstCards(ColorScheme cs, TextTheme t) {
    Widget card(String title, Map<String,dynamic>? d, Color color, IconData icon) {
      return Expanded(child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))]),
        padding: const EdgeInsets.all(12),
        child: d==null? const Text('لا توجد بيانات'): Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 6),
          Text('${d['date']}', style: t.labelMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            Chip(label: Text('سعرات: ${(d['cal'] as num).toString()}')),
            Chip(label: Text('بروتين: ${(d['p'] as num).toString()}غ')),
            Chip(label: Text('كارب: ${(d['c'] as num).toString()}غ')),
            Chip(label: Text('دهون: ${(d['f'] as num).toString()}غ')),
          ]),
        ]),
      ));
    }
    return Row(children: [
      card('أفضل يوم', _bestDay, Colors.green, Icons.trending_up_rounded),
      const SizedBox(width: 12),
      card('أقل التزام', _worstDay, Colors.redAccent, Icons.trending_down_rounded),
    ]);
  }

  
Widget _microGoals(ColorScheme cs, TextTheme t) {
    Widget goalCard(String id, String label, String helper) {
      final enabled = _microEnabled.contains(id);
      final prog = _microProgress[id] ?? 0;
      return Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))]),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Switch(
              value: enabled,
              onChanged: (v) async {
                setState(() { if (v) _microEnabled.add(id); else _microEnabled.remove(id); });
                final prefs = _prefsRef ?? await SharedPreferences.getInstance();
                final email = _emailRef ?? await _currentEmail() ?? 'unknown_user';
                await _saveMicroEnabled(prefs, email);
                _computeMicroProgress();
              },
            ),
            const SizedBox(width: 6),
            Text(label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          LinearProgressIndicator(value: prog, minHeight: 8, backgroundColor: cs.surfaceVariant),
          const SizedBox(height: 6),
          Text(helper, style: t.bodySmall?.copyWith(color: cs.onSurface.withOpacity(.7))),
        ]),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final spacing = 12.0;
      int cols = 1;
      if (w >= 900) cols = 3;
      else if (w >= 560) cols = 2;
      final itemW = (w - spacing * (cols - 1)) / cols;

      List<Widget> tiles = [
        SizedBox(width: itemW, child: goalCard('cal_ok', 'ضمن السعرات ±10%', 'كم نسبة الأيام ضمن هدف السعرات خلال المدة؟')),
        SizedBox(width: itemW, child: goalCard('protein_ok', 'البروتين ≥ 90% من الهدف', 'نسبة الأيام التي حققت حد البروتين الأدنى.')),
        SizedBox(width: itemW, child: goalCard('logging_ok', 'تسجيل يومي مستمر', 'كم يوم تم تسجيل وجبات فيه خلال المدة؟')),
        SizedBox(width: itemW, child: Container(
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))]),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('هدف مخصص', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('أضف هدفًا مخصصًا لاحقًا'),
          ]),
        )),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('أهداف مصغّرة (تتبع المدة المختارة)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: spacing, runSpacing: spacing, children: tiles),
        ],
      );
    });
  }


double _maxOf(List<double> vals) => vals.isEmpty ? 0 : vals.reduce((a,b)=>a>b?a:b);

  List<String> _tipsForGoal(String goal, Map<String,double> avg) {
    final out = <String>[];
    final cal = avg['cal']!, p = avg['p']!, c = avg['c']!, f = avg['f']!;
    // نسب تقريبية من السعرات
    final calFromP = p*4, calFromC = c*4, calFromF = f*9;
    final pc = cal==0?0: (calFromP/cal);
    final cc = cal==0?0: (calFromC/cal);
    final fc = cal==0?0: (calFromF/cal);

    switch (goal) {
      case 'بناء العضلات':
      case 'بناء عضلات':
        if (pc < 0.25) out.add('هدفك بناء عضلات: ارفع البروتين (جرّب إضافة وجبة/سناك بروتيني).');
        if (fc > 0.35) out.add('هدفك بناء عضلات: الدهون مرتفعة؛ خفّف المقليات والزيوت ووجّه السعرات للبروتين/الكارب حول التمرين.');
        if (cc < 0.35) out.add('هدفك بناء عضلات: الكارب منخفض؛ أضف نشويات معقّدة (شوفان/أرز/بطاطس) خاصة قبل وبعد التمرين.');
        out.add('حافظ على فائض سعرات بسيط ومنتظم (حوالي +10٪ من احتياجك).');
        break;

      case 'إنقاص الوزن':
      case 'خفض الدهون':
        if (pc < 0.30) out.add('إنقاص وزن: ارفع البروتين للحفاظ على الكتلة العضلية.');
        if (cc > 0.45) out.add('إنقاص وزن: قلّل السكريات/الكارب العالي المؤشر وأضف أليافًا وخضار.');
        if (fc > 0.35) out.add('إنقاص وزن: راقب الدهون (أوزن الزيت/المكسرات) واختر الطبخ بدون قلي.');
        out.add('استهدف عجزًا بسيطًا (‑15٪ تقريبًا) مع مشي يومي.');
        break;

      case 'زيادة الوزن':
        if (pc < 0.25) out.add('زيادة وزن: احرص على بروتين كافٍ بكل وجبة.');
        if (cc < 0.45) out.add('زيادة وزن: زِد الكارب المعقّد (أرز/خبز كامل/مكرونة).');
        out.add('قسّم السعرات على 3–5 وجبات مع سناكات عالية الطاقة.');
        break;

      case 'الصيام المتقطع':
        if (pc < 0.30) out.add('الصيام: البروتين منخفض داخل نافذة الأكل — عزّزه في الوجبتين الرئيسيتين.');
        if (cc > 0.50) out.add('الصيام: الكارب مرتفع — اختر نشويات منخفضة المؤشر.');
        out.add('التزم بمواعيد النافذة واشرب ماءً كافيًا خلال اليوم.');
        break;

      default:
        out.add('استمر على توزيع متزن وراقب جودة الاختيارات.');
    }

    // نصائح عامة إضافية
    if (cal == 0) out.add('لا توجد بيانات كافية — احرص على تسجيل وجباتك.');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;

    List<double> kcal = _series.map((e)=> (e['cal'] as num).toDouble()).toList();
    List<double> prot = _series.map((e)=> (e['p'] as num).toDouble()).toList();
    List<double> carb = _series.map((e)=> (e['c'] as num).toDouble()).toList();
    List<double> fat  = _series.map((e)=> (e['f'] as num).toDouble()).toList();

    final maxCal = _maxOf(kcal);
    final maxP   = _maxOf(prot);
    final maxC   = _maxOf(carb);
    final maxF   = _maxOf(fat);

    pw.Widget? _; // لا شيء — فقط لإرضاء التحذير إن وُجد 😄

    Widget _rangeChip(String label, int days) {
      final sel = _days == days;
      return ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) { setState(() { _days = days; }); _load(); },
      );
    }

    
    Widget _periodInsightCard(List<double> kcal, List<double> prot, List<double> carb, List<double> fat) {
      double avg(List<double> v) => v.isEmpty ? 0.0 : v.reduce((a, b) => a + b) / v.length;
      double sum(List<double> v) => v.isEmpty ? 0.0 : v.reduce((a, b) => a + b);
      String fmt(double v, {bool intLike = false}) => intLike ? v.round().toString() : v.toStringAsFixed(v >= 100 ? 0 : 1);

      final t = Theme.of(context).textTheme;
      final cs = Theme.of(context).colorScheme;
      final days = kcal.length;
      final avgCal = avg(kcal);
      final avgP = avg(prot);
      final avgC = avg(carb);
      final avgF = avg(fat);
      final proteinShare = (sum(prot) + sum(carb) + sum(fat)) > 0
          ? (sum(prot) / (sum(prot) + sum(carb) + sum(fat)) * 100).round()
          : 0;

      String trendText() {
        if (kcal.length < 4) return 'أضف أيام أكثر حتى تظهر لك قراءة أدق.';
        final half = (kcal.length / 2).floor();
        final oldAvg = avg(kcal.take(half).toList());
        final newAvg = avg(kcal.skip(half).toList());
        final diff = newAvg - oldAvg;
        if (diff.abs() < 80) return 'سعراتك مستقرة تقريبًا خلال الفترة.';
        return diff > 0
            ? 'سعراتك ارتفعت آخر الفترة بمتوسط ${fmt(diff, intLike: true)} سعرة.'
            : 'سعراتك نزلت آخر الفترة بمتوسط ${fmt(diff.abs(), intLike: true)} سعرة.';
      }

      Widget line({required IconData icon, required String title, required String value}) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                value,
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w900, color: cs.primary),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Text('قراءة مفيدة للفترة', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              trendText(),
              style: t.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(.82), height: 1.35),
            ),
            const SizedBox(height: 10),
            line(
              icon: Icons.local_fire_department_rounded,
              title: 'متوسط السعرات اليومي',
              value: days == 0 ? '—' : '${fmt(avgCal, intLike: true)} سعرة',
            ),
            line(
              icon: Icons.fitness_center_rounded,
              title: 'متوسط البروتين',
              value: days == 0 ? '—' : '${fmt(avgP)} غ',
            ),
            line(
              icon: Icons.pie_chart_rounded,
              title: 'نسبة البروتين من الماكروز',
              value: proteinShare == 0 ? '—' : '$proteinShare%',
            ),
            line(
              icon: Icons.restaurant_menu_rounded,
              title: 'متوسط الكارب / الدهون',
              value: days == 0 ? '—' : '${fmt(avgC)}غ / ${fmt(avgF)}غ',
            ),
          ],
        ),
      );
    }


Widget _singleChart(String title, List<double> values, Color color) {
      final spots = values.asMap().entries.map((e)=> FlSpot(e.key.toDouble(), e.value)).toList();
      final maxY = (values.isEmpty ? 1 : _maxOf(values)) * 1.1;
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Expanded(
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY <= 0 ? 1 : maxY,
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: math.max(1, values.length ~/ 6).toDouble(),
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= _series.length) return const SizedBox.shrink();
                            final d = _series[i]['date'] as String;
                            return Text(d.substring(5), style: const TextStyle(fontSize: 10));
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        color: color,
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withOpacity(.10),
                        ),
                        spots: spots,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // متوسطات للفترة المختارة
    Map<String,double> avg = {
      'cal': (kcal.isEmpty?0: kcal.reduce((a,b)=>a+b)/kcal.length),
      'p'  : (prot.isEmpty?0: prot.reduce((a,b)=>a+b)/prot.length),
      'c'  : (carb.isEmpty?0: carb.reduce((a,b)=>a+b)/carb.length),
      'f'  : (fat.isEmpty?0:  fat.reduce((a,b)=>a+b)/fat.length),
    };
    final tips = _tipsForGoal(_goal ?? 'عام', avg);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // اختيار المدة
        Row(
          children: [
            Text('تتبّع الماكروز', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: PopupMenuButton<int>(
                tooltip: 'تصفية المدة',
                icon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(Icons.filter_alt_rounded),
                ),
                onSelected: (v) { setState(() { _days = v; }); _load(); },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 7,  child: Text('آخر ٧ أيام')),
                  PopupMenuItem(value: 14, child: Text('آخر ١٤ يوم')),
                  PopupMenuItem(value: 30, child: Text('آخر شهر')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _adherenceHero(cs, t),
        const SizedBox(height: 12),
        _combinedMacroChart(kcal, prot, carb, fat),
        const SizedBox(height: 12),
        _weeklyHeatmap(cs, t),
        const SizedBox(height: 12),
        _bestWorstCards(cs, t),
        const SizedBox(height: 12),
        _periodInsightCard(kcal, prot, carb, fat),
        const SizedBox(height: 12),
        _microGoals(cs, t),
        const SizedBox(height: 12),
        _singleChart('السعرات', kcal, _calColor),
        const SizedBox(height: 12),
        _singleChart('البروتين (غم)', prot, _pColor),
        const SizedBox(height: 12),
        _singleChart('الكارب (غم)', carb, _cColor),
        const SizedBox(height: 12),
        _singleChart('الدهون (غم)', fat, _fColor),
        const SizedBox(height: 16),

        // نصائح ذكية حسب الهدف
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نصائح حسب هدفك${_goal!=null ? ' — $_goal' : ''}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...tips.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s, style: t.bodyMedium)),
                  ],
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }
}


//// ========= Weight Tab =========
class _WeightTab extends StatefulWidget {
  const _WeightTab();
  @override
  State<_WeightTab> createState() => _WeightTabState();
}

class _WeightTabState extends State<_WeightTab> with WidgetsBindingObserver {
  List<_WeightPoint> points = [];
  double? currentWeight;
  double? targetWeight;

  StreamSubscription<void>? _weightSub; // ✅ اشتراك البث اللحظي
  bool _cloudWeightsRestored = false;
  Map<String, double> _cachedRemoteWeights = <String, double>{};

  Timer? _tick;
  bool _loadingWeights = false;
  bool _weightsReloadPending = false;

  // اسم المستخدم للعرض + التقرير
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWeights();
    _weightSub = WeightLiveBus.stream.listen((_) => _loadWeights());
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _loadWeights());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weightSub?.cancel();
    _userNameSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadWeights();
    }
  }

  double? _numFrom(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value
          .trim()
          .replaceAll('٫', '.')
          .replaceAll('،', '.')
          .replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  double? _readKg(Map<dynamic, dynamic> data) {
    for (final key in const [
      'kg',
      'weight',
      'weightKg',
      'currentWeight',
      'current_weight',
      'value',
    ]) {
      final v = _numFrom(data[key]);
      if (v != null && v > 0) return v;
    }
    return null;
  }

  String? _readDate(Map<dynamic, dynamic> data) {
    for (final key in const [
      'date',
      'day',
      'ymd',
      'createdAt',
      'updatedAt',
      'timestamp',
      'time',
      't',
    ]) {
      final d = _normalizeYmd(data[key]);
      if (d != null) return d;
    }
    return null;
  }

  Future<void> _upsertTodayWeightLog(
    SharedPreferences prefs,
    String email,
    double kg,
  ) async {
    final today = _todayKey();
    final key = 'weight_log_$email';
    final list = <Map<String, dynamic>>[];

    final raw = prefs.getString(key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final m = Map<String, dynamic>.from(item);
              final d = _readDate(m);
              final w = _readKg(m);
              if (d != null && w != null && w > 0) {
                list.add({'date': d, 'kg': w});
              }
            }
          }
        }
      } catch (_) {}
    }

    final index = list.indexWhere((e) => _normalizeYmd(e['date']) == today);
    if (index >= 0) {
      list[index] = {'date': today, 'kg': kg};
    } else {
      list.add({'date': today, 'kg': kg});
    }

    list.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    await prefs.setString(key, jsonEncode(list));
  }

  Future<Map<String, double>> _readRemoteWeightsSafely() async {
    // تبويب الوزن صار يعتمد على السجل المحلي فقط حتى لا يعلق عند فتح صفحة التتبع.
    _cloudWeightsRestored = true;
    _cachedRemoteWeights = <String, double>{};
    return _cachedRemoteWeights;
  }


  Future<void> _loadWeights() async {
    if (_loadingWeights) {
      _weightsReloadPending = true;
      return;
    }
    _loadingWeights = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await _currentEmail() ?? 'unknown_user';
      final aliases = await _currentProfileAliases();
      final profileKey = _latestProfileAlias(prefs, aliases);

      final loadedCurrentWeight = _prefDoubleAnyAlias(
        prefs,
        const ['current_weight_', 'weight_', 'user_weight_', 'weightKg_', 'currentWeight_'],
        aliases,
        preferred: profileKey,
      );

      final loadedTargetWeight = _prefDoubleAnyAlias(
        prefs,
        const ['goal_target_', 'targetWeight_', 'target_weight_', 'goalWeight_'],
        aliases,
        preferred: profileKey,
      );

      final remoteWeights = await _readRemoteWeightsSafely();

      // نجمع كل القراءات من المحلي والسحابة، ثم نحدّث قراءة اليوم دائمًا من صفحة بياناتي.
      final map = <String, double>{};

      void addPoint(String? ymd, double? kg, {bool override = false}) {
        if (ymd == null || kg == null || kg <= 0) return;
        if (override || !map.containsKey(ymd)) {
          map[ymd] = kg;
        }
      }

      // 1) الحديث: weight_log_$alias => List<Map>{date, kg}
      for (final alias in _orderedAliases(aliases, profileKey)) {
        final raw = prefs.getString('weight_log_$alias');
        if (raw != null && raw.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              for (final item in decoded) {
                if (item is Map) {
                  addPoint(_readDate(item), _readKg(item));
                }
              }
            }
          } catch (_) {}
        }

        // 2) القديم: weightHistory_$alias => List<String(json)> {"date","weight"}
        final histList = _safePrefStringList(prefs, 'weightHistory_$alias');
        if (histList.isNotEmpty) {
          for (final s in histList) {
            try {
              final decoded = jsonDecode(s);
              if (decoded is Map) {
                addPoint(_readDate(decoded), _readKg(decoded));
              }
            } catch (_) {}
          }
        }
      }

      final legacyHistory = _safePrefStringList(prefs, 'weightHistory');
      if (legacyHistory.isNotEmpty) {
        for (final s in legacyHistory) {
          try {
            final decoded = jsonDecode(s);
            if (decoded is Map) {
              addPoint(_readDate(decoded), _readKg(decoded));
            }
          } catch (_) {}
        }
      }

      // 3) السحابة
      for (final e in remoteWeights.entries) {
        addPoint(_normalizeYmd(e.key), e.value);
      }

      // 4) الأهم: وزن صفحة بياناتي يعتبر قراءة اليوم دائمًا، ويغطي أي قيمة قديمة لنفس اليوم.
      if (loadedCurrentWeight != null && loadedCurrentWeight > 0) {
        final today = _todayKey();
        addPoint(today, loadedCurrentWeight, override: true);
        for (final alias in _orderedAliases(aliases, profileKey)) {
          await _upsertTodayWeightLog(prefs, alias, loadedCurrentWeight);
        }
        if (!aliases.contains(email)) {
          await _upsertTodayWeightLog(prefs, email, loadedCurrentWeight);
        }
      }

      double? finalCurrentWeight = loadedCurrentWeight;
      if (finalCurrentWeight == null && map.isNotEmpty) {
        final sortedDates = map.keys.toList()..sort();
        finalCurrentWeight = map[sortedDates.last];
        if (finalCurrentWeight != null && finalCurrentWeight > 0) {
          await prefs.setDouble('weight_$email', finalCurrentWeight);
          await prefs.setDouble('current_weight_$email', finalCurrentWeight);
        }
      }

      final pts = <_WeightPoint>[];
      for (final e in map.entries) {
        final dt = DateTime.tryParse(e.key);
        if (dt == null || e.value <= 0) continue;
        pts.add(_WeightPoint(DateTime(dt.year, dt.month, dt.day), e.value));
      }
      pts.sort((a, b) => a.t.compareTo(b.t));

      if (!mounted) return;
      setState(() {
        currentWeight = finalCurrentWeight;
        targetWeight = loadedTargetWeight;
        points = pts;
      });
    } finally {
      _loadingWeights = false;
      if (_weightsReloadPending) {
        _weightsReloadPending = false;
        unawaited(_loadWeights());
      }
    }
  }

  double _weeklyAvg() {
    final now = DateTime.now();
    final last7 = points
        .where((p) => now.difference(p.t).inDays <= 7)
        .map((e) => e.kg)
        .toList();
    if (last7.isEmpty) return 0;
    return last7.reduce((a, b) => a + b) / last7.length;
  }

  Widget _metricCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(.78),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(.95),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWeightChart(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return Container(
        height: 260,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withOpacity(.22)),
        ),
        child: Text(
          'لا توجد قراءات وزن بعد',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface.withOpacity(.65),
          ),
        ),
      );
    }

    // واجهة التطبيق تعرض آخر 4 قراءات فقط حتى يبقى الرسم ثابتًا وغير قابل للتمرير.
    final chartPoints = points.length > 4 ? points.sublist(points.length - 4) : points;
    final n = chartPoints.length;
    final spots = <FlSpot>[
      for (int i = 0; i < n; i++) FlSpot(i.toDouble(), chartPoints[i].kg),
    ];
    final ys = chartPoints.map((e) => e.kg).toList();
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final pad = (maxY - minY).abs() < 0.5 ? 1.0 : (maxY - minY) * 0.22;
    final avgY = ys.reduce((a, b) => a + b) / ys.length;
    final yInterval = (((maxY - minY).abs() / 4).clamp(0.5, 5.0)).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'رسم آخر 4 قراءات',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                points.length > 4 ? 'آخر 4 من ${points.length}' : '${points.length} قراءة',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 270,
            width: double.infinity,
            child: LineChart(
              LineChartData(
                minX: n == 1 ? -0.5 : 0,
                maxX: n == 1 ? 0.5 : (n - 1).toDouble(),
                minY: minY - pad,
                maxY: maxY + pad,
                clipData: const FlClipData.all(),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) => touched.map((s) {
                      final i = s.x.round().clamp(0, n - 1);
                      final dt = chartPoints[i].t;
                      return LineTooltipItem(
                        '${chartPoints[i].kg.toStringAsFixed(1)} كجم\n${DateFormat('yyyy/MM/dd').format(dt)}',
                        TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= n || (value - i).abs() > .05) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                chartPoints[i].kg.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: cs.primary,
                                ),
                              ),
                              Text(
                                DateFormat('MM/dd').format(chartPoints[i].t),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurface.withOpacity(.58),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: yInterval,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withOpacity(.58),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: 1,
                  horizontalInterval: yInterval,
                  getDrawingVerticalLine: (value) => FlLine(
                    color: cs.outlineVariant.withOpacity(.18),
                    strokeWidth: 1,
                  ),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: cs.outlineVariant.withOpacity(.28),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: avgY,
                      color: cs.primary.withOpacity(.34),
                      strokeWidth: 1.4,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 4, bottom: 2),
                        style: TextStyle(fontSize: 10, color: cs.primary),
                        labelResolver: (_) => 'متوسط',
                      ),
                    ),
                    if (targetWeight != null && targetWeight! > 0)
                      HorizontalLine(
                        y: targetWeight!,
                        color: cs.secondary.withOpacity(.45),
                        strokeWidth: 1.5,
                        dashArray: [2, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 4, bottom: 2),
                          style: TextStyle(fontSize: 10, color: cs.secondary),
                          labelResolver: (_) => 'هدف',
                        ),
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: n > 2,
                    curveSmoothness: .28,
                    barWidth: 3.2,
                    gradient: LinearGradient(colors: [
                      cs.primary,
                      cs.secondary,
                    ]),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withOpacity(.18),
                          cs.secondary.withOpacity(.04),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4.7,
                        color: cs.primary,
                        strokeWidth: 2.2,
                        strokeColor: cs.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (points.length > 4) ...[
            const SizedBox(height: 8),
            Text(
              'يعرض التطبيق آخر 4 قراءات فقط، بينما يتم تضمين كامل سجل الوزن في ملف PDF.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(.60),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadingsList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (points.isEmpty) return const SizedBox.shrink();

    final latest = points.length > 4 ? points.sublist(points.length - 4) : points;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'آخر القراءات',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'يتم عرض آخر 4 قراءات فقط هنا. كامل السجل محفوظ في تقرير PDF.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(.60),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...latest.reversed.map((p) {
            final isLatest = p == points.last;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isLatest
                      ? cs.primary.withOpacity(.08)
                      : cs.surfaceVariant.withOpacity(.28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isLatest
                        ? cs.primary.withOpacity(.20)
                        : cs.outlineVariant.withOpacity(.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.monitor_weight_outlined,
                      size: 19,
                      color: isLatest ? cs.primary : cs.onSurface.withOpacity(.55),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        DateFormat('yyyy/MM/dd').format(p.t),
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(.70),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${p.kg.toStringAsFixed(1)} كجم',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avg = _weeklyAvg();
    final cs = Theme.of(context).colorScheme;

    final double? delta = points.length >= 2
        ? (points.last.kg - points[points.length - 2].kg)
        : null;
    final deltaText = delta == null
        ? null
        : 'التغيّر: ${(delta >= 0 ? '+' : '')}${delta.toStringAsFixed(1)} كجم';

    return RefreshIndicator(
      onRefresh: _loadWeights,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  cs.primary.withOpacity(.10),
                  cs.secondary.withOpacity(.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withOpacity(.10)),
            ),
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مصدر بيانات الوزن',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'يعتمد تغيّر الوزن بالكامل على صفحة بياناتي، ويمكنك تعديل وزنك من هناك. عند التعديل يتم تحديث الرسم البياني وإضافة قراءة بتاريخ اليوم تلقائيًا.',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(.75),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (currentWeight != null || avg > 0 || (targetWeight != null && targetWeight! > 0)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard(
                  context: context,
                  icon: Icons.monitor_weight_outlined,
                  title: 'الحالي',
                  value: currentWeight == null
                      ? '--'
                      : '${currentWeight!.toStringAsFixed(1)} كجم',
                  subtitle: deltaText,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                _metricCard(
                  context: context,
                  icon: Icons.insights_outlined,
                  title: 'متوسط 7 أيام',
                  value: avg <= 0 ? '--' : '${avg.toStringAsFixed(1)} كجم',
                  color: cs.secondary,
                ),
                if (targetWeight != null && targetWeight! > 0) ...[
                  const SizedBox(width: 10),
                  _metricCard(
                    context: context,
                    icon: Icons.flag_outlined,
                    title: 'الهدف',
                    value: '${targetWeight!.toStringAsFixed(1)} كجم',
                    color: cs.tertiary,
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),
          _buildWeightChart(context),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildReadingsList(context),
          ],
        ],
      ),
    );
  }
}

class _WeightPoint {
  final DateTime t;
  final double kg;
  _WeightPoint(this.t, this.kg);
}

double? _reportWeightNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(
      value.trim().replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.'),
    );
  }
  return null;
}

double? _reportReadKg(Map<dynamic, dynamic> data) {
  for (final key in const [
    'kg',
    'weight',
    'weightKg',
    'currentWeight',
    'current_weight',
    'value',
  ]) {
    final v = _reportWeightNum(data[key]);
    if (v != null && v > 0) return v;
  }
  return null;
}

String? _reportReadDate(Map<dynamic, dynamic> data) {
  for (final key in const [
    'date',
    'day',
    'ymd',
    'createdAt',
    'updatedAt',
    'timestamp',
    'time',
    't',
  ]) {
    final d = _normalizeYmd(data[key]);
    if (d != null) return d;
  }
  return null;
}

Future<List<_WeightPoint>> _loadAllWeightPointsForReport() async {
  final prefs = await SharedPreferences.getInstance();
  final email = await _currentEmail() ?? 'unknown_user';
  final aliases = await _currentProfileAliases();
  final profileKey = _latestProfileAlias(prefs, aliases);
  final allKeys = <String>[
    email,
    ..._orderedAliases(aliases, profileKey),
  ].where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList();

  final map = <String, double>{};

  void add(String? ymd, double? kg, {bool override = false}) {
    if (ymd == null || kg == null || kg <= 0) return;
    if (override || !map.containsKey(ymd)) {
      map[ymd] = kg;
    }
  }

  for (final key in allKeys) {
    final raw = prefs.getString('weight_log_$key');
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              add(_reportReadDate(item), _reportReadKg(item));
            }
          }
        }
      } catch (_) {}
    }

    final historyList = _safePrefStringList(prefs, 'weightHistory_$key');
    if (historyList.isNotEmpty) {
      for (final item in historyList) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map) {
            add(_reportReadDate(decoded), _reportReadKg(decoded));
          }
        } catch (_) {}
      }
    }
  }

  final legacyHistory = _safePrefStringList(prefs, 'weightHistory');
  if (legacyHistory.isNotEmpty) {
    for (final item in legacyHistory) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          add(_reportReadDate(decoded), _reportReadKg(decoded));
        }
      } catch (_) {}
    }
  }

  // تقرير التتبع يعتمد على سجل الوزن المحلي فقط حتى يبقى سريعًا ومطابقًا لصفحة بياناتي.

  final current = _prefDoubleAnyAlias(
    prefs,
    const ['current_weight_', 'weight_', 'user_weight_', 'weightKg_', 'currentWeight_'],
    allKeys,
    preferred: profileKey,
  );
  if (current != null && current > 0) {
    add(_todayKey(), current, override: true);
  }

  final pts = <_WeightPoint>[];
  for (final e in map.entries) {
    final dt = DateTime.tryParse(e.key);
    if (dt == null || e.value <= 0) continue;
    pts.add(_WeightPoint(DateTime(dt.year, dt.month, dt.day), e.value));
  }
  pts.sort((a, b) => a.t.compareTo(b.t));
  return pts;
}

//// ========= Activity Tab =========
class _ActivityTab extends StatefulWidget {
  const _ActivityTab();
  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  // ⬅️ Health بنسخته الحديثة (بدل HealthFactory)
  final Health health = Health();

  int steps = 0;
  int burned = 0;

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _fetchFromHealth();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _loadSaved());
  }

  @override
  void dispose() {
    _userNameSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    final raw = prefs.getString('activity_${_todayKey()}_$email');
    if (raw != null) {
      final m = jsonDecode(raw);
      if (!mounted) return;
      final s = (m['steps'] as num?)?.toInt() ?? 0;
      final b = (m['burned'] as num?)?.toInt() ?? 0;
      setState(() {
        steps = s;
        burned = b;
      });
}
  }

  Future<void> _saveActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    await prefs.setString(
      'activity_${_todayKey()}_$email',
      jsonEncode({'steps': steps, 'burned': burned}),
    );
  }

  Future<void> _fetchFromHealth() async {
    try {
      final types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);

      await health.configure();

      final ok = await health.requestAuthorization(types);
      if (ok) {
        final data = await health.getHealthDataFromTypes(
          types: types,
          startTime: start,
          endTime: now,
        );

        int s = 0;
        double b = 0;
        for (final p in data) {
          if (p.type == HealthDataType.STEPS) s += (p.value as num).toInt();
          if (p.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
            b += (p.value as num).toDouble();
          }
        }
        if (!mounted) return;
        setState(() {
          steps = s;
          burned = b.toInt();
        });
await _saveActivity();
      }
    } catch (_) {
      // تجاهل لو غير مدعوم
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _stat('الخطوات', '$steps 👣', Icons.directions_walk, Colors.green),
        _stat('المحروق', '$burned 🔥', Icons.local_fire_department_outlined,
            Colors.red),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              minY: 0.0,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.black87,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final idx = group.x.toInt();
                    final value = rod.toY.toStringAsFixed(0);
                    return BarTooltipItem(
                      idx == 0 ? '$value خطوة' : '$value سعرة',
                      const TextStyle(color: Colors.white),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      switch (v.toInt()) {
                        case 0:
                          return const Text('خطوات');
                        case 1:
                          return const Text('محروق');
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(.2), dashArray: [4,4], strokeWidth: 1),),
              borderData: FlBorderData(show: false),
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: steps.toDouble(),
                      color: Colors.green.withOpacity(.9),
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: math.max(steps.toDouble(), burned.toDouble()),
                        color: Colors.green.withOpacity(.15),
                      ),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: burned.toDouble(),
                      color: Theme.of(context).colorScheme.primary.withOpacity(.9),
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: math.max(steps.toDouble(), burned.toDouble()),
                        color: Colors.red.withOpacity(.15),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _fetchFromHealth,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث من Health'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final sCtl = TextEditingController(text: steps.toString());
                final bCtl = TextEditingController(text: burned.toString());
                await showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('تعديل يدوي'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                            controller: sCtl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(hintText: 'الخطوات')),
TextField(
                            controller: bCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                hintText: 'السعرات المحروقة')),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء')),
                      ElevatedButton(
                        onPressed: () async {
                          steps = int.tryParse(sCtl.text) ?? steps;
                          burned = int.tryParse(bCtl.text) ?? burned;
                          await _saveActivity();
                          if (context.mounted) Navigator.pop(context);
                          setState(() {});
                        },
                        child: const Text('حفظ'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('تعديل يدوي'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    final onSurface = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withOpacity(.12)),
        color: color.withOpacity(0.06),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ==== Health Vitals Tab (Apple Health) ====
class _HealthVitalsTab extends StatefulWidget {
  const _HealthVitalsTab();

  @override
  State<_HealthVitalsTab> createState() => _HealthVitalsTabState();
}



class _HealthVitalsTabState extends State<_HealthVitalsTab> with WidgetsBindingObserver {
  final Health _health = Health();
  static const Duration _liveRefreshEvery = Duration(seconds: 12);

  Timer? _liveTimer;
  bool _healthEnabled = false;
  bool _alertsEnabled = true;
  bool _liveSyncing = false;
  bool _loading = false;
  bool _permissionDenied = false;
  String? _error;
  _HealthVitalsSnapshot _snapshot = const _HealthVitalsSnapshot();

  int _stepsGoal = 10000;
  int _heartHigh = 120;
  int _heartLow = 45;
  int _oxygenLow = 92;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapHealthTab();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_healthEnabled) {
        _refreshActivityVitalsOnly(silent: true);
        _startLiveActivityTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopLiveActivityTimer();
    }
  }

  Future<void> _bootstrapHealthTab() async {
    await _loadHealthSettings();
    await _loadCachedVitals();
    if (!mounted) return;
    if (_healthEnabled) {
      await _refreshActivityVitalsOnly(silent: true);
      _startLiveActivityTimer();
    }
  }

  String get _sourceName {
    if (Platform.isIOS || Platform.isMacOS) return 'Apple Health';
    if (Platform.isAndroid) return 'Health Connect';
    return 'Health';
  }

  String get _watchSourceText {
    if (Platform.isAndroid) {
      return 'ساعات Galaxy تعرض بياناتها عبر Health Connect عند توفر الصلاحيات على الجهاز.';
    }
    if (Platform.isIOS) {
      return 'Apple Watch تعرض بياناتها عبر Apple Health بعد منح الصلاحيات.';
    }
    return 'يعتمد الدعم على منصة الجهاز وصلاحيات الصحة المتاحة.';
  }

  Future<String> _healthPrefsKey(String suffix) async {
    final email = await _currentEmail() ?? 'unknown_user';
    return 'wazen_health_${suffix}_$email';
  }

  Future<void> _loadHealthSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabledKey = await _healthPrefsKey('enabled');
    final alertsKey = await _healthPrefsKey('alerts_enabled');
    final stepsGoalKey = await _healthPrefsKey('steps_goal');
    final heartHighKey = await _healthPrefsKey('heart_high');
    final heartLowKey = await _healthPrefsKey('heart_low');
    final oxygenLowKey = await _healthPrefsKey('oxygen_low');

    if (!mounted) return;
    setState(() {
      _healthEnabled = prefs.getBool(enabledKey) ?? false;
      _alertsEnabled = prefs.getBool(alertsKey) ??
          prefs.getBool(AppNotifications.kHealthAlertsEnabled) ??
          true;
      _stepsGoal = prefs.getInt(stepsGoalKey) ?? 10000;
      _heartHigh = prefs.getInt(heartHighKey) ?? 120;
      _heartLow = prefs.getInt(heartLowKey) ?? 45;
      _oxygenLow = prefs.getInt(oxygenLowKey) ?? 92;
    });
  }

  Future<void> _saveHealthSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _healthPrefsKey('enabled'), _healthEnabled);
    await prefs.setBool(await _healthPrefsKey('alerts_enabled'), _alertsEnabled);
    await prefs.setBool(AppNotifications.kHealthAlertsEnabled, _alertsEnabled);
    await prefs.setInt(await _healthPrefsKey('steps_goal'), _stepsGoal);
    await prefs.setInt(await _healthPrefsKey('heart_high'), _heartHigh);
    await prefs.setInt(await _healthPrefsKey('heart_low'), _heartLow);
    await prefs.setInt(await _healthPrefsKey('oxygen_low'), _oxygenLow);
  }

  void _startLiveActivityTimer() {
    if (!_healthEnabled) return;
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(_liveRefreshEvery, (_) {
      if (!mounted || !_healthEnabled) return;
      _refreshActivityVitalsOnly(silent: true);
    });
  }

  void _stopLiveActivityTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  Future<void> _setHealthEnabled(bool value) async {
    if (_loading) return;
    if (!value) {
      _stopLiveActivityTimer();
      setState(() {
        _healthEnabled = false;
        _liveSyncing = false;
        _permissionDenied = false;
        _error = null;
      });
      await _saveHealthSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إيقاف صحتي.')),
      );
      return;
    }

    setState(() {
      _healthEnabled = true;
      _error = null;
      _permissionDenied = false;
    });
    await _saveHealthSettings();
    await _refreshFromAppleHealth();
    if (!mounted) return;
    if (!_permissionDenied && _error == null) {
      _startLiveActivityTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تفعيل $_sourceName.')),
      );
    }
  }

  Future<void> _setAlertsEnabled(bool value) async {
    setState(() => _alertsEnabled = value);
    await _saveHealthSettings();
    if (value) {
      await AppNotifications.instance.requestPermission();
    } else {
      await AppNotifications.instance.cancelHealthAlerts();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث تنبيهات صحتي.')),
    );
  }

  Future<void> _loadCachedVitals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await _currentEmail() ?? 'unknown_user';
      final raw = prefs.getString('apple_health_vitals_$email') ??
          prefs.getString('wazen_health_vitals_$email');
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cached = _HealthVitalsSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      if (!mounted) return;
      setState(() => _snapshot = cached);
    } catch (_) {}
  }

  Future<void> _saveCachedVitals(_HealthVitalsSnapshot value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await _currentEmail() ?? 'unknown_user';
      final payload = jsonEncode(value.toJson());
      await prefs.setString('apple_health_vitals_$email', payload);
      await prefs.setString('wazen_health_vitals_$email', payload);
    } catch (_) {}
  }

  List<HealthDataType> get _liveHealthTypes => const [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.BASAL_ENERGY_BURNED,
        HealthDataType.DISTANCE_WALKING_RUNNING,
        HealthDataType.EXERCISE_TIME,
        HealthDataType.HEART_RATE,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.BLOOD_OXYGEN,
        HealthDataType.RESPIRATORY_RATE,
      ];

  List<HealthDataType> get _fullHealthTypes => const [
        HealthDataType.HEART_RATE,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.BLOOD_OXYGEN,
        HealthDataType.RESPIRATORY_RATE,
        HealthDataType.BODY_TEMPERATURE,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_GLUCOSE,
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.BASAL_ENERGY_BURNED,
        HealthDataType.DISTANCE_WALKING_RUNNING,
        HealthDataType.EXERCISE_TIME,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
      ];

  Future<void> _saveTodayActivityToPrefs(_HealthVitalsSnapshot value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await _currentEmail() ?? 'unknown_user';
      final aliases = await _currentProfileAliases();
      final keys = <String>{email, ...aliases}
        ..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
      final ymd = _todayKey();
      final steps = (value.steps ?? 0).round();
      final activeBurned = (value.activeEnergyBurned ?? 0).round();
      final basalBurned = (value.basalEnergyBurned ?? 0).round();
      final distanceKm = value.distanceWalkingRunning ?? 0.0;
      final exerciseMinutes = (value.exerciseMinutes ?? 0).round();
      final payload = jsonEncode({
        'steps': steps,
        'burned': activeBurned,
        'activeBurned': activeBurned,
        'basalBurned': basalBurned,
        'distanceKm': double.parse(distanceKm.toStringAsFixed(3)),
        'exerciseMinutes': exerciseMinutes,
        'source': _sourceName.toLowerCase().replaceAll(' ', '_'),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      for (final key in keys) {
        await prefs.setString('activity_${ymd}_$key', payload);
        await prefs.setInt('steps_${ymd}_$key', steps);
        await prefs.setInt('active_burned_${ymd}_$key', activeBurned);
        await prefs.setDouble('distance_km_${ymd}_$key', distanceKm);
        await prefs.setInt('exercise_minutes_${ymd}_$key', exerciseMinutes);
      }
    } catch (_) {}
  }

  Future<void> _refreshActivityVitalsOnly({bool silent = false}) async {
    if (!_healthEnabled || _liveSyncing || _loading) return;
    _liveSyncing = true;
    try {
      await _health.configure();
      final granted = await _health.requestAuthorization(_liveHealthTypes);
      if (!granted) {
        if (!silent && mounted) setState(() => _permissionDenied = true);
        return;
      }
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final data = await _health.getHealthDataFromTypes(
        types: _liveHealthTypes,
        startTime: startToday,
        endTime: now,
      );
      final cleaned = _health.removeDuplicates(data);
      final activity = _HealthVitalsSnapshot(
        updatedAt: now,
        steps: _sumValue(cleaned, HealthDataType.STEPS),
        activeEnergyBurned: _sumValue(cleaned, HealthDataType.ACTIVE_ENERGY_BURNED),
        basalEnergyBurned: _sumValue(cleaned, HealthDataType.BASAL_ENERGY_BURNED),
        distanceWalkingRunning: _sumValue(cleaned, HealthDataType.DISTANCE_WALKING_RUNNING) / 1000.0,
        exerciseMinutes: _sumValue(cleaned, HealthDataType.EXERCISE_TIME),
        heartRate: _latestValue(cleaned, HealthDataType.HEART_RATE),
        restingHeartRate: _latestValue(cleaned, HealthDataType.RESTING_HEART_RATE),
        heartRateVariability: _latestValue(cleaned, HealthDataType.HEART_RATE_VARIABILITY_SDNN),
        bloodOxygen: _latestValue(cleaned, HealthDataType.BLOOD_OXYGEN, percentage: true),
        respiratoryRate: _latestValue(cleaned, HealthDataType.RESPIRATORY_RATE),
      );
      final merged = _snapshot.copyWithActivity(activity);
      await _saveCachedVitals(merged);
      await _saveTodayActivityToPrefs(merged);
      await _evaluateHealthAlerts(merged);
      if (!mounted) return;
      setState(() {
        _snapshot = merged;
        _permissionDenied = false;
        if (!silent) _error = null;
      });
    } catch (_) {
      if (!silent && mounted) setState(() => _error = 'تعذر تحديث بيانات $_sourceName.');
    } finally {
      _liveSyncing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshFromAppleHealth() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _permissionDenied = false;
    });
    try {
      await _health.configure();
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final start7Days = now.subtract(const Duration(days: 7));
      final granted = await _health.requestAuthorization(_fullHealthTypes);
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _permissionDenied = true;
          _loading = false;
          _healthEnabled = false;
        });
        await _saveHealthSettings();
        return;
      }
      final todayData = await _health.getHealthDataFromTypes(
        types: _fullHealthTypes.where((t) => t != HealthDataType.SLEEP_ASLEEP).toList(),
        startTime: startToday,
        endTime: now,
      );
      final sleepData = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.SLEEP_ASLEEP],
        startTime: start7Days,
        endTime: now,
      );
      final cleanedToday = _health.removeDuplicates(todayData);
      final cleanedSleep = _health.removeDuplicates(sleepData);
      final snapshot = _HealthVitalsSnapshot(
        updatedAt: now,
        heartRate: _latestValue(cleanedToday, HealthDataType.HEART_RATE),
        restingHeartRate: _latestValue(cleanedToday, HealthDataType.RESTING_HEART_RATE),
        heartRateVariability: _latestValue(cleanedToday, HealthDataType.HEART_RATE_VARIABILITY_SDNN),
        bloodOxygen: _latestValue(cleanedToday, HealthDataType.BLOOD_OXYGEN, percentage: true),
        respiratoryRate: _latestValue(cleanedToday, HealthDataType.RESPIRATORY_RATE),
        bodyTemperature: _latestValue(cleanedToday, HealthDataType.BODY_TEMPERATURE),
        bloodPressureSystolic: _latestValue(cleanedToday, HealthDataType.BLOOD_PRESSURE_SYSTOLIC),
        bloodPressureDiastolic: _latestValue(cleanedToday, HealthDataType.BLOOD_PRESSURE_DIASTOLIC),
        bloodGlucose: _latestValue(cleanedToday, HealthDataType.BLOOD_GLUCOSE),
        steps: _sumValue(cleanedToday, HealthDataType.STEPS),
        activeEnergyBurned: _sumValue(cleanedToday, HealthDataType.ACTIVE_ENERGY_BURNED),
        basalEnergyBurned: _sumValue(cleanedToday, HealthDataType.BASAL_ENERGY_BURNED),
        distanceWalkingRunning: _sumValue(cleanedToday, HealthDataType.DISTANCE_WALKING_RUNNING) / 1000.0,
        exerciseMinutes: _sumValue(cleanedToday, HealthDataType.EXERCISE_TIME),
        sleepHours: _sleepHours(cleanedSleep),
        weight: _latestValue(cleanedToday, HealthDataType.WEIGHT),
        bodyFatPercentage: _latestValue(cleanedToday, HealthDataType.BODY_FAT_PERCENTAGE, percentage: true),
      );
      await _saveCachedVitals(snapshot);
      await _saveTodayActivityToPrefs(snapshot);
      await _evaluateHealthAlerts(snapshot);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _healthEnabled = true;
        _permissionDenied = false;
      });
      await _saveHealthSettings();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر قراءة بيانات $_sourceName. تأكد من الصلاحيات ثم حاول مرة أخرى.';
        _loading = false;
      });
    }
  }

  Future<void> _evaluateHealthAlerts(_HealthVitalsSnapshot value) async {
    if (!_alertsEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final allNotificationsEnabled = prefs.getBool(AppNotifications.kAll) ?? true;
    final globalHealthAlertsEnabled =
        prefs.getBool(AppNotifications.kHealthAlertsEnabled) ?? true;
    if (!allNotificationsEnabled || !globalHealthAlertsEnabled) return;
    final email = await _currentEmail() ?? 'unknown_user';
    final today = _todayKey();

    Future<void> sendOnce(String code, int idOffset, String title, String body) async {
      final key = 'wazen_health_alert_${today}_${code}_$email';
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
      await AppNotifications.instance.showHealthAlert(idOffset: idOffset, title: title, body: body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body)));
    }

    final steps = (value.steps ?? 0).round();
    if (_stepsGoal > 0 && steps >= _stepsGoal) {
      await sendOnce(
        'steps_goal_$_stepsGoal',
        1,
        'هدف الخطوات تحقق 👣',
        'وصلت إلى $steps خطوة اليوم. ممتاز يا بطل!',
      );
    }

    final heart = (value.heartRate ?? 0).round();
    if (heart >= _heartHigh) {
      await sendOnce(
        'heart_high_$heart',
        2,
        'تنبيه نبض القلب',
        'نبض القلب وصل إلى $heart نبضة/د. إذا كنت مرتاحًا أو تشعر بأعراض، أوقف النشاط واطلب المساعدة الطبية عند الحاجة.',
      );
    } else if (heart > 0 && heart <= _heartLow) {
      await sendOnce(
        'heart_low_$heart',
        3,
        'تنبيه نبض القلب',
        'نبض القلب منخفض: $heart نبضة/د. إذا عندك دوخة أو تعب غير طبيعي، اطلب المساعدة الطبية عند الحاجة.',
      );
    }

    final oxygen = (value.bloodOxygen ?? 0).round();
    if (oxygen > 0 && oxygen <= _oxygenLow) {
      await sendOnce(
        'oxygen_low_$oxygen',
        4,
        'تنبيه أكسجين الدم',
        'أكسجين الدم ظاهر عند $oxygen%. إذا القراءة صحيحة ومعك أعراض، اطلب المساعدة الطبية فورًا.',
      );
    }
  }

  double? _latestValue(List<HealthDataPoint> points, HealthDataType type, {bool percentage = false}) {
    final filtered = points.where((p) => p.type == type).toList()
      ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
    for (final p in filtered) {
      final value = _healthValueToDouble(p.value);
      if (value == null || value <= 0) continue;
      if (percentage && value > 0 && value <= 1) return value * 100;
      return value;
    }
    return null;
  }

  double _sumValue(List<HealthDataPoint> points, HealthDataType type) {
    double total = 0;
    for (final p in points.where((p) => p.type == type)) {
      final value = _healthValueToDouble(p.value);
      if (value != null && value > 0) total += value;
    }
    return total;
  }

  double? _sleepHours(List<HealthDataPoint> points) {
    double minutes = 0;
    for (final p in points.where((p) => p.type == HealthDataType.SLEEP_ASLEEP)) {
      final direct = _healthValueToDouble(p.value);
      if (direct != null && direct > 0 && direct <= 24 * 60) {
        minutes += direct;
      } else {
        minutes += p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
      }
    }
    if (minutes <= 0) return null;
    return minutes / 60.0;
  }

  double? _healthValueToDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    try {
      final dynamic v = value;
      final dynamic numericValue = v.numericValue;
      if (numericValue is num) return numericValue.toDouble();
    } catch (_) {}
    try {
      final dynamic v = value;
      final dynamic valueField = v.value;
      if (valueField is num) return valueField.toDouble();
    } catch (_) {}
    final text = value.toString();
    final match = RegExp(r'-?\d+(?:[\.,]\d+)?').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(0)!.replaceAll(',', '.'));
  }

  String _lastUpdatedText(DateTime? dt) {
    if (dt == null) return 'لم يتم التحديث بعد';
    return DateFormat('hh:mm a', 'ar').format(dt);
  }

  Future<void> _editHealthAlertSettings() async {
    final stepsCtl = TextEditingController(text: _stepsGoal.toString());
    final highCtl = TextEditingController(text: _heartHigh.toString());
    final lowCtl = TextEditingController(text: _heartLow.toString());
    final oxygenCtl = TextEditingController(text: _oxygenLow.toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات تنبيهات صحتي'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stepsCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'هدف الخطوات اليومي'),
              ),
              TextField(
                controller: highCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'تنبيه نبض مرتفع'),
              ),
              TextField(
                controller: lowCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'تنبيه نبض منخفض'),
              ),
              TextField(
                controller: oxygenCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'تنبيه أكسجين منخفض %'),
              ),
              const SizedBox(height: 10),
              const Text(
                'هذه التنبيهات للمساعدة فقط وليست تشخيصًا طبيًا أو بديلًا عن الطوارئ.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (saved != true) return;
    setState(() {
      _stepsGoal = int.tryParse(stepsCtl.text.trim()) ?? _stepsGoal;
      _heartHigh = int.tryParse(highCtl.text.trim()) ?? _heartHigh;
      _heartLow = int.tryParse(lowCtl.text.trim()) ?? _heartLow;
      _oxygenLow = int.tryParse(oxygenCtl.text.trim()) ?? _oxygenLow;
    });
    await _saveHealthSettings();
  }

  Widget _statusChip({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _healthSwitchCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(.32)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(.05), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _HealthCompositeIcon(color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صحتي', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      '$_sourceName · آخر تحديث ${_lastUpdatedText(_snapshot.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(value: _healthEnabled, onChanged: _loading ? null : _setHealthEnabled),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip(
                icon: _healthEnabled ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
                text: _healthEnabled ? 'مفعل' : 'متوقف',
                color: _healthEnabled ? Colors.green : cs.onSurfaceVariant,
              ),
              if (_liveSyncing) _statusChip(icon: Icons.sync_rounded, text: 'تحديث مباشر', color: cs.secondary),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (!_healthEnabled || _loading) ? null : _refreshFromAppleHealth,
                  icon: _loading
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                      : const Icon(Icons.sync_rounded),
                  label: Text(_loading ? 'جاري التحديث...' : 'تحديث الآن'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editHealthAlertSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('التنبيهات'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تنبيهات صحتي', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  'خطوات $_stepsGoal · نبض عالي $_heartHigh · نبض منخفض $_heartLow · أكسجين أقل من $_oxygenLow%',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: _alertsEnabled, onChanged: _setAlertsEnabled),
        ],
      ),
    );
  }

  Widget _watchCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.35),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.watch_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الساعات الذكية', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(_watchSourceText, style: t.bodySmall?.copyWith(height: 1.45, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    final crossAxisCount = w >= 700 ? 4 : 2;
    final tiles = <_VitalTile>[
      _VitalTile(title: 'الخطوات', value: _snapshot.format(_snapshot.steps, 0), unit: 'خطوة', note: 'اليوم', icon: Icons.directions_walk_rounded),
      _VitalTile(title: 'السعرات النشطة', value: _snapshot.format(_snapshot.activeEnergyBurned, 0), unit: 'سعرة', note: 'اليوم', icon: Icons.local_fire_department_outlined),
      _VitalTile(title: 'المسافة', value: _snapshot.format(_snapshot.distanceWalkingRunning, 2), unit: 'كم', note: 'اليوم', icon: Icons.route_outlined),
      _VitalTile(title: 'دقائق التمرين', value: _snapshot.format(_snapshot.exerciseMinutes, 0), unit: 'دقيقة', note: 'اليوم', icon: Icons.timer_outlined),
      _VitalTile(title: 'نبض القلب', value: _snapshot.format(_snapshot.heartRate, 0), unit: 'نبضة/د', note: 'آخر قراءة', icon: Icons.monitor_heart_outlined),
      _VitalTile(title: 'نبض الراحة', value: _snapshot.format(_snapshot.restingHeartRate, 0), unit: 'نبضة/د', note: 'آخر قراءة', icon: Icons.favorite_border_rounded),
      _VitalTile(title: 'أكسجين الدم', value: _snapshot.format(_snapshot.bloodOxygen, 0), unit: '%', note: 'آخر قراءة', icon: Icons.bubble_chart_outlined),
      _VitalTile(title: 'ضغط الدم', value: _snapshot.bloodPressureText, unit: 'mmHg', note: 'آخر قراءة', icon: Icons.speed_rounded),
      _VitalTile(title: 'التنفس', value: _snapshot.format(_snapshot.respiratoryRate, 0), unit: 'مرة/د', note: 'آخر قراءة', icon: Icons.air_rounded),
      _VitalTile(title: 'النوم', value: _snapshot.format(_snapshot.sleepHours, 1), unit: 'ساعة', note: 'آخر 7 أيام', icon: Icons.bedtime_outlined),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        _healthSwitchCard(context),
        if (_permissionDenied || _error != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cs.errorContainer.withOpacity(.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.error.withOpacity(.16)),
            ),
            child: Text(
              _permissionDenied
                  ? 'فعّل صلاحيات $_sourceName لعرض البيانات.'
                  : (_error ?? ''),
              style: t.bodySmall?.copyWith(color: cs.onErrorContainer, fontWeight: FontWeight.w700),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _alertsCard(context),
        const SizedBox(height: 12),
        _watchCard(context),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Text('نشاط اليوم والعلامات الحيوية', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
            Text(_healthEnabled ? 'متصل' : 'فعّل صحتي أولًا', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: w >= 700 ? 1.82 : 1.28,
          children: tiles,
        ),
        const SizedBox(height: 10),
        Text(
          'تظهر بعض المؤشرات فقط عند توفر جهاز يدعمها ومنح الصلاحية. تنبيهات وازن للمساعدة وليست تشخيصًا طبيًا.',
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _HealthVitalsSnapshot {
  final DateTime? updatedAt;
  final double? heartRate;
  final double? restingHeartRate;
  final double? heartRateVariability;
  final double? bloodOxygen;
  final double? respiratoryRate;
  final double? bodyTemperature;
  final double? bloodPressureSystolic;
  final double? bloodPressureDiastolic;
  final double? bloodGlucose;
  final double? steps;
  final double? activeEnergyBurned;
  final double? basalEnergyBurned;
  final double? distanceWalkingRunning;
  final double? exerciseMinutes;
  final double? sleepHours;
  final double? weight;
  final double? bodyFatPercentage;

  const _HealthVitalsSnapshot({
    this.updatedAt,
    this.heartRate,
    this.restingHeartRate,
    this.heartRateVariability,
    this.bloodOxygen,
    this.respiratoryRate,
    this.bodyTemperature,
    this.bloodPressureSystolic,
    this.bloodPressureDiastolic,
    this.bloodGlucose,
    this.steps,
    this.activeEnergyBurned,
    this.basalEnergyBurned,
    this.distanceWalkingRunning,
    this.exerciseMinutes,
    this.sleepHours,
    this.weight,
    this.bodyFatPercentage,
  });

  factory _HealthVitalsSnapshot.fromJson(Map<String, dynamic> json) {
    double? d(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return _HealthVitalsSnapshot(
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      heartRate: d('heartRate'),
      restingHeartRate: d('restingHeartRate'),
      heartRateVariability: d('heartRateVariability'),
      bloodOxygen: d('bloodOxygen'),
      respiratoryRate: d('respiratoryRate'),
      bodyTemperature: d('bodyTemperature'),
      bloodPressureSystolic: d('bloodPressureSystolic'),
      bloodPressureDiastolic: d('bloodPressureDiastolic'),
      bloodGlucose: d('bloodGlucose'),
      steps: d('steps'),
      activeEnergyBurned: d('activeEnergyBurned'),
      basalEnergyBurned: d('basalEnergyBurned'),
      distanceWalkingRunning: d('distanceWalkingRunning'),
      exerciseMinutes: d('exerciseMinutes'),
      sleepHours: d('sleepHours'),
      weight: d('weight'),
      bodyFatPercentage: d('bodyFatPercentage'),
    );
  }

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt?.toIso8601String(),
        'heartRate': heartRate,
        'restingHeartRate': restingHeartRate,
        'heartRateVariability': heartRateVariability,
        'bloodOxygen': bloodOxygen,
        'respiratoryRate': respiratoryRate,
        'bodyTemperature': bodyTemperature,
        'bloodPressureSystolic': bloodPressureSystolic,
        'bloodPressureDiastolic': bloodPressureDiastolic,
        'bloodGlucose': bloodGlucose,
        'steps': steps,
        'activeEnergyBurned': activeEnergyBurned,
        'basalEnergyBurned': basalEnergyBurned,
        'distanceWalkingRunning': distanceWalkingRunning,
        'exerciseMinutes': exerciseMinutes,
        'sleepHours': sleepHours,
        'weight': weight,
        'bodyFatPercentage': bodyFatPercentage,
      };

  String format(double? value, int decimals) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) return 'غير متوفر';
    return value.toStringAsFixed(decimals);
  }



  _HealthVitalsSnapshot copyWithActivity(_HealthVitalsSnapshot activity) {
    return _HealthVitalsSnapshot(
      updatedAt: activity.updatedAt ?? updatedAt,
      heartRate: heartRate,
      restingHeartRate: restingHeartRate,
      heartRateVariability: heartRateVariability,
      bloodOxygen: bloodOxygen,
      respiratoryRate: respiratoryRate,
      bodyTemperature: bodyTemperature,
      bloodPressureSystolic: bloodPressureSystolic,
      bloodPressureDiastolic: bloodPressureDiastolic,
      bloodGlucose: bloodGlucose,
      steps: activity.steps ?? steps,
      activeEnergyBurned: activity.activeEnergyBurned ?? activeEnergyBurned,
      basalEnergyBurned: activity.basalEnergyBurned ?? basalEnergyBurned,
      distanceWalkingRunning: activity.distanceWalkingRunning ?? distanceWalkingRunning,
      exerciseMinutes: activity.exerciseMinutes ?? exerciseMinutes,
      sleepHours: sleepHours,
      weight: weight,
      bodyFatPercentage: bodyFatPercentage,
    );
  }

  String get bloodPressureText {
    if (bloodPressureSystolic == null || bloodPressureDiastolic == null) return 'غير متوفر';
    if (bloodPressureSystolic! <= 0 || bloodPressureDiastolic! <= 0) return 'غير متوفر';
    return '${bloodPressureSystolic!.toStringAsFixed(0)}/${bloodPressureDiastolic!.toStringAsFixed(0)}';
  }
}


class _HealthCompositeIcon extends StatelessWidget {
  final Color color;
  const _HealthCompositeIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 8,
          right: 8,
          child: Icon(Icons.monitor_heart_rounded, size: 17, color: color),
        ),
        Positioned(
          bottom: 8,
          right: 9,
          child: Icon(Icons.directions_walk_rounded, size: 18, color: color.withOpacity(.88)),
        ),
        Positioned(
          left: 8,
          bottom: 9,
          child: Icon(Icons.route_rounded, size: 16, color: color.withOpacity(.78)),
        ),
      ],
    );
  }
}

class _HealthHeaderCard extends StatelessWidget {
  final String lastUpdated;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _HealthHeaderCard({
    required this.lastUpdated,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primaryContainer.withOpacity(.9),
            cs.surfaceVariant.withOpacity(.72),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(.85),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _HealthCompositeIcon(color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صحتي', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('مصدر البيانات: Apple Health', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withOpacity(.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.update_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'آخر تحديث: $lastUpdated',
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onRefresh,
              icon: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(loading ? 'جاري التحديث...' : 'تحديث من Apple Health'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthNoticeCard extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _HealthNoticeCard({
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.error.withOpacity(.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(message, style: t.bodySmall?.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_VitalTile> children;

  const _VitalsSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(.045), blurRadius: 14, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 640 ? 3 : 2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: constraints.maxWidth >= 640 ? 1.72 : 1.18,
                children: children,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VitalTile extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final String note;
  final IconData icon;

  const _VitalTile({
    required this.title,
    required this.value,
    required this.unit,
    required this.note,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final available = value != 'غير متوفر';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: available ? cs.surfaceVariant.withOpacity(.38) : cs.surfaceVariant.withOpacity(.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: available ? cs.primary : cs.onSurfaceVariant.withOpacity(.58)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: available ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            available ? unit : note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (available) ...[
            const SizedBox(height: 2),
            Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant.withOpacity(.82))),
          ],
        ],
      ),
    );
  }
}


// ===== UI Enhancements: Kcal Summary Card & Cutting Hint =====
class _KcalSummaryCard extends StatelessWidget {
  final double todayKcal, targetKcal, p, c, f;
  final String goalType;
  const _KcalSummaryCard({
    required this.todayKcal,
    required this.targetKcal,
    required this.p,
    required this.c,
    required this.f,
    required this.goalType,
  });

  @override
Widget build(BuildContext context) {
  final remain = (targetKcal - todayKcal);
  final percent = targetKcal > 0 ? (todayKcal / targetKcal).clamp(0, 1) : 0.0;

  return Directionality(
    textDirection: ui.TextDirection.ltr, // ✅ Flutter TextDirection بدون تعارض
    child: Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department),
                const SizedBox(width: 8),
                Text(
                  'ملخص السعرات اليوم',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    '${remain >= 0 ? 'متبقي' : 'تجاوز'} ${_fmt(remain.abs())}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: percent.toDouble(),
                minHeight: 12,
              ),
            ),
Row(
              children: [
                Expanded(child: Text('اليوم: ${_fmt(todayKcal)} kcal')),
                Expanded(
                  child: Text(
                    'الهدف: ${_fmt(targetKcal)} kcal',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MacroRow(label: 'بروتين', grams: p, kcal: p * 4),
            const Divider(height: 12),
            _MacroRow(label: 'كربوهيدرات', grams: c, kcal: c * 4),
            const Divider(height: 12),
            _MacroRow(label: 'دهون', grams: f, kcal: f * 9),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'إجمالي طاقة الماكروز: ${_fmt(p * 4 + c * 4 + f * 9)} kcal',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(height: 6),
            _CuttingHint(goalType: goalType, fatGrams: f),
          ],
        ),
      ),
    ),
  );
}


  String _fmt(num n) =>
      (n is int || n == n.roundToDouble()) ? n.toString() : n.toStringAsFixed(1);
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double grams;
  final double kcal;
  const _MacroRow({required this.label, required this.grams, required this.kcal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          '${grams.toStringAsFixed(0)} جم  ·  ${kcal.toStringAsFixed(0)} kcal',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _CuttingHint extends StatelessWidget {
  final String goalType;
  final double fatGrams;
  const _CuttingHint({required this.goalType, required this.fatGrams});

  @override
  Widget build(BuildContext context) {
    if (goalType != 'cut' && goalType != 'تنشيف') return const SizedBox.shrink();
    // 👇 عدّل العتبة حسب سياستك/وزن المستخدم
    final bool highFat = fatGrams > 70;
    if (!highFat) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'دهونك اليوم مرتفعة وأنت على هدف تنشيف — حاول تخفّض الدهون في الوجبات القادمة.',
            ),
          ),
        ],
      ),
    );
  }
}


class _GoalCoachLine extends StatelessWidget {
  final String goal;
  final double latestKg;
  final double protein;
  final double fat;
  final double carbs;

  const _GoalCoachLine({
    required this.goal,
    required this.latestKg,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  Widget build(BuildContext context) {
    // عبارات بسيطة حسب الهدف — دون لمس أي منطق حسابي موجود
    String tip;
    switch (goal) {
      case 'تنشيف الدهون':
        tip = fat > 0 && protein > 0 ? 'تنبيه: الدهون أعلى من هدفك. جرّب تقليل الدهون وزيادة البروتين اليوم.' : 'ركز على بروتين أعلى ودهون أقل.';
        break;
      case 'بناء العضلات':
        tip = protein <= 0 ? 'ارفع البروتين وقسّم وجباتك لدعم البناء.' : 'استمر على بروتين كافٍ مع كارب داعم للتمرين.';
        break;
      case 'إنقاص الوزن':
        tip = 'حافظ على عجز سعري بسيط وتتبع الماء. تقدّم ثابت أهم من السرعة.';
        break;
      case 'زيادة الوزن':
        tip = 'ارفع الكارب الصحي وزد عدد الوجبات تدريجيًا.';
        break;
      default:
        tip = 'استمر على توازن الماكروز والماء والنوم الجيد.';
    }
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: Color(0xFF6A7C7C)),
        const SizedBox(width: 6),
        Expanded(child: Text(tip, style: TextStyle(color: cs.outline, fontSize: 12.5))),
      ],
    );
  }
}

//// ========= Insights Tab =========
class _InsightsTab extends StatefulWidget {
  const _InsightsTab();
  @override
  State<_InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<_InsightsTab> with WidgetsBindingObserver {
  final PageController _page = PageController();
  int _idx = 0;
  Timer? _auto;

  // كاش مؤقت لاسترجاع بيانات السعرات/الماء/الوزن من السحابة مرة واحدة فقط داخل تبويب التتبع.
  bool _cloudDailyRestoreDone = false;
  List<Map<String, dynamic>> _cachedRemoteDays = const <Map<String, dynamic>>[];

  // البيانات الأساسية
  double? heightCm;
  double? weightKg;
  int? age;
  String? gender;
  double? targetCal;
  double? targetProteinG;
  double? targetCarbG;
  double? targetFatG;
  int waterTargetMl = 2000;
  int stepsTarget = 8000;

  // ملخص الأيام الأخيرة
  late List<_DaySummary> last7 = [];

  Timer? _tick;
  StreamSubscription<void>? _weightSub;
  VoidCallback? _targetsListener;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _loadAll());
    _weightSub = WeightLiveBus.stream.listen((_) => _loadAll());
    _targetsListener = () => _loadAll();
    MacroTargetsController.revision.addListener(_targetsListener!);
    _auto = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final next = (_idx + 1) % 5; // خمس شرائح
      _page.animateToPage(next, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _tick?.cancel();
    _weightSub?.cancel();
    if (_targetsListener != null) {
      MacroTargetsController.revision.removeListener(_targetsListener!);
    }
    _userNameSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _page.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    final aliases = await _currentProfileAliases();
    final profileKey = _latestProfileAlias(prefs, aliases);

    // تحليلات التتبع تقرأ من المحلي فقط حتى لا تتأخر الصفحة عند الفتح.
    final remoteDays = <Map<String, dynamic>>[];
    _cachedRemoteDays = remoteDays;
    _cloudDailyRestoreDone = true;

    // -------- بيانات أساسية (قراءة مرنة للمفاتيح) --------
    heightCm = _prefDoubleAnyAlias(
      prefs,
      const ['height_', 'height_cm_', 'heightCm_'],
      aliases,
      preferred: profileKey,
    );

    weightKg = _prefDoubleAnyAlias(
      prefs,
      const [
        'current_weight_',
        'weight_',
        'weightKg_',
        'currentWeight_',
        'user_weight_',
        'goal_current_',
      ],
      aliases,
      preferred: profileKey,
    );

    age = _prefIntAnyAlias(prefs, 'age_', aliases, preferred: profileKey);

    gender = _prefStringAnyAlias(prefs, 'gender_', aliases, preferred: profileKey);

    targetCal = _prefDoubleAnyAlias(prefs, const ['caloriesNeeded_'], aliases, preferred: profileKey);
    targetProteinG = _prefDoubleAnyAlias(prefs, const ['protein_'], aliases, preferred: profileKey);
    targetCarbG = _prefDoubleAnyAlias(prefs, const ['carbs_', 'carb_'], aliases, preferred: profileKey);
    targetFatG = _prefDoubleAnyAlias(prefs, const ['fat_'], aliases, preferred: profileKey);

    waterTargetMl = _prefIntAnyAlias(prefs, 'waterMlTarget_', aliases, preferred: profileKey) ?? waterTargetMl;
    stepsTarget = _prefIntAnyAlias(prefs, 'stepsTarget_', aliases, preferred: profileKey) ?? stepsTarget;

    // -------- خرائط مساعدة (ماء/وزن) --------
    final waterLitersMap = <String, double>{};
    for (final alias in _orderedAliases(aliases, profileKey)) {
      final waterLogRaw = prefs.getString('water_log_$alias');
      if (waterLogRaw != null) {
        try {
          final m = jsonDecode(waterLogRaw) as Map<String, dynamic>;
          for (final e in m.entries) {
            final v = _toD(e.value);
            if (v > 0) waterLitersMap[e.key] = v;
          }
        } catch (_) {}
      }
    }
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final water = d['water'];
      final liters = water is Map && water['liters'] is num
          ? (water['liters'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && liters > 0) {
        waterLitersMap.putIfAbsent(ymd, () => liters);
      }
    }

    final weightMap = <String, double>{};
    for (final alias in _orderedAliases(aliases, profileKey)) {
      final weightLogRaw = prefs.getString('weight_log_$alias');
      if (weightLogRaw != null) {
        try {
          final decoded = jsonDecode(weightLogRaw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final d = _normalizeYmd(item['date'] ?? item['day'] ?? item['ymd']);
                final kg = _toD(item['kg'] ?? item['weight'] ?? item['weightKg']);
                if (d != null && kg > 0) weightMap[d] = kg;
              }
            }
          }
        } catch (_) {}
      }

      final historyList = _safePrefStringList(prefs, 'weightHistory_$alias');
      if (historyList.isNotEmpty) {
        for (final s in historyList) {
          try {
            final m = jsonDecode(s) as Map<String, dynamic>;
            final d = _normalizeYmd(m['date']);
            final kg = _toD(m['weight'] ?? m['kg'] ?? m['weightKg']);
            if (d != null && kg > 0) weightMap.putIfAbsent(d, () => kg);
          } catch (_) {}
        }
      }
    }
    final todayYmd =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toIso8601String()
            .split('T')
            .first;
    final currentW = _prefDoubleAnyAlias(
      prefs,
      const ['current_weight_', 'weight_', 'weightKg_', 'currentWeight_', 'user_weight_'],
      aliases,
      preferred: profileKey,
    );
    if (currentW != null && currentW > 0) {
      // وزن صفحة بياناتي هو أحدث قيمة لليوم ويجب أن يغطي أي قيمة قديمة.
      weightMap[todayYmd] = currentW;
    }
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final tracking = d['tracking'];
      final kg = tracking is Map && tracking['weightKg'] is num
          ? (tracking['weightKg'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && kg > 0) {
        weightMap.putIfAbsent(ymd, () => kg);
      }
    }

    // -------- آخر 7 أيام (أقدم -> أحدث) --------
    final now = DateTime.now();
    final tmp = <_DaySummary>[];

    for (int i = 6; i >= 0; i--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final ymd = day.toIso8601String().split('T').first;

      // السعرات/الماكروز — اقرأ من كل مفاتيح المستخدم لأن صفحة بياناتي توحّدها بين uid/email.
      double kcal = 0.0, p = 0.0, c = 0.0, f = 0.0;
      for (final alias in _orderedAliases(aliases, profileKey)) {
        final totals = await _readTotalsForDate(prefs, alias, ymd);
        kcal = totals['cal'] ?? 0.0;
        p = totals['p'] ?? 0.0;
        c = totals['c'] ?? 0.0;
        f = totals['f'] ?? 0.0;
        if (kcal > 0 || p > 0 || c > 0 || f > 0) break;
      }

      // الماء — التخزين باللتر وقد يكون مربوطًا بالـ uid أو البريد.
      double liters = waterLitersMap[ymd] ?? 0.0;
      for (final alias in _orderedAliases(aliases, profileKey)) {
        liters = _prefDouble(prefs, 'water_${ymd}_$alias') ?? liters;
        final legacyMl = _prefDouble(prefs, 'waterMl_${ymd}_$alias') ??
            _prefDouble(prefs, 'water_ml_${ymd}_$alias');
        if (legacyMl != null && legacyMl > 0) {
          liters = legacyMl / 1000.0;
          break;
        }
        if (liters > 0) break;
      }
      final waterMl = (liters * 1000).round();

      // النشاط — قد يُحفظ بالـ uid أو البريد حسب مصدر Apple Health.
      int steps = 0, burned = 0;
      for (final alias in _orderedAliases(aliases, profileKey)) {
        final aRaw = prefs.getString('activity_${ymd}_$alias');
        if (aRaw != null) {
          try {
            final a = jsonDecode(aRaw) as Map<String, dynamic>;
            steps = _asSafeInt(a['steps']);
            burned = _asSafeInt(a['burned'] ?? a['activeBurned']);
          } catch (_) {}
        }
        if (steps <= 0) steps = _prefInt(prefs, 'steps_${ymd}_$alias') ?? steps;
        if (burned <= 0) burned = _prefInt(prefs, 'active_burned_${ymd}_$alias') ?? burned;
        if (steps > 0 || burned > 0) break;
      }

      // الوزن (اختياري)
      final w = weightMap[ymd];

      tmp.add(_DaySummary(
        date: day,
        kcal: kcal,
        waterMl: waterMl,
        steps: steps,
        protein: p,
        carb: c,
        fat: f,
        burned: burned,
        weightKg: w,
      ));
    }

    last7 = tmp;

    if (mounted) setState(() {});
  }

  _CalScore get _calScore {
    if (targetCal == null || targetCal == 0) return _CalScore(0, 'لا يوجد هدف سعرات');
    final tol = targetCal! * 0.10; // ±10%
    int okDays = 0;
    for (final d in last7) {
      if ((d.kcal - targetCal!).abs() <= tol) okDays++;
    }
    final pct = okDays / (last7.isEmpty ? 1 : last7.length);
    String label;
    if (pct >= .7) label = 'ممتاز';
    else if (pct >= .5) label = 'جيد';
    else label = 'بحاجة لتحسين';
    return _CalScore(okDays, label);
  }

  _WaterScore get _waterScore {
    int okDays = 0;
    for (final d in last7) {
      if (d.waterMl >= waterTargetMl) okDays++;
    }
    String label;
    if (okDays >= 5) label = 'ممتاز';
    else if (okDays >= 3) label = 'جيد';
    else label = 'بحاجة لتحسين';
    return _WaterScore(okDays, label);
  }

  _StepsScore get _stepsScore {
    int okDays = 0;
    for (final d in last7) {
      if (d.steps >= stepsTarget) okDays++;
    }
    String label;
    if (okDays >= 5) label = 'ممتاز';
    else if (okDays >= 3) label = 'جيد';
    else label = 'بحاجة لتحسين';
    return _StepsScore(okDays, label);
  }

  double? get _bmi {
    final h = heightCm;
    final w = weightKg;
    if (h == null || w == null || h <= 0) return null;
    final m = h / 100.0;
    return w / (m * m);
  }

  String _bmiLabel(double bmi) {
    if (bmi < 18.5) return 'نحافة';
    if (bmi < 25) return 'طبيعي';
    if (bmi < 30) return 'زيادة وزن';
    if (bmi < 35) return 'سمنة (١)';
    if (bmi < 40) return 'سمنة (٢)';
    return 'سمنة مفرطة';
  }


  List<String> _buildRecommendations() {
    final recs = <String>[];

    // بناء على BMI
    if (_bmi != null) {
      final b = _bmi!;
      if (b >= 30) {
        recs.addAll([
          'استهدف عجزًا سعريًا 10–15% لمدة 6–8 أسابيع ثم راحة أسبوع.',
          'اجعل البروتين بين 1.8–2.2 جم/كجم من وزن الجسم يوميًا.',
          'قسّم وجباتك إلى 3–4 وجبات ثابتة لتقليل الجوع.',
        ]);
      } else if (b >= 25) {
        recs.addAll([
          'عجز سعري معتدل 10% يكفي للوصول لهدفك تدريجيًا.',
          'ارفع خطواتك اليومية +1500 خطوة فوق المتوسط الحالي.',
        ]);
      } else if (b < 18.5) {
        recs.addAll([
          'فائض سعري خفيف 5–10% مع تركيز على البروتين والجودة.',
          'تمارين مقاومة 3 مرات أسبوعيًا لزيادة الكتلة العضلية.',
        ]);
      } else {
        recs.add('حافظ على السعرات الحالية مع بروتين كافٍ وتمارين مقاومة للحفاظ على التناسق.');
      }
    }

    // التزام السعرات
    if (_calScore.okDays >= 5) {
      recs.add('استمر! التزامك بالسعرات ممتاز خلال الأسبوع.');
    } else if (_calScore.okDays <= 2) {
      recs.addAll([
        'حضّر وجباتك مسبقًا ليومين–ثلاثة لتسهيل الالتزام.',
        'استبدل المشروبات السكرية بالماء/القهوة السوداء/الشاي.',
      ]);
    } else {
      recs.add('قلّل “اللقيمات بين الوجبات” واجعل سناك بروتيني/خضار.');
    }

    // الماء
    if (_waterScore.okDays <= 2) {
      recs.addAll([
        'احمل معك قنينة ماء وحدد تنبيه كل 90 دقيقة.',
        'ابدأ يومك بكوبين ماء وأضف كوبًا قبل كل وجبة.',
      ]);
    } else if (_waterScore.okDays >= 5) {
      recs.add('ترطيب ممتاز — استمر على هدف الماء اليومي.');
    }

    // الخطوات
    if (_stepsScore.okDays <= 2) {
      recs.addAll([
        'أضف 10 دقائق مشي بعد الغداء والعشاء.',
        'اركن بعيدًا درجتين إضافيتين + استخدم الدرج بدل المصعد.',
      ]);
    } else if (_stepsScore.okDays >= 5) {
      recs.add('فكّر بزيادة هدفك 500–1000 خطوة للأسبوع القادم.');
    }

    // توصيات عامة مرنة
    if (weightKg != null) {
      final minP = (weightKg!*1.6).round();
      final maxP = (weightKg!*2.2).round();
      recs.add('استهدف بروتين يومي بين ~%d–%d جم.'.replaceFirst('%d', minP.toString()).replaceFirst('%d', maxP.toString()));
    }
    recs.addAll([
      'نم 7–8 ساعات ليلًا واغلق الشاشات قبل النوم بـ 60 دقيقة.',
      'أدخل خضار/ألياف في وجبتين على الأقل يوميًا.',
      'ثبّت مواعيد وجباتك قدر الإمكان لتقليل قرارات اليوم.',
      'مرّة أسبوعيًا: مراجعة الوزن والمتوسط لتقييم التقدم.',
    ]);

    // إزالة التكرارات والاقتصار على 8–12 بند
    final seen = <String>{};
    final dedup = <String>[];
    for (final r in recs) {
      if (!seen.contains(r)) { seen.add(r); dedup.add(r); }
    }
    if (dedup.length > 12) {
      return dedup.sublist(0, 12);
    } else if (dedup.length < 8) {
      const fillers = [
        'بدّل المقليات بالشوي أو القلاية الهوائية.',
        'اجعل أول لقمة من البروتين/الخضار لتقليل الشهية.',
        'اختر قهوة بدون إضافات سكرية.',
        'وزّع حصص الدهون الصحية (زيت زيتون/مكسرات) بدل الزيادات العشوائية.',
      ];
      dedup.addAll(fillers.take(8 - dedup.length));
    }
    return dedup;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;
    final nPages = 5;

    final recs = _buildRecommendations();

    return Column(
      children: [
        // مؤشّر شبيه الستوري
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: List.generate(nPages, (i) {
              final active = i == _idx;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsetsDirectional.only(end: i == nPages-1 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: active ? cs.primary : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _page,
            onPageChanged: (i) => setState(() => _idx = i),
            children: [
              _InsightCard(
                gradient: [cs.primaryContainer, cs.surface],
                title: 'الطول والوزن',
                big: _bmi == null ? '—' : _bmi!.toStringAsFixed(1),
                subtitle: _bmi == null ? 'أدخل بياناتك لنحسب مؤشر كتلة الجسم' : 'BMI — ${_bmiLabel(_bmi!)}',
                extra: (heightCm != null && weightKg != null)
                    ? 'الطول: ${heightCm!.toStringAsFixed(0)} سم • الوزن: ${weightKg!.toStringAsFixed(1)} كجم'
                    : 'الطول/الوزن غير مكتملين',
              ),
              _InsightCard(
                gradient: [cs.secondaryContainer, cs.surface],
                title: 'التزام السعرات (٧ أيام)',
                big: '${_calScore.okDays}/7',
                subtitle: targetCal == null ? 'لا يوجد هدف سعرات' : 'هدفك: ${targetCal!.toStringAsFixed(0)} سعرة',
                extra: 'التقييم: ${_calScore.label}',
              ),
              _InsightCard(
                gradient: [cs.tertiaryContainer, cs.surface],
                title: 'الماء (٧ أيام)',
                big: '${_waterScore.okDays}/7',
                subtitle: 'هدفك: ${waterTargetMl} مل',
                extra: 'التقييم: ${_waterScore.label}',
              ),
              _InsightCard(
                gradient: [cs.primaryContainer, cs.surfaceVariant],
                title: 'الخطوات (٧ أيام)',
                big: '${_stepsScore.okDays}/7',
                subtitle: 'هدفك: ${stepsTarget} خطوة',
                extra: 'التقييم: ${_stepsScore.label}',
              ),
              // الشريحة الخامسة: توصيات ذكية
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.secondaryContainer, cs.surface], begin: Alignment.topRight, end: Alignment.bottomLeft),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: cs.shadow.withOpacity(.08), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('توصيات ذكية لك', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: recs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check_circle_rounded, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(recs[i], style: t.bodyMedium)),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final List<Color> gradient;
  final String title;
  final String big;
  final String subtitle;
  final String extra;
  const _InsightCard({
    required this.gradient,
    required this.title,
    required this.big,
    required this.subtitle,
    required this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: cs.shadow.withOpacity(.08), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(big, style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(width: 10),
                Expanded(child: Text(subtitle, style: t.bodyMedium)),
              ],
            ),
            const Spacer(),
            Text(extra, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DaySummary {
  final DateTime date;
  final double kcal;
  final double protein;
  final double carb;
  final double fat;
  final int waterMl;
  final int steps;
  final int burned;
  final double? weightKg;

  _DaySummary({
    required this.date,
    required this.kcal,
    required this.waterMl,
    required this.steps,
    this.protein = 0,
    this.carb = 0,
    this.fat = 0,
    this.burned = 0,
    this.weightKg,
  });
}

class _CalScore {
  final int okDays; final String label;
  _CalScore(this.okDays, this.label);
}
class _WaterScore {
  final int okDays; final String label;
  _WaterScore(this.okDays, this.label);
}
class _StepsScore {
  final int okDays; final String label;
  _StepsScore(this.okDays, this.label);
}

/// Event bus لتحديث صفحة تتبع الماكروز فورياً عند إضافة/حذف الوجبات من صفحات أخرى.
class MacrosLiveBus {
  static final _ctrl = StreamController<void>.broadcast();
  static void ping() { if (!_ctrl.isClosed) _ctrl.add(null); }
  static StreamSubscription listen(void Function() fn) => _ctrl.stream.listen((_) => fn());
}

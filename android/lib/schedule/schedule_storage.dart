// lib/schedule/schedule_storage.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleStorage {
  // ---------- المفاتيح القديمة (حفاظًا على التوافق) ----------
  static const _kSelectedPlanName = 'selected_plan_name';
  static const _kSelectedPlanSavedAt = 'selected_plan_saved_at';

  // ---------- مفاتيح الجداول المخصّصة (لكل مستخدم) ----------
  static String _customPlansKey(String email) => 'customWorkoutPlans_$email';

  // محاولة لاستخراج إيميل المستخدم من الشيرد
  static Future<String> _resolveEmail(SharedPreferences prefs) async {
    final candidates = <String?>[
      prefs.getString('currentEmail'),
      prefs.getString('email'),
      prefs.getString('userEmail'),
      prefs.getString('user_email'),
    ];
    return (candidates.firstWhere(
          (e) => e != null && e.trim().isNotEmpty,
          orElse: () => 'unknown_user',
        )!)
        .trim()
        .toLowerCase();
  }

  // ============================================================
  // القسم (A): نفس الدوال القديمة — لا تغييرات (توافق كامل)
  // ============================================================
  static Future<void> saveSelectedPlan(String planName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedPlanName, planName);
    await prefs.setString(
        _kSelectedPlanSavedAt, DateTime.now().toIso8601String());
  }

  static Future<String?> loadSelectedPlan() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSelectedPlanName);
  }

  static Future<DateTime?> loadSelectedPlanSavedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kSelectedPlanSavedAt);
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSelectedPlanName);
    await prefs.remove(_kSelectedPlanSavedAt);
  }

  // ============================================================
  // القسم (B): دعم "قائمة جداولي" (حفظ/قراءة/حذف) لكل مستخدم
  // ============================================================

  /// توحيد أي كائن جدول إلى شكل واحد:
  /// { name, goal, days, createdAt, raw }
  static Map<String, dynamic>? normalizePlan(dynamic v) {
    if (v == null) return null;

    // 1) إن كان Map
    if (v is Map) {
      final name = _pickFirstString(v, const ['name', 'title', 'planName', 'id']);
      if (name == null || name.trim().isEmpty) return null;

      final goal = v['goal'] ?? v['description'] ?? '';
      final days = v['days'] ?? v['plan'] ?? v['sessions'] ?? <String, dynamic>{};

      return {
        'name': name.toString(),
        'goal': goal?.toString() ?? '',
        'days': (days is Map) ? days : <String, dynamic>{},
        'createdAt': DateTime.now().toIso8601String(),
        'raw': v, // نخزّن الأصل لمرونة مستقبلية
      };
    }

    // 2) إن كان موديل/كائن
    String? name;
    dynamic goal;
    dynamic days;

    try {
      final n = (v as dynamic).name;
      if (n is String && n.isNotEmpty) name = n;
    } catch (_) {}
    try {
      final t = (v as dynamic).title;
      if (name == null && t is String && t.isNotEmpty) name = t;
    } catch (_) {}
    try {
      final pn = (v as dynamic).planName;
      if (name == null && pn is String && pn.isNotEmpty) name = pn;
    } catch (_) {}
    try {
      final id = (v as dynamic).id;
      if (name == null && id is String && id.isNotEmpty) name = id;
    } catch (_) {}

    try {
      goal = (v as dynamic).goal;
    } catch (_) {}
    try {
      goal ??= (v as dynamic).description;
    } catch (_) {}
    try {
      days = (v as dynamic).days;
    } catch (_) {}

    if (name == null || name.trim().isEmpty) {
      final s = v.toString();
      if (s != 'Instance of Object' && s != 'Instance of _') name = s;
    }
    if (name == null || name.trim().isEmpty) return null;

    return {
      'name': name,
      'goal': (goal is String) ? goal : (goal?.toString() ?? ''),
      'days': (days is Map) ? days : <String, dynamic>{},
      'createdAt': DateTime.now().toIso8601String(),
      'raw': _safeToEncodable(v),
    };
  }

  static String? _pickFirstString(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  static dynamic _safeToEncodable(dynamic v) {
    try {
      if (v is Map || v is List || v is String || v is num || v is bool) {
        return v;
      }
      return {'_string': v.toString()};
    } catch (_) {
      return {'_string': '$v'};
    }
  }

  /// حفظ/تحديث جدول مخصّص باسم فريد (يستبدل إن وُجد نفس الاسم).
  static Future<void> saveCustomPlan(dynamic plan) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final key = _customPlansKey(email);

    final norm = normalizePlan(plan);
    if (norm == null) return;

    final List list = _readList(prefs.getString(key));
    // إزالة أي سجل بنفس الاسم (case-insensitive)
    list.removeWhere((e) =>
        e is Map &&
        (e['name'] ?? '').toString().toLowerCase() ==
            norm['name'].toString().toLowerCase());
    list.add(norm);

    await prefs.setString(key, jsonEncode(list));
  }

  /// قراءة كل الجداول المخصّصة للمستخدم.
  static Future<List<Map<String, dynamic>>> loadCustomPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final key = _customPlansKey(email);

    final List list = _readList(prefs.getString(key));
    // ترتيب بالأحدث أولًا (createdAt)
    list.sort((a, b) {
      final da = _parseDateSafe((a is Map) ? a['createdAt'] : null);
      final db = _parseDateSafe((b is Map) ? b['createdAt'] : null);
      return db.compareTo(da);
    });

    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// حذف جدول مخصّص بالاسم.
  static Future<void> deleteCustomPlan(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final key = _customPlansKey(email);

    final List list = _readList(prefs.getString(key));
    list.removeWhere((e) =>
        e is Map &&
        (e['name'] ?? '').toString().toLowerCase() == name.toLowerCase());

    await prefs.setString(key, jsonEncode(list));
  }

  // ---------- أدوات مساعدة ----------
  static List _readList(String? raw) {
    if (raw == null || raw.isEmpty) return <dynamic>[];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) return parsed;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  static DateTime _parseDateSafe(dynamic s) {
    if (s is String && s.isNotEmpty) {
      try {
        return DateTime.parse(s);
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

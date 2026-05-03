// lib/regimens/keto_guard.dart
// حارس الكيتو: حالة التفعيل + حد الكارب + كارب اليوم + حساب درجة الالتزام + سجل الجلسات

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class KetoGuard {
  // مفاتيح الحالة العامة
  static const _kKeyActive = 'keto_active';
  static const _kKeyLimit  = 'keto_limit';
  static const _kDefaultLimit = 30.0;

  // مفتاح سجل الكيتو
  static const _kKeyLog = 'keto_log'; // List<Map<String,dynamic>>

  // ---------------------------
  // تفعيل / إيقاف النظام + سجل
  // ---------------------------
  static Future<void> startRegimen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyActive, true);

    // حد افتراضي إن ما كان مضبوط
    if (!prefs.containsKey(_kKeyLimit)) {
      await prefs.setDouble(_kKeyLimit, _kDefaultLimit);
    }

    // ضع كنظام نشط عام لكي تظهر الشارة في "رجيمي"
    final model = {
      'id': 'keto',
      'title': 'رجيم الكيتو',
      'goal': 'خفض الكارب',
      'benefits': ['استقرار السكر','تقليل الشهية','اختيارات كاملة الدسم'],
      'risks': ['كيتو فلو مؤقت','غير مناسب لبعض الحالات'],
      'popularFoods': ['بيض/لحوم/أسماك','أفوكادو/زيوت صحية','خضار قليلة الكارب'],
      'dailyCalorieCap': null,
    };
    await prefs.setString('active_regimen', jsonEncode(model));

    // افتح جلسة في السجل إذا لا توجد جلسة مفتوحة
    await _openSessionIfNeeded();
  }

  static Future<void> endRegimen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyActive, false);

    // إن كان النشط هو الكيتو، أزله
    final raw = prefs.getString('active_regimen');
    if (raw != null) {
      try {
        final m = jsonDecode(raw);
        if (m is Map && (m['id']?.toString() == 'keto')) {
          await prefs.remove('active_regimen');
        }
      } catch (_) {}
    }

    // اغلق آخر جلسة مفتوحة مع حفظ نتيجة تقريبية
    final score = await computeAndStoreTodayScore();
    final limit = await carbLimit();
    final carbs = await todayCarbs();
    await _closeOpenSession(
      extra: {
        'score': score,
        'limit': limit,
        'carbs': carbs,
      },
    );
  }

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKeyActive) ?? false;
  }

  // ----------
  // حدّ الكارب
  // ----------
  static Future<double> carbLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kKeyLimit) ?? _kDefaultLimit;
  }

  static Future<void> setCarbLimit(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kKeyLimit, v);
  }

  // --------------
  // كارب اليوم
  // --------------
  static Future<double> todayCarbs() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        (FirebaseAuth.instance.currentUser?.email ?? 'unknown_user');
    final ymd = DateTime.now().toIso8601String().split('T').first;

    // إجماليات اليوم (إن وُجدت)
    final totalsKey = 'kcal_daytotals_${email}_$ymd';
    final rawT = prefs.getString(totalsKey);
    if (rawT != null) {
      try {
        final m = jsonDecode(rawT);
        if (m is Map && m['c'] is num) return (m['c'] as num).toDouble();
      } catch (_) {}
    }

    // أو من قائمة الإدخالات
    final entriesKey = 'intake_entries_${email}_$ymd';
    final rawE = prefs.getString(entriesKey);
    double c = 0.0;
    if (rawE != null) {
      try {
        final list = jsonDecode(rawE);
        if (list is List) {
          for (final e in list) {
            final v = (e is Map) ? e['c'] ?? e['carb'] ?? e['carbs'] : 0;
            if (v is num) c += v.toDouble();
          }
        }
      } catch (_) {}
    }
    return c;
  }

  // -------------------------------
  // درجة الالتزام التقريبية (0..1)
  // -------------------------------
  static Future<double> computeAndStoreTodayScore() async {
    final c = await todayCarbs();
    final limit = await carbLimit();
    if (limit <= 0) return 0.0;
    final ratio = (1.0 - (c / limit)).clamp(0.0, 1.0);

    // بإمكانك حفظها إن رغبت
    final prefs = await SharedPreferences.getInstance();
    final ymd = DateTime.now().toIso8601String().split('T').first;
    await prefs.setDouble('keto_score_$ymd', ratio);
    return ratio;
  }

  // ============
  // سجل الجلسات
  // ============
  static Future<List<Map<String, dynamic>>> getLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKeyLog);
    List<Map<String, dynamic>> log = [];
    if (raw != null) {
      try {
        final l = jsonDecode(raw);
        if (l is List) {
          log = l.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    // رتّب من الأحدث للأقدم حسب start
    log.sort((a, b) {
      final sa = DateTime.tryParse('${a['start']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final sb = DateTime.tryParse('${b['start']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return sb.compareTo(sa);
    });
    return log;
  }

  static Future<void> _openSessionIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final log = await getLog();
    final hasOpen = log.any((e) => e['end'] == null);

    if (hasOpen) return;

    final now = DateTime.now().toIso8601String();
    final newEntry = <String, dynamic>{
      'start': now,
      'end': null,     // لم تُغلق بعد
      // حقول إضافية ستملأ عند الإغلاق
      // 'score': double,
      // 'limit': double,
      // 'carbs': double,
    };

    log.add(newEntry);
    await prefs.setString(_kKeyLog, jsonEncode(log));
  }

  static Future<void> _closeOpenSession({Map<String, dynamic>? extra}) async {
    final prefs = await SharedPreferences.getInstance();
    final log = await getLog();

    // ابحث عن أحدث جلسة مفتوحة (end == null)
    for (int i = 0; i < log.length; i++) {
      final idx = i; // log مرتب الأحدث أولًا
      final e = log[idx];
      if (e['end'] == null) {
        e['end'] = DateTime.now().toIso8601String();
        if (extra != null) {
          e.addAll(extra);
        }
        // اكتب مرة أخرى
        await prefs.setString(_kKeyLog, jsonEncode(log));
        return;
      }
    }
    // إن لم توجد جلسة مفتوحة، لا شيء
  }
}

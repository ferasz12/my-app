// lib/services/end_of_day_cloud_backup_service.dart
// حفظ محلي طوال اليوم + رفع لقطة واحدة للسحابة في نهاية اليوم.
// ملاحظة مهمة: iOS لا يضمن تشغيل التطبيق بالضبط 11:59 إذا كان مقفلاً بالكامل،
// لذلك نحفظ عند 11:59 إذا التطبيق مفتوح، ونحفظ اليوم الفائت تلقائياً عند أول فتح لاحق.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_repository.dart';
import '../shared/session_manager.dart';

class DailyCloudBackupService with WidgetsBindingObserver {
  DailyCloudBackupService._();

  static final DailyCloudBackupService instance = DailyCloudBackupService._();

  Timer? _timer;
  bool _started = false;
  bool _backupInProgress = false;

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
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

  Future<String> _emailKey() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'unknown_user')
        .trim();
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    // فحص بعد فتح التطبيق بدون تعليق الواجهة.
    unawaited(_backupMissedPreviousDays().catchError((_) {}));
    unawaited(_backupTodayIfDue().catchError((_) {}));

    // فحص خفيف كل دقيقة. لا يقرأ Firestore ولا يوقف الواجهة.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_backupTodayIfDue().catchError((_) {}));
      unawaited(_backupMissedPreviousDays().catchError((_) {}));
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  /// نستخدمها فقط كإشارة مستقبلية؛ لا تحفظ في السحابة أثناء اليوم.
  Future<void> markDirty() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _emailKey();
    await prefs.setBool('eod_cloud_dirty_${email}_${_ymd(DateTime.now())}', true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_backupMissedPreviousDays().catchError((_) {}));
      unawaited(_backupTodayIfDue().catchError((_) {}));
      return;
    }

    // إذا المستخدم خرج آخر الليل قبل 11:59، نعطيه فرصة يحفظ لقطة اليوم.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      final now = DateTime.now();
      if (now.hour >= 23 && now.minute >= 50) {
        unawaited(backupDay(_ymd(now), reason: 'late_app_pause').catchError((_) {}));
      }
    }
  }

  Future<void> _backupTodayIfDue() async {
    final now = DateTime.now();
    if (now.hour == 23 && now.minute >= 59) {
      await backupDay(_ymd(now), reason: 'scheduled_2359');
    }
  }

  Future<void> _backupMissedPreviousDays() async {
    final now = DateTime.now();
    // لو التطبيق كان مقفل وقت 11:59، نرفع أمس وأول أمس عند أول فتح.
    for (int i = 1; i <= 2; i++) {
      final d = now.subtract(Duration(days: i));
      await backupDay(_ymd(d), reason: 'missed_previous_day');
    }
  }

  Future<void> backupTodayNow({String reason = 'manual'}) async {
    await backupDay(_ymd(DateTime.now()), reason: reason, force: true);
  }

  Future<void> backupDay(
    String ymd, {
    String reason = 'scheduled',
    bool force = false,
  }) async {
    if (_backupInProgress) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final email = await _emailKey();
    final doneKey = 'eod_cloud_backup_done_${email}_$ymd';
    if (!force && (prefs.getBool(doneKey) ?? false)) return;

    final snapshot = await _buildLocalSnapshot(prefs: prefs, email: email, ymd: ymd);
    if (!(snapshot['hasData'] == true)) return;

    _backupInProgress = true;
    try {
      await AppRepository.writeEndOfDaySnapshot(
        ymd: ymd,
        totals: Map<String, dynamic>.from(snapshot['totals'] as Map),
        entries: List<Map<String, dynamic>>.from(snapshot['entries'] as List),
        meals: List<Map<String, dynamic>>.from(snapshot['meals'] as List),
        waterLiters: _toD(snapshot['waterLiters']),
        steps: (snapshot['steps'] as num?)?.toInt() ?? 0,
        burned: (snapshot['burned'] as num?)?.toInt() ?? 0,
        weightKg: _toD(snapshot['weightKg']),
        reason: reason,
      ).timeout(const Duration(seconds: 10));

      await prefs.setBool(doneKey, true);
      await prefs.setString('eod_cloud_backup_at_${email}_$ymd', DateTime.now().toIso8601String());
      await prefs.setBool('eod_cloud_dirty_${email}_$ymd', false);
    } catch (_) {
      // لا نكسر التطبيق. سيعيد المحاولة عند الفتح التالي أو الدقيقة التالية إذا كان الوقت مناسب.
    } finally {
      _backupInProgress = false;
    }
  }

  Future<Map<String, dynamic>> _buildLocalSnapshot({
    required SharedPreferences prefs,
    required String email,
    required String ymd,
  }) async {
    // السعرات والماكروز
    Map<String, dynamic>? totals = _decodeMap(prefs.getString('kcal_daytotals_${email}_$ymd'));
    final legacyDiet = _decodeMap(prefs.getString('diet_$ymd'));
    totals ??= legacyDiet == null
        ? <String, dynamic>{'k': 0.0, 'p': 0.0, 'c': 0.0, 'f': 0.0}
        : <String, dynamic>{
            'k': _toD(legacyDiet['calories']),
            'p': _toD(legacyDiet['protein']),
            'c': _toD(legacyDiet['carb']),
            'f': _toD(legacyDiet['fat']),
          };

    final entries = _decodeListOfMaps(prefs.getString('intake_entries_${email}_$ymd'));

    // الماء
    double waterLiters = prefs.getDouble('water_${ymd}_$email') ?? 0.0;
    if (waterLiters <= 0) {
      waterLiters = double.tryParse(prefs.getString('water_total_${email}_$ymd') ?? '') ?? 0.0;
    }
    if (waterLiters <= 0) {
      final log = _decodeMap(prefs.getString('water_log_$email')) ?? <String, dynamic>{};
      waterLiters = _toD(log[ymd]);
    }

    // النشاط
    final activity = _decodeMap(prefs.getString('activity_${ymd}_$email')) ?? <String, dynamic>{};
    final steps = (activity['steps'] as num?)?.toInt() ?? 0;
    final burned = (activity['burned'] as num?)?.toInt() ?? 0;

    // الوجبات الحالية: نضيفها فقط إذا اللقطة لليوم الحالي لأنها ليست مؤرشفة لكل يوم.
    final today = _ymd(DateTime.now());
    List<Map<String, dynamic>> meals = <Map<String, dynamic>>[];
    if (ymd == today) {
      final storageKey = await SessionManager.currentStorageKey();
      meals = _decodeListOfMaps(prefs.getString('meals_$storageKey'));
    }

    // الوزن
    double weightKg = 0.0;
    final weightRaw = prefs.getString('weight_log_$email');
    final weightList = _decodeListOfMaps(weightRaw);
    for (final row in weightList) {
      if ((row['date'] ?? '').toString() == ymd) {
        weightKg = _toD(row['kg']);
        break;
      }
    }
    if (weightKg <= 0 && ymd == today) {
      weightKg = prefs.getDouble('current_weight_$email') ??
          prefs.getDouble('weight_$email') ??
          prefs.getDouble('goal_current_$email') ??
          0.0;
    }

    final hasData = _toD(totals['k']) > 0 ||
        _toD(totals['p']) > 0 ||
        _toD(totals['c']) > 0 ||
        _toD(totals['f']) > 0 ||
        entries.isNotEmpty ||
        meals.isNotEmpty ||
        waterLiters > 0 ||
        steps > 0 ||
        burned > 0 ||
        weightKg > 0;

    return {
      'hasData': hasData,
      'totals': {
        'k': _toD(totals['k'] ?? totals['calories']),
        'p': _toD(totals['p'] ?? totals['protein']),
        'c': _toD(totals['c'] ?? totals['carb'] ?? totals['carbs']),
        'f': _toD(totals['f'] ?? totals['fat']),
      },
      'entries': entries,
      'meals': meals,
      'waterLiters': waterLiters,
      'steps': steps,
      'burned': burned,
      'weightKg': weightKg,
    };
  }
}

// lib/services/health_data_sync_service.dart
// قراءة Apple Health / Google Health بشكل آمن وموسع.
// مهم: القراءة المباشرة من Health لا تستخدم Firestore، والكاش هنا محلي فقط
// حتى تبقى صفحة "صحتي" سريعة وما ترفع تكلفة Firebase.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HealthDataSyncResult {
  const HealthDataSyncResult({
    required this.ymd,
    required this.steps,
    required this.activeEnergyKcal,
    required this.metrics,
  });

  final String ymd;
  final int steps;
  final int activeEnergyKcal;
  final Map<String, dynamic> metrics;
}

class HealthDataSyncService {
  HealthDataSyncService._();

  static final Health _health = Health();

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _typeName(HealthDataType t) {
    try {
      return (t as dynamic).name.toString();
    } catch (_) {
      return t.toString().split('.').last;
    }
  }

  static HealthDataType? _typeByName(String name) {
    for (final t in HealthDataType.values) {
      if (_typeName(t) == name) return t;
    }
    return null;
  }

  static List<HealthDataType> _typesByNames(Iterable<String> names) {
    final seen = <String>{};
    final out = <HealthDataType>[];
    for (final name in names) {
      final t = _typeByName(name);
      if (t == null) continue;
      final n = _typeName(t);
      if (seen.add(n)) out.add(t);
    }
    return out;
  }

  static Future<void> _configure() async {
    try {
      final cfg = (_health as dynamic).configure();
      if (cfg is Future) await cfg.timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  static double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();

    try {
      final nv = (v as dynamic).numericValue;
      if (nv is num) return nv.toDouble();
    } catch (_) {}

    try {
      final vv = (v as dynamic).value;
      if (vv is num) return vv.toDouble();
    } catch (_) {}

    try {
      final e = (v as dynamic).totalEnergyBurned;
      if (e is num) return e.toDouble();
    } catch (_) {}

    try {
      final m = (v as dynamic).toJson();
      if (m is Map) {
        for (final key in const [
          'numericValue',
          'value',
          'totalEnergyBurned',
          'totalDistance',
        ]) {
          final x = m[key];
          if (x is num) return x.toDouble();
          final p = double.tryParse('$x'.replaceAll(',', '.'));
          if (p != null) return p;
        }
      }
    } catch (_) {}

    return double.tryParse('$v'.replaceAll(',', '.')) ?? 0.0;
  }

  static double _durationMinutes(HealthDataPoint p) {
    try {
      final m = p.dateTo.difference(p.dateFrom).inSeconds / 60.0;
      if (m.isFinite && m > 0) return m;
    } catch (_) {}
    return 0.0;
  }

  static void _add(Map<String, double> m, String k, double v) {
    if (!v.isFinite || v <= 0) return;
    m[k] = (m[k] ?? 0.0) + v;
  }

  static void _avgBucket(Map<String, List<double>> m, String k, double v) {
    if (!v.isFinite || v <= 0) return;
    (m[k] ??= <double>[]).add(v);
  }

  static Map<String, double> _averages(Map<String, List<double>> buckets) {
    final out = <String, double>{};
    for (final e in buckets.entries) {
      if (e.value.isEmpty) continue;
      out[e.key] = e.value.reduce((a, b) => a + b) / e.value.length;
    }
    return out;
  }

  static double _latestValue(List<HealthDataPoint> points, String typeName) {
    HealthDataPoint? best;
    for (final p in points) {
      if (_typeName(p.type) != typeName) continue;
      if (best == null || p.dateTo.isAfter(best.dateTo)) best = p;
    }
    return best == null ? 0.0 : _toD(best.value);
  }

  static const Map<String, List<String>> _typeGroups = <String, List<String>>{
    'activity': <String>[
      'STEPS',
      'ACTIVE_ENERGY_BURNED',
      'BASAL_ENERGY_BURNED',
      'DISTANCE_WALKING_RUNNING',
      'DISTANCE_CYCLING',
      'DISTANCE_SWIMMING',
      'EXERCISE_TIME',
      'WORKOUT',
      'FLIGHTS_CLIMBED',
      'SWIMMING_STROKE_COUNT',
      'WHEELCHAIR_PUSHES',
    ],
    'sleep': <String>[
      'SLEEP_ASLEEP',
      'SLEEP_ASLEEP_CORE',
      'SLEEP_ASLEEP_DEEP',
      'SLEEP_ASLEEP_REM',
      'SLEEP_LIGHT',
      'SLEEP_DEEP',
      'SLEEP_REM',
      'SLEEP_IN_BED',
      'SLEEP_AWAKE',
    ],
    'vitals': <String>[
      'HEART_RATE',
      'RESTING_HEART_RATE',
      'WALKING_HEART_RATE',
      'HEART_RATE_VARIABILITY_SDNN',
      'RESPIRATORY_RATE',
      'BLOOD_OXYGEN',
      'BODY_TEMPERATURE',
      'BASAL_BODY_TEMPERATURE',
      'VO2MAX',
      'BLOOD_GLUCOSE',
      'BLOOD_PRESSURE_SYSTOLIC',
      'BLOOD_PRESSURE_DIASTOLIC',
    ],
    'body': <String>[
      'BODY_MASS',
      'HEIGHT',
      'BODY_FAT_PERCENTAGE',
      'LEAN_BODY_MASS',
      'WAIST_CIRCUMFERENCE',
    ],
    'nutrition': <String>[
      'WATER',
      'DIETARY_ENERGY_CONSUMED',
      'DIETARY_PROTEIN_CONSUMED',
      'DIETARY_CARBS_CONSUMED',
      'DIETARY_FATS_CONSUMED',
      'DIETARY_FIBER',
      'DIETARY_SUGAR',
      'DIETARY_CAFFEINE',
      'MINDFULNESS',
      'MINDFULNESS_MINUTES',
    ],
  };

  /// قراءة مباشرة من Apple Health / Health Connect بدون الاعتماد على Firestore.
  /// تقسم الصلاحيات إلى مجموعات حتى لو فشل نوع واحد لا يعطل النوم أو الخطوات كلها.
  static Future<HealthDataSyncResult> fetchTodayDirect({
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return fetchRangeDirect(start: start, end: now, timeout: timeout);
  }

  static Future<HealthDataSyncResult> fetchRangeDirect({
    required DateTime start,
    required DateTime end,
    Duration timeout = const Duration(seconds: 18),
  }) async {
    await _configure();

    final allPoints = <HealthDataPoint>[];
    final requestedTypes = <String>[];
    final loadedGroups = <String>[];
    final failedGroups = <String>[];

    for (final entry in _typeGroups.entries) {
      final types = _typesByNames(entry.value);
      if (types.isEmpty) continue;
      requestedTypes.addAll(types.map(_typeName));
      final points = await _fetchGroupPoints(
        groupName: entry.key,
        types: types,
        start: start,
        end: end,
        timeout: timeout,
      );
      if (points == null) {
        failedGroups.add(entry.key);
      } else {
        loadedGroups.add(entry.key);
        allPoints.addAll(points);
      }
    }

    // احتياط: إذا فشلت المجموعات كلها، حاول الخطوات والمحروق فقط.
    if (allPoints.isEmpty) {
      final core = _typesByNames(const ['STEPS', 'ACTIVE_ENERGY_BURNED']);
      final points = await _fetchGroupPoints(
        groupName: 'core',
        types: core,
        start: start,
        end: end,
        timeout: const Duration(seconds: 8),
      );
      if (points != null) {
        loadedGroups.add('core');
        allPoints.addAll(points);
      }
    }

    final metrics = _aggregate(allPoints);
    final activity = Map<String, dynamic>.from(metrics['activity'] as Map? ?? const {});
    final steps = _toD(activity['steps']).round();
    final activeEnergy = _toD(activity['activeEnergyKcal']).round();

    final payload = <String, dynamic>{
      ...metrics,
      'date': _ymd(start),
      'updatedAtIso': DateTime.now().toIso8601String(),
      'source': 'apple_health_direct',
      'requestedTypes': requestedTypes.toSet().toList(),
      'loadedGroups': loadedGroups,
      'failedGroups': failedGroups,
      'pointsCount': allPoints.length,
    };

    return HealthDataSyncResult(
      ymd: _ymd(start),
      steps: steps,
      activeEnergyKcal: activeEnergy,
      metrics: payload,
    );
  }

  static Future<List<HealthDataPoint>?> _fetchGroupPoints({
    required String groupName,
    required List<HealthDataType> types,
    required DateTime start,
    required DateTime end,
    required Duration timeout,
  }) async {
    if (types.isEmpty) return <HealthDataPoint>[];
    try {
      final granted = await _health.requestAuthorization(types).timeout(timeout);
      if (!granted) return <HealthDataPoint>[];
      final points = await _health
          .getHealthDataFromTypes(types: types, startTime: start, endTime: end)
          .timeout(timeout);
      return points;
    } catch (_) {
      // بعض أجهزة iOS ترفض نوع معين داخل المجموعة. نجرب كل نوع لحاله بدل إسقاط المجموعة كاملة.
      final out = <HealthDataPoint>[];
      var hadAnySuccess = false;
      for (final t in types) {
        try {
          final granted = await _health.requestAuthorization(<HealthDataType>[t])
              .timeout(const Duration(seconds: 6));
          if (!granted) {
            hadAnySuccess = true;
            continue;
          }
          final points = await _health
              .getHealthDataFromTypes(types: <HealthDataType>[t], startTime: start, endTime: end)
              .timeout(const Duration(seconds: 6));
          hadAnySuccess = true;
          out.addAll(points);
        } catch (_) {}
      }
      return hadAnySuccess ? out : null;
    }
  }

  static Map<String, dynamic> _aggregate(List<HealthDataPoint> points) {
    final totals = <String, double>{};
    final avgs = <String, List<double>>{};
    final typeTotals = <String, double>{};
    final typeCounts = <String, int>{};
    final sleep = <String, double>{};

    int workouts = 0;
    double workoutMinutes = 0.0;

    for (final p in points) {
      final name = _typeName(p.type);
      final val = _toD(p.value);
      final minutes = _durationMinutes(p);

      typeCounts[name] = (typeCounts[name] ?? 0) + 1;
      if (val > 0) _add(typeTotals, name, val);

      switch (name) {
        case 'STEPS':
          _add(totals, 'steps', val);
          break;
        case 'ACTIVE_ENERGY_BURNED':
          _add(totals, 'activeEnergyKcal', val);
          break;
        case 'BASAL_ENERGY_BURNED':
          _add(totals, 'basalEnergyKcal', val);
          break;
        case 'DISTANCE_WALKING_RUNNING':
          _add(totals, 'walkingRunningDistanceMeters', val);
          break;
        case 'DISTANCE_CYCLING':
          _add(totals, 'cyclingDistanceMeters', val);
          break;
        case 'DISTANCE_SWIMMING':
          _add(totals, 'swimmingDistanceMeters', val);
          break;
        case 'EXERCISE_TIME':
          _add(totals, 'exerciseMinutes', val > 0 ? val : minutes);
          break;
        case 'WORKOUT':
          workouts++;
          workoutMinutes += minutes;
          break;
        case 'FLIGHTS_CLIMBED':
          _add(totals, 'flightsClimbed', val);
          break;
        case 'SWIMMING_STROKE_COUNT':
          _add(totals, 'swimmingStrokeCount', val);
          break;
        case 'WHEELCHAIR_PUSHES':
          _add(totals, 'wheelchairPushes', val);
          break;
        case 'WATER':
          _add(totals, 'waterLiters', val);
          break;
        case 'DIETARY_ENERGY_CONSUMED':
          _add(totals, 'dietaryEnergyKcal', val);
          break;
        case 'DIETARY_PROTEIN_CONSUMED':
          _add(totals, 'dietaryProteinG', val);
          break;
        case 'DIETARY_CARBS_CONSUMED':
          _add(totals, 'dietaryCarbsG', val);
          break;
        case 'DIETARY_FATS_CONSUMED':
          _add(totals, 'dietaryFatsG', val);
          break;
        case 'DIETARY_FIBER':
          _add(totals, 'dietaryFiberG', val);
          break;
        case 'DIETARY_SUGAR':
          _add(totals, 'dietarySugarG', val);
          break;
        case 'DIETARY_CAFFEINE':
          _add(totals, 'dietaryCaffeineMg', val);
          break;
        case 'MINDFULNESS':
        case 'MINDFULNESS_MINUTES':
          _add(totals, 'mindfulnessMinutes', val > 0 ? val : minutes);
          break;
        case 'HEART_RATE':
          _avgBucket(avgs, 'heartRateBpm', val);
          break;
        case 'RESTING_HEART_RATE':
          _avgBucket(avgs, 'restingHeartRateBpm', val);
          break;
        case 'WALKING_HEART_RATE':
          _avgBucket(avgs, 'walkingHeartRateBpm', val);
          break;
        case 'HEART_RATE_VARIABILITY_SDNN':
          _avgBucket(avgs, 'hrvSdnnMs', val);
          break;
        case 'RESPIRATORY_RATE':
          _avgBucket(avgs, 'respiratoryRate', val);
          break;
        case 'BLOOD_OXYGEN':
          _avgBucket(avgs, 'bloodOxygen', val);
          break;
        case 'BODY_TEMPERATURE':
          _avgBucket(avgs, 'bodyTemperatureC', val);
          break;
        case 'BASAL_BODY_TEMPERATURE':
          _avgBucket(avgs, 'basalBodyTemperatureC', val);
          break;
        case 'VO2MAX':
          _avgBucket(avgs, 'vo2max', val);
          break;
        case 'BLOOD_GLUCOSE':
          _avgBucket(avgs, 'bloodGlucose', val);
          break;
        case 'BLOOD_PRESSURE_SYSTOLIC':
          _avgBucket(avgs, 'bloodPressureSystolic', val);
          break;
        case 'BLOOD_PRESSURE_DIASTOLIC':
          _avgBucket(avgs, 'bloodPressureDiastolic', val);
          break;
        case 'SLEEP_ASLEEP':
          _add(sleep, 'asleepHours', minutes / 60.0);
          break;
        case 'SLEEP_ASLEEP_CORE':
        case 'SLEEP_LIGHT':
          _add(sleep, 'lightOrCoreHours', minutes / 60.0);
          _add(sleep, 'asleepHours', minutes / 60.0);
          break;
        case 'SLEEP_ASLEEP_DEEP':
        case 'SLEEP_DEEP':
          _add(sleep, 'deepHours', minutes / 60.0);
          _add(sleep, 'asleepHours', minutes / 60.0);
          break;
        case 'SLEEP_ASLEEP_REM':
        case 'SLEEP_REM':
          _add(sleep, 'remHours', minutes / 60.0);
          _add(sleep, 'asleepHours', minutes / 60.0);
          break;
        case 'SLEEP_IN_BED':
          _add(sleep, 'inBedHours', minutes / 60.0);
          break;
        case 'SLEEP_AWAKE':
          _add(sleep, 'awakeHours', minutes / 60.0);
          break;
      }
    }

    if (workouts > 0) {
      totals['workouts'] = workouts.toDouble();
      totals['workoutMinutes'] = workoutMinutes;
    }

    final avgMap = _averages(avgs);
    final body = <String, dynamic>{
      'bodyMassKg': _latestValue(points, 'BODY_MASS'),
      'heightCm': _latestValue(points, 'HEIGHT'),
      'bodyFatPercent': _latestValue(points, 'BODY_FAT_PERCENTAGE'),
      'leanBodyMassKg': _latestValue(points, 'LEAN_BODY_MASS'),
      'waistCircumferenceCm': _latestValue(points, 'WAIST_CIRCUMFERENCE'),
    }..removeWhere((_, v) => v is num && v <= 0);

    final totalDistanceMeters =
        (totals['walkingRunningDistanceMeters'] ?? 0) +
        (totals['cyclingDistanceMeters'] ?? 0) +
        (totals['swimmingDistanceMeters'] ?? 0);

    return <String, dynamic>{
      'activity': {
        ...totals,
        'totalDistanceMeters': totalDistanceMeters,
        'walkingRunningDistanceKm': (totals['walkingRunningDistanceMeters'] ?? 0) / 1000.0,
        'totalDistanceKm': totalDistanceMeters / 1000.0,
        'totalEnergyKcal':
            (totals['activeEnergyKcal'] ?? 0) + (totals['basalEnergyKcal'] ?? 0),
      }..removeWhere((_, v) => v is num && v <= 0),
      'sleep': sleep..removeWhere((_, v) => v <= 0),
      'vitals': avgMap,
      'body': body,
      'rawTypeTotals': typeTotals,
      'rawTypeCounts': typeCounts,
    };
  }

  /// قراءة مباشرة ثم حفظ محليًا فقط حتى تبقى الصفحات القديمة متوافقة.
  /// لا يكتب هذا الميثود أي شيء في Firestore.
  static Future<HealthDataSyncResult> fetchTodayAndCache({
    Duration timeout = const Duration(seconds: 18),
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final email = prefs.getString('currentEmail') ?? user?.email ?? 'unknown_user';
    final now = DateTime.now();
    final ymd = _ymd(now);
    final healthKey = 'health_${ymd}_$email';
    final activityKey = 'activity_${ymd}_$email';
    final lastKey = 'health_last_fetch_${email}_$ymd';

    if (!force) {
      final lastRaw = prefs.getString(lastKey);
      final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
      if (last != null && now.difference(last) < const Duration(minutes: 20)) {
        final cached = _decodeMap(prefs.getString(healthKey));
        final act = _decodeMap(prefs.getString(activityKey));
        final cachedActivity = Map<String, dynamic>.from(
          cached['activity'] as Map? ?? const {},
        );
        return HealthDataSyncResult(
          ymd: ymd,
          steps: _toD(act['steps'] ?? cachedActivity['steps']).toInt(),
          activeEnergyKcal: _toD(act['burned'] ?? cachedActivity['activeEnergyKcal']).toInt(),
          metrics: cached,
        );
      }
    }

    final result = await fetchTodayDirect(timeout: timeout);
    final activity = Map<String, dynamic>.from(result.metrics['activity'] as Map? ?? const {});
    final sleep = Map<String, dynamic>.from(result.metrics['sleep'] as Map? ?? const {});
    final vitals = Map<String, dynamic>.from(result.metrics['vitals'] as Map? ?? const {});

    await prefs.setString(healthKey, jsonEncode(result.metrics));
    await prefs.setString(
      activityKey,
      jsonEncode({
        'steps': result.steps,
        'burned': result.activeEnergyKcal,
        'distanceMeters': _toD(activity['totalDistanceMeters']),
        'distanceKm': _toD(activity['totalDistanceKm']),
        'walkingRunningDistanceKm': _toD(activity['walkingRunningDistanceKm']),
        'exerciseMinutes': _toD(activity['exerciseMinutes']),
        'workouts': _toD(activity['workouts']).toInt(),
        'workoutMinutes': _toD(activity['workoutMinutes']),
        'sleepHours': _toD(sleep['asleepHours']),
        'heartRateBpm': _toD(vitals['heartRateBpm']),
        'restingHeartRateBpm': _toD(vitals['restingHeartRateBpm']),
        'updatedAtIso': result.metrics['updatedAtIso'],
      }),
    );
    await prefs.setString(lastKey, now.toIso8601String());

    return result;
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

// lib/data/app_repository.dart
// واجهة موحدة للقراءة/الكتابة على فايرستور لتجميع كل عمليات التخزين هنا.
// تعتمد على FirebaseAuth للحصول على uid وتخزن بيانات اليوم داخل
// users/{uid}/days/{YYYY-MM-DD}/...

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppRepository {
  AppRepository._();

  // ===== Helpers =====
  static String _requireUid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated user – login required before writing.');
    }
    return user.uid; // non-nullable
  }

  static DocumentReference<Map<String, dynamic>> _userDoc() {
    final uid = _requireUid();
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static DocumentReference<Map<String, dynamic>> _dayDoc(String ymd) {
    return _userDoc().collection('days').doc(ymd);
  }

  static Future<void> _ensureUserMeta() async {
    // تأكد أن وثيقة المستخدم موجودة (merge)
    final user = FirebaseAuth.instance.currentUser;
    await _userDoc().set({
      'uid': _requireUid(),
      'email': user?.email,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  static void _touchUserMetaInBackground() {
    unawaited(_ensureUserMeta().catchError((_) {}));
  }

  static double _toD(dynamic v) => (v is num) ? v.toDouble() : 0.0;

  // ===== Activity (steps/burned) =====
  static Future<void> writeActivity({
    required String ymd,
    required int steps,
    required int burned,
  }) async {
    _touchUserMetaInBackground();
    await _dayDoc(ymd).set({
      'activity': {
        'steps': steps,
        'burned': burned,
        'updatedAt': Timestamp.now(),
      }
    }, SetOptions(merge: true));
  }

  // ===== Water =====
  static Future<void> writeWaterLiters({
    required String ymd,
    required double liters,
  }) async {
    _touchUserMetaInBackground();
    await _dayDoc(ymd).set({
      'water': {
        'liters': liters,
        'updatedAt': Timestamp.now(),
      }
    }, SetOptions(merge: true));
  }

  // ===== Meals (للعرض السريع) =====
  static Future<void> writeMeals({
    required String ymd,
    required List<Map<String, dynamic>> meals,
  }) async {
    _touchUserMetaInBackground();
    await _dayDoc(ymd).set({
      'meals': meals,
      'mealsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // ===== Entries & Totals =====
  // يحفظ عناصر الاستهلاك التفصيلية + المجاميع لليوم
  static Future<void> writeEntriesAndTotals({
    required String ymd,
    required List<Map<String, dynamic>> entries,
    required Map<String, dynamic> totals, // {k,p,c,f}
  }) async {
    _touchUserMetaInBackground();
    await _dayDoc(ymd).set({
      'intake': {
        'entries': entries,
        'totals': {
          'k': _toD(totals['k']),
          'p': _toD(totals['p']),
          'c': _toD(totals['c']),
          'f': _toD(totals['f']),
        },
        'updatedAt': Timestamp.now(),
      }
    }, SetOptions(merge: true));
  }

  // ===== Rewards (Pending/Resolve) =====
  // يخزن مكافآت اليوم المعلّقة لعرض Sheet المطالبة
  static Future<void> putPendingRewards({
    required String ymd,
    required List<Map<String, dynamic>> pending, // [{id,points,message}]
  }) async {
    _touchUserMetaInBackground();
    await _dayDoc(ymd).set({
      'rewards': {
        'pending': pending,
        'resolved': false,
        'claimed': null,
        'awardedPoints': 0,
        'updatedAt': Timestamp.now(),
      }
    }, SetOptions(merge: true));
  }

  // عند تجميع (claim=true) أو رفض (claim=false)
  static Future<void> markRewardsResolved({
    required String ymd,
    required bool claimed,
    required int awardedPoints,
  }) async {
    _touchUserMetaInBackground();
    final dayRef = _dayDoc(ymd);
    final userRef = _userDoc();

    final batch = FirebaseFirestore.instance.batch();

    // حدّث اليوم
    batch.set(dayRef, {
      'rewards': {
        'pending': [], // لم تعد معلّقة
        'resolved': true,
        'claimed': claimed,
        'awardedPoints': awardedPoints,
        'resolvedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      }
    }, SetOptions(merge: true));

    // زِد النقاط فقط إذا تم المطالبة فعلاً
    final inc = claimed ? (awardedPoints.clamp(0, 1 << 30)) : 0;
    if (inc > 0) {
      batch.set(userRef, {
        'meta': {
          'totalAwardedPoints': FieldValue.increment(inc),
          'lastRewardsResolvedAt': Timestamp.now(),
        }
      }, SetOptions(merge: true));
    } else {
      // حتى لو ما زدنا نقاط، حدّث آخر وقت معالجة
      batch.set(userRef, {
        'meta': {
          'lastRewardsResolvedAt': Timestamp.now(),
        }
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }



  // ===== Restore / read helpers =====
  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static Future<Map<String, dynamic>?> readDay(String ymd) async {
    try {
      final snap = await _dayDoc(ymd)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      final data = snap.data();
      if (data == null) return null;
      return _normalizeDayData(ymd, data);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> readDays({int limit = 90}) async {
    try {
      final q = _userDoc()
          .collection('days')
          .orderBy(FieldPath.documentId, descending: true)
          .limit(limit);
      final snap = await q
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      final days = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        days.add(_normalizeDayData(d.id, d.data()));
      }
      days.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
      return days;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Map<String, dynamic> _normalizeDayData(
    String ymd,
    Map<String, dynamic> data,
  ) {
    final intake = _asMap(data['intake']) ?? <String, dynamic>{};
    final totals = _asMap(intake['totals']) ?? <String, dynamic>{};
    final water = _asMap(data['water']) ?? <String, dynamic>{};
    final activity = _asMap(data['activity']) ?? <String, dynamic>{};
    final tracking = _asMap(data['tracking']) ?? <String, dynamic>{};

    final rawEntries = intake['entries'];
    final entries = rawEntries is List
        ? rawEntries.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    final rawMeals = data['meals'];
    final meals = rawMeals is List
        ? rawMeals.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    return {
      'date': ymd,
      'intake': {
        'entries': entries,
        'totals': {
          'k': _toD(totals['k']),
          'p': _toD(totals['p']),
          'c': _toD(totals['c']),
          'f': _toD(totals['f']),
        },
      },
      'water': {
        'liters': _toD(water['liters']),
      },
      'activity': {
        'steps': ((activity['steps'] as num?) ?? 0).toInt(),
        'burned': ((activity['burned'] as num?) ?? 0).toInt(),
      },
      'tracking': {
        'weightKg': _toD(tracking['weightKg']),
      },
      'meals': meals,
    };
  }


  static Future<void> clearDayIntake({required String ymd}) async {
    try {
      _touchUserMetaInBackground();
      await _dayDoc(ymd).set({
        'intake': {
          'entries': [],
          'totals': {'k': 0.0, 'p': 0.0, 'c': 0.0, 'f': 0.0},
          'updatedAt': Timestamp.now(),
          'cleared': true,
        },
        'meals': [],
        'mealsUpdatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ===== Weight tracking =====
  static Future<void> writeWeightKg({
    required String ymd,
    required double kg,
  }) async {
    if (kg <= 0) return;
    _touchUserMetaInBackground();
    await _dayDoc(ymd).set({
      'tracking': {
        'weightKg': kg,
        'updatedAt': Timestamp.now(),
      },
      'currentWeightKg': kg,
    }, SetOptions(merge: true));
    await _userDoc().set({
      'currentWeightKg': kg,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  static Future<Map<String, double>> readWeightLogs({int limit = 120}) async {
    final out = <String, double>{};
    try {
      final days = await readDays(limit: limit);
      for (final d in days) {
        final ymd = (d['date'] ?? '').toString();
        final tracking = _asMap(d['tracking']) ?? <String, dynamic>{};
        final kg = _toD(tracking['weightKg']);
        if (ymd.isNotEmpty && kg > 0) out[ymd] = kg;
      }

      // fallback: لو المستخدم عنده وزن محفوظ في جذر وثيقة المستخدم فقط
      final root = await _userDoc()
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      final data = root.data() ?? <String, dynamic>{};
      final rootKg = _toD(data['currentWeightKg']);
      if (rootKg > 0) {
        final today = DateTime.now().toIso8601String().split('T').first;
        out.putIfAbsent(today, () => rootKg);
      }
    } catch (_) {}
    return out;
  }

  // ===== (اختياري) ستريم نقاط اليوم — غير مستخدم إلا إذا استدعي من الواجهة =====
  static Stream<int> todayAwardedPointsStream() {
    try {
      final _ = _requireUid(); // للتأكد من تسجيل الدخول
      final ymd = DateTime.now().toIso8601String().split('T').first;
      return _dayDoc(ymd).snapshots().map((snap) {
        final data = snap.data() ?? <String, dynamic>{};
        final rewards = (data['rewards'] as Map<String, dynamic>?) ?? {};
        return ((rewards['awardedPoints'] as num?) ?? 0).toInt();
      });
    } catch (_) {
      // في حال عدم تسجيل الدخول، نرجّع ستريم فاضي
      return const Stream<int>.empty();
    }
  }
}

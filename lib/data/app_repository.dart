// lib/data/app_repository.dart
// حفظ محلي طوال اليوم + رفع لقطة واحدة في نهاية اليوم.
// ملاحظة: دوال write اليومية القديمة أصبحت لا تعمل على الشبكة حتى لا تسبب تعليق.
// الرفع الحقيقي يتم عبر AppRepository.writeEndOfDaySnapshot من DailyCloudBackupService.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppRepository {
  AppRepository._();

  static String _requireUid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated user – login required before writing.');
    }
    return user.uid;
  }

  static DocumentReference<Map<String, dynamic>> _userDoc() {
    return FirebaseFirestore.instance.collection('users').doc(_requireUid());
  }

  static DocumentReference<Map<String, dynamic>> _dayDoc(String ymd) {
    return _userDoc().collection('days').doc(ymd);
  }

  static double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static Future<void> _ensureUserMeta() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _userDoc().set({
      'uid': user.uid,
      'email': user.email,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  static void _touchUserMetaInBackground() {
    unawaited(_ensureUserMeta().catchError((_) {}));
  }

  // ---------------------------------------------------------------------------
  // دوال الكتابة اليومية القديمة: أصبحت No-op حتى لا يصير أي اتصال Firestore
  // أثناء استخدام التطبيق. لا تغير التواقيع حتى ما ينكسر أي ملف يستدعيها.
  // ---------------------------------------------------------------------------

  static Future<void> writeActivity({
    required String ymd,
    required int steps,
    required int burned,
  }) async {}

  static Future<void> writeWaterLiters({
    required String ymd,
    required double liters,
  }) async {}

  static Future<void> writeMeals({
    required String ymd,
    required List<Map<String, dynamic>> meals,
  }) async {}

  static Future<void> writeEntriesAndTotals({
    required String ymd,
    required List<Map<String, dynamic>> entries,
    required Map<String, dynamic> totals,
  }) async {}

  static Future<void> clearDayIntake({required String ymd}) async {}

  static Future<void> writeWeightKg({
    required String ymd,
    required double kg,
  }) async {}

  // ---------------------------------------------------------------------------
  // الرفع الحقيقي الوحيد: لقطة نهاية اليوم.
  // ---------------------------------------------------------------------------

  static Future<void> writeEndOfDaySnapshot({
    required String ymd,
    required Map<String, dynamic> totals,
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> meals,
    required double waterLiters,
    required int steps,
    required int burned,
    required double weightKg,
    String reason = 'scheduled',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _touchUserMetaInBackground();

    final now = Timestamp.now();
    final dayPayload = <String, dynamic>{
      'date': ymd,
      'intake': {
        'entries': entries,
        'totals': {
          'k': _toD(totals['k'] ?? totals['calories']),
          'p': _toD(totals['p'] ?? totals['protein']),
          'c': _toD(totals['c'] ?? totals['carb'] ?? totals['carbs']),
          'f': _toD(totals['f'] ?? totals['fat']),
        },
        'updatedAt': now,
      },
      'water': {
        'liters': waterLiters < 0 ? 0.0 : waterLiters,
        'updatedAt': now,
      },
      'activity': {
        'steps': steps < 0 ? 0 : steps,
        'burned': burned < 0 ? 0 : burned,
        'updatedAt': now,
      },
      'meals': meals,
      'mealsUpdatedAt': now,
      'endOfDayBackup': {
        'savedAt': now,
        'reason': reason,
        'schema': 2,
      },
      'updatedAt': now,
    };

    if (weightKg > 0) {
      dayPayload['tracking'] = {
        'weightKg': weightKg,
        'updatedAt': now,
      };
      dayPayload['currentWeightKg'] = weightKg;
    }

    await _dayDoc(ymd).set(dayPayload, SetOptions(merge: true));

    if (weightKg > 0) {
      await _userDoc().set({
        'currentWeightKg': weightKg,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
  }

  // ---------------------------------------------------------------------------
  // القراءة من السحابة: معطلة من الواجهات حتى لا يتأخر التطبيق.
  // لاحقاً يمكن نسوي شاشة "استرجاع من السحابة" بزر يدوي.
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> readDay(String ymd) async => null;

  static Future<List<Map<String, dynamic>>> readDays({int limit = 90}) async {
    return <Map<String, dynamic>>[];
  }

  static Future<Map<String, double>> readWeightLogs({int limit = 120}) async {
    return <String, double>{};
  }

  // ---------------------------------------------------------------------------
  // Rewards تركناها كما هي لأنها ليست سبب تعليق سجل السعرات، وتعمل بالخلفية غالباً.
  // ---------------------------------------------------------------------------

  static Future<void> putPendingRewards({
    required String ymd,
    required List<Map<String, dynamic>> pending,
  }) async {
    try {
      _touchUserMetaInBackground();
      await _dayDoc(ymd).set({
        'rewards': {
          'pending': pending,
          'resolved': false,
          'claimed': null,
          'awardedPoints': 0,
          'updatedAt': Timestamp.now(),
        }
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static Future<void> markRewardsResolved({
    required String ymd,
    required bool claimed,
    required int awardedPoints,
  }) async {
    try {
      _touchUserMetaInBackground();
      final dayRef = _dayDoc(ymd);
      final userRef = _userDoc();
      final now = Timestamp.now();

      final batch = FirebaseFirestore.instance.batch();
      batch.set(dayRef, {
        'rewards': {
          'pending': [],
          'resolved': true,
          'claimed': claimed,
          'awardedPoints': awardedPoints,
          'resolvedAt': now,
          'updatedAt': now,
        }
      }, SetOptions(merge: true));

      final inc = claimed ? awardedPoints.clamp(0, 1 << 30) : 0;
      batch.set(userRef, {
        'meta': {
          if (inc > 0) 'totalAwardedPoints': FieldValue.increment(inc),
          'lastRewardsResolvedAt': now,
        }
      }, SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static Stream<int> todayAwardedPointsStream() {
    try {
      final _ = _requireUid();
      final ymd = DateTime.now().toIso8601String().split('T').first;
      return _dayDoc(ymd).snapshots().map((snap) {
        final data = snap.data() ?? <String, dynamic>{};
        final rewards = (data['rewards'] as Map<String, dynamic>?) ?? {};
        return ((rewards['awardedPoints'] as num?) ?? 0).toInt();
      });
    } catch (_) {
      return const Stream<int>.empty();
    }
  }
}

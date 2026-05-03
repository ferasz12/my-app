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

  static double _toD(dynamic v) => (v is num) ? v.toDouble() : 0.0;

  // ===== Activity (steps/burned) =====
  static Future<void> writeActivity({
    required String ymd,
    required int steps,
    required int burned,
  }) async {
    await _ensureUserMeta();
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
    await _ensureUserMeta();
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
    await _ensureUserMeta();
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
    await _ensureUserMeta();
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
    await _ensureUserMeta();
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
    await _ensureUserMeta();
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

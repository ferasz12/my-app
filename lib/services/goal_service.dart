import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/weight_goal.dart';

/// GoalService (Legacy Source of Truth)
/// - يقرأ/يكتب weightGoal داخل users/{uid} (الجذر)
/// - يسمح بـ fallback مؤقت من users/{uid}/meta/goal فقط للمهاجرة (ثم ينسخه للجذر مرة واحدة)
class GoalService {
  static DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  static DocumentReference<Map<String, dynamic>> _metaGoalRef(String uid) =>
      FirebaseFirestore.instance.doc('users/$uid/meta/goal');

  static Future<WeightGoal?> getGoal(String uid) async {
    // 1) اقرأ من الجذر أولاً
    final rootSnap = await _userRef(uid).get();
    final root = rootSnap.data();
    final wg = root?['weightGoal'];
    if (wg is Map) {
      try {
        return WeightGoal.fromMap(Map<String, dynamic>.from(wg as Map));
      } catch (_) {
        // تجاهل
      }
    }

    // 2) fallback مؤقت: اقرأ من meta/goal ثم انسخه للجذر مرة واحدة
    try {
      final metaSnap = await _metaGoalRef(uid).get();
      final meta = metaSnap.data();
      if (meta != null && meta.isNotEmpty) {
        // محاولة بناء الهدف
        WeightGoal? goal;
        try {
          goal = WeightGoal.fromMap(Map<String, dynamic>.from(meta));
        } catch (_) {
          goal = null;
        }

        final now = Timestamp.now();
        await _userRef(uid).set({
          'weightGoal': meta,
          // mirror لو كانت موجودة في الماب
          if (meta['currentWeight'] is num)
            'currentWeightKg': (meta['currentWeight'] as num).toDouble(),
          if (meta['targetWeight'] is num)
            'targetWeightKg': (meta['targetWeight'] as num).toDouble(),
          if (meta['targetDate'] is Timestamp) 'targetDate': meta['targetDate'],
          'updatedAt': now,
        }, SetOptions(merge: true));

        return goal;
      }
    } catch (_) {
      // تجاهل
    }

    return null;
  }

  static Future<void> saveGoal(String uid, WeightGoal goal) async {
    final now = Timestamp.now();
    await _userRef(uid).set({
      'weightGoal': goal.toMap(),
      // mirror
      'currentWeightKg': goal.currentWeight,
      'targetWeightKg': goal.targetWeight,
      'targetDate': Timestamp.fromDate(goal.targetDate),
      'updatedAt': now,
    }, SetOptions(merge: true));
  }
}

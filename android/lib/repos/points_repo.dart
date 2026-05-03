import 'package:cloud_firestore/cloud_firestore.dart';

class PointsRepo {
  static final _fs = FirebaseFirestore.instance;

  /// ستريم إجمالي نقاط المستخدم من users/{uid}/achievements/totals.points_total
  static Stream<int> streamUserTotal(String uid) {
    final ref = _fs
        .collection('users')
        .doc(uid)
        .collection('achievements')
        .doc('totals');

    return ref.snapshots().map((d) {
      final data = d.data();
      if (data == null) return 0;
      final v = data['points_total'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    });
  }

  /// منح نقاط + تسجيل حدث في users/{uid}/achievements_events
  static Future<void> award({
    required String uid,
    required String eventKey,
    required int points,
    Map<String, dynamic>? meta,
  }) async {
    final userRef = _fs.collection('users').doc(uid);
    final totalsRef = userRef.collection('achievements').doc('totals');
    final eventsRef = userRef.collection('achievements_events').doc();

    await _fs.runTransaction((tx) async {
      final tSnap = await tx.get(totalsRef);
      final current = (tSnap.data()?['points_total'] ?? 0) as int;

      tx.set(
        totalsRef,
        {
          'points_total': current + points,
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      tx.set(eventsRef, {
        'event': eventKey,
        'points': points,
        'meta': meta ?? <String, dynamic>{},
        'createdAt': Timestamp.now(),
      });
    });
  }
}

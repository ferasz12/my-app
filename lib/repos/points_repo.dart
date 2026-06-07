import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PointsRepo {
  static final _fs = FirebaseFirestore.instance;

  /// ستريم إجمالي نقاط المستخدم من المصدر الموحد users/{uid}.points_total
  /// مع fallback من achievements/totals للتوافق القديم.
  static Stream<int> streamUserTotal(String uid) async* {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getInt('points_total_$uid') ??
        prefs.getInt('wazen_points_$uid') ??
        prefs.getInt('userPoints') ??
        0;
    yield local;

    yield* _fs.collection('users').doc(uid).snapshots(includeMetadataChanges: true).asyncMap((d) async {
      final root = _readPoints(d.data());
      if (root > 0) {
        unawaited(_cachePoints(uid, root));
        return root;
      }

      try {
        final totals = await _fs
            .collection('users')
            .doc(uid)
            .collection('achievements')
            .doc('totals')
            .get(const GetOptions(source: Source.cache));
        final pts = _readPoints(totals.data());
        if (pts > 0) {
          unawaited(_cachePoints(uid, pts));
          return pts;
        }
      } catch (_) {}
      return local;
    });
  }

  /// منح نقاط + تسجيل حدث في users/{uid}/achievements_events
  /// ويحدث الجذر + totals حتى لا تختلف الصفحات.
  static Future<void> award({
    required String uid,
    required String eventKey,
    required int points,
    Map<String, dynamic>? meta,
  }) async {
    if (points == 0) return;
    final userRef = _fs.collection('users').doc(uid);
    final totalsRef = userRef.collection('achievements').doc('totals');
    final eventsRef = userRef.collection('achievements_events').doc();

    var cachedNext = 0;
    await _fs.runTransaction((tx) async {
      final rootSnap = await tx.get(userRef);
      final totalsSnap = await tx.get(totalsRef);
      final current = [
        _readPoints(rootSnap.data()),
        _readPoints(totalsSnap.data()),
      ].fold<int>(0, (a, b) => b > a ? b : a);
      final next = current + points;
      cachedNext = next;

      tx.set(userRef, {
        'points_total': next,
        'pointsTotal': next,
        'points': next,
        'stats': {'points': next},
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      tx.set(totalsRef, {
        'points_total': next,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      tx.set(eventsRef, {
        'event': eventKey,
        'points': points,
        'meta': meta ?? <String, dynamic>{},
        'createdAt': Timestamp.now(),
      });
    });

    if (cachedNext > 0) unawaited(_cachePoints(uid, cachedNext));
  }

  static int _readPoints(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final values = <dynamic>[
      data['points_total'],
      data['points'],
      data['pointsTotal'],
      if (data['stats'] is Map) (data['stats'] as Map)['points'],
    ];
    for (final v in values) {
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static Future<void> _cachePoints(String uid, int points) async {
    final prefs = await SharedPreferences.getInstance();
    final old = [
      prefs.getInt('points_total_$uid') ?? 0,
      prefs.getInt('wazen_points_$uid') ?? 0,
      prefs.getInt('userPoints') ?? 0,
    ].fold<int>(0, (a, b) => b > a ? b : a);
    final value = points > old ? points : old;
    await prefs.setInt('points_total_$uid', value);
    await prefs.setInt('wazen_points_$uid', value);
    await prefs.setInt('userPoints', value);
  }
}

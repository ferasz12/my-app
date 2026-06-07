// lib/screens/achievements_page.dart
// Compatibility shim only.
// The active achievements UI is lib/achievements/achievements_with_leaderboard.dart.
// Keep this store so older calls in Home keep working without importing the old duplicate page.

import 'package:firebase_auth/firebase_auth.dart';

import '../repos/points_repo.dart';

class AchievementsStore {
  const AchievementsStore._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static Future<int> getPoints() async {
    final uid = _uid;
    if (uid == null) return 0;
    return PointsRepo.streamUserTotal(uid).first;
  }

  static Future<void> addPoints(int delta) async {
    final uid = _uid;
    if (uid == null || delta == 0) return;
    await PointsRepo.award(
      uid: uid,
      eventKey: 'home_reward',
      points: delta,
      meta: const {'source': 'home'},
    );
  }
}

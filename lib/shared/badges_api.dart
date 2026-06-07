// Barrel + claim helper
export 'badges.dart';
export 'user_badges_store.dart' show getBadge, setBadge, watchBadge, UserBadgesStore;

// Convenience barrel file to import BadgeType + badge helpers in one line.

import 'package:firebase_auth/firebase_auth.dart';
Future<bool> isOwnerClaimNow({bool forceRefresh = false}) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return false;
  final res = await u.getIdTokenResult(forceRefresh);
  final role = (res.claims?['role'] ?? '').toString().toLowerCase();
  return role == 'owner';
}

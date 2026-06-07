import 'badges_api.dart';
// lib/shared/user_badges.dart
import 'badges.dart';
import 'user_badges_store.dart';

class UserBadges {
  const UserBadges._();

  static Future<BadgeType> getUserBadge(String uid) => getBadge(uid);

  static Stream<BadgeType> watchUserBadge(String uid) =>
      const UserBadgesStore().watchBadge(uid);

  static Future<void> setUserBadge({
    required String targetUid,
    required BadgeType badge,
  }) =>
      setBadge(targetUid, badge);
}

import 'package:my_app/shared/badges_api.dart';
// lib/shared/user_badges.dart
import 'shared.dart' if (dart.library.io) 'badges.dart'; // تجاهل هذا الشرط لو يسبب لخبطة
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

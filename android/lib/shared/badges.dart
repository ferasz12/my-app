// lib/shared/badges.dart
import 'package:flutter/foundation.dart';

/// أنواع الشارات الموحّدة في المشروع
enum BadgeType {
  owner,
  admin,
  support,
  coach,
  verified,
  vip,
  none,
}

/// تحويل من String إلى BadgeType
BadgeType badgeFromString(String? v) {
  switch ((v ?? '').toLowerCase()) {
    case 'owner':
      return BadgeType.owner;
    case 'admin':
      return BadgeType.admin;
    case 'support':
      return BadgeType.support;
    case 'coach':
      return BadgeType.coach;
    case 'verified':
      return BadgeType.verified;
    case 'vip':
      return BadgeType.vip;
    case 'none':
    case '':
      return BadgeType.none;
    default:
      debugPrint('badgeFromString: unknown <$v>, defaulting to none');
      return BadgeType.none;
  }
}

/// تحويل من BadgeType إلى String للتخزين
String badgeToString(BadgeType b) {
  switch (b) {
    case BadgeType.owner:
      return 'owner';
    case BadgeType.admin:
      return 'admin';
    case BadgeType.support:
      return 'support';
    case BadgeType.coach:
      return 'coach';
    case BadgeType.verified:
      return 'verified';
    case BadgeType.vip:
      return 'vip';
    case BadgeType.none:
      return 'none';
  }
}

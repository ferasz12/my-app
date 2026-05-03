// lib/shared/user_badges_store.dart
// Clean implementation: owner-claim enforced badge management

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'badges.dart';
import 'badges_api.dart' show isOwnerClaimNow;

final _fs = FirebaseFirestore.instance;

/// يحوّل نص الحقل في Firestore إلى BadgeType
BadgeType _badgeFromString(String s) {
  switch (s.toLowerCase()) {
    case 'verified':
      return BadgeType.verified;
    case 'coach':
      return BadgeType.coach;
    case 'support':
      return BadgeType.support;
    case 'admin':
      return BadgeType.admin;
    case 'owner': // عرض فقط لو مسجّلة
      return BadgeType.owner;
    case 'vip':
      return BadgeType.vip;
    default:
      return BadgeType.none;
  }
}

/// قراءة شارة المستخدم (للـ UI)
Future<BadgeType> getBadge(String uid) async {
  final doc = await _fs.collection('users').doc(uid).get();
  final b = (doc.data()?['badge'] ?? '').toString();
  return _badgeFromString(b);
}

/// مراقبة الشارة كسيل (Stream) للعرض الحي
Stream<BadgeType> watchBadge(String uid) {
  return _fs.collection('users').doc(uid).snapshots().map((d) {
    final b = (d.data()?['badge'] ?? '').toString();
    return _badgeFromString(b);
  });
}

/// تعيين الشارة — مسموح للـ Owner فقط (claims)، وممنوع تعيين owner من العميل
Future<void> setBadge(String targetUid, BadgeType badge) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) {
    throw StateError('Not signed in');
  }

  // المالك فقط (من الـ custom claims)
  final ok = await isOwnerClaimNow(forceRefresh: true);
  if (!ok) {
    throw StateError('Owner-only action');
  }

  // لا نسمح بتعيين شارة owner من التطبيق
  if (badge == BadgeType.owner) {
    throw StateError('Cannot assign owner badge from client');
  }

  await _fs.collection('users').doc(targetUid).set(
    {'badge': badge.name}, // Dart 3: enum.name
    SetOptions(merge: true),
  );
}

/// Wrapper اختياري إذا كودك يتوقع كائن متجر
class UserBadgesStore {
  const UserBadgesStore();

  Future<BadgeType> getBadge(String uid) => _delegateGetBadge(uid);
  Stream<BadgeType> watchBadge(String uid) => _delegateWatchBadge(uid);
  Future<void> setBadge(String targetUid, BadgeType badge) =>
      _delegateSetBadge(targetUid, badge);
}

// تفويضات للدوال العلوية لتفادي الاستدعاء الذاتي داخل الكلاس
Future<BadgeType> _delegateGetBadge(String uid) => getBadge(uid);
Stream<BadgeType> _delegateWatchBadge(String uid) => watchBadge(uid);
Future<void> _delegateSetBadge(String targetUid, BadgeType badge) =>
    setBadge(targetUid, badge);

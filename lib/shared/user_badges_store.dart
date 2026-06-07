// lib/shared/user_badges_store.dart
// Clean implementation: owner-claim enforced badge management

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// قراءة شارة المستخدم بسرعة من الكاش أولًا ثم Firestore بمهلة قصيرة.
Future<BadgeType> getBadge(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('badge_$uid') ?? prefs.getString('support_badge_$uid');
    if (raw != null && raw.trim().isNotEmpty) {
      return _badgeFromString(raw);
    }
  } catch (_) {}

  Future<BadgeType?> read(Source source, Duration timeout) async {
    try {
      Map<String, dynamic>? data;
      if (uid.contains('@')) {
        final qs = await _fs
            .collection('users')
            .where('email', isEqualTo: uid)
            .limit(1)
            .get(GetOptions(source: source))
            .timeout(timeout);
        if (qs.docs.isNotEmpty) data = qs.docs.first.data();
      } else {
        final doc = await _fs.collection('users').doc(uid).get(GetOptions(source: source)).timeout(timeout);
        data = doc.data();
      }
      final b = (data?['badge'] ?? '').toString();
      if (b.trim().isEmpty) return null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('badge_$uid', b);
        await prefs.setString('support_badge_$uid', b);
      } catch (_) {}
      return _badgeFromString(b);
    } catch (_) {
      return null;
    }
  }

  return await read(Source.cache, const Duration(milliseconds: 650)) ??
      await read(Source.server, const Duration(seconds: 2)) ??
      BadgeType.none;
}

/// مراقبة الشارة كسيل (Stream) للعرض الحي
Stream<BadgeType> watchBadge(String uid) async* {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('badge_$uid') ?? prefs.getString('support_badge_$uid');
    if (raw != null && raw.trim().isNotEmpty) yield _badgeFromString(raw);
  } catch (_) {}

  yield* _fs.collection('users').doc(uid).snapshots(includeMetadataChanges: true).map((d) {
    final b = (d.data()?['badge'] ?? '').toString();
    if (b.trim().isNotEmpty) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString('badge_$uid', b))
          .catchError((_) {});
    }
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

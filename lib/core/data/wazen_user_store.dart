// lib/core/data/wazen_user_store.dart
//
// طبقة موحّدة وخفيفة لبيانات المستخدم:
// - users/{uid} هو مصدر الحقيقة الوحيد.
// - SharedPreferences مجرد كاش سريع للعرض الفوري.
// - لا تجعل الصفحات تنتظر Firestore قبل أن ترسم الواجهة.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wazen_identity_store.dart';

class WazenUserStore {
  WazenUserStore._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      _db.collection('users').doc(uid);

  static String cacheKey(String uid) => 'wazen_user_cache_$uid';

  static String _string(dynamic value) => (value ?? '').toString().trim();

  static Map<String, dynamic> normalize(
    Map<String, dynamic> raw, {
    User? authUser,
    String? uid,
  }) {
    final out = Map<String, dynamic>.from(raw);

    final email = _string(out['email']).isNotEmpty
        ? _string(out['email'])
        : _string(authUser?.email);
    final username = _string(out['username']);
    final first = _string(out['firstName']);
    final last = _string(out['lastName']);
    final name = _string(out['name']);
    final displayName = _string(out['displayName']);
    final fullName = _string(out['fullName']);
    final resolvedName = [
      name,
      displayName,
      fullName,
      [first, last].where((s) => s.isNotEmpty).join(' ').trim(),
      _string(authUser?.displayName),
      email.contains('@') ? email.split('@').first : '',
    ].firstWhere((s) => s.trim().isNotEmpty, orElse: () => 'مستخدم وازن');

    final photo = [
      _string(out['photoUrl']),
      _string(out['photoURL']),
      _string(out['avatarUrl']),
      _string(out['profileImageUrl']),
      _string(out['image']),
      _string(authUser?.photoURL),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');

    out['uid'] = uid ?? _string(out['uid']);
    if (email.isNotEmpty) out['email'] = email;
    out['name'] = resolvedName;
    out['displayName'] = resolvedName;
    if (username.isNotEmpty) out['username'] = username;
    if (photo.isNotEmpty) out['photoUrl'] = photo;

    return out;
  }

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> raw) {
    dynamic safe(dynamic value) {
      if (value == null || value is String || value is num || value is bool) {
        return value;
      }
      if (value is Timestamp) return value.toDate().toIso8601String();
      if (value is DateTime) return value.toIso8601String();
      if (value is Iterable) return value.map(safe).toList(growable: false);
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), safe(v)));
      }
      return value.toString();
    }

    return raw.map((k, v) => MapEntry(k, safe(v)));
  }

  static Future<Map<String, dynamic>> readCachedUser(
    String uid, {
    User? authUser,
    String? email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};

    final raw = prefs.getString(cacheKey(uid));
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) out.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }

    final emailKey = email ?? prefs.getString('currentEmail') ?? authUser?.email ?? '';

    String firstString(List<String> keys) {
      for (final k in keys) {
        final v = prefs.getString(k)?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final name = firstString([
      'displayName_$uid',
      'name_$uid',
      if (emailKey.isNotEmpty) 'displayName_$emailKey',
      if (emailKey.isNotEmpty) 'name_$emailKey',
      if (emailKey.isNotEmpty) 'fullName_$emailKey',
    ]);
    final username = firstString([
      'username_$uid',
      if (emailKey.isNotEmpty) 'currentUsername_$emailKey',
      if (emailKey.isNotEmpty) 'username_$emailKey',
    ]);
    final bio = firstString([
      'bio_$uid',
      if (emailKey.isNotEmpty) 'bio_$emailKey',
    ]);
    final photo = firstString([
      'photoUrl_$uid',
      'avatarUrl_$uid',
      'profileImageUrl_$uid',
      if (emailKey.isNotEmpty) 'photoUrl_$emailKey',
      if (emailKey.isNotEmpty) 'avatarUrl_$emailKey',
      if (emailKey.isNotEmpty) 'profileImageUrl_$emailKey',
      if (emailKey.isNotEmpty) 'profile_image_path_$emailKey',
    ]);

    if (name.isNotEmpty) {
      out['name'] = name;
      out['displayName'] = name;
    }
    if (username.isNotEmpty) out['username'] = username;
    if (bio.isNotEmpty) out['bio'] = bio;
    if (photo.isNotEmpty) out['photoUrl'] = photo;
    if (emailKey.isNotEmpty) out['email'] = emailKey;

    return normalize(out, authUser: authUser, uid: uid);
  }

  static Future<void> saveUserCache(
    String uid,
    Map<String, dynamic> raw, {
    User? authUser,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (authUser != null) {
      await WazenIdentityStore.syncFromFirebaseUser(authUser, prefs: prefs, migrate: false);
    }
    final data = normalize(raw, authUser: authUser, uid: uid);
    await prefs.setString(cacheKey(uid), jsonEncode(_jsonSafeMap(data)));

    final email = _string(data['email']).isNotEmpty
        ? _string(data['email'])
        : _string(authUser?.email);
    if (email.isNotEmpty) {
      await prefs.setString('currentEmail', email);
      await prefs.setString('displayName_$email', _string(data['displayName']));
      await prefs.setString('name_$email', _string(data['name']));
      if (_string(data['username']).isNotEmpty) {
        await prefs.setString('username_$email', _string(data['username']));
        await prefs.setString('currentUsername_$email', _string(data['username']));
      }
      if (_string(data['bio']).isNotEmpty) await prefs.setString('bio_$email', _string(data['bio']));
      if (data.containsKey('photoUrl') && _string(data['photoUrl']).isEmpty) {
        await prefs.remove('photoUrl_$email');
        await prefs.remove('avatarUrl_$email');
        await prefs.remove('profileImageUrl_$email');
      } else if (_string(data['photoUrl']).isNotEmpty) {
        await prefs.setString('photoUrl_$email', _string(data['photoUrl']));
      }
    }

    await prefs.setString('displayName_$uid', _string(data['displayName']));
    await prefs.setString('name_$uid', _string(data['name']));
    if (_string(data['username']).isNotEmpty) await prefs.setString('username_$uid', _string(data['username']));
    if (_string(data['bio']).isNotEmpty) await prefs.setString('bio_$uid', _string(data['bio']));
    if (data.containsKey('photoUrl') && _string(data['photoUrl']).isEmpty) {
      await prefs.remove('photoUrl_$uid');
      await prefs.remove('avatarUrl_$uid');
      await prefs.remove('profileImageUrl_$uid');
    } else if (_string(data['photoUrl']).isNotEmpty) {
      await prefs.setString('photoUrl_$uid', _string(data['photoUrl']));
    }

    final role = _string(data['role']);
    if (role.isNotEmpty) {
      await prefs.setString('guide_role_$uid', role);
      await prefs.setString('cached_role_$uid', role);
    }
    final badge = _string(data['badge']);
    if (badge.isNotEmpty) {
      await prefs.setString('guide_badge_$uid', badge);
      await prefs.setString('badge_$uid', badge);
      await prefs.setString('support_badge_$uid', badge);
    }

    final pts = readPoints(data);
    if (pts > 0) {
      await prefs.setInt('userPoints', pts);
      await prefs.setInt('points_total_$uid', pts);
      await prefs.setInt('wazen_points_$uid', pts);
    }

    if (authUser != null) {
      final id = await WazenIdentityStore.currentIdentity(user: authUser, migrate: false);
      await WazenIdentityStore.mirrorKnownLocalKeys(prefs, id);
    }
  }

  static int readPoints(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final candidates = <dynamic>[
      data['points_total'],
      data['points'],
      data['pointsTotal'],
      if (data['stats'] is Map) (data['stats'] as Map)['points'],
    ];
    for (final v in candidates) {
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static Future<Map<String, dynamic>?> readUserDocFast(String uid) async {
    final authUser = FirebaseAuth.instance.currentUser;
    try {
      final snap = await userDoc(uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 600));
      final data = snap.data();
      if (data != null && data.isNotEmpty) {
        unawaited(saveUserCache(uid, data, authUser: authUser));
        return normalize(data, authUser: authUser, uid: uid);
      }
    } catch (_) {}

    try {
      final snap = await userDoc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      final data = snap.data();
      if (data != null && data.isNotEmpty) {
        unawaited(saveUserCache(uid, data, authUser: authUser));
        return normalize(data, authUser: authUser, uid: uid);
      }
    } catch (_) {}

    return null;
  }

  static Stream<Map<String, dynamic>> watchUser(String uid) async* {
    final authUser = FirebaseAuth.instance.currentUser;
    final cached = await readCachedUser(uid, authUser: authUser);
    if (cached.isNotEmpty) yield cached;

    yield* userDoc(uid).snapshots(includeMetadataChanges: true).map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      final normalized = normalize(data, authUser: authUser, uid: uid);
      unawaited(saveUserCache(uid, normalized, authUser: authUser));
      return normalized;
    });
  }

  static Future<void> setUserPatch(String uid, Map<String, dynamic> patch) async {
    final authUser = FirebaseAuth.instance.currentUser;
    await userDoc(uid).set({
      ...patch,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
    unawaited(saveUserCache(uid, patch, authUser: authUser));
  }
}

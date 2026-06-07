import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/data/wazen_user_store.dart';
import 'models.dart';

class LocalAuthRepo {
  final _db = FirebaseFirestore.instance;

  Future<AppUser> currentUser() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return AppUser(uid: 'anonymous');

    final cached = await WazenUserStore.readCachedUser(u.uid, authUser: u);
    unawaited(WazenUserStore.readUserDocFast(u.uid));
    return AppUser.fromJson(cached, uid: u.uid);
  }

  Future<AppUser?> getUserById(String uid) async {
    final cached = await WazenUserStore.readCachedUser(uid);
    if (cached.isNotEmpty && (cached['displayName'] ?? cached['username'] ?? '').toString().trim().isNotEmpty) {
      unawaited(WazenUserStore.readUserDocFast(uid));
      return AppUser.fromJson(cached, uid: uid);
    }

    final data = await WazenUserStore.readUserDocFast(uid);
    if (data == null || data.isEmpty) return null;
    return AppUser.fromJson(data, uid: uid);
  }

  Future<AppUser?> getByEmailOrKey(String keyOrEmail) async {
    final byEmail = await _db.collection('users_by_email').doc(keyOrEmail).get();
    if (byEmail.exists) {
      final uid = (byEmail.data()!['uid'] ?? '') as String;
      if (uid.isNotEmpty) return getUserById(uid);
    }
    final q = await _db.collection('users').where('username', isEqualTo: keyOrEmail).limit(1).get();
    if (q.docs.isNotEmpty) {
      final d = q.docs.first;
      unawaited(WazenUserStore.saveUserCache(d.id, d.data()));
      return AppUser.fromJson(d.data(), uid: d.id);
    }
    return null;
  }

  Future<void> markUsernameExplicit(String uid, {required bool explicit}) async {
    await _db.collection('users').doc(uid).set({'usernameExplicit': explicit}, SetOptions(merge: true));
  }

  Future<void> updateUser(AppUser u) async {
    await _db.collection('users').doc(u.uid).set(u.toJson(), SetOptions(merge: true));
    unawaited(WazenUserStore.saveUserCache(u.uid, u.toJson()));
  }
}

class LocalChatRepo {
  Future<String> openChatWith(String me, String other) async {
    return 'disabled_chat_${me}_$other';
  }
  Future<String> openOrCreateChatWith(String me, String other) async {
    return 'disabled_chat_${me}_$other';
  }
}

class LocalPostsRepo {
  Stream<List<Post>> watchFeed({int limit = 100}) async* {
    yield const <Post>[];
  }
  Future<void> deletePost(String id) async {}
}

// lib/support/moderation_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ModerationRepo {
  final _fs = FirebaseFirestore.instance;

  Future<void> banUser(String uid, {int days = 7}) async {
    final ref = _fs.collection('users').doc(uid);
    final bannedUntil = days <= 0 ? null : DateTime.now().toUtc().add(Duration(days: days));
    await ref.set({'bannedUntil': bannedUntil == null ? null : Timestamp.fromDate(bannedUntil)}, SetOptions(merge: true));
  }

  Future<void> unbanUser(String uid) async {
    final ref = _fs.collection('users').doc(uid);
    await ref.update({'bannedUntil': FieldValue.delete()});
  }

  /// Delete user content. Tries client-side; if denied, uses Callable Function 'modDeleteUser'.
  Future<void> deleteUser(String uid) async {
    try {
      await _deleteUserClient(uid);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        final callable = FirebaseFunctions.instance.httpsCallable('modDeleteUser');
        await callable.call({'uid': uid});
      } else {
        rethrow;
      }
    }
  }

  Future<void> _deleteUserClient(String uid) async {
    final userRef = _fs.collection('users').doc(uid);
    for (final sub in const ['weights', 'intakes', 'water', 'goals']) {
      final snaps = await userRef.collection(sub).get();
      for (final d in snaps.docs) { await d.reference.delete(); }
    }
    final posts = await _fs.collection('posts').where('authorUid', isEqualTo: uid).get();
    for (final p in posts.docs) {
      for (final sub in const ['comments', 'likes']) {
        final subs = await p.reference.collection(sub).get();
        for (final d in subs.docs) { await d.reference.delete(); }
      }
      await p.reference.delete();
    }
    await userRef.delete();
  }
}

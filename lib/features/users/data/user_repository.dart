import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_public.dart';

class UserRepository {
  final FirebaseFirestore _db;
  UserRepository(this._db);

  DocumentReference _doc(String uid) => _db.collection('users').doc(uid);

  Stream<UserPublic?> streamUser(String uid) {
    return _doc(uid).snapshots().map((s) {
      if (!s.exists) return null;
      return UserPublic.fromMap(s.id, s.data() as Map<String, dynamic>?);
    });
  }

  Future<UserPublic?> getUser(String uid) async {
    final s = await _doc(uid).get();
    if (!s.exists) return null;
    return UserPublic.fromMap(s.id, s.data() as Map<String, dynamic>?);
  }

  Future<void> updateMe(String uid, UserPublic user) async {
    await _doc(uid).set(user.toMap(), SetOptions(merge: true));
  }
}

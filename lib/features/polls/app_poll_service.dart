import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_poll_model.dart';

class AppPollService {
  AppPollService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _pollDoc =>
      _db.collection('appConfig').doc('app_poll');

  DocumentReference<Map<String, dynamic>> _voteDoc(String uid, String pollId) =>
      _db.collection('users').doc(uid).collection('pollVotes').doc(pollId);

  Stream<AppPollConfig?> watchPoll() {
    return _pollDoc.snapshots().map((snap) {
      if (!snap.exists) return null;
      return AppPollConfig.fromMap(Map<String, dynamic>.from(snap.data() ?? {}));
    });
  }

  Future<AppPollConfig?> getPoll() async {
    final snap = await _pollDoc.get();
    if (!snap.exists) return null;
    return AppPollConfig.fromMap(Map<String, dynamic>.from(snap.data() ?? {}));
  }

  Future<bool> currentUserHasVoted(String pollId) async {
    final user = _auth.currentUser;
    if (user == null || pollId.trim().isEmpty) return true;
    final snap = await _voteDoc(user.uid, pollId).get();
    return snap.exists;
  }

  Future<void> submitVote({
    required AppPollConfig poll,
    required int optionIndex,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول أولًا');
    if (optionIndex < 0 || optionIndex >= poll.options.length) {
      throw ArgumentError('خيار التصويت غير صحيح');
    }

    final optionText = poll.options[optionIndex];
    final ref = _voteDoc(user.uid, poll.pollId);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'pollId': poll.pollId,
      'pollTitle': poll.title,
      'question': poll.question,
      'optionIndex': optionIndex,
      'optionText': optionText,
      'linkUrl': poll.linkUrl,
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> publishPoll({
    required String title,
    required String question,
    required String description,
    required List<String> options,
    required String linkText,
    required String linkUrl,
    bool enabled = true,
  }) async {
    final user = _auth.currentUser;
    final cleanedOptions = options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (question.trim().isEmpty) throw ArgumentError('اكتب سؤال التصويت');
    if (cleanedOptions.length < 2) throw ArgumentError('أضف خيارين على الأقل');

    final now = DateTime.now();
    final pollId = 'poll_${now.millisecondsSinceEpoch}';

    await _pollDoc.set({
      'enabled': enabled,
      'pollId': pollId,
      'title': title.trim().isEmpty ? 'ساعدنا نطور وازن' : title.trim(),
      'question': question.trim(),
      'description': description.trim(),
      'options': cleanedOptions,
      'linkText': linkText.trim(),
      'linkUrl': linkUrl.trim(),
      'createdBy': user?.uid,
      'updatedBy': user?.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));
  }

  Future<void> setEnabled(bool enabled) async {
    final user = _auth.currentUser;
    await _pollDoc.set({
      'enabled': enabled,
      'updatedBy': user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<AppPollVote>> watchVotes(String pollId) {
    if (pollId.trim().isEmpty) return Stream.value(const <AppPollVote>[]);
    return _db
        .collectionGroup('pollVotes')
        .where('pollId', isEqualTo: pollId)
        .snapshots()
        .map((snap) => snap.docs.map(AppPollVote.fromDoc).toList(growable: false));
  }
}

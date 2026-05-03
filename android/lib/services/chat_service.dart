// lib/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  ChatService(this._db, this._auth);
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');

  // ========= Helpers =========

  /// chatId ثابت لمحادثة ثنائية: min(uidA,uidB)__max(uidA,uidB)
  String chatIdFor(String a, String b) {
    final ab = [a, b]..sort();
    return '${ab.first}__${ab.last}';
  }

  DocumentReference<Map<String, dynamic>> chatDoc(String chatId) =>
      _chats.doc(chatId);

  CollectionReference<Map<String, dynamic>> messagesCol(String chatId) =>
      chatDoc(chatId).collection('messages');

  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    }
    return const <String>[];
  }

  // ========= إنشاء/تهيئة محادثة =========

  /// يضمن أن وثيقة الشات موجودة وبهيئة متوافقة
  Future<List<String>> _ensureDirectShape(String chatId) async {
    final me = _auth.currentUser!;
    final ref = chatDoc(chatId);
    final snap = await ref.get();
    Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};

    // participants/members
    var members = List<String>.from(
      (data['members'] as List?) ?? (data['participants'] as List? ?? const <String>[]),
    );

    if (!snap.exists || members.length != 2) {
      // إن كانت الوثيقة لا تحتوي أعضاء صحيحين سنحاول الاستنتاج من chatId
      if (members.length != 2) {
        final parts = chatId.split('__');
        if (parts.length == 2) {
          members = [parts[0], parts[1]];
        } else if (members.isEmpty) {
          members = [me.uid];
        }
      }
      final ab = [...members]..sort();
      await ref.set({
        'members': ab,
        'unread': {for (final m in ab) m: 0},
        'typing': {for (final m in ab) m: false},
        'hiddenFor': <String, bool>{},
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    } else {
      // تأكد من الحقول المساعدة
      final ab = [...members]..sort();
      await ref.set({
        'members': ab,
        'unread': {for (final m in ab) m: (data['unread'] is Map ? (data['unread'][m] ?? 0) : 0)},
        'typing': {for (final m in ab) m: false},
        'hiddenFor': data['hiddenFor'] is Map ? data['hiddenFor'] : <String, bool>{},
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }
    return members;
  }

  /// إنشاء أو استرجاع محادثة مباشرة مع مستخدم آخر
  Future<String> getOrCreateDirectChat(String otherUid, {String? seedText}) async {
    final me = _auth.currentUser!;
    if (otherUid.isEmpty || otherUid == me.uid) {
      throw Exception('otherUid غير صالح');
    }
    final id = chatIdFor(me.uid, otherUid);
    final ref = chatDoc(id);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        final members = [me.uid, otherUid]..sort();
        tx.set(ref, {
          'members': members,
          'unread': {for (final m in members) m: 0},
          'typing': {for (final m in members) m: false},
          'hiddenFor': <String, bool>{},
          'updatedAt': Timestamp.now(),
        });
      } else {
        tx.set(ref, {'updatedAt': Timestamp.now()}, SetOptions(merge: true));
      }
    });

    if (seedText != null && seedText.trim().isNotEmpty) {
      await sendMessage(id, seedText.trim(), otherUidOverride: otherUid);
    }
    return id;
  }

  /// يحاول استنتاج الطرف الآخر من الرسائل/الوثيقة
  Future<String?> _inferOtherFromMessages(String chatId) async {
    final me = _auth.currentUser!;
    // من وثيقة الشات
    try {
      final d = await chatDoc(chatId).get();
      final m = d.data() ?? const <String, dynamic>{};
      final members = List<String>.from((m['members'] as List?) ?? const <String>[]);
      if (members.length == 2) {
        return members.first == me.uid ? members.last : members.first;
      }
      // من lastMessage
      final last = (m['lastMessage'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final sid = (last['senderId'] ?? '').toString();
      if (sid.isNotEmpty && sid != me.uid) return sid;
    } catch (_) {}
    // من الرسائل
    try {
      final q = await messagesCol(chatId).orderBy('createdAt', descending: true).limit(50).get();
      for (final d in q.docs) {
        final sid = (d.data()['senderId'] ?? '').toString();
        if (sid.isNotEmpty && sid != me.uid) return sid;
      }
    } catch (_) {}
    return null;
  }

  /// إرسال رسالة نصية وتحديث ملخص الشات
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? otherUidOverride,
  }) async {
    final me = _auth.currentUser!;
    var members = await _ensureDirectShape(chatId);

    String? otherUid;
    if (members.length == 2) {
      otherUid = members.first == me.uid ? members.last : members.first;
    }
    otherUid ??= await _inferOtherFromMessages(chatId);
    if (otherUid == null || otherUid.isEmpty || otherUid == me.uid) {
      otherUid = otherUidOverride;
    }
    if (otherUid == null || otherUid.isEmpty) {
      throw Exception('لا يمكن تحديد الطرف الآخر في المحادثة');
    }

    final chatRef = chatDoc(chatId);
    final msgRef = messagesCol(chatId).doc();
    final msg = <String, dynamic>{
      'id': msgRef.id,
      'text': text,
      'senderId': me.uid,
      'createdAt': Timestamp.now(),
      'readBy': [me.uid],
      'attachments': <dynamic>[],
      'type': 'text',
    };

    await _db.runTransaction((tx) async {
      // اكتب الرسالة
      tx.set(msgRef, msg);

      // حدث ملخص الشات
      final membersNow = [me.uid, otherUid!]..sort();
      final unread = {for (final m in membersNow) m: (m == me.uid) ? 0 : FieldValue.increment(1)};

      tx.set(chatRef, {
        'members': membersNow,
        'lastMessage': {
          'text': msg['text'],
          'senderId': me.uid,
          'createdAt': Timestamp.now(),
        },
        'unread': unread,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    });
  }

  /// تعليم الرسائل كمقروءة
  Future<void> markRead(String chatId) async {
    final me = _auth.currentUser!;
    await _ensureDirectShape(chatId);
    await chatDoc(chatId).set({'unread.${me.uid}': 0}, SetOptions(merge: true));

    final q = await messagesCol(chatId).orderBy('createdAt', descending: true).limit(50).get();
    final batch = _db.batch();
    for (final d in q.docs) {
      final readBy = _asStringList(d.data()['readBy']);
      if (!readBy.contains(me.uid)) {
        batch.update(d.reference, {'readBy': FieldValue.arrayUnion([me.uid])});
      }
    }
    await batch.commit();
  }

  /// مؤشر يكتب الآن
  Future<void> setTyping(String chatId, bool isTyping) async {
    final me = _auth.currentUser!;
    await chatDoc(chatId).set({'typing.${me.uid}': isTyping}, SetOptions(merge: true));
  }

  // ========= الحظر =========

  Future<void> blockUser(String otherUid) async {
    final me = _auth.currentUser!;
    final id = chatIdFor(me.uid, otherUid);
    await chatDoc(id).set({'hiddenFor.${me.uid}': true}, SetOptions(merge: true));
  }

  Future<void> unblockUser(String otherUid) async {
    final me = _auth.currentUser!;
    final id = chatIdFor(me.uid, otherUid);
    await chatDoc(id).set({'hiddenFor.${me.uid}': false}, SetOptions(merge: true));
  }

  Future<bool> isBlockedByMe(String otherUid) async {
    final me = _auth.currentUser!;
    final id = chatIdFor(me.uid, otherUid);
    final d = await chatDoc(id).get();
    final m = d.data() ?? const <String, dynamic>{};
    final hidden = (m['hiddenFor'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return (hidden[me.uid] ?? false) == true;
  }

  Future<bool> isBlockedEither(String otherUid) async {
    final me = _auth.currentUser!;
    final id = chatIdFor(me.uid, otherUid);
    final d = await chatDoc(id).get();
    final m = d.data() ?? const <String, dynamic>{};
    final hidden = (m['hiddenFor'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final a = (hidden[me.uid] ?? false) == true;
    final b = (hidden[otherUid] ?? false) == true;
    return a || b;
  }

  // ========= حذف المحادثة =========

  Future<void> deleteChat(String chatId) async {
    final chatRef = chatDoc(chatId);
    // حذف على دفعات لتفادي حدود فايرستور
    const int page = 300;
    while (true) {
      final snap = await messagesCol(chatId).limit(page).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < page) break;
    }
    await chatRef.delete();
  }

  Future<String> openWith(String otherUid) => getOrCreateDirectChat(otherUid);
}

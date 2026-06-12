import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// صندوق إشعارات وازن الداخلي.
///
/// المسار الأساسي:
/// notifications/{uid}/inbox/{notificationId}
///
/// يستخدم لكل الأنواع:
/// - رسائل Firebase/FCM العامة.
/// - إشعارات المجتمع والتعليقات والإعجابات.
/// - إشعارات الوصفات مستقبلًا.
/// - رسائل دعم وازن.
class WazenInboxService {
  WazenInboxService._();
  static final WazenInboxService instance = WazenInboxService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>? _currentInboxRef() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    return _db.collection('notifications').doc(user.uid).collection('inbox');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> inboxStream({int limit = 80}) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null || user.isAnonymous) {
        return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
      }
      return _db
          .collection('notifications')
          .doc(user.uid)
          .collection('inbox')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots();
    });
  }

  Stream<int> unreadCountStream() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null || user.isAnonymous) return Stream<int>.value(0);
      return _db
          .collection('notifications')
          .doc(user.uid)
          .collection('inbox')
          .where('read', isEqualTo: false)
          .snapshots()
          .map((snap) {
        var count = 0;
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['active'] == false) continue;
          count++;
        }
        return count;
      });
    });
  }

  Future<void> markAllRead({int maxRounds = 6}) async {
    final inbox = _currentInboxRef();
    if (inbox == null) return;

    for (var round = 0; round < maxRounds; round++) {
      final snap = await inbox.where('read', isEqualTo: false).limit(100).get();
      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.set(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      if (snap.docs.length < 100) return;
    }
  }

  Future<void> markRead(String notificationId) async {
    final inbox = _currentInboxRef();
    if (inbox == null || notificationId.trim().isEmpty) return;
    await inbox.doc(notificationId).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteNotification(String notificationId) async {
    final inbox = _currentInboxRef();
    if (inbox == null || notificationId.trim().isEmpty) return;
    await inbox.doc(notificationId).set({
      'active': false,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// يحفظ رسالة Firebase/FCM داخل صندوق وازن بدل الاعتماد فقط على إشعار النظام.
  Future<void> saveFcmMessage({
    required String? messageId,
    required String title,
    required String body,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) async {
    final inbox = _currentInboxRef();
    if (inbox == null) return;

    final cleanTitle = title.trim().isEmpty ? 'رسالة عامة من وازن' : title.trim();
    final cleanBody = body.trim();
    if (cleanBody.isEmpty) return;

    final rawId = (messageId ?? data['messageId'] ?? data['id'] ?? '').toString().trim();
    final stableSeed = rawId.isNotEmpty
        ? rawId
        : '${cleanTitle}_${cleanBody}_${DateTime.now().millisecondsSinceEpoch}';
    final docId = 'fcm_${_stableId(stableSeed)}';
    final ref = inbox.doc(docId);

    final existing = await ref.get();
    if (existing.exists) return;

    await ref.set({
      'title': cleanTitle,
      'body': cleanBody,
      'source': 'fcm',
      'category': 'general',
      'notificationType': 'general_message',
      'type': 'general_message',
      'active': true,
      'read': false,
      'priority': (data['priority'] ?? 'normal').toString(),
      'fcmMessageId': rawId,
      'deeplink': (data['deeplink'] ?? data['route'] ?? '/notifications').toString(),
      'rawData': data.map((key, value) => MapEntry(key, value?.toString() ?? '')),
      'createdAt': FieldValue.serverTimestamp(),
      'scheduledAt': FieldValue.serverTimestamp(),
      'createdByClient': true,
    }, SetOptions(merge: true));
  }

  int _stableId(String value) {
    var hash = 0;
    for (var i = 0; i < value.length; i++) {
      hash = 0x1fffffff & (hash + value.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash.abs();
  }
}

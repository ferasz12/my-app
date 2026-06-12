import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// يتابع صندوق إشعارات مجتمع وازن المحفوظ في:
/// notifications/{uid}/inbox/{notificationId}
///
/// ملاحظة: الوضع الافتراضي لا يعرض إشعارًا خارجيًا.
/// الإشعارات تظهر داخل تبويب إشعارات وازن، حتى لا تظهر كغير مقروءة خارج التطبيق.
class CommunityInboxNotificationService {
  CommunityInboxNotificationService._();
  static final CommunityInboxNotificationService instance =
      CommunityInboxNotificationService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _plugin = FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inboxSub;
  bool _started = false;
  bool _ready = false;
  bool _showLocalNotifications = true;

  static const String _androidChannelId = 'wazen_community_inbox_v1';
  static const String _androidChannelName = 'Wazen Community';

  Future<void> start({bool showLocalNotifications = false}) async {
    if (_started) return;
    _started = true;
    _showLocalNotifications = showLocalNotifications;

    if (_showLocalNotifications) {
      await _initLocalNotifications();
    }

    _authSub = _auth.authStateChanges().listen((user) {
      _listenToInbox(user);
    });
    _listenToInbox(_auth.currentUser);
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _inboxSub?.cancel();
    _authSub = null;
    _inboxSub = null;
    _started = false;
  }

  Future<void> _initLocalNotifications() async {
    if (_ready || kIsWeb) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: 'تنبيهات الردود والتفاعل داخل مجتمع وازن',
          importance: Importance.high,
          playSound: true,
        ),
      );
    }

    _ready = true;
  }

  Future<void> _listenToInbox(User? user) async {
    await _inboxSub?.cancel();
    _inboxSub = null;

    if (user == null || user.isAnonymous) return;

    _inboxSub = _db
        .collection('notifications')
        .doc(user.uid)
        .collection('inbox')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added &&
            change.type != DocumentChangeType.modified) {
          continue;
        }
        await _maybeDeliver(change.doc);
      }
    });
  }

  Future<void> _maybeDeliver(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null) return;
    if (data['active'] == false) return;
    if (data['read'] == true) return;
    if (data['deliveredAt'] != null) return;

    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      final age = DateTime.now().difference(createdAt.toDate()).abs();
      if (age.inDays > 7) {
        await _markDelivered(doc.reference, skipped: true);
        return;
      }
    }

    final title = (data['title'] ?? 'مجتمع وازن').toString().trim();
    final body = (data['body'] ?? 'لديك تحديث جديد في مجتمع وازن.').toString().trim();

    if (_showLocalNotifications && _ready && !kIsWeb) {
      await _showNow(
        id: _stableNotificationId(doc.reference.path),
        title: title.isEmpty ? 'مجتمع وازن' : title,
        body: body.isEmpty ? 'لديك تحديث جديد في مجتمع وازن.' : body,
      );
    }

    await _markDelivered(doc.reference);
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: 'تنبيهات الردود والتفاعل داخل مجتمع وازن',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentSound: true);
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _plugin.show(id, title, body, details);
  }

  Future<void> _markDelivered(
    DocumentReference<Map<String, dynamic>> ref, {
    bool skipped = false,
  }) async {
    try {
      await ref.set({
        'deliveredAt': FieldValue.serverTimestamp(),
        if (skipped) 'deliverySkipped': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  int _stableNotificationId(String value) {
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

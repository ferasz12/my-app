// =============================================================
// FILE: lib/notifications/fcm_marketing_push.dart
// إشعارات العروض التسويقية عبر Firebase Cloud Messaging (FCM)
//
// - يشترك في Topics:
//    - wazen_all (عام)
//    - wazen_marketing (عروض تسويق)
// - يطبّق التفضيلات القادمة من Firestore (push / marketing)
// - يعرض إشعار Foreground على Android عبر flutter_local_notifications
// - لا يغير أي منطق قديم للإشعارات المحلية
// =============================================================

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // نتركه فارغًا لأننا نعتمد غالبًا على notification payload
  // النظام سيعرضه تلقائيًا عندما يكون التطبيق بالخلفية.
}

class FcmMarketingPush {
  FcmMarketingPush._();
  static final FcmMarketingPush instance = FcmMarketingPush._();

  static const String topicAll = 'wazen_all';
    static const String topicMarketing = 'wazen_marketing';

  // صوت إشعارات وازن (مخصص)
  static const String _androidSound = 'wazen_notif';
  static const String _iosSound = 'wazen_notif.wav';
  // Android 8+: قناة جديدة لضمان تطبيق الصوت فورًا
  static const String _chFcmMarketing = 'wazen_marketing_fcm_v2';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Local notifications init (Foreground Android)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(initSettings);

    // Android channel (مهم)
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _chFcmMarketing,
        'Wazen Marketing',
        description: 'Marketing notifications for Wazen',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // صلاحيات الإشعارات (iOS)
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // iOS: عرض الإشعار حتى لو التطبيق مفتوح
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground listener
    FirebaseMessaging.onMessage.listen(_onMessageForeground);

    // حفظ التوكن عند توفر مستخدم
    FirebaseAuth.instance.authStateChanges().listen((u) {
      if (u != null && !u.isAnonymous) {
        _saveTokenForUser(u.uid);
      }
    });

    final u = FirebaseAuth.instance.currentUser;
    if (u != null && !u.isAnonymous) {
      await _saveTokenForUser(u.uid);
    }
  }

  Future<void> applyPrefs({required bool allEnabled, required bool marketingEnabled}) async {
    // لو المستخدم قفل الإشعارات نهائيًا
    if (!allEnabled) {
      await _safeUnsub(topicAll);
      await _safeUnsub(topicMarketing);
      return;
    }

    await _safeSub(topicAll);

    if (marketingEnabled) {
      await _safeSub(topicMarketing);
    } else {
      await _safeUnsub(topicMarketing);
    }
  }

  Future<void> _saveTokenForUser(String uid) async {
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;

    await _db.collection('users').doc(uid).collection('fcmTokens').doc(token).set({
      'token': token,
      'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _messaging.onTokenRefresh.listen((newToken) async {
      await _db.collection('users').doc(uid).collection('fcmTokens').doc(newToken).set({
        'token': newToken,
        'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _onMessageForeground(RemoteMessage m) async {
    // على Android غالبًا ما يطلع بانر في foreground -> نعرض Local notification
    final title = m.notification?.title ?? m.data['title']?.toString() ?? 'وازن';
    final body = m.notification?.body ?? m.data['body']?.toString() ?? '';
    if (body.trim().isEmpty) return;

    final payload = jsonEncode(m.data);

    const androidDetails = AndroidNotificationDetails(
      _chFcmMarketing,
      'Wazen Marketing',
      channelDescription: 'Marketing notifications for Wazen',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      sound: _iosSound,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  Future<void> _safeSub(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
    } catch (_) {}
  }

  Future<void> _safeUnsub(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (_) {}
  }
}

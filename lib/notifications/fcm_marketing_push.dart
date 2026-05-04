// =============================================================
// FILE: lib/notifications/fcm_marketing_push.dart
// إشعارات FCM لتطبيق وازن
//
// التحديث المهم:
// - حفظ FCM Token للمستخدم بشكل أقوى داخل users/{uid}/fcmTokens وأيضًا داخل وثيقة المستخدم.
// - معالجة مشكلة iOS APNS token not ready بإعادة المحاولة بدل ما تفشل التهيئة للأبد.
// - التهيئة لا تعلق على _inited=true إذا صار خطأ في البداية.
// - هذا ضروري حتى إشعارات لوحة الأونر/الدعم الفعلية توصل للمستخدم.
// =============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // نعتمد غالبًا على notification payload؛ النظام يعرضه تلقائيًا بالخلفية.
}

class FcmMarketingPush {
  FcmMarketingPush._();
  static final FcmMarketingPush instance = FcmMarketingPush._();

  static const String topicAll = 'wazen_all';
  static const String topicMarketing = 'wazen_marketing';

  // صوت إشعارات وازن (مخصص)
  static const String _androidSound = 'wazen_notif';
  static const String _iosSound = 'wazen_notif.wav';

  // نفس القناة المستخدمة في Cloud Function: adminSendUserPushNotification
  static const String _chFcmMarketing = 'wazen_marketing_fcm_v2';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _inited = false;
  bool _initializing = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  Future<void> init() async {
    if (_inited || _initializing) return;
    _initializing = true;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
      await _local.initialize(initSettings);

      if (!kIsWeb && Platform.isAndroid) {
        const channel = AndroidNotificationChannel(
          _chFcmMarketing,
          'Wazen Notifications',
          description: 'إشعارات وازن من الإدارة والعروض والتنبيهات المهمة',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_androidSound),
        );
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _foregroundSub ??= FirebaseMessaging.onMessage.listen(_onMessageForeground);

      _authSub ??= FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null && !u.isAnonymous) {
          _saveTokenForUser(u.uid);
        }
      });

      _tokenRefreshSub ??= _messaging.onTokenRefresh.listen((newToken) async {
        final u = FirebaseAuth.instance.currentUser;
        if (u == null || u.isAnonymous) return;
        await _persistToken(uid: u.uid, token: newToken, source: 'refresh');
      }, onError: (e) {
        debugPrint('⚠️ FCM token refresh listener error: $e');
      });

      final u = FirebaseAuth.instance.currentUser;
      if (u != null && !u.isAnonymous) {
        // لا نخلي فشل APNS/FCM يمنع init؛ نحاول بالخلفية.
        unawaited(_saveTokenForUser(u.uid));
      }

      _inited = true;
    } catch (e, st) {
      _inited = false;
      debugPrint('⚠️ FCM init failed, will retry on next start: $e');
      debugPrint('$st');
    } finally {
      _initializing = false;
    }
  }

  Future<void> refreshUserTokenNow() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return;
    await _saveTokenForUser(u.uid, forceRefresh: true);
  }

  Future<void> applyPrefs({required bool allEnabled, required bool marketingEnabled}) async {
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

  Future<void> _saveTokenForUser(
    String uid, {
    int attempt = 0,
    bool forceRefresh = false,
  }) async {
    try {
      final token = await _getTokenSafely(forceRefresh: forceRefresh);
      if (token == null || token.trim().isEmpty) {
        throw StateError('empty_fcm_token');
      }
      await _persistToken(uid: uid, token: token, source: forceRefresh ? 'forced' : 'startup');
    } catch (e) {
      debugPrint('⚠️ Unable to save FCM token attempt=$attempt: $e');

      // iOS أحيانًا يحتاج ثواني حتى يتوفر APNS token.
      if (attempt < 5) {
        final delaySeconds = <int>[2, 5, 10, 20, 45][attempt];
        Future.delayed(Duration(seconds: delaySeconds), () {
          final u = FirebaseAuth.instance.currentUser;
          if (u != null && !u.isAnonymous && u.uid == uid) {
            _saveTokenForUser(uid, attempt: attempt + 1, forceRefresh: forceRefresh);
          }
        });
      }
    }
  }

  Future<String?> _getTokenSafely({bool forceRefresh = false}) async {
    // في iOS لازم APNS token يكون جاهز قبل FCM token.
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      for (var i = 0; i < 8; i++) {
        final apns = await _messaging.getAPNSToken();
        if (apns != null && apns.trim().isNotEmpty) break;
        await Future.delayed(Duration(milliseconds: 700 + (i * 350)));
      }
    }

    if (forceRefresh) {
      try {
        await _messaging.deleteToken();
      } catch (e) {
        debugPrint('⚠️ deleteToken skipped: $e');
      }
    }

    return _messaging.getToken();
  }

  Future<void> _persistToken({
    required String uid,
    required String token,
    required String source,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.length < 20) return;

    final platform = kIsWeb
        ? 'web'
        : (Platform.isIOS
            ? 'ios'
            : (Platform.isAndroid ? 'android' : Platform.operatingSystem));

    final userRef = _db.collection('users').doc(uid);
    final now = FieldValue.serverTimestamp();

    // 1) المسار الأساسي الذي تقرأه Cloud Function
    await userRef.collection('fcmTokens').doc(cleanToken).set({
      'token': cleanToken,
      'platform': platform,
      'source': source,
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));

    // 2) fallback مباشر داخل وثيقة المستخدم، لأن السيرفر يبحث هنا أيضًا.
    await userRef.set({
      'fcmToken': cleanToken,
      'lastFcmToken': cleanToken,
      'fcmPlatform': platform,
      'fcmTokenUpdatedAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    debugPrint('✅ FCM token saved for user=$uid platform=$platform');
  }

  Future<void> _onMessageForeground(RemoteMessage m) async {
    final title = m.notification?.title ?? m.data['title']?.toString() ?? 'وازن';
    final body = m.notification?.body ?? m.data['body']?.toString() ?? '';
    if (body.trim().isEmpty) return;

    final payload = jsonEncode(m.data);

    const androidDetails = AndroidNotificationDetails(
      _chFcmMarketing,
      'Wazen Notifications',
      channelDescription: 'إشعارات وازن من الإدارة والعروض والتنبيهات المهمة',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
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
    } catch (e) {
      debugPrint('⚠️ FCM subscribe $topic skipped: $e');
    }
  }

  Future<void> _safeUnsub(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (e) {
      debugPrint('⚠️ FCM unsubscribe $topic skipped: $e');
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _foregroundSub = null;
    _inited = false;
    _initializing = false;
  }
}

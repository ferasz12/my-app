// =============================================================
// FILE: lib/fasting/fasting_notifications.dart
// إشعارات الصيام (Flutter Local Notifications + timezone) — متوافق مع 19.x
// يوفر: init / showNow / scheduleOnce / scheduleDaily / cancel / cancelAll
// =============================================================
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../notifications/tz_config.dart';

class FastingNotifications {
  FastingNotifications._();
  static final FastingNotifications instance = FastingNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// التهيئة + الأذونات.
  /// على Windows أثناء التطوير نخليها no-op حتى لا تكسر صفحة الصيام.
  Future<void> init() async {
    if (_ready) return;

    if (!_isMobilePlatform) {
      _ready = true;
      debugPrint('ℹ️ Fasting notifications skipped on this platform.');
      return;
    }

    TzConfig.ensureInitialized();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  NotificationDetails _details({
    String androidChannelId = 'fasting_channel',
    String androidChannelName = 'Fasting',
    String androidChannelDescription = 'تنبيهات الصيام',
  }) {
    final androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      channelDescription: androidChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails();
    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  /// إلغاء إشعار محدد
  Future<void> cancel(int id) async {
    if (!_ready) await init();
    if (!_isMobilePlatform) return;
    await _plugin.cancel(id);
  }

  /// إلغاء كل إشعارات الصيام المجدولة
  Future<void> cancelAll() async {
    if (!_ready) await init();
    if (!_isMobilePlatform) return;
    for (final id in const [1001, 1002, 1003, 1004]) {
      await _plugin.cancel(id);
    }
  }

  /// إشعار فوري — نستخدمه عند بدء الصيام الآن بدل جدولة وقت فات.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    if (!_isMobilePlatform) return;

    await _plugin.show(
      id,
      title,
      body,
      _details(),
    );
  }

  /// إشعار لموعد واحد (تاريخ + وقت)
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String androidChannelId = 'fasting_channel',
    String androidChannelName = 'Fasting',
    String androidChannelDescription = 'تنبيهات الصيام',
  }) async {
    if (!_ready) await init();
    if (!_isMobilePlatform) return;

    final now = DateTime.now();
    final safeAt = at.isAfter(now.add(const Duration(seconds: 4)))
        ? at
        : now.add(const Duration(seconds: 5));
    final tzAt = tz.TZDateTime.from(safeAt, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzAt,
      _details(
        androidChannelId: androidChannelId,
        androidChannelName: androidChannelName,
        androidChannelDescription: androidChannelDescription,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// إشعار يومي متكرر على نفس الوقت (ساعة/دقيقة)
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String androidChannelId = 'fasting_channel',
    String androidChannelName = 'Fasting',
    String androidChannelDescription = 'تنبيهات الصيام',
  }) async {
    if (!_ready) await init();
    if (!_isMobilePlatform) return;

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      next,
      _details(
        androidChannelId: androidChannelId,
        androidChannelName: androidChannelName,
        androidChannelDescription: androidChannelDescription,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

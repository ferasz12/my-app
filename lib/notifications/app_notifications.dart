// =============================================================
// FILE: lib/notifications/app_notifications.dart
// إشعارات العادات (ماء / تمارين / نصيحة يومية)
// Flutter Local Notifications + timezone — متوافق مع 19.x
// =============================================================

import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'tz_config.dart';

class AppNotifications {
  AppNotifications._();
  static final AppNotifications instance = AppNotifications._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // ----------------------------
  // صوت إشعارات وازن (مخصص)
  // ----------------------------
  // Android: ضع الملف في android/app/src/main/res/raw/wazen_notif.wav (أو mp3/ogg)
  // iOS: ضع الملف في ios/Runner/wazen_notif.wav ثم أضفه لـ Copy Bundle Resources في Xcode
  static const String _androidSound = 'wazen_notif'; // بدون امتداد
  static const String _iosSound = 'wazen_notif.wav'; // مع الامتداد

  // ملاحظة Android 8+:
  // الصوت مرتبط بـ Notification Channel ولا يتغير بعد إنشاء القناة.
  // لذلك نستخدم IDs جديدة (v2) لضمان تطبيق الصوت فورًا حتى لو كانت هناك قنوات قديمة.
  static const String _chWater = 'wazen_water_v2';
  static const String _chWorkout = 'wazen_workout_v2';
  static const String _chTips = 'wazen_tips_v2';
  static const String _chWeight = 'wazen_weight_v2';
  static const String _chCalories = 'wazen_calories_v2';
  static const String _chStreak = 'wazen_streak_v1';
  static const String _chTest = 'wazen_test_v2';


  // ----------------------------
  // IDs (ثابتة)
  // ----------------------------
  // ملاحظة: غيّرنا النطاقات حتى نستوعب تكرارات أكثر (مثل كل 10 دقائق)
  // ونضمن عدم التعارض بين الأنواع المختلفة.
  static const int _waterBaseId = 20000; // 20000..20199
  static const int _workoutBaseId = 21000; // 21001..21007 (weekday)
  static const int _tipsId = 22000;
  static const int _weightId = 22100;
  static const int _caloriesId = 22101;
  static const int _streakWarningId = 22200;

  // تنظيف أي IDs قديمة من نسخة سابقة
  static const int _legacyWorkoutBaseId = 20100;
  static const int _legacyTipsId = 20200;

  // ----------------------------
  // مفاتيح التخزين المحلي
  // ----------------------------
  static const String kAll = 'notif_all_enabled';
  static const String kWaterEnabled = 'notif_water_enabled';
  static const String kWaterStartH = 'notif_water_start_h';
  static const String kWaterStartM = 'notif_water_start_m';
  static const String kWaterEndH = 'notif_water_end_h';
  static const String kWaterEndM = 'notif_water_end_m';
  static const String kWaterInterval = 'notif_water_interval_min';

  static const String kWorkoutEnabled = 'notif_workout_enabled';
  static const String kWorkoutH = 'notif_workout_h';
  static const String kWorkoutM = 'notif_workout_m';
  static const String kWorkoutDays = 'notif_workout_days_csv'; // "1,3,5" (Mon=1..Sun=7)

  static const String kTipsEnabled = 'notif_tips_enabled';
  static const String kTipsH = 'notif_tips_h';
  static const String kTipsM = 'notif_tips_m';

  static const String kWeightEnabled = 'notif_weight_enabled';
  static const String kWeightH = 'notif_weight_h';
  static const String kWeightM = 'notif_weight_m';

  static const String kCaloriesEnabled = 'notif_calories_enabled';
  static const String kCaloriesH = 'notif_calories_h';
  static const String kCaloriesM = 'notif_calories_m';

  // ----------------------------
  // Init + Permissions
  // ----------------------------

  Future<void> init() async {
    if (_ready) return;

    // ضبط المنطقة الزمنية (لتفادي جدولة UTC بالخطأ)
    TzConfig.ensureInitialized();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);

    // Android 13+: طلب إذن الإشعارات
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Android 12+: بعض الأجهزة تحتاج إذن Exact Alarms حتى تعمل exactAllowWhileIdle
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    } catch (_) {
      // ignore: قد لا تكون الدالة موجودة حسب إصدار المكتبة
    }

    // iOS/macOS: طلب الأذونات (التوافق عبر إصدارات flutter_local_notifications)
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    if (Platform.isAndroid) {
      await _createAndroidChannels();
    }

    _ready = true;
  }

  Future<bool> requestPermission() async {
    if (!_ready) await init();
    bool ok = true;

    if (Platform.isAndroid) {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final r = await a?.requestNotificationsPermission();
      if (r != null) ok = ok && r;
      final enabled = await a?.areNotificationsEnabled();
      if (enabled != null) ok = ok && enabled;
    } else if (Platform.isIOS) {
      final i = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final r = await i?.requestPermissions(alert: true, badge: true, sound: true);
      if (r != null) ok = ok && r;
    } else if (Platform.isMacOS) {
      final m = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      final r = await m?.requestPermissions(alert: true, badge: true, sound: true);
      if (r != null) ok = ok && r;
    }

    return ok;
  }

  // ----------------------------
  // Restore / Apply
  // ----------------------------

  /// يعيد جدولة إشعارات العادات من SharedPreferences (مفيد بعد إعادة تشغيل التطبيق)
  Future<void> restoreFromLocalPrefs() async {
    if (!_ready) await init();
    final p = await SharedPreferences.getInstance();

    final all = p.getBool(kAll) ?? true;

    final waterEnabled = p.getBool(kWaterEnabled) ?? false;
    final wsH = p.getInt(kWaterStartH) ?? 8;
    final wsM = p.getInt(kWaterStartM) ?? 0;
    final weH = p.getInt(kWaterEndH) ?? 22;
    final weM = p.getInt(kWaterEndM) ?? 0;
    final interval = p.getInt(kWaterInterval) ?? 120;

    final workoutEnabled = p.getBool(kWorkoutEnabled) ?? false;
    final wH = p.getInt(kWorkoutH) ?? 18;
    final wM = p.getInt(kWorkoutM) ?? 0;
    final daysCsv = p.getString(kWorkoutDays) ?? '';
    final days = _parseDaysCsv(daysCsv);

    final tipsEnabled = p.getBool(kTipsEnabled) ?? false;
    final tH = p.getInt(kTipsH) ?? 9;
    final tM = p.getInt(kTipsM) ?? 0;

    final weightEnabled = p.getBool(kWeightEnabled) ?? false;
    final wgH = p.getInt(kWeightH) ?? 8;
    final wgM = p.getInt(kWeightM) ?? 0;

    final calEnabled = p.getBool(kCaloriesEnabled) ?? false;
    final cH = p.getInt(kCaloriesH) ?? 21;
    final cM = p.getInt(kCaloriesM) ?? 0;

    await applySettings(
      allEnabled: all,
      waterEnabled: waterEnabled,
      waterStartHour: wsH,
      waterStartMinute: wsM,
      waterEndHour: weH,
      waterEndMinute: weM,
      waterIntervalMinutes: interval,
      workoutEnabled: workoutEnabled,
      workoutHour: wH,
      workoutMinute: wM,
      workoutWeekdays: days,
      tipsEnabled: tipsEnabled,
      tipsHour: tH,
      tipsMinute: tM,

      weightEnabled: weightEnabled,
      weightHour: wgH,
      weightMinute: wgM,

      caloriesEnabled: calEnabled,
      caloriesHour: cH,
      caloriesMinute: cM,
    );
  }

  /// تطبق الحالة (جدولة/إلغاء) حسب إعدادات المستخدم
  Future<void> applySettings({
    required bool allEnabled,
    required bool waterEnabled,
    required int waterStartHour,
    required int waterStartMinute,
    required int waterEndHour,
    required int waterEndMinute,
    required int waterIntervalMinutes,
    required bool workoutEnabled,
    required int workoutHour,
    required int workoutMinute,
    required List<int> workoutWeekdays, // 1..7
    required bool tipsEnabled,
    required int tipsHour,
    required int tipsMinute,

    required bool weightEnabled,
    required int weightHour,
    required int weightMinute,

    required bool caloriesEnabled,
    required int caloriesHour,
    required int caloriesMinute,
  }) async {
    if (!_ready) await init();

    if (!allEnabled) {
      await cancelWaterReminders();
      await cancelWorkoutReminders();
      await cancelDailyTips();
      await cancelWeighInReminder();
      await cancelCaloriesReminder();
      await cancelStreakWarning();
      return;
    }

    if (waterEnabled) {
      await scheduleWaterReminders(
        startHour: waterStartHour,
        startMinute: waterStartMinute,
        endHour: waterEndHour,
        endMinute: waterEndMinute,
        intervalMinutes: waterIntervalMinutes,
      );
    } else {
      await cancelWaterReminders();
    }

    if (workoutEnabled) {
      await scheduleWorkoutReminders(
        hour: workoutHour,
        minute: workoutMinute,
        weekdays: workoutWeekdays,
      );
    } else {
      await cancelWorkoutReminders();
    }

    if (tipsEnabled) {
      await scheduleDailyTip(hour: tipsHour, minute: tipsMinute);
    } else {
      await cancelDailyTips();
    }

    if (weightEnabled) {
      await scheduleWeighInReminder(hour: weightHour, minute: weightMinute);
    } else {
      await cancelWeighInReminder();
    }

    if (caloriesEnabled) {
      await scheduleCaloriesReminder(hour: caloriesHour, minute: caloriesMinute);
    } else {
      await cancelCaloriesReminder();
    }
  }

  // ----------------------------
  // ماء
  // ----------------------------

  Future<void> scheduleWaterReminders({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int intervalMinutes,
  }) async {
    if (!_ready) await init();

    // أولاً ألغِ أي جدولة قديمة
    await cancelWaterReminders();

    final times = _buildTimesOfDay(
      startHour: startHour,
      startMinute: startMinute,
      endHour: endHour,
      endMinute: endMinute,
      intervalMinutes: intervalMinutes,
      maxCount: _waterMaxForPlatform(),
    );

    final androidDetails = AndroidNotificationDetails(
      _chWater,
      'Water',
      channelDescription: 'تذكيرات شرب الماء',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    for (var i = 0; i < times.length; i++) {
      final t = times[i];
      final next = _nextInstanceOfTime(t.hour, t.minute);
      await _plugin.zonedSchedule(
        _waterBaseId + i,
        'تذكير ماء 💧',
        'لا تنسَ تشرب ماء — خلك على هدفك اليومي',
        next,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelWaterReminders() async {
    if (!_ready) await init();
    // جديد
    for (var i = 0; i < 200; i++) {
      await _plugin.cancel(_waterBaseId + i);
    }
    // قديم
    for (var i = 0; i < 60; i++) {
      await _plugin.cancel(20000 + i);
    }
  }

  // ----------------------------
  // تمارين
  // ----------------------------

  Future<void> scheduleWorkoutReminders({
    required int hour,
    required int minute,
    required List<int> weekdays, // 1..7 (Mon..Sun)
  }) async {
    if (!_ready) await init();

    await cancelWorkoutReminders();

    final days = (weekdays.isEmpty) ? <int>[1, 2, 3, 4, 5, 6, 7] : weekdays;

    final androidDetails = AndroidNotificationDetails(
      _chWorkout,
      'Workout',
      channelDescription: 'تذكيرات التمارين',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    for (final wd in days) {
      if (wd < 1 || wd > 7) continue;
      final next = _nextInstanceOfWeekdayTime(wd, hour, minute);
      await _plugin.zonedSchedule(
        _workoutBaseId + wd,
        'وقت التمرين 🏋️',
        'جلسة بسيطة اليوم تفرق — يلا نتحرك!',
        next,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> cancelWorkoutReminders() async {
    if (!_ready) await init();
    for (var wd = 1; wd <= 7; wd++) {
      await _plugin.cancel(_workoutBaseId + wd);
      await _plugin.cancel(_legacyWorkoutBaseId + wd);
    }
  }

  // ----------------------------
  // نصيحة يومية
  // ----------------------------

  Future<void> scheduleDailyTip({required int hour, required int minute}) async {
    if (!_ready) await init();

    await cancelDailyTips();

    final androidDetails = AndroidNotificationDetails(
      _chTips,
      'Tips',
      channelDescription: 'نصائح صحية يومية',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final next = _nextInstanceOfTime(hour, minute);
    await _plugin.zonedSchedule(
      _tipsId,
      'نصيحة اليوم ✅',
      'خطوة صغيرة كل يوم = نتائج كبيرة على المدى البعيد',
      next,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyTips() async {
    if (!_ready) await init();
    await _plugin.cancel(_tipsId);
    await _plugin.cancel(_legacyTipsId);
  }

  // ----------------------------
  // تذكير الميزان (وزن)
  // ----------------------------

  Future<void> scheduleWeighInReminder({required int hour, required int minute}) async {
    if (!_ready) await init();
    await cancelWeighInReminder();

    final androidDetails = AndroidNotificationDetails(
      _chWeight,
      'Weight',
      channelDescription: 'تذكير تسجيل الوزن',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final next = _nextInstanceOfTime(hour, minute);
    await _plugin.zonedSchedule(
      _weightId,
      'تذكير الوزن ⚖️',
      'سجّل وزنك اليوم لمتابعة تقدمك',
      next,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelWeighInReminder() async {
    if (!_ready) await init();
    await _plugin.cancel(_weightId);
  }

  // ----------------------------
  // تذكير تسجيل الوجبات/السعرات
  // ----------------------------

  Future<void> scheduleCaloriesReminder({required int hour, required int minute}) async {
    if (!_ready) await init();
    await cancelCaloriesReminder();

    final androidDetails = AndroidNotificationDetails(
      _chCalories,
      'Calories',
      channelDescription: 'تذكير تسجيل الوجبات والسعرات',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final next = _nextInstanceOfTime(hour, minute);
    await _plugin.zonedSchedule(
      _caloriesId,
      'لا تنسَ تسجل أكلك 🍽️',
      'تسجيل وجباتك يساعدك تحقق هدفك بسهولة',
      next,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelCaloriesReminder() async {
    if (!_ready) await init();
    await _plugin.cancel(_caloriesId);
  }



  // ----------------------------
  // تذكير الستريك قبل أن ينقطع
  // ----------------------------

  /// يحدد رسالة تحفيزية مختلفة حسب اليوم وعدد أيام الستريك.
  String _streakBodyFor(tz.TZDateTime date, int streakCount) {
    final messages = <String>[
      'لا تستسلم الآن، افتح وازن وسجّل يومك قبل ما ينتهي اليوم.',
      'لا توقف هنا، دخول بسيط اليوم يحافظ على تقدمك.',
      'ستريكك يستاهل دقيقة منك. ادخل وابدأ من اليوم.',
      'خطوة صغيرة اليوم تمنع انقطاع الستريك وتقرّبك من هدفك.',
      'باقي عليك تسجيل اليوم. لا تخلي تعب الأيام الماضية يروح.',
      'وازن ينتظرك. افتح التطبيق وكمل رحلتك الصحية.',
      'لا تفقد حماسك، سجّل أي وجبة أو تابع هدفك اليوم.',
      'استمرارك هو الفرق. ادخل وازن وحافظ على الستريك.',
    ];
    final seed = date.year + date.month + date.day + streakCount;
    return messages[seed.abs() % messages.length];
  }

  /// يجدول تذكيرًا لليوم التالي آخر اليوم.
  /// الفكرة: إذا فتح المستخدم التطبيق بكرة قبل وقت التذكير، نلغي التذكير ونعيد جدولته لبعد بكرة.
  /// وإذا ما فتحه، يصله التنبيه قبل نهاية اليوم حتى لا ينقطع الستريك.
  Future<void> scheduleStreakWarningForTomorrow({
    required int streakCount,
    int hour = 21,
    int minute = 0,
  }) async {
    if (!_ready) await init();

    final prefs = await SharedPreferences.getInstance();
    final allEnabled = prefs.getBool(kAll) ?? true;
    if (!allEnabled) {
      await cancelStreakWarning();
      return;
    }

    await cancelStreakWarning();

    final now = tz.TZDateTime.now(tz.local);
    final when = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, hour, minute);
    final safeStreak = streakCount < 1 ? 1 : streakCount;

    final androidDetails = AndroidNotificationDetails(
      _chStreak,
      'Streak',
      channelDescription: 'تذكير قبل انقطاع الستريك اليومي',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      _streakWarningId,
      'لا تفقد الستريك حقك 🔥',
      'ستريكك $safeStreak يوم. ${_streakBodyFor(when, safeStreak)}',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'wazen://home?source=streak_warning',
    );
  }

  Future<void> cancelStreakWarning() async {
    if (!_ready) await init();
    await _plugin.cancel(_streakWarningId);
  }
  
// ----------------------------
// Debug / Test
// ----------------------------

/// إشعار اختبار بعد X ثواني (مفيد للتأكد أن Local Notifications تعمل فعليًا)
Future<void> debugTestNotification({int seconds = 10}) async {
  if (!_ready) await init();

  const androidDetails = AndroidNotificationDetails(
    _chTest,
    'Test',
    channelDescription: 'Test notifications',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentSound: true,
    presentBadge: true,
    sound: _iosSound,
    );

  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
  final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));

  await _plugin.zonedSchedule(
    99999,
    'اختبار إشعار ✅',
    'إذا وصلك هذا، فالإشعارات المحلية شغالة',
    when,
    details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

/// عدد الإشعارات المجدولة حاليًا (للتشخيص)
Future<int> debugPendingCount() async {
  if (!_ready) await init();
  final pending = await _plugin.pendingNotificationRequests();
  return pending.length;
}

// ----------------------------
  // Helpers
  // ----------------------------


  Future<void> _createAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    // قنوات وازن (كلها نفس الصوت)
    final channels = <AndroidNotificationChannel>[
      AndroidNotificationChannel(
        _chWater,
        'تذكيرات الماء',
        description: 'تذكيرات شرب الماء',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
      AndroidNotificationChannel(
        _chWorkout,
        'تذكيرات التمارين',
        description: 'تذكيرات التمارين',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
      AndroidNotificationChannel(
        _chTips,
        'نصائح يومية',
        description: 'نصائح صحية يومية',
        importance: Importance.defaultImportance,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
      AndroidNotificationChannel(
        _chWeight,
        'تذكير الوزن',
        description: 'تذكير تسجيل الوزن',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
      AndroidNotificationChannel(
        _chCalories,
        'تذكير تسجيل الوجبات',
        description: 'تذكير تسجيل الوجبات والسعرات',
        importance: Importance.defaultImportance,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
      AndroidNotificationChannel(
        _chStreak,
        'تذكير الستريك',
        description: 'تذكير قبل انقطاع الستريك اليومي',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
      AndroidNotificationChannel(
        _chTest,
        'اختبار إشعارات',
        description: 'Test notifications',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_androidSound),
      ),
    ];

    for (final c in channels) {
      await android.createNotificationChannel(c);
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
    var next = _nextInstanceOfTime(hour, minute);
    while (next.weekday != weekday) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  List<_TimeOfDay> _buildTimesOfDay({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int intervalMinutes,
    required int maxCount,
  }) {
    final start = startHour * 60 + startMinute;
    var end = endHour * 60 + endMinute;
    // دعم نافذة تتجاوز منتصف الليل (مثلاً 22:00 → 02:00)
    if (end < start) end += 24 * 60;

    final requested = intervalMinutes.clamp(10, 24 * 60);
    final span = (end - start).clamp(0, 24 * 60) as int;

    // إذا عدد الإشعارات المتوقع أكبر من الحد، نوسع الفاصل تلقائيًا
    // حتى لا تفشل الجدولة على iOS (حد 64) أو تتسبب في مشاكل.
    int effective = requested;
    if (maxCount > 1) {
      final needed = (span ~/ requested) + 1;
      if (needed > maxCount) {
        effective = ((span / (maxCount - 1)).ceil()).clamp(requested, 24 * 60);
      }
    }

    final list = <_TimeOfDay>[];
    for (int m = start; m <= end; m += effective) {
      final mm = m % (24 * 60);
      final h = mm ~/ 60;
      final mi = mm % 60;
      list.add(_TimeOfDay(h, mi));
      if (list.length >= maxCount) break;
    }
    return list;
  }

  int _waterMaxForPlatform() {
    // iOS/macOS: حد النظام 64 إشعار مجدول.
    if (Platform.isIOS || Platform.isMacOS) return 60; // نترك هامش لباقي التذكيرات
    return 120;
  }

  List<int> _parseDaysCsv(String csv) {
    final s = csv.trim();
    if (s.isEmpty) return <int>[];
    return s
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .where((d) => d >= 1 && d <= 7)
        .toSet()
        .toList()
      ..sort();
  }
}

class _TimeOfDay {
  const _TimeOfDay(this.hour, this.minute);
  final int hour;
  final int minute;
}

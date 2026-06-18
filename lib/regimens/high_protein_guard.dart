import 'package:shared_preferences/shared_preferences.dart';

import '../fasting/fasting_notifications.dart';

class HighProteinGuard {
  static const _kActive = 'high_protein_active';
  static const _kTarget = 'high_protein_target';
  static const _kMealMin = 'high_protein_meal_min';
  static const _kNotifEnabled = 'high_protein_notif_enabled';
  static const _kMorningH = 'high_protein_morning_h';
  static const _kMorningM = 'high_protein_morning_m';
  static const _kEveningH = 'high_protein_evening_h';
  static const _kEveningM = 'high_protein_evening_m';

  static const double defaultTarget = 120.0;
  static const double defaultMealMin = 25.0;
  static const int _morningId = 31010;
  static const int _eveningId = 31011;

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kActive) ?? false;
  }

  static Future<void> setActive(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kActive, value);
    if (!value) {
      await cancelNotifications();
    } else if (prefs.getBool(_kNotifEnabled) ?? true) {
      await scheduleNotifications();
    }
  }

  static Future<double> targetProtein() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kTarget) ?? defaultTarget;
  }

  static Future<void> setTargetProtein(double grams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTarget, grams.clamp(70.0, 240.0).toDouble());
  }

  static Future<double> mealMinProtein() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kMealMin) ?? defaultMealMin;
  }

  static Future<void> setMealMinProtein(double grams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMealMin, grams.clamp(15.0, 50.0).toDouble());
  }

  static Future<bool> notificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotifEnabled) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, value);
    if (value && (prefs.getBool(_kActive) ?? false)) {
      await scheduleNotifications();
    } else {
      await cancelNotifications();
    }
  }

  static Future<void> setReminderTimes({
    required int morningHour,
    required int morningMinute,
    required int eveningHour,
    required int eveningMinute,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMorningH, morningHour);
    await prefs.setInt(_kMorningM, morningMinute);
    await prefs.setInt(_kEveningH, eveningHour);
    await prefs.setInt(_kEveningM, eveningMinute);
    if ((prefs.getBool(_kActive) ?? false) && (prefs.getBool(_kNotifEnabled) ?? true)) {
      await scheduleNotifications();
    }
  }

  static Future<({int morningH, int morningM, int eveningH, int eveningM})> reminderTimes() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      morningH: prefs.getInt(_kMorningH) ?? 11,
      morningM: prefs.getInt(_kMorningM) ?? 30,
      eveningH: prefs.getInt(_kEveningH) ?? 20,
      eveningM: prefs.getInt(_kEveningM) ?? 30,
    );
  }

  static Future<void> scheduleNotifications() async {
    final times = await reminderTimes();
    await FastingNotifications.instance.init();
    await cancelNotifications();
    await FastingNotifications.instance.scheduleDaily(
      id: _morningId,
      title: 'وازن: لا تنسى البروتين',
      body: 'وزّع البروتين على وجباتك اليوم عشان توصل هدفك بسهولة 💪',
      hour: times.morningH,
      minute: times.morningM,
      androidChannelId: 'wazen_high_protein',
      androidChannelName: 'High Protein',
      androidChannelDescription: 'تذكيرات رجيم عالي البروتين',
    );
    await FastingNotifications.instance.scheduleDaily(
      id: _eveningId,
      title: 'وازن: راجع بروتينك',
      body: 'افتح وازن وتأكد كم باقي لك بروتين قبل نهاية اليوم.',
      hour: times.eveningH,
      minute: times.eveningM,
      androidChannelId: 'wazen_high_protein',
      androidChannelName: 'High Protein',
      androidChannelDescription: 'تذكيرات رجيم عالي البروتين',
    );
  }

  static Future<void> cancelNotifications() async {
    await FastingNotifications.instance.cancel(_morningId);
    await FastingNotifications.instance.cancel(_eveningId);
  }
}

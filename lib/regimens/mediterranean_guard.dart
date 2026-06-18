import 'package:shared_preferences/shared_preferences.dart';

import '../fasting/fasting_notifications.dart';

class MediterraneanGuard {
  static const _kActive = 'mediterranean_active';
  static const _kPlantServings = 'mediterranean_plant_servings';
  static const _kFishMeals = 'mediterranean_fish_meals';
  static const _kFatNudgeLimit = 'mediterranean_fat_nudge_limit';
  static const _kNotifEnabled = 'mediterranean_notif_enabled';
  static const _kLunchH = 'mediterranean_lunch_h';
  static const _kLunchM = 'mediterranean_lunch_m';
  static const _kDinnerH = 'mediterranean_dinner_h';
  static const _kDinnerM = 'mediterranean_dinner_m';

  static const int _lunchId = 32010;
  static const int _dinnerId = 32011;

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

  static Future<int> plantServingsGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPlantServings) ?? 5;
  }

  static Future<void> setPlantServingsGoal(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlantServings, value.clamp(3, 8).toInt());
  }

  static Future<int> fishMealsGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kFishMeals) ?? 2;
  }

  static Future<void> setFishMealsGoal(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFishMeals, value.clamp(0, 5).toInt());
  }

  static Future<double> fatNudgeLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kFatNudgeLimit) ?? 35.0;
  }

  static Future<void> setFatNudgeLimit(double grams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFatNudgeLimit, grams.clamp(20.0, 70.0).toDouble());
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

  static Future<({int lunchH, int lunchM, int dinnerH, int dinnerM})> reminderTimes() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      lunchH: prefs.getInt(_kLunchH) ?? 13,
      lunchM: prefs.getInt(_kLunchM) ?? 0,
      dinnerH: prefs.getInt(_kDinnerH) ?? 20,
      dinnerM: prefs.getInt(_kDinnerM) ?? 0,
    );
  }

  static Future<void> setReminderTimes({
    required int lunchHour,
    required int lunchMinute,
    required int dinnerHour,
    required int dinnerMinute,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLunchH, lunchHour);
    await prefs.setInt(_kLunchM, lunchMinute);
    await prefs.setInt(_kDinnerH, dinnerHour);
    await prefs.setInt(_kDinnerM, dinnerMinute);
    if ((prefs.getBool(_kActive) ?? false) && (prefs.getBool(_kNotifEnabled) ?? true)) {
      await scheduleNotifications();
    }
  }

  static Future<void> scheduleNotifications() async {
    final times = await reminderTimes();
    await FastingNotifications.instance.init();
    await cancelNotifications();
    await FastingNotifications.instance.scheduleDaily(
      id: _lunchId,
      title: 'وازن: طبق متوسطي',
      body: 'خل طبقك اليوم خضار + بروتين + زيت زيتون أو مكسرات بكمية محسوبة 🥗',
      hour: times.lunchH,
      minute: times.lunchM,
      androidChannelId: 'wazen_mediterranean',
      androidChannelName: 'Mediterranean Diet',
      androidChannelDescription: 'تذكيرات رجيم البحر المتوسط',
    );
    await FastingNotifications.instance.scheduleDaily(
      id: _dinnerId,
      title: 'وازن: راجع توازن وجبتك',
      body: 'هل أضفت خضار أو فاكهة اليوم؟ خلي اختياراتك أخف وأقرب للبحر المتوسط.',
      hour: times.dinnerH,
      minute: times.dinnerM,
      androidChannelId: 'wazen_mediterranean',
      androidChannelName: 'Mediterranean Diet',
      androidChannelDescription: 'تذكيرات رجيم البحر المتوسط',
    );
  }

  static Future<void> cancelNotifications() async {
    await FastingNotifications.instance.cancel(_lunchId);
    await FastingNotifications.instance.cancel(_dinnerId);
  }
}

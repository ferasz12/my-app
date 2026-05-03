
import 'package:shared_preferences/shared_preferences.dart';

class LowFatGuard {
  static const _kKeyActive = 'lowfat_active';
  static const _kKeyLimit  = 'lowfat_limit';
  static const double _kDefaultLimit = 60.0; // غرام/يوم

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKeyActive) ?? false;
  }

  static Future<void> setActive(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyActive, v);
  }

  static Future<double> fatLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kKeyLimit) ?? _kDefaultLimit;
  }

  static Future<void> setFatLimit(double grams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kKeyLimit, grams);
  }
}


import 'package:shared_preferences/shared_preferences.dart';

class LowCarbGuard {
  static const _kKeyActive = 'lowcarb_active';
  static const _kKeyLimit  = 'lowcarb_limit';
  static const double _kDefaultLimit = 100.0; // غرام كارب/يوم

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKeyActive) ?? false;
  }

  static Future<void> setActive(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyActive, v);
  }

  static Future<double> carbLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kKeyLimit) ?? _kDefaultLimit;
  }

  static Future<void> setCarbLimit(double grams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kKeyLimit, grams);
  }
}

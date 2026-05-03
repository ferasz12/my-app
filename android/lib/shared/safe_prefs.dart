import 'package:shared_preferences/shared_preferences.dart';

class SafePrefs {
  // مفاتيح/بادئات نتوقعها "boolean" فقط
  static const List<String> _boolPrefixes = [
    'award_kcal_done_',        // مكافأة السعرات لليوم
    'award_water_done_',       // مكافأة الماء لليوم
    'onboarding_done_',        // قرار الأونبوردنق
    'onboardingCompleted_',    // توافق قديم
    'fasting.active',          // حالة الصيام
    'fasting.enforce',         // منع الأكل أثناء الصيام
    'isLoggedIn',              // حالة تسجيل الدخول
  ];

  static bool _shouldBeBoolKey(String key) {
    for (final p in _boolPrefixes) {
      if (key.startsWith(p)) return true;
    }
    return false;
  }

  /// يمسح أي مفتاح من المتوقع أن يكون bool لكن مخزّن كـ double/int/string بالغلط
  static Future<void> fixKnownMismatches() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    for (final k in keys) {
      if (!_shouldBeBoolKey(k)) continue;
      final v = prefs.get(k); // dynamic
      // لو لقيّنا النوع مش bool نمسح المفتاح (يتعاد ضبطه لاحقًا بأول استخدام صحيح)
      if (v is! bool && v != null) {
        await prefs.remove(k);
      }
    }
  }

  /// Getter آمن للـ bool لا يعمل cast داخلي خاطئ
  static Future<bool> getBoolSafe(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.get(key);
    return v is bool ? v : false;
  }
}

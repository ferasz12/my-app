import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  static Future<void> login(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('currentEmail', email);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('currentEmail');
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  static Future<String?> currentEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('currentEmail');
  }
}

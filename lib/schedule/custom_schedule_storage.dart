import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CustomScheduleStorage {
  static String _key(String email) => 'custom_schedules_$email';

  static Future<List<Map<String, dynamic>>> loadAll(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key(email));
    if (s == null || s.isEmpty) return [];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveAll(String email, List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(email), jsonEncode(items));
  }

  static Future<void> upsert(String email, Map<String, dynamic> plan) async {
    final name = (plan['name'] ?? '').toString();
    if (name.isEmpty) return;
    final all = await loadAll(email);
    final i = all.indexWhere((e) => (e['name'] ?? '') == name);
    if (i >= 0) {
      all[i] = plan;
    } else {
      all.add(plan);
    }
    await saveAll(email, all);
  }

  static Future<Map<String, dynamic>?> getByName(String email, String name) async {
    final all = await loadAll(email);
    try {
      return all.firstWhere((e) => (e['name'] ?? '') == name);
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String email, String name) async {
    final all = await loadAll(email);
    all.removeWhere((e) => (e['name'] ?? '') == name);
    await saveAll(email, all);
  }
}
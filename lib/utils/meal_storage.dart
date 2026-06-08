import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/session_manager.dart';
import '../core/data/wazen_identity_store.dart';

/// تخزين سريع محلي لوجبات اليوم (لكل مستخدم).
/// كان سابقًا مفتاح واحد للجهاز (dailyMealHistory) وهذا يسبب اختلاط حسابين.
/// الآن: dailyMealHistory_<uid/email>
Future<void> saveMealForToday(String name, double calories) async {
  final prefs = await SharedPreferences.getInstance();
  final storageKey = await SessionManager.currentStorageKey();
  final k = 'dailyMealHistory_$storageKey';

  // ✅ Migration من المفتاح القديم
  final legacy = prefs.getString('dailyMealHistory');
  if (legacy != null && prefs.getString(k) == null) {
    await prefs.setString(k, legacy);
    await prefs.remove('dailyMealHistory');
  }

  final today = DateTime.now().toIso8601String().split('T').first;
  final dataRaw = prefs.getString(k) ?? '{}';

  Map<String, dynamic> data;
  try {
    data = json.decode(dataRaw) as Map<String, dynamic>;
  } catch (_) {
    data = {};
  }

  final todayData = (data[today] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{
        'totalCalories': 0.0,
        'meals': [],
      };

  todayData['totalCalories'] = (todayData['totalCalories'] ?? 0.0) + calories;
  (todayData['meals'] as List).add({'name': name, 'calories': calories});

  data[today] = todayData;

  final encoded = json.encode(data);
  await prefs.setString(k, encoded);
  final id = await WazenIdentityStore.currentIdentity(migrate: false);
  await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'dailyMealHistory_$a', encoded);
}

Future<Map<String, dynamic>> getTodayMeals() async {
  final prefs = await SharedPreferences.getInstance();
  final storageKey = await SessionManager.currentStorageKey();
  final k = 'dailyMealHistory_$storageKey';

  // ✅ Migration من المفتاح القديم
  final legacy = prefs.getString('dailyMealHistory');
  if (legacy != null && prefs.getString(k) == null) {
    await prefs.setString(k, legacy);
    await prefs.remove('dailyMealHistory');
  }

  final today = DateTime.now().toIso8601String().split('T').first;
  final dataRaw = prefs.getString(k) ?? '{}';

  Map<String, dynamic> data;
  try {
    data = json.decode(dataRaw) as Map<String, dynamic>;
  } catch (_) {
    data = {};
  }

  return (data[today] as Map?)?.cast<String, dynamic>() ??
      {'totalCalories': 0.0, 'meals': []};
}

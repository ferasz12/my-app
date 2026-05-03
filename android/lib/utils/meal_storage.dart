import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> saveMealForToday(String name, double calories) async {
  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().split('T').first;

  final raw = prefs.getString('dailyMealHistory');
  Map<String, dynamic> history = {};

  if (raw != null) {
    history = json.decode(raw);
  }

  if (!history.containsKey(today)) {
    history[today] = {
      'meals': [],
      'totalCalories': 0,
    };
  }

  final todayData = history[today];
  todayData['meals'].add({'name': name, 'calories': calories});
  todayData['totalCalories'] += calories;

  await prefs.setString('dailyMealHistory', json.encode(history));
}

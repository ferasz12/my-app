import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserGoalController {
  static final ValueNotifier<String> userGoal = ValueNotifier('نمط حياة صحي');

  static Future<void> loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    userGoal.value = prefs.getString('user_goal') ?? 'نمط حياة صحي';
  }

  static Future<void> updateGoal(String newGoal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_goal', newGoal);
    userGoal.value = newGoal;
  }
}

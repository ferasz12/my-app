import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_manager.dart';
import '../core/data/wazen_identity_store.dart';

class UserGoalController {
  static final ValueNotifier<String> userGoal = ValueNotifier('نمط حياة صحي');

  static Future<void> loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();
    final k = 'user_goal_$storageKey';

    // ✅ Migration: key القديم كان عام (بدون suffix)
    final legacy = prefs.getString('user_goal');
    if (legacy != null && prefs.getString(k) == null) {
      await prefs.setString(k, legacy);
      await prefs.remove('user_goal');
    }

    userGoal.value = prefs.getString(k) ?? 'نمط حياة صحي';
  }

  static Future<void> updateGoal(String newGoal) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();
    final k = 'user_goal_$storageKey';

    await prefs.setString(k, newGoal);
    final id = await WazenIdentityStore.currentIdentity(migrate: false);
    await WazenIdentityStore.writeToAllAliases(prefs, id.aliases, (a) => 'user_goal_$a', newGoal);
    userGoal.value = newGoal;
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_repository.dart';

import '../utils/calorie_calculator.dart';
import '../utils/macro_plan_engine.dart';

class UserDataProvider extends ChangeNotifier {
  double weight = 60.0;
  double height = 170.0;
  int age = 25;
  String gender = 'ذكر';
  String goal = 'نمط حياة صحي';
  int lifestyleScore = 18;
  double activityFactor = 1.55;

  double calories = 0;
  double protein = 0;
  double fat = 0;
  double carbs = 0;
  double maintenanceCalories = 0;

  String _normEmail(String email) => email.trim().toLowerCase();

  Future<void> loadUserData(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final e = _normEmail(email);

    weight = prefs.getDouble('weight_$e') ?? 60.0;
    height = prefs.getDouble('height_$e') ?? 170.0;
    age = prefs.getInt('age_$e') ?? 25;
    gender = prefs.getString('gender_$e') ?? 'ذكر';
    goal = prefs.getString('goal_$e') ?? 'نمط حياة صحي';
    lifestyleScore = prefs.getInt('lifestyleScore_$e') ?? prefs.getInt('lifestyleScore') ?? 18;
    activityFactor = prefs.getDouble('activityFactor_$e') ?? _activityFromScore(lifestyleScore);

    final kCal = 'caloriesNeeded_$e';
    final kMaint = 'maintenanceCalories_$e';
    final kP = 'protein_$e';
    final kF = 'fat_$e';
    final kC = 'carbs_$e';

    // Migration: الماكروز كانت قديمًا بدون suffix
    final legacyCal = prefs.getDouble('caloriesNeeded');
    final legacyP = prefs.getDouble('protein');
    final legacyF = prefs.getDouble('fat');
    final legacyC = prefs.getDouble('carbs');

    if (prefs.getDouble(kCal) == null && legacyCal != null) {
      await prefs.setDouble(kCal, legacyCal);
    }
    if (prefs.getDouble(kP) == null && legacyP != null) {
      await prefs.setDouble(kP, legacyP);
    }
    if (prefs.getDouble(kF) == null && legacyF != null) {
      await prefs.setDouble(kF, legacyF);
    }
    if (prefs.getDouble(kC) == null && legacyC != null) {
      await prefs.setDouble(kC, legacyC);
    }

    calories = prefs.getDouble(kCal) ?? 0;
    maintenanceCalories = prefs.getDouble(kMaint) ?? 0;
    protein = prefs.getDouble(kP) ?? 0;
    fat = prefs.getDouble(kF) ?? 0;
    carbs = prefs.getDouble(kC) ?? 0;

    if (calories <= 0 || protein <= 0 || fat < 0 || carbs < 0) {
      await _calculateMacros(e);
      return;
    }

    notifyListeners();
  }

  Future<void> updateWeight(String email, double newWeight) async {
    final prefs = await SharedPreferences.getInstance();
    final e = _normEmail(email);
    final today = DateTime.now().toIso8601String().split('T').first;

    weight = newWeight;
    await prefs.setDouble('weight_$e', newWeight);

    // حفظ قراءة الوزن في سجل محلي + سحابي حتى تظهر في صفحة التتبع بعد إعادة تثبيت التطبيق.
    try {
      final raw = prefs.getString('weight_log_$e');
      final list = <Map<String, dynamic>>[];
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(decoded.whereType<Map>().map((x) => Map<String, dynamic>.from(x)));
        }
      }
      list.removeWhere((x) => (x['date'] ?? '').toString() == today);
      list.add({'date': today, 'kg': newWeight});
      list.sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
      await prefs.setString('weight_log_$e', jsonEncode(list));
    } catch (_) {}
    unawaited(AppRepository.writeWeightKg(ymd: today, kg: newWeight).catchError((_) {}));

    await _calculateMacros(e);
  }

  Future<void> updateHeight(String email, double newHeight) async {
    final prefs = await SharedPreferences.getInstance();
    final e = _normEmail(email);

    height = newHeight;
    await prefs.setDouble('height_$e', newHeight);
    await _calculateMacros(e);
  }

  Future<void> _calculateMacros(String e) async {
    final prefs = await SharedPreferences.getInstance();

    age = prefs.getInt('age_$e') ?? age;
    gender = prefs.getString('gender_$e') ?? gender;
    goal = prefs.getString('goal_$e') ?? goal;
    lifestyleScore = prefs.getInt('lifestyleScore_$e') ?? prefs.getInt('lifestyleScore') ?? lifestyleScore;
    activityFactor = prefs.getDouble('activityFactor_$e') ?? _activityFromScore(lifestyleScore);

    maintenanceCalories = calculateCalories(
      age: age,
      gender: gender,
      weight: weight,
      height: height,
      activityFactor: activityFactor,
      goal: 'نمط حياة صحي',
    );

    final bmr = calculateBmr(
      age: age,
      gender: gender,
      weight: weight,
      height: height,
    );

    final effectiveGoal = (goal.trim() == 'تنشيف الدهون') ? 'تنشيف الدهون' : goal;
    final planId = prefs.getString('macroPlanId_$e') ?? MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
    final options = MacroPlanEngine.buildOptions(
      goal: effectiveGoal,
      maintenanceCalories: maintenanceCalories,
      weightKg: weight,
      gender: gender,
      bmr: bmr,
    );
    final selected = options.firstWhere(
      (o) => o.id == planId,
      orElse: () {
        final def = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
        return options.firstWhere((o) => o.id == def, orElse: () => options.first);
      },
    );

    calories = selected.calories;
    protein = selected.proteinG;
    carbs = selected.carbsG;
    fat = selected.fatG;

    await prefs.setDouble('caloriesNeeded_$e', calories);
    await prefs.setDouble('maintenanceCalories_$e', maintenanceCalories);
    await prefs.setDouble('protein_$e', protein);
    await prefs.setDouble('fat_$e', fat);
    await prefs.setDouble('carbs_$e', carbs);
    await prefs.setDouble('activityFactor_$e', activityFactor);
    await prefs.setString('macroMode_$e', MacroPlanEngine.modeAuto);
    await prefs.setString('macroPlanId_$e', selected.id);
    await prefs.setInt('macrosUpdatedAt_$e', DateTime.now().millisecondsSinceEpoch);

    notifyListeners();
  }

  double _activityFromScore(int score) {
    // نظام الأسئلة الحالي غالبًا 0-34، والقديم 0-100.
    // عند عدم وجود activityFactor محفوظ، نستخدم هذا fallback فقط.
    if (score <= 34) {
      if (score <= 10) return 1.2;
      if (score <= 18) return 1.375;
      if (score <= 26) return 1.55;
      if (score <= 30) return 1.725;
      return 1.9;
    }
    if (score <= 20) return 1.2;
    if (score <= 40) return 1.375;
    if (score <= 60) return 1.55;
    if (score <= 80) return 1.725;
    return 1.9;
  }
}

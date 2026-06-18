import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_repository.dart';
import '../core/data/wazen_identity_store.dart';
import '../shared/weight_sync_service.dart';
import '../shared/wazen_profile_prefs.dart';

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
  String macroCalculationNote = '';

  String _normEmail(String email) => email.trim().toLowerCase();

  Future<String> _canonicalKey(SharedPreferences prefs, String email) async {
    final id = await WazenIdentityStore.currentIdentity();
    final aliases = <String>{id.storageKey, id.emailKey, _normEmail(email), ...id.aliases}
      ..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
    await WazenIdentityStore.mirrorKnownLocalKeys(prefs, id);
    return id.storageKey.isNotEmpty ? id.storageKey : (aliases.isNotEmpty ? aliases.first : _normEmail(email));
  }

  Future<void> loadUserData(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final e = await _canonicalKey(prefs, email);

    final aliases = await WazenProfilePrefs.aliases(prefs, user: null, migrate: false);
    final profileKey = WazenProfilePrefs.latestAlias(prefs, aliases);

    weight = WazenProfilePrefs.readDouble(
          prefs,
          const ['current_weight_', 'weight_', 'weightKg_', 'currentWeight_', 'user_weight_', 'goal_current_'],
          aliases,
          preferred: profileKey,
        ) ??
        60.0;
    height = WazenProfilePrefs.readDouble(
          prefs,
          const ['height_', 'height_cm_', 'heightCm_'],
          aliases,
          preferred: profileKey,
        ) ??
        170.0;
    age = WazenProfilePrefs.readInt(prefs, const ['age_'], aliases, preferred: profileKey) ?? 25;
    gender = WazenProfilePrefs.readString(prefs, const ['gender_'], aliases, preferred: profileKey) ?? 'ذكر';
    goal = WazenProfilePrefs.readString(prefs, const ['goal_', 'user_goal_'], aliases, preferred: profileKey) ?? 'نمط حياة صحي';
    lifestyleScore = WazenProfilePrefs.readInt(prefs, const ['lifestyleScore_'], aliases, preferred: profileKey) ?? prefs.getInt('lifestyleScore') ?? 18;
    activityFactor = WazenProfilePrefs.readDouble(prefs, const ['activityFactor_'], aliases, preferred: profileKey) ?? _activityFromScore(lifestyleScore);

    final kCal = 'caloriesNeeded_$profileKey';
    final kMaint = 'maintenanceCalories_$profileKey';
    final kP = 'protein_$profileKey';
    final kF = 'fat_$profileKey';
    final kC = 'carbs_$profileKey';

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

    calories = WazenProfilePrefs.readDouble(prefs, const ['caloriesNeeded_'], aliases, preferred: profileKey) ?? prefs.getDouble(kCal) ?? 0;
    maintenanceCalories = WazenProfilePrefs.readDouble(prefs, const ['maintenanceCalories_'], aliases, preferred: profileKey) ?? prefs.getDouble(kMaint) ?? 0;
    protein = WazenProfilePrefs.readDouble(prefs, const ['protein_'], aliases, preferred: profileKey) ?? prefs.getDouble(kP) ?? 0;
    fat = WazenProfilePrefs.readDouble(prefs, const ['fat_'], aliases, preferred: profileKey) ?? prefs.getDouble(kF) ?? 0;
    carbs = WazenProfilePrefs.readDouble(prefs, const ['carbs_', 'carb_'], aliases, preferred: profileKey) ?? prefs.getDouble(kC) ?? 0;
    macroCalculationNote = WazenProfilePrefs.readString(prefs, const ['macroCalculationNote_'], aliases, preferred: profileKey) ?? '';

    if (calories <= 0 || protein <= 0 || fat < 0 || carbs < 0) {
      await _calculateMacros(e);
      return;
    }

    notifyListeners();
  }

  Future<void> updateWeight(String email, double newWeight) async {
    final prefs = await SharedPreferences.getInstance();
    final e = await _canonicalKey(prefs, email);
    final today = DateTime.now().toIso8601String().split('T').first;

    weight = newWeight;
    final aliases = await WazenProfilePrefs.aliases(prefs, migrate: false);
    final identity = await WazenIdentityStore.currentIdentity(migrate: false);
    final allAliases = <String>{...aliases, ...identity.aliases}..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'weight_$a', newWeight);
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'current_weight_$a', newWeight);
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'currentWeight_$a', newWeight);
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'weightKg_$a', newWeight);
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'user_weight_$a', newWeight);
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'goal_current_$a', newWeight);
    await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'lastWeightChangeAt_$a', DateTime.now().millisecondsSinceEpoch);
    await WeightSyncService.saveCurrentWeight(kg: newWeight);

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
      await WazenProfilePrefs.writeAll(prefs, allAliases, (a) => 'weight_log_$a', jsonEncode(list));
    } catch (_) {}
    unawaited(AppRepository.writeWeightKg(ymd: today, kg: newWeight).catchError((_) {}));

    await _calculateMacros(e);
  }

  Future<void> updateHeight(String email, double newHeight) async {
    final prefs = await SharedPreferences.getInstance();
    final e = await _canonicalKey(prefs, email);

    height = newHeight;
    final aliases = await WazenProfilePrefs.aliases(prefs, migrate: false);
    await WazenProfilePrefs.writeAll(prefs, aliases, (a) => 'height_$a', newHeight);
    await WazenProfilePrefs.writeAll(prefs, aliases, (a) => 'height_cm_$a', newHeight);
    await WazenProfilePrefs.writeAll(prefs, aliases, (a) => 'heightCm_$a', newHeight);
    await WazenProfilePrefs.writeAll(prefs, aliases, (a) => 'profileUpdatedAt_$a', DateTime.now().millisecondsSinceEpoch);
    await _calculateMacros(e);
  }

  Future<void> _calculateMacros(String e) async {
    final prefs = await SharedPreferences.getInstance();

    final aliases = await WazenProfilePrefs.aliases(prefs, migrate: false);
    final profileKey = WazenProfilePrefs.latestAlias(prefs, aliases);
    age = WazenProfilePrefs.readInt(prefs, const ['age_'], aliases, preferred: profileKey) ?? prefs.getInt('age_$e') ?? age;
    gender = WazenProfilePrefs.readString(prefs, const ['gender_'], aliases, preferred: profileKey) ?? prefs.getString('gender_$e') ?? gender;
    goal = WazenProfilePrefs.readString(prefs, const ['goal_', 'user_goal_'], aliases, preferred: profileKey) ?? prefs.getString('goal_$e') ?? goal;
    lifestyleScore = WazenProfilePrefs.readInt(prefs, const ['lifestyleScore_'], aliases, preferred: profileKey) ?? prefs.getInt('lifestyleScore_$e') ?? prefs.getInt('lifestyleScore') ?? lifestyleScore;
    activityFactor = WazenProfilePrefs.readDouble(prefs, const ['activityFactor_'], aliases, preferred: profileKey) ?? prefs.getDouble('activityFactor_$e') ?? _activityFromScore(lifestyleScore);

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
      heightCm: height,
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
    macroCalculationNote = selected.calculationNote;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await WazenProfilePrefs.writeMacroTargets(
      prefs: prefs,
      aliases: aliases,
      calories: calories,
      maintenanceCalories: maintenanceCalories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      activityFactor: activityFactor,
      macroMode: MacroPlanEngine.modeAuto,
      macroPlanId: selected.id,
      macroCalculationNote: macroCalculationNote,
      lastUpdatedYmd: DateTime.now().toIso8601String().split('T').first,
      stamp: nowMs,
    );

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

// lib/utils/macro_plan_engine.dart
// المحرك الموحد لحساب خطط السعرات والماكروز في وازن.

import 'dart:math' as math;

import 'calorie_calculator.dart';

class MacroPlanOption {
  const MacroPlanOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.calculationNote = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// شرح مختصر وواضح لطريقة حساب هذه الخطة ليظهر للمستخدم بعد التعديل.
  final String calculationNote;
}

class MacroPlanEngine {
  static const String modeAuto = 'auto';
  static const String modeCustom = 'custom';

  static String normalizeGoal(String goal) {
    final g = goal.trim();
    if (g == 'زيادة النشاط اليومي') return 'زيادة النشاط اليومي';
    if (g == 'ضبط مستوى السكر' || g == 'ضبط مستوى السكر في الدم') {
      return 'ضبط مستوى السكر في الدم';
    }
    if (g == 'تنشيف الدهون') return 'تنشيف الدهون';
    if (g == 'إنقاص الوزن') return 'إنقاص الوزن';
    if (g == 'بناء العضلات') return 'بناء العضلات';
    if (g == 'زيادة الوزن') return 'زيادة الوزن';
    return 'نمط حياة صحي';
  }

  static String defaultPlanIdForGoal(String goal) {
    switch (normalizeGoal(goal)) {
      case 'تنشيف الدهون':
        return 'fat_shred_standard';
      case 'إنقاص الوزن':
        return 'loss_standard';
      case 'بناء العضلات':
        return 'muscle_standard';
      case 'زيادة الوزن':
        return 'gain_standard';
      case 'ضبط مستوى السكر في الدم':
        return 'sugar_balanced';
      case 'زيادة النشاط اليومي':
        return 'activity_balanced';
      case 'نمط حياة صحي':
      default:
        return 'healthy_balanced';
    }
  }

  static List<MacroPlanOption> buildOptions({
    required String goal,
    required double maintenanceCalories,
    required double weightKg,
    required String gender,
    required double bmr,
    double? heightCm,
  }) {
    final maintenance = _safeCalories(maintenanceCalories, fallback: bmr * 1.55);
    final context = _MacroContext.from(
      weightKg: weightKg,
      heightCm: heightCm,
    );

    switch (normalizeGoal(goal)) {
      case 'تنشيف الدهون':
        return [
          _fromSmartTargets(
            id: 'fat_shred_strong',
            title: 'تنشيف قوي',
            subtitle: 'عجز قوي مع بروتين أعلى، مناسب إذا التزامك عالي.',
            calories: maintenance - _clampDouble(maintenance * 0.25, 450.0, 850.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'تنشيف الدهون',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.60,
            carbMaxPerKg: 2.0,
            maxCarbKcalRatio: 0.40,
            minCarbsG: 70,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'fat_shred_standard',
            title: 'تنشيف قياسي',
            subtitle: 'عجز متوازن لحرق الدهون مع المحافظة على العضلات.',
            calories: maintenance - _clampDouble(maintenance * 0.22, 350.0, 800.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'تنشيف الدهون',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.65,
            carbMaxPerKg: 2.3,
            maxCarbKcalRatio: 0.42,
            minCarbsG: 80,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'fat_shred_light',
            title: 'تنشيف خفيف',
            subtitle: 'عجز أخف وأسهل للالتزام والطاقة في التمرين.',
            calories: maintenance - _clampDouble(maintenance * 0.15, 250.0, 550.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'تنشيف الدهون',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.70,
            carbMaxPerKg: 2.8,
            maxCarbKcalRatio: 0.45,
            minCarbsG: 90,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
      case 'إنقاص الوزن':
        return [
          _fromSmartTargets(
            id: 'loss_fast',
            title: 'نزول سريع',
            subtitle: 'عجز أعلى، مناسب إذا تقدر تلتزم بدون هبوط بالطاقة.',
            calories: maintenance - _clampDouble(maintenance * 0.25, 450.0, 850.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'إنقاص الوزن',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.65,
            carbMaxPerKg: 2.1,
            maxCarbKcalRatio: 0.40,
            minCarbsG: 70,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'loss_standard',
            title: 'نزول طبيعي',
            subtitle: 'عجز ذكي ومناسب لمعظم المستخدمين.',
            calories: maintenance - _clampDouble(maintenance * 0.20, 300.0, 700.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'إنقاص الوزن',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.75,
            carbMaxPerKg: 2.4,
            maxCarbKcalRatio: 0.45,
            minCarbsG: 80,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'loss_slow',
            title: 'نزول بطيء',
            subtitle: 'عجز مريح أكثر ويحافظ على الأداء.',
            calories: maintenance - _clampDouble(maintenance * 0.12, 200.0, 450.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'إنقاص الوزن',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.80,
            carbMaxPerKg: 3.0,
            maxCarbKcalRatio: 0.48,
            minCarbsG: 90,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
      case 'بناء العضلات':
        return [
          _fromSmartTargets(
            id: 'muscle_lean',
            title: 'بناء نظيف',
            subtitle: 'فائض خفيف لتقليل زيادة الدهون.',
            calories: maintenance + _clampDouble(maintenance * 0.05, 120.0, 220.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'بناء العضلات',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.80,
            carbMaxPerKg: 4.0,
            maxCarbKcalRatio: 0.52,
            minCarbsG: 120,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'muscle_standard',
            title: 'بناء قياسي',
            subtitle: 'فائض متوسط لبناء العضلات تدريجيًا.',
            calories: maintenance + _clampDouble(maintenance * 0.08, 180.0, 350.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'بناء العضلات',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.90,
            carbMaxPerKg: 4.8,
            maxCarbKcalRatio: 0.55,
            minCarbsG: 140,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'muscle_aggressive',
            title: 'بناء أسرع',
            subtitle: 'فائض أعلى لمن يصعب عليه زيادة الوزن.',
            calories: maintenance + _clampDouble(maintenance * 0.12, 250.0, 500.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'بناء العضلات',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 1.00,
            carbMaxPerKg: 5.5,
            maxCarbKcalRatio: 0.58,
            minCarbsG: 160,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
      case 'زيادة الوزن':
        return [
          _fromSmartTargets(
            id: 'gain_slow',
            title: 'زيادة تدريجية',
            subtitle: 'فائض هادئ وأنظف.',
            calories: maintenance + _clampDouble(maintenance * 0.08, 180.0, 350.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'زيادة الوزن',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.85,
            carbMaxPerKg: 4.5,
            maxCarbKcalRatio: 0.55,
            minCarbsG: 130,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'gain_standard',
            title: 'زيادة طبيعية',
            subtitle: 'فائض واضح لزيادة الوزن بدون مبالغة.',
            calories: maintenance + _clampDouble(maintenance * 0.15, 250.0, 650.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'زيادة الوزن',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.95,
            carbMaxPerKg: 5.2,
            maxCarbKcalRatio: 0.58,
            minCarbsG: 150,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'gain_fast',
            title: 'زيادة سريعة',
            subtitle: 'فائض أعلى لمن يحتاج سعرات أكثر.',
            calories: maintenance + _clampDouble(maintenance * 0.20, 350.0, 800.0),
            proteinMultiplier: _proteinMultiplier(
              goal: 'زيادة الوزن',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 1.05,
            carbMaxPerKg: 6.0,
            maxCarbKcalRatio: 0.60,
            minCarbsG: 170,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
      case 'ضبط مستوى السكر في الدم':
        return [
          _fromSmartTargets(
            id: 'sugar_lower_carb',
            title: 'كارب أقل',
            subtitle: 'كارب أخفض وتوزيع أهدأ خلال اليوم.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'ضبط مستوى السكر في الدم',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 1.00,
            carbMaxPerKg: 2.2,
            maxCarbKcalRatio: 0.35,
            minCarbsG: 80,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'sugar_balanced',
            title: 'متوازن للسكر',
            subtitle: 'كارب متوسط مع بروتين ودهون متوازنة.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'ضبط مستوى السكر في الدم',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.90,
            carbMaxPerKg: 2.8,
            maxCarbKcalRatio: 0.40,
            minCarbsG: 100,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'sugar_active',
            title: 'نشاط أعلى',
            subtitle: 'كارب أعلى نسبيًا لمن يتمرن ويحتاج طاقة أكثر.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'ضبط مستوى السكر في الدم',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.85,
            carbMaxPerKg: 3.2,
            maxCarbKcalRatio: 0.45,
            minCarbsG: 120,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
      case 'زيادة النشاط اليومي':
        return [
          _fromSmartTargets(
            id: 'activity_light',
            title: 'نشاط خفيف',
            subtitle: 'صيانة مع كارب متوسط للطاقة اليومية.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'زيادة النشاط اليومي',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.85,
            carbMaxPerKg: 3.5,
            maxCarbKcalRatio: 0.48,
            minCarbsG: 110,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'activity_balanced',
            title: 'نشاط متوازن',
            subtitle: 'صيانة مع كارب مناسب للحركة والتمرين.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'زيادة النشاط اليومي',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.80,
            carbMaxPerKg: 4.2,
            maxCarbKcalRatio: 0.52,
            minCarbsG: 130,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'activity_high',
            title: 'نشاط عالي',
            subtitle: 'صيانة مع كارب أعلى لمن نشاطه اليومي كبير.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'زيادة النشاط اليومي',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.75,
            carbMaxPerKg: 5.0,
            maxCarbKcalRatio: 0.56,
            minCarbsG: 150,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
      case 'نمط حياة صحي':
      default:
        return [
          _fromSmartTargets(
            id: 'healthy_light',
            title: 'صحي خفيف',
            subtitle: 'صيانة مع بروتين أعلى قليلًا وشبع أفضل.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'نمط حياة صحي',
              intensity: 3,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.85,
            carbMaxPerKg: 3.2,
            maxCarbKcalRatio: 0.45,
            minCarbsG: 100,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'healthy_balanced',
            title: 'صحي متوازن',
            subtitle: 'توزيع يومي متوازن ومناسب لمعظم المستخدمين.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'نمط حياة صحي',
              intensity: 2,
              bmi: context.bmi,
            ),
            fatMultiplier: 0.85,
            carbMaxPerKg: 3.8,
            maxCarbKcalRatio: 0.50,
            minCarbsG: 120,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
          _fromSmartTargets(
            id: 'healthy_flexible',
            title: 'صحي مرن',
            subtitle: 'مرونة أعلى في الدهون والكارب مع نفس السعرات.',
            calories: maintenance,
            proteinMultiplier: _proteinMultiplier(
              goal: 'نمط حياة صحي',
              intensity: 1,
              bmi: context.bmi,
            ),
            fatMultiplier: 1.00,
            carbMaxPerKg: 4.0,
            maxCarbKcalRatio: 0.48,
            minCarbsG: 120,
            gender: gender,
            maintenanceCalories: maintenance,
            bmr: bmr,
            context: context,
          ),
        ];
    }
  }

  static MacroPlanOption _fromSmartTargets({
    required String id,
    required String title,
    required String subtitle,
    required double calories,
    required double proteinMultiplier,
    required double fatMultiplier,
    required double carbMaxPerKg,
    required double maxCarbKcalRatio,
    required double minCarbsG,
    required String gender,
    required double maintenanceCalories,
    required double bmr,
    required _MacroContext context,
  }) {
    final kcal = _targetWithFloor(calories, gender, maintenanceCalories).roundToDouble();
    final refWeight = context.referenceWeightKg;

    var protein = _round(refWeight * proteinMultiplier);
    var fat = _round(math.max(refWeight * fatMultiplier, (kcal * 0.20) / 9));
    var carbs = (kcal - (protein * 4) - (fat * 9)) / 4;

    final carbCapByKg = refWeight * carbMaxPerKg;
    final carbCapByRatio = (kcal * maxCarbKcalRatio) / 4;
    final carbCap = math.max(minCarbsG, math.min(carbCapByKg, carbCapByRatio));

    if (carbs > carbCap) {
      final fatIfCapped = (kcal - (protein * 4) - (carbCap * 4)) / 9;
      final fatCeiling = math.max(
        fat,
        math.min(refWeight * 1.35, (kcal * 0.40) / 9),
      );
      if (fatIfCapped.isFinite && fatIfCapped > 0 && fatIfCapped <= fatCeiling) {
        carbs = carbCap;
        fat = fatIfCapped;
      } else {
        fat = fatCeiling;
        carbs = (kcal - (protein * 4) - (fat * 9)) / 4;
      }
    }

    if (carbs < minCarbsG) {
      carbs = minCarbsG;
      fat = (kcal - (protein * 4) - (carbs * 4)) / 9;
      if (!fat.isFinite || fat < 0) {
        fat = math.max(0, refWeight * 0.45);
        protein = math.max(0, (kcal - (carbs * 4) - (fat * 9)) / 4);
      }
    }

    protein = _round(math.max(0, protein));
    fat = _round(math.max(0, fat));
    carbs = _round(math.max(0, (kcal - (protein * 4) - (fat * 9)) / 4));

    final note = _buildCalculationNote(
      bmr: bmr,
      maintenanceCalories: maintenanceCalories,
      targetCalories: kcal,
      proteinMultiplier: proteinMultiplier,
      fatMultiplier: fatMultiplier,
      carbMaxPerKg: carbMaxPerKg,
      maxCarbKcalRatio: maxCarbKcalRatio,
      protein: protein,
      carbs: carbs,
      fat: fat,
      context: context,
    );

    return MacroPlanOption(
      id: id,
      title: title,
      subtitle: subtitle,
      calories: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      calculationNote: note,
    );
  }

  static String _buildCalculationNote({
    required double bmr,
    required double maintenanceCalories,
    required double targetCalories,
    required double proteinMultiplier,
    required double fatMultiplier,
    required double carbMaxPerKg,
    required double maxCarbKcalRatio,
    required double protein,
    required double carbs,
    required double fat,
    required _MacroContext context,
  }) {
    final diff = targetCalories - maintenanceCalories;
    final targetText = diff.abs() < 50
        ? 'صيانة'
        : diff < 0
            ? 'عجز ${diff.abs().round()} سعرة'
            : 'فائض ${diff.round()} سعرة';
    final bmiText = context.bmi > 0 ? 'BMI ${context.bmi.toStringAsFixed(1)}' : 'BMI غير متاح';
    final carbRatio = (maxCarbKcalRatio * 100).round();
    final ref = context.referenceWeightKg;
    return 'طريقة الحسبة: BMR ${bmr.round()} ثم سعرات المحافظة ${maintenanceCalories.round()}، الهدف $targetText = ${targetCalories.round()} سعرة. '
        'استخدمنا ${context.referenceWeightLabel} ($bmiText). البروتين = ${ref.toStringAsFixed(1)} × ${proteinMultiplier.toStringAsFixed(1)} = ${protein.round()}جم، '
        'الدهون تبدأ من ${ref.toStringAsFixed(1)} × ${fatMultiplier.toStringAsFixed(2)} مع حد أدنى 20% من السعرات = ${fat.round()}جم، '
        'والكارب هو السعرات المتبقية ÷ 4 مع سقف ذكي تقريبًا ${carbMaxPerKg.toStringAsFixed(1)}جم/كجم أو $carbRatio% من السعرات = ${carbs.round()}جم.';
  }

  static double _proteinMultiplier({
    required String goal,
    required int intensity,
    required double bmi,
  }) {
    final highBmi = bmi >= 30;
    final veryHighBmi = bmi >= 35;

    switch (normalizeGoal(goal)) {
      case 'تنشيف الدهون':
        if (veryHighBmi) return intensity == 3 ? 1.8 : intensity == 2 ? 1.7 : 1.6;
        if (highBmi) return intensity == 3 ? 2.0 : intensity == 2 ? 1.8 : 1.6;
        return intensity == 3 ? 2.2 : intensity == 2 ? 2.0 : 1.8;
      case 'إنقاص الوزن':
        if (veryHighBmi) return intensity == 3 ? 1.7 : intensity == 2 ? 1.6 : 1.5;
        if (highBmi) return intensity == 3 ? 1.8 : intensity == 2 ? 1.6 : 1.5;
        return intensity == 3 ? 2.0 : intensity == 2 ? 1.8 : 1.6;
      case 'بناء العضلات':
        if (highBmi) return intensity == 3 ? 1.9 : intensity == 2 ? 1.8 : 1.6;
        return intensity == 3 ? 2.1 : intensity == 2 ? 2.0 : 1.8;
      case 'زيادة الوزن':
        if (highBmi) return intensity == 3 ? 1.8 : intensity == 2 ? 1.7 : 1.6;
        return intensity == 3 ? 1.9 : intensity == 2 ? 1.8 : 1.6;
      case 'ضبط مستوى السكر في الدم':
        if (highBmi) return intensity == 3 ? 1.7 : intensity == 2 ? 1.6 : 1.5;
        return intensity == 3 ? 1.8 : intensity == 2 ? 1.6 : 1.5;
      case 'زيادة النشاط اليومي':
        if (highBmi) return intensity == 3 ? 1.6 : intensity == 2 ? 1.5 : 1.4;
        return intensity == 3 ? 1.7 : intensity == 2 ? 1.6 : 1.4;
      case 'نمط حياة صحي':
      default:
        if (highBmi) return intensity == 3 ? 1.7 : intensity == 2 ? 1.6 : 1.4;
        return intensity == 3 ? 1.8 : intensity == 2 ? 1.6 : 1.4;
    }
  }

  static double _targetWithFloor(double target, String gender, double maintenanceCalories) {
    final floor = normalizeGender(gender) == 'أنثى' ? 1200.0 : 1500.0;
    if (maintenanceCalories <= floor) return math.max(900.0, maintenanceCalories);
    return math.max(target, floor);
  }

  static double _safeCalories(double value, {required double fallback}) {
    if (value.isFinite && value > 0) return value;
    if (fallback.isFinite && fallback > 0) return fallback;
    return 2000.0;
  }

  static double _round(double value) => value.isFinite ? value.roundToDouble() : 0.0;

  static double _clampDouble(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble();
  }
}

class _MacroContext {
  const _MacroContext({
    required this.actualWeightKg,
    required this.referenceWeightKg,
    required this.bmi,
    required this.referenceWeightLabel,
  });

  final double actualWeightKg;
  final double referenceWeightKg;
  final double bmi;
  final String referenceWeightLabel;

  static _MacroContext from({
    required double weightKg,
    double? heightCm,
  }) {
    final actual = weightKg.isFinite && weightKg > 0 ? weightKg : 70.0;
    final safeHeight = (heightCm != null && heightCm.isFinite && heightCm >= 120 && heightCm <= 230)
        ? heightCm
        : 0.0;

    if (safeHeight <= 0) {
      return _MacroContext(
        actualWeightKg: actual,
        referenceWeightKg: actual,
        bmi: 0,
        referenceWeightLabel: 'الوزن الحالي',
      );
    }

    final hM = safeHeight / 100.0;
    final bmi = actual / (hM * hM);
    final targetAtBmi24 = 24.0 * hM * hM;

    if (bmi >= 30 && actual > targetAtBmi24) {
      final adjusted = targetAtBmi24 + (0.40 * (actual - targetAtBmi24));
      return _MacroContext(
        actualWeightKg: actual,
        referenceWeightKg: _clampStatic(adjusted, targetAtBmi24, actual),
        bmi: bmi,
        referenceWeightLabel: 'وزن مرجعي معدل بدل الوزن الكامل لأن الوزن الحالي مرتفع',
      );
    }

    if (bmi >= 27 && actual > targetAtBmi24) {
      final adjusted = targetAtBmi24 + (0.60 * (actual - targetAtBmi24));
      return _MacroContext(
        actualWeightKg: actual,
        referenceWeightKg: _clampStatic(adjusted, targetAtBmi24, actual),
        bmi: bmi,
        referenceWeightLabel: 'وزن مرجعي مخفف لأن BMI أعلى من الطبيعي',
      );
    }

    return _MacroContext(
      actualWeightKg: actual,
      referenceWeightKg: actual,
      bmi: bmi,
      referenceWeightLabel: 'الوزن الحالي',
    );
  }

  static double _clampStatic(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble();
  }
}

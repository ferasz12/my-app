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
  });

  final String id;
  final String title;
  final String subtitle;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
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
  }) {
    final maintenance = _safeCalories(maintenanceCalories, fallback: bmr * 1.55);
    final weight = weightKg.isFinite && weightKg > 0 ? weightKg : 70.0;

    switch (normalizeGoal(goal)) {
      case 'تنشيف الدهون':
        return [
          _fromProteinFat(
            id: 'fat_shred_strong',
            title: 'تنشيف قوي',
            subtitle: 'عجز 25%، مناسب إذا تبغى نزول أسرع مع التزام عالي.',
            calories: maintenance * 0.75,
            proteinG: weight * 2.3,
            fatG: weight * 0.6,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'fat_shred_standard',
            title: 'تنشيف قياسي',
            subtitle: 'عجز 22%، خيار متوازن لحرق الدهون مع المحافظة على العضلات.',
            calories: maintenance * 0.78,
            proteinG: weight * 2.2,
            fatG: weight * 0.65,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'fat_shred_light',
            title: 'تنشيف خفيف',
            subtitle: 'عجز 15%، أسهل للالتزام والطاقة في التمرين.',
            calories: maintenance * 0.85,
            proteinG: weight * 2.0,
            fatG: weight * 0.7,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
      case 'إنقاص الوزن':
        return [
          _fromProteinFat(
            id: 'loss_fast',
            title: 'نزول سريع',
            subtitle: 'عجز 650 سعرة تقريبًا، يحتاج التزام عالي.',
            calories: maintenance - 650,
            proteinG: weight * 2.1,
            fatG: weight * 0.7,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'loss_standard',
            title: 'نزول طبيعي',
            subtitle: 'عجز 500 سعرة، مناسب لمعظم المستخدمين.',
            calories: maintenance - 500,
            proteinG: weight * 2.0,
            fatG: weight * 0.8,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'loss_slow',
            title: 'نزول بطيء',
            subtitle: 'عجز 300 سعرة، مريح أكثر ويحافظ على الأداء.',
            calories: maintenance - 300,
            proteinG: weight * 1.8,
            fatG: weight * 0.8,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
      case 'بناء العضلات':
        return [
          _fromProteinFat(
            id: 'muscle_lean',
            title: 'بناء نظيف',
            subtitle: 'فائض خفيف 150 سعرة لتقليل زيادة الدهون.',
            calories: maintenance + 150,
            proteinG: weight * 2.0,
            fatG: weight * 0.8,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'muscle_standard',
            title: 'بناء قياسي',
            subtitle: 'فائض 300 سعرة، مناسب لبناء العضلات تدريجيًا.',
            calories: maintenance + 300,
            proteinG: weight * 2.2,
            fatG: weight * 0.9,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'muscle_aggressive',
            title: 'بناء أسرع',
            subtitle: 'فائض 450 سعرة، مناسب لمن يصعب عليه زيادة الوزن.',
            calories: maintenance + 450,
            proteinG: weight * 2.2,
            fatG: weight * 1.0,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
      case 'زيادة الوزن':
        return [
          _fromProteinFat(
            id: 'gain_slow',
            title: 'زيادة تدريجية',
            subtitle: 'فائض 250 سعرة لزيادة أهدأ وأنظف.',
            calories: maintenance + 250,
            proteinG: weight * 1.8,
            fatG: weight * 0.8,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'gain_standard',
            title: 'زيادة طبيعية',
            subtitle: 'فائض 500 سعرة، مناسب لزيادة الوزن بوضوح.',
            calories: maintenance + 500,
            proteinG: weight * 1.8,
            fatG: weight * 1.0,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromProteinFat(
            id: 'gain_fast',
            title: 'زيادة سريعة',
            subtitle: 'فائض 700 سعرة لمن يحتاج سعرات أعلى.',
            calories: maintenance + 700,
            proteinG: weight * 2.0,
            fatG: weight * 1.1,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
      case 'ضبط مستوى السكر في الدم':
        return [
          _fromRatios(
            id: 'sugar_lower_carb',
            title: 'كارب أقل',
            subtitle: '35% كارب، مناسب لتوزيع كارب أهدأ خلال اليوم.',
            calories: maintenance,
            proteinRatio: 0.30,
            carbsRatio: 0.35,
            fatRatio: 0.35,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromRatios(
            id: 'sugar_balanced',
            title: 'متوازن للسكر',
            subtitle: '40% كارب مع بروتين ودهون متوازنة.',
            calories: maintenance,
            proteinRatio: 0.30,
            carbsRatio: 0.40,
            fatRatio: 0.30,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromRatios(
            id: 'sugar_active',
            title: 'نشاط أعلى',
            subtitle: '45% كارب لمن يتمرن ويحتاج طاقة أكثر.',
            calories: maintenance,
            proteinRatio: 0.28,
            carbsRatio: 0.45,
            fatRatio: 0.27,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
      case 'زيادة النشاط اليومي':
        return [
          _fromRatios(
            id: 'activity_light',
            title: 'نشاط خفيف',
            subtitle: 'صيانة مع كارب متوسط للطاقة اليومية.',
            calories: maintenance,
            proteinRatio: 0.28,
            carbsRatio: 0.45,
            fatRatio: 0.27,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromRatios(
            id: 'activity_balanced',
            title: 'نشاط متوازن',
            subtitle: 'صيانة مع كارب أعلى قليلًا لدعم الحركة والتمرين.',
            calories: maintenance,
            proteinRatio: 0.27,
            carbsRatio: 0.48,
            fatRatio: 0.25,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromRatios(
            id: 'activity_high',
            title: 'نشاط عالي',
            subtitle: 'صيانة مع كارب أعلى لمن نشاطه اليومي كبير.',
            calories: maintenance,
            proteinRatio: 0.25,
            carbsRatio: 0.52,
            fatRatio: 0.23,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
      case 'نمط حياة صحي':
      default:
        return [
          _fromRatios(
            id: 'healthy_light',
            title: 'صحي خفيف',
            subtitle: 'صيانة مع بروتين أعلى قليلًا.',
            calories: maintenance,
            proteinRatio: 0.30,
            carbsRatio: 0.42,
            fatRatio: 0.28,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromRatios(
            id: 'healthy_balanced',
            title: 'صحي متوازن',
            subtitle: 'توزيع يومي متوازن ومناسب لمعظم المستخدمين.',
            calories: maintenance,
            proteinRatio: 0.28,
            carbsRatio: 0.47,
            fatRatio: 0.25,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
          _fromRatios(
            id: 'healthy_flexible',
            title: 'صحي مرن',
            subtitle: 'مرونة أعلى في الدهون والكارب مع نفس السعرات.',
            calories: maintenance,
            proteinRatio: 0.25,
            carbsRatio: 0.45,
            fatRatio: 0.30,
            gender: gender,
            maintenanceCalories: maintenance,
          ),
        ];
    }
  }

  static MacroPlanOption _fromProteinFat({
    required String id,
    required String title,
    required String subtitle,
    required double calories,
    required double proteinG,
    required double fatG,
    required String gender,
    required double maintenanceCalories,
  }) {
    final kcal = _targetWithFloor(calories, gender, maintenanceCalories).roundToDouble();
    final protein = _round(proteinG);
    final fat = _round(fatG);
    final carbs = _round(math.max(0, (kcal - (protein * 4 + fat * 9)) / 4));
    return MacroPlanOption(
      id: id,
      title: title,
      subtitle: subtitle,
      calories: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    );
  }

  static MacroPlanOption _fromRatios({
    required String id,
    required String title,
    required String subtitle,
    required double calories,
    required double proteinRatio,
    required double carbsRatio,
    required double fatRatio,
    required String gender,
    required double maintenanceCalories,
  }) {
    final kcal = _targetWithFloor(calories, gender, maintenanceCalories).roundToDouble();
    final total = proteinRatio + carbsRatio + fatRatio;
    final pRatio = total > 0 ? proteinRatio / total : 0.30;
    final cRatio = total > 0 ? carbsRatio / total : 0.45;
    final fRatio = total > 0 ? fatRatio / total : 0.25;

    return MacroPlanOption(
      id: id,
      title: title,
      subtitle: subtitle,
      calories: kcal,
      proteinG: _round((kcal * pRatio) / 4),
      carbsG: _round((kcal * cRatio) / 4),
      fatG: _round((kcal * fRatio) / 9),
    );
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
}

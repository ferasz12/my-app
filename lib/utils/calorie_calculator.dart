// lib/utils/calorie_calculator.dart
// مصدر موحد لحساب السعرات في وازن.
// يعتمد على معادلة Mifflin-St Jeor لحساب BMR ثم TDEE.

import 'dart:math' as math;

String normalizeGender(String gender) {
  final g = gender.trim().toLowerCase();
  if (g == 'female' || g == 'أنثى' || g == 'انثى') return 'أنثى';
  return 'ذكر';
}

String normalizeGoalForCalories(String goal) {
  final g = goal.trim();
  if (g == 'زيادة النشاط اليومي' || g == 'ضبط مستوى السكر في الدم') {
    return 'نمط حياة صحي';
  }
  return g.isEmpty ? 'نمط حياة صحي' : g;
}

double calculateBmr({
  required int age,
  required String gender,
  required double weight,
  required double height,
}) {
  final safeAge = age.clamp(10, 100).toInt();
  final safeWeight = weight.isFinite && weight > 0 ? weight : 70.0;
  final safeHeight = height.isFinite && height > 0 ? height : 170.0;
  final base = 10 * safeWeight + 6.25 * safeHeight - 5 * safeAge;
  return normalizeGender(gender) == 'أنثى' ? base - 161 : base + 5;
}

double calculateMaintenanceCalories({
  required int age,
  required String gender,
  required double weight,
  required double height,
  required double activityFactor,
}) {
  final bmr = calculateBmr(age: age, gender: gender, weight: weight, height: height);
  final factor = (activityFactor.isFinite && activityFactor > 0) ? activityFactor : 1.55;
  return (bmr * factor).roundToDouble();
}

/// يحسب السعرات النهائية حسب الهدف.
///
/// ملاحظة مهمة:
/// - الهدفان "زيادة النشاط اليومي" و"ضبط مستوى السكر" لا نعتبرهما عجز/فائض
///   من ناحية السعرات، بل صيانة، والاختلاف يكون في توزيع الماكروز.
/// - يوجد حد أمان حتى لا تنخفض السعرات بشكل مبالغ فيه.
double calculateCalories({
  required int age,
  required String gender,
  required double weight,
  required double height,
  required double activityFactor,
  required String goal,
}) {
  final maintenance = calculateMaintenanceCalories(
    age: age,
    gender: gender,
    weight: weight,
    height: height,
    activityFactor: activityFactor,
  );

  final normalizedGoal = normalizeGoalForCalories(goal);
  double target;

  switch (normalizedGoal) {
    case 'إنقاص الوزن':
      target = maintenance - 500;
      break;
    case 'تنشيف الدهون':
      target = maintenance * 0.78;
      break;
    case 'بناء العضلات':
      target = maintenance + 300;
      break;
    case 'زيادة الوزن':
      target = maintenance + 500;
      break;
    case 'نمط حياة صحي':
    default:
      target = maintenance;
      break;
  }

  return _applySafetyFloor(
    target: target,
    maintenance: maintenance,
    gender: gender,
  ).roundToDouble();
}

double _applySafetyFloor({
  required double target,
  required double maintenance,
  required String gender,
}) {
  final floor = normalizeGender(gender) == 'أنثى' ? 1200.0 : 1500.0;

  // إذا كانت سعرات المحافظة نفسها أقل من حد الأمان، لا نرفعها فوق المحافظة.
  // هذا يمنع تحويل العجز إلى فائض عند المستخدمين قليلي الوزن/النشاط.
  if (maintenance <= floor) {
    return math.max(900.0, maintenance);
  }
  return math.max(target, floor);
}

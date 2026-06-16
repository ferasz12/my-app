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
  final factor = _safeActivityFactor(activityFactor);
  return (bmr * factor).roundToDouble();
}

/// يحسب السعرات النهائية حسب الهدف.
///
/// ملاحظات:
/// - BMR = Mifflin-St Jeor من الجنس/العمر/الوزن/الطول.
/// - TDEE = BMR × معامل النشاط.
/// - العجز/الفائض صار نسبيًا مع حدود منطقية بدل رقم ثابت دائمًا.
///   هذا يمنع نزول السعرات بقوة عند الأوزان الصغيرة، ويعطي هدفًا أوضح عند الأوزان العالية.
/// - أهداف "زيادة النشاط اليومي" و"ضبط السكر" تعتبر صيانة من ناحية السعرات،
///   والاختلاف يكون في توزيع الماكروز.
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
      target = maintenance - _clampDouble(maintenance * 0.20, 300.0, 700.0);
      break;
    case 'تنشيف الدهون':
      target = maintenance - _clampDouble(maintenance * 0.22, 350.0, 800.0);
      break;
    case 'بناء العضلات':
      target = maintenance + _clampDouble(maintenance * 0.08, 150.0, 350.0);
      break;
    case 'زيادة الوزن':
      target = maintenance + _clampDouble(maintenance * 0.15, 250.0, 650.0);
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

double _safeActivityFactor(double activityFactor) {
  if (!activityFactor.isFinite || activityFactor <= 0) return 1.55;
  return _clampDouble(activityFactor, 1.2, 1.95);
}

double _clampDouble(double value, double min, double max) {
  if (!value.isFinite) return min;
  return value.clamp(min, max).toDouble();
}

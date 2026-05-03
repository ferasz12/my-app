/// يحسب السعرات اليومية بناءً على:
/// - الجنس/العمر/الوزن/الطول
/// - عامل النشاط (مأخوذ من صفحة نمط الحياة)
/// - الهدف الصحي (من القائمة التالية فقط):
///   1) إنقاص الوزن        → عجز ~500 سعرة
///   2) تنشيف الدهون       → عجز نسبي ~22% من الصيانة
///   3) بناء العضلات       → فائض ~300 سعرة
///   4) زيادة الوزن        → فائض ~500 سعرة
///   5) نمط حياة صحي       → محافظة
///   6) زيادة النشاط اليومي → محافظة
///   7) ضبط مستوى السكر في الدم → محافظة
double calculateCalories({
  required int age,
  required String gender,         // "ذكر" أو "أنثى"
  required double weight,         // كجم
  required double height,         // سم
  required double activityFactor, // 1.2 - 1.9 (من صفحة نمط الحياة)
  required String goal,           // أحد الأهداف أعلاه
}) {
  // 1) BMR حسب معادلة Mifflin-St Jeor
  final bool isMale = (gender == 'ذكر');
  final double bmr = isMale
      ? (10 * weight + 6.25 * height - 5 * age + 5)
      : (10 * weight + 6.25 * height - 5 * age - 161);

  // 2) سعرات المحافظة حسب عامل النشاط
  final double maintenanceCalories = bmr * activityFactor;

  // 3) تطبيع نص الهدف (ودعم بعض الأسماء القديمة الموجودة عند بعض المستخدمين)
  final String g = goal.trim();
  double adjusted = maintenanceCalories;

  switch (g) {
    case 'إنقاص الوزن':
      adjusted = maintenanceCalories - 500; // عجز قياسي آمن
      break;

    case 'تنشيف الدهون': {
      // عجز نسبي صحي 20–25% (افتراضيًا 22%)
      const double deficitRatio = 0.22;
      adjusted = maintenanceCalories * (1.0 - deficitRatio);
      break;
    }

    case 'بناء العضلات':
      adjusted = maintenanceCalories + 300; // فائض خفيف للجودة
      break;

    case 'زيادة الوزن':
      adjusted = maintenanceCalories + 500; // فائض أوضح
      break;

    case 'نمط حياة صحي':
    case 'زيادة النشاط اليومي':
    case 'ضبط مستوى السكر في الدم':
      adjusted = maintenanceCalories; // محافظة
      break;

    // ===== تطبيع أسماء قديمة/سابق استخدامها =====
    case 'خفض الدهون':
      adjusted = maintenanceCalories - 500;
      break;
    case 'ضبط مستوى السكر':
    case 'تحسين الصحة العامة':
    case 'الصيام المتقطع':
    case 'اتباع رجيم نباتي':
    case 'رفع الطاقة والحيوية':
      adjusted = maintenanceCalories; // محافظة
      break;

    default:
      adjusted = maintenanceCalories; // افتراضيًا محافظة
      break;
  }

  return adjusted.roundToDouble();
}

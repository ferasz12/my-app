import 'package:flutter/material.dart';

/// الميزات المدفوعة داخل وازن.
///
/// هذا الملف مستقل عن منطق الشراء؛ هو فقط تعريف للميزات ونصوصها.
///
/// ملاحظة توافق: بعض الشاشات القديمة/الجديدة قد تستخدم أسماء مختلفة لنفس الفكرة
/// مثل (regimen/regimens) و (virtualClubGuide) لذلك تم دعمها هنا.
enum PremiumFeature {
  aiPhoto,
  aiText,
  restaurants,
  coach,
  trackingPdf,

  /// صفحات الدليل
  guide,

  /// النادي الافتراضي
  virtualGym,

  /// صفحة الدليل/النادي الافتراضي (مستخدمة في main_navigation_screen.dart)
  virtualClubGuide,

  recipes,

  /// رجيمي (قديمة)
  regimens,

  /// رجيمي (مستخدمة في main_navigation_screen.dart)
  regimen,

  theme,
  notifications,
}

extension PremiumFeatureX on PremiumFeature {
  String get titleAr {
    switch (this) {
      case PremiumFeature.aiPhoto:
        return 'تحليل الصور';
      case PremiumFeature.aiText:
        return 'تحليل النص';
      case PremiumFeature.restaurants:
        return 'الإضافة من المطاعم';
      case PremiumFeature.coach:
        return 'مدرب وازن الذكي';
      case PremiumFeature.trackingPdf:
        return 'تصدير التتبع PDF';
      case PremiumFeature.guide:
        return 'دليلك';
      case PremiumFeature.virtualGym:
        return 'النادي الافتراضي';
      case PremiumFeature.virtualClubGuide:
        return 'دليلك / النادي الافتراضي';
      case PremiumFeature.recipes:
        return 'الوصفات';
      case PremiumFeature.regimens:
      case PremiumFeature.regimen:
        return 'رجيمي';
      case PremiumFeature.theme:
        return 'تغيير المظهر';
      case PremiumFeature.notifications:
        return 'تخصيص الإشعارات';
    }
  }

  String get subtitleAr {
    switch (this) {
      case PremiumFeature.aiPhoto:
        return 'حلّل وجبتك من الصورة بدقة مع حساب السعرات والماكروز.';
      case PremiumFeature.aiText:
        return 'اكتب وصف الوجبة وخلك على طول تعرف السعرات والماكروز.';
      case PremiumFeature.restaurants:
        return 'اختيار وجبات المطاعم وإضافتها للسجل بسهولة.';
      case PremiumFeature.coach:
        return 'اسأل مدرب وازن الذكي وخذ توجيه حسب يومك.';
      case PremiumFeature.trackingPdf:
        return 'صدّر تقرير التتبع بشكل PDF مرتب.';
      case PremiumFeature.guide:
        return 'محتوى دليل وازن والنصائح المتقدمة.';
      case PremiumFeature.virtualGym:
        return 'تمارين النادي الافتراضي والمحتوى الكامل.';
      case PremiumFeature.virtualClubGuide:
        return 'دليلك + النادي الافتراضي والمحتوى الكامل.';
      case PremiumFeature.recipes:
        return 'استكشاف وإنشاء الوصفات داخل وازن.';
      case PremiumFeature.regimens:
      case PremiumFeature.regimen:
        return 'خطط رجيمي كاملة ومتابعتها.';
      case PremiumFeature.theme:
        return 'خصص الألوان والمظهر بالطريقة اللي تعجبك.';
      case PremiumFeature.notifications:
        return 'تحكم كامل في تذكيرات وإشعارات وازن.';
    }
  }

  IconData get icon {
    switch (this) {
      case PremiumFeature.aiPhoto:
        return Icons.camera_alt_outlined;
      case PremiumFeature.aiText:
        return Icons.text_snippet_outlined;
      case PremiumFeature.restaurants:
        return Icons.restaurant_menu;
      case PremiumFeature.coach:
        return Icons.chat_bubble_outline;
      case PremiumFeature.trackingPdf:
        return Icons.picture_as_pdf_outlined;
      case PremiumFeature.guide:
        return Icons.menu_book_outlined;
      case PremiumFeature.virtualGym:
        return Icons.fitness_center;
      case PremiumFeature.virtualClubGuide:
        return Icons.map_outlined;
      case PremiumFeature.recipes:
        return Icons.receipt_long_outlined;
      case PremiumFeature.regimens:
      case PremiumFeature.regimen:
        return Icons.local_hospital_outlined;
      case PremiumFeature.theme:
        return Icons.palette_outlined;
      case PremiumFeature.notifications:
        return Icons.notifications_active_outlined;
    }
  }
}

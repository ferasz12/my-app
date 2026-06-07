import 'package:flutter/material.dart';

/// الميزات المدفوعة داخل وازن.
///
/// هذا الملف مستقل عن منطق الشراء؛ هو فقط تعريف للميزات ونصوصها.
/// تم الإبقاء على بعض الأسماء القديمة كـ aliases حتى لا تتعطل الشاشات القديمة.
enum PremiumFeature {
  aiPhoto,
  aiText,

  /// المطاعم (الاسم الحالي)
  restaurants,

  /// المطاعم (اسم قديم لبعض الملفات)
  restaurantsAdd,

  /// مدرب وازن (الاسم الحالي)
  coach,

  /// مدرب وازن (اسم قديم لبعض الملفات)
  smartCoach,

  /// تصدير تقرير التتبع (الاسم الحالي)
  trackingPdf,

  /// تصدير تقرير التتبع (اسم قديم لبعض الملفات)
  pdfTracking,

  /// صفحات الدليل
  guide,

  /// النادي الافتراضي
  virtualGym,

  /// صفحة الدليل/النادي الافتراضي
  virtualClubGuide,

  recipes,

  /// رجيمي (قديمة)
  regimens,

  /// رجيمي (مستخدمة في main_navigation_screen.dart)
  regimen,

  /// المظهر (الاسم الحالي)
  theme,

  /// المظهر (اسم قديم لبعض الملفات)
  appearance,

  notifications,

  /// المزامنة السحابية اليدوية
  cloudSync,
}

extension PremiumFeatureX on PremiumFeature {
  String get titleAr {
    switch (this) {
      case PremiumFeature.aiPhoto:
        return 'تحليل الصور';
      case PremiumFeature.aiText:
        return 'تحليل النص';
      case PremiumFeature.restaurants:
      case PremiumFeature.restaurantsAdd:
        return 'الإضافة من المطاعم';
      case PremiumFeature.coach:
      case PremiumFeature.smartCoach:
        return 'مدرب وازن الذكي';
      case PremiumFeature.trackingPdf:
      case PremiumFeature.pdfTracking:
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
      case PremiumFeature.appearance:
        return 'تغيير المظهر';
      case PremiumFeature.notifications:
        return 'تخصيص الإشعارات';
      case PremiumFeature.cloudSync:
        return 'المزامنة السحابية';
    }
  }

  String get subtitleAr {
    switch (this) {
      case PremiumFeature.aiPhoto:
        return 'حلّل وجبتك من الصورة بدقة مع حساب السعرات والماكروز.';
      case PremiumFeature.aiText:
        return 'اكتب وصف الوجبة واعرف السعرات والماكروز بسهولة.';
      case PremiumFeature.restaurants:
      case PremiumFeature.restaurantsAdd:
        return 'اختيار وجبات المطاعم وإضافتها للسجل بسهولة.';
      case PremiumFeature.coach:
      case PremiumFeature.smartCoach:
        return 'اسأل مدرب وازن الذكي وخذ توجيه حسب يومك.';
      case PremiumFeature.trackingPdf:
      case PremiumFeature.pdfTracking:
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
      case PremiumFeature.appearance:
        return 'خصص الألوان والمظهر بالطريقة التي تناسبك.';
      case PremiumFeature.notifications:
        return 'تحكم كامل في تذكيرات وإشعارات وازن.';
      case PremiumFeature.cloudSync:
        return 'احفظ بياناتك واسترجعها عبر السحابة عند الحاجة.';
    }
  }

  IconData get icon {
    switch (this) {
      case PremiumFeature.aiPhoto:
        return Icons.camera_alt_outlined;
      case PremiumFeature.aiText:
        return Icons.text_snippet_outlined;
      case PremiumFeature.restaurants:
      case PremiumFeature.restaurantsAdd:
        return Icons.restaurant_menu;
      case PremiumFeature.coach:
      case PremiumFeature.smartCoach:
        return Icons.chat_bubble_outline;
      case PremiumFeature.trackingPdf:
      case PremiumFeature.pdfTracking:
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
      case PremiumFeature.appearance:
        return Icons.palette_outlined;
      case PremiumFeature.notifications:
        return Icons.notifications_active_outlined;
      case PremiumFeature.cloudSync:
        return Icons.cloud_sync_rounded;
    }
  }
}

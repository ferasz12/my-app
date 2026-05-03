import 'package:flutter/foundation.dart';

/// إشعار بسيط لتحديث أهداف الماكروز/السعرات بين الصفحات.
///
/// ملاحظة: التطبيق يستخدم IndexedStack في التنقّل الرئيسي،
/// وهذا يعني أن صفحة "الرئيسية" لا تُعاد بناؤها عند الرجوع من "بياناتي".
/// لذلك نستخدم [revision] كـ "نبضة" (event) لتحديث الأهداف فور حفظها.
class MacroTargetsController {
  /// تتغير قيمتها مع كل تحديث للأهداف.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// استدعها بعد حفظ أهداف جديدة (في صفحة بياناتي أو أي مكان).
  static void bump() {
    revision.value = revision.value + 1;
  }
}

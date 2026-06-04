// lib/notifications/notification_sync_service.dart
//
// تم تعطيل المزامنة التلقائية لإعدادات الإشعارات من Firestore عند فتح التطبيق.
// السبب: المستمعات والجدولة الكثيفة كانت تسبب تعليقًا عند الانتقال بين الصفحات.
//
// الإشعارات المهمة للمجتمع والرسائل تصل الآن عبر FCM + Cloud Functions،
// أما تذكيرات الماء/التمارين/النصائح فتُجدول فقط عندما يحفظ المستخدم إعداداتها من صفحة الإشعارات.

class NotificationSyncService {
  NotificationSyncService._();
  static final NotificationSyncService instance = NotificationSyncService._();

  bool _started = false;

  void start() {
    // no-op intentional: لا مزامنة/جدولة تلقائية بالخلفية.
    _started = true;
  }

  Future<void> dispose() async {
    _started = false;
  }

  bool get isStarted => _started;
}

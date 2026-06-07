// lib/services/end_of_day_cloud_backup_service.dart
// تم تعطيل النسخ الاحتياطي السحابي التلقائي بالكامل.
// هذا الملف يبقى كواجهة توافق فقط حتى لا تتأثر ملفات التتبع والماء الحالية.

import 'package:flutter/widgets.dart';

class DailyCloudBackupService with WidgetsBindingObserver {
  DailyCloudBackupService._();
  static final DailyCloudBackupService instance = DailyCloudBackupService._();

  void start() {
    // No-op: لا مؤقتات ولا اتصالات Firestore.
  }

  void dispose() {
    // No-op.
  }

  Future<void> markDirty() async {
    // No-op: الحفظ محلي فقط.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No-op.
  }

  Future<void> backupTodayNow({String reason = 'manual'}) async {
    // No-op.
  }

  Future<void> backupDay(
    String ymd, {
    String reason = 'scheduled',
    bool force = false,
  }) async {
    // No-op.
  }
}

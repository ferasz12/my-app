// lib/services/cloud_sync_service.dart
// تم تعطيل المزامنة السحابية بالكامل لأنها سببت بطء وتعليق في الصفحات.
// يبقى هذا الملف كواجهة توافق فقط حتى لا تنكسر الاستيرادات القديمة.

class CloudSyncCategory {
  final String id;
  final String title;
  final String description;

  const CloudSyncCategory({
    required this.id,
    required this.title,
    required this.description,
  });
}

class CloudSyncResult {
  final int categoriesCount;
  final int localKeysCount;
  final int cloudWritesCount;
  final int restoredKeysCount;
  final List<String> messages;

  const CloudSyncResult({
    required this.categoriesCount,
    required this.localKeysCount,
    required this.cloudWritesCount,
    required this.restoredKeysCount,
    required this.messages,
  });

  String get summary => messages.isEmpty ? 'المزامنة السحابية متوقفة حاليًا.' : messages.join('\n');
}

class CloudSyncService {
  CloudSyncService._();

  static const String allCategoryId = 'all';
  static const List<CloudSyncCategory> categories = <CloudSyncCategory>[];

  static List<String> normalizeCategoryIds(Iterable<String> ids) => const <String>[];

  static Future<bool> hasActiveSubscription() async => false;

  static Future<Map<String, DateTime?>> readLastSyncTimes() async => <String, DateTime?>{};

  static Future<CloudSyncResult> upload({required Iterable<String> categoryIds}) async {
    return const CloudSyncResult(
      categoriesCount: 0,
      localKeysCount: 0,
      cloudWritesCount: 0,
      restoredKeysCount: 0,
      messages: <String>['المزامنة السحابية متوقفة حاليًا. بياناتك الحالية تبقى محفوظة محليًا على الجهاز.'],
    );
  }

  static Future<CloudSyncResult> restore({required Iterable<String> categoryIds}) async {
    return const CloudSyncResult(
      categoriesCount: 0,
      localKeysCount: 0,
      cloudWritesCount: 0,
      restoredKeysCount: 0,
      messages: <String>['استرجاع المزامنة السحابية متوقف حاليًا.'],
    );
  }
}

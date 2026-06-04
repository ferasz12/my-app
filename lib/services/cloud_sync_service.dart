// lib/services/cloud_sync_service.dart
// مزامنة يدوية آمنة للمشتركين فقط.
// تحفظ بيانات SharedPreferences المهمة في Firestore، وتكتب سجلات اليوم/الأيام
// بشكل منظم داخل users/{uid}/days حتى لا تضيع السعرات والماء والتتبع.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'end_of_day_cloud_backup_service.dart';

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

  String get summary {
    if (messages.isNotEmpty) return messages.join('\n');
    if (restoredKeysCount > 0) {
      return 'تم استرجاع $restoredKeysCount عنصر من السحابة.';
    }
    return 'تمت مزامنة $localKeysCount عنصر في $categoriesCount قسم.';
  }
}

class CloudSyncService {
  CloudSyncService._();

  static const String allCategoryId = 'all';
  static const List<CloudSyncCategory> categories = <CloudSyncCategory>[
    CloudSyncCategory(
      id: 'profile',
      title: 'بياناتي وأهدافي',
      description: 'العمر، الطول، الوزن، الهدف، الماكروز، أهداف الماء والخطوات والنوم.',
    ),
    CloudSyncCategory(
      id: 'calories',
      title: 'سجل السعرات والوجبات',
      description: 'مجاميع السعرات والماكروز، الوجبات، وعناصر سجل الأكل اليومية.',
    ),
    CloudSyncCategory(
      id: 'water',
      title: 'سجل الماء',
      description: 'أيام شرب الماء، هدف الماء، وإجماليات الماء اليومية.',
    ),
    CloudSyncCategory(
      id: 'tracking',
      title: 'صفحة التتبع والصحة',
      description: 'سجل الوزن، النشاط، الخطوات، Apple Health، النوم والنبض إذا كانت متاحة.',
    ),
    CloudSyncCategory(
      id: 'settings',
      title: 'الإعدادات والإشعارات',
      description: 'الثيم، حجم الخط، اللغة، تفضيلات الإشعارات والتنبيهات.',
    ),
    CloudSyncCategory(
      id: 'plans',
      title: 'الرجيم والتمارين',
      description: 'النظام الغذائي النشط، الصيام، الكيتو/لو كارب، الجداول الرياضية والتمارين.',
    ),
  ];

  static List<String> normalizeCategoryIds(Iterable<String> ids) {
    final requested = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (requested.contains(allCategoryId)) {
      return categories.map((c) => c.id).toList(growable: false);
    }
    final allowed = categories.map((c) => c.id).toSet();
    return requested.where(allowed.contains).toList(growable: false)..sort();
  }

  static Future<bool> hasActiveSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final now = DateTime.now();

    // 1) قراءة محلية سريعة، حتى لو فتح المستخدم الصفحة بدون نت.
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (prefs.getString('currentEmail') ?? user.email ?? '').trim();
      final uidExpiry = _dateFromMillis(prefs.getInt('subscriptionExpiry_uid_${user.uid}'));
      final emailExpiry = email.isEmpty ? null : _dateFromMillis(prefs.getInt('subscriptionExpiry_$email'));
      if ((uidExpiry != null && uidExpiry.isAfter(now)) ||
          (emailExpiry != null && emailExpiry.isAfter(now))) {
        return true;
      }
    } catch (_) {}

    // 2) قراءة السحابة هي المصدر الأهم للاشتراك والمنح.
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get().timeout(const Duration(seconds: 8));
      final data = snap.data();
      final expiry = _readBestEntitlementExpiry(data);
      return expiry != null && expiry.isAfter(now);
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, DateTime?>> readLastSyncTimes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String, DateTime?>{};
    final result = <String, DateTime?>{};
    try {
      final col = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('syncMeta');
      final snaps = await Future.wait(categories.map((c) => col.doc(c.id).get().timeout(const Duration(seconds: 4))));
      for (int i = 0; i < categories.length; i++) {
        result[categories[i].id] = _coerceDate(snaps[i].data()?['updatedAt']);
      }
    } catch (_) {}
    return result;
  }

  static Future<CloudSyncResult> upload({required Iterable<String> categoryIds}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول قبل المزامنة.');
    if (!await hasActiveSubscription()) {
      throw StateError('المزامنة السحابية متاحة للمشتركين فقط.');
    }

    final ids = normalizeCategoryIds(categoryIds);
    if (ids.isEmpty) throw StateError('اختر قسمًا واحدًا على الأقل للمزامنة.');

    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail(prefs, user);
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final now = Timestamp.now();

    int localKeysCount = 0;
    int writes = 0;
    final messages = <String>[];

    await userRef.set({
      'uid': user.uid,
      'email': user.email,
      'sync': {
        'lastManualSyncAt': now,
        'lastManualSyncCategories': ids,
      },
      'updatedAt': now,
    }, SetOptions(merge: true));
    writes++;

    for (final id in ids) {
      final picked = _collectPrefsForCategory(prefs: prefs, categoryId: id, email: email, uid: user.uid);
      localKeysCount += picked.length;

      final backupRef = userRef.collection('syncBackups').doc(id);
      final chunks = _splitEncodedMap(picked);
      await backupRef.set({
        'categoryId': id,
        'emailKey': email,
        'uid': user.uid,
        'schema': 3,
        'keysCount': picked.length,
        'chunksCount': chunks.length,
        'updatedAt': now,
      }, SetOptions(merge: true));
      writes++;

      for (int i = 0; i < chunks.length; i++) {
        await backupRef.collection('chunks').doc('chunk_${i.toString().padLeft(3, '0')}').set({
          'index': i,
          'data': chunks[i],
          'updatedAt': now,
        }, SetOptions(merge: true));
        writes++;
      }

      await userRef.collection('syncMeta').doc(id).set({
        'categoryId': id,
        'keysCount': picked.length,
        'chunksCount': chunks.length,
        'updatedAt': now,
      }, SetOptions(merge: true));
      writes++;
    }

    if (ids.contains('calories')) {
      final count = await _uploadCaloriesDays(prefs: prefs, userRef: userRef, email: email);
      writes += count;
      messages.add('تم رفع سجل السعرات والوجبات.');
    }

    if (ids.contains('water')) {
      final count = await _uploadWaterDays(prefs: prefs, userRef: userRef, email: email);
      writes += count;
      messages.add('تم رفع سجل الماء.');
    }

    if (ids.contains('tracking')) {
      final count = await _uploadTrackingDays(prefs: prefs, userRef: userRef, email: email);
      writes += count;
      messages.add('تم رفع بيانات التتبع والصحة.');
    }

    // إذا المستخدم يزامن بيانات يومية، نرفع لقطة اليوم الحالية فوراً أيضاً.
    if (ids.any((id) => id == 'calories' || id == 'water' || id == 'tracking')) {
      unawaited(DailyCloudBackupService.instance.backupTodayNow(reason: 'manual_cloud_sync').catchError((_) {}));
    }

    await userRef.collection('syncMeta').doc('latest').set({
      'categories': ids,
      'keysCount': localKeysCount,
      'cloudWritesCount': writes,
      'updatedAt': now,
    }, SetOptions(merge: true));

    return CloudSyncResult(
      categoriesCount: ids.length,
      localKeysCount: localKeysCount,
      cloudWritesCount: writes,
      restoredKeysCount: 0,
      messages: messages,
    );
  }

  static Future<CloudSyncResult> restore({required Iterable<String> categoryIds}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول قبل الاسترجاع.');
    if (!await hasActiveSubscription()) {
      throw StateError('الاسترجاع السحابي متاح للمشتركين فقط.');
    }

    final ids = normalizeCategoryIds(categoryIds);
    if (ids.isEmpty) throw StateError('اختر قسمًا واحدًا على الأقل للاسترجاع.');

    final prefs = await SharedPreferences.getInstance();
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    int restored = 0;
    final messages = <String>[];

    for (final id in ids) {
      final backupRef = userRef.collection('syncBackups').doc(id);
      final doc = await backupRef.get().timeout(const Duration(seconds: 12));
      final data = doc.data();
      if (data == null) {
        messages.add('لا توجد نسخة محفوظة لقسم: ${_titleFor(id)}');
        continue;
      }

      final restoredMap = <String, dynamic>{};
      final legacyRaw = data['data'];
      if (legacyRaw is Map) {
        restoredMap.addAll(Map<String, dynamic>.from(legacyRaw));
      } else {
        final chunksCount = (data['chunksCount'] as num?)?.toInt() ?? 0;
        if (chunksCount <= 0) {
          messages.add('لا توجد نسخة محفوظة لقسم: ${_titleFor(id)}');
          continue;
        }
        for (int i = 0; i < chunksCount; i++) {
          final chunk = await backupRef
              .collection('chunks')
              .doc('chunk_${i.toString().padLeft(3, '0')}')
              .get()
              .timeout(const Duration(seconds: 8));
          final rawChunk = chunk.data()?['data'];
          if (rawChunk is Map) restoredMap.addAll(Map<String, dynamic>.from(rawChunk));
        }
      }

      for (final entry in restoredMap.entries) {
        final key = entry.key.toString();
        if (_isExcludedKey(key)) continue;
        final value = entry.value;
        final ok = await _writePrefValue(prefs, key, value);
        if (ok) restored++;
      }
    }

    await userRef.collection('syncMeta').doc('lastRestore').set({
      'categories': ids,
      'restoredKeysCount': restored,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    return CloudSyncResult(
      categoriesCount: ids.length,
      localKeysCount: 0,
      cloudWritesCount: 1,
      restoredKeysCount: restored,
      messages: messages,
    );
  }

  static String _titleFor(String id) {
    for (final c in categories) {
      if (c.id == id) return c.title;
    }
    return id;
  }

  static Future<String> _currentEmail(SharedPreferences prefs, User user) async {
    final email = (prefs.getString('currentEmail') ?? user.email ?? user.uid).trim();
    if (email.isNotEmpty && prefs.getString('currentEmail') == null) {
      await prefs.setString('currentEmail', email);
    }
    if (prefs.getString('currentUid') == null) {
      await prefs.setString('currentUid', user.uid);
    }
    return email.isEmpty ? user.uid : email;
  }

  static Map<String, dynamic> _collectPrefsForCategory({
    required SharedPreferences prefs,
    required String categoryId,
    required String email,
    required String uid,
  }) {
    final out = <String, dynamic>{};
    final keys = prefs.getKeys().toList()..sort();
    for (final key in keys) {
      if (_isExcludedKey(key)) continue;
      if (!_belongsToCategory(key, categoryId: categoryId, email: email, uid: uid)) continue;
      final encoded = _encodePrefValue(prefs, key);
      if (encoded != null) out[key] = encoded;
    }
    return out;
  }

  static bool _belongsToCategory(
    String key, {
    required String categoryId,
    required String email,
    required String uid,
  }) {
    if (categoryId == allCategoryId) return true;

    final lower = key.toLowerCase();
    final emailLower = email.toLowerCase();
    final scoped = lower.contains(emailLower) || lower.contains(uid.toLowerCase());

    switch (categoryId) {
      case 'profile':
        return key == 'currentEmail' ||
            key == 'currentUid' ||
            _startsAny(lower, const [
              'name_',
              'username_',
              'displayname_',
              'bio_',
              'gender_',
              'age_',
              'height_',
              'weight_',
              'current_weight_',
              'goal_',
              'goalhistory_',
              'goal_history_',
              'caloriesneeded_',
              'maintenancecalories_',
              'protein_',
              'fat_',
              'carbs_',
              'activityfactor_',
              'macro',
              'watermltarget_',
              'stepstarget_',
              'sleephourstarget_',
              'lifestylescore_',
              'profileupdatedat_',
              'macrosupdatedat_',
              'lastupdated_',
            ]) && (scoped || !lower.contains('_'));

      case 'calories':
        return lower.startsWith('diet_') ||
            lower.startsWith('dietcalories_') ||
            lower.startsWith('dietprotein_') ||
            lower.startsWith('dietcarb_') ||
            lower.startsWith('dietfat_') ||
            lower.startsWith('kcal_daytotals_') ||
            lower.startsWith('intake_entries_') ||
            lower.startsWith('kcal_entries_') ||
            lower.startsWith('meals_') ||
            lower.startsWith('ready_foods_') ||
            lower.startsWith('custom_foods_') ||
            lower.startsWith('eod_cloud_backup_') ||
            lower.startsWith('eod_cloud_dirty_');

      case 'water':
        return lower.startsWith('water_log_') ||
            lower.startsWith('water_total_') ||
            lower.startsWith('water_') ||
            lower.startsWith('waterml_') ||
            lower.startsWith('water_ml_') ||
            lower.startsWith('watermltarget_');

      case 'tracking':
        return lower.startsWith('weight_log_') ||
            lower.startsWith('current_weight_') ||
            lower.startsWith('activity_') ||
            lower.startsWith('health_') ||
            lower.startsWith('steps_') ||
            lower.startsWith('sleep') ||
            lower.contains('heartrate') ||
            lower.contains('hrv') ||
            lower.contains('bodytemperature') ||
            lower.contains('oxygen') ||
            lower.contains('bmi');

      case 'settings':
        return lower.contains('notification') ||
            lower.contains('notify') ||
            lower.contains('reminder') ||
            lower.contains('theme') ||
            lower.contains('font') ||
            lower.contains('language') ||
            lower.contains('locale') ||
            lower.contains('dark') ||
            lower.contains('marketing') ||
            lower.contains('broadcast');

      case 'plans':
        return lower.contains('regimen') ||
            lower.contains('fasting') ||
            lower.contains('keto') ||
            lower.contains('lowcarb') ||
            lower.contains('lowfat') ||
            lower.contains('schedule') ||
            lower.contains('workout') ||
            lower.contains('training') ||
            lower.contains('selectedplan') ||
            lower.contains('custom_schedule');
    }

    return false;
  }

  static bool _startsAny(String value, List<String> prefixes) {
    for (final p in prefixes) {
      if (value.startsWith(p)) return true;
    }
    return false;
  }

  static bool _isExcludedKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('password') ||
        lower.contains('secret') ||
        lower.contains('privatekey') ||
        lower.contains('authkey') ||
        lower.contains('apikey') ||
        lower.contains('token') ||
        lower.contains('fcm') ||
        lower.contains('apns') ||
        lower.contains('receipt') ||
        lower.contains('purchase') ||
        lower.contains('transaction') ||
        lower.contains('sessioncookie') ||
        lower.contains('csrf');
  }

  static Map<String, dynamic>? _encodePrefValue(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value == null) return null;
    if (value is bool) return {'type': 'bool', 'value': value};
    if (value is int) return {'type': 'int', 'value': value};
    if (value is double) return {'type': 'double', 'value': value};
    if (value is String) return {'type': 'string', 'value': value};
    if (value is List<String>) return {'type': 'stringList', 'value': value};
    return null;
  }

  static List<Map<String, dynamic>> _splitEncodedMap(Map<String, dynamic> input) {
    if (input.isEmpty) return <Map<String, dynamic>>[<String, dynamic>{}];
    const int maxApproxBytes = 520 * 1024;
    final chunks = <Map<String, dynamic>>[];
    var current = <String, dynamic>{};
    var currentBytes = 0;

    for (final entry in input.entries) {
      final approx = utf8.encode(jsonEncode({entry.key: entry.value})).length;
      if (current.isNotEmpty && currentBytes + approx > maxApproxBytes) {
        chunks.add(current);
        current = <String, dynamic>{};
        currentBytes = 0;
      }
      current[entry.key] = entry.value;
      currentBytes += approx;
    }

    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  static Future<bool> _writePrefValue(SharedPreferences prefs, String key, dynamic encoded) async {
    if (encoded is! Map) return false;
    final map = Map<String, dynamic>.from(encoded);
    final type = (map['type'] ?? '').toString();
    final value = map['value'];
    try {
      switch (type) {
        case 'bool':
          if (value is bool) return prefs.setBool(key, value);
          return false;
        case 'int':
          if (value is int) return prefs.setInt(key, value);
          if (value is num) return prefs.setInt(key, value.toInt());
          return false;
        case 'double':
          if (value is num) return prefs.setDouble(key, value.toDouble());
          return false;
        case 'string':
          return prefs.setString(key, value?.toString() ?? '');
        case 'stringList':
          if (value is Iterable) return prefs.setStringList(key, value.map((e) => e.toString()).toList());
          return false;
      }
    } catch (_) {}
    return false;
  }

  static Future<int> _uploadCaloriesDays({
    required SharedPreferences prefs,
    required DocumentReference<Map<String, dynamic>> userRef,
    required String email,
  }) async {
    final days = <String>{};
    final totalsPrefix = 'kcal_daytotals_${email}_';
    final entriesPrefix = 'intake_entries_${email}_';

    for (final key in prefs.getKeys()) {
      if (key.startsWith(totalsPrefix)) days.add(key.substring(totalsPrefix.length));
      if (key.startsWith(entriesPrefix)) days.add(key.substring(entriesPrefix.length));
      if (_isDietDayKey(key)) days.add(key.substring('diet_'.length));
    }

    int writes = 0;
    final batcher = _FirestoreBatcher();
    final now = Timestamp.now();

    for (final ymd in days.where(_looksLikeYmd)) {
      final totals = _jsonMap(prefs.getString('kcal_daytotals_${email}_$ymd')) ??
          _legacyDietTotals(prefs.getString('diet_$ymd'));
      final entries = _jsonList(prefs.getString('intake_entries_${email}_$ymd'));
      final dayRef = userRef.collection('days').doc(ymd);
      final hasTotals = totals.values.any((v) => _toD(v) > 0);
      if (!hasTotals && entries.isEmpty) continue;

      await batcher.set(dayRef, {
        'date': ymd,
        'intake': {
          'totals': {
            'k': _toD(totals['k'] ?? totals['calories']),
            'p': _toD(totals['p'] ?? totals['protein']),
            'c': _toD(totals['c'] ?? totals['carb'] ?? totals['carbs']),
            'f': _toD(totals['f'] ?? totals['fat']),
          },
          'entries': entries,
          'updatedAt': now,
        },
        'updatedAt': now,
      }, SetOptions(merge: true));
      writes++;
    }

    await batcher.commit();
    return writes;
  }

  static Future<int> _uploadWaterDays({
    required SharedPreferences prefs,
    required DocumentReference<Map<String, dynamic>> userRef,
    required String email,
  }) async {
    final waterByDay = <String, double>{};
    final log = _jsonMap(prefs.getString('water_log_$email')) ?? <String, dynamic>{};
    for (final e in log.entries) {
      if (_looksLikeYmd(e.key)) waterByDay[e.key] = _toD(e.value);
    }

    for (final key in prefs.getKeys()) {
      final p1 = 'water_';
      final suffix = '_$email';
      if (key.startsWith(p1) && key.endsWith(suffix)) {
        final ymd = key.substring(p1.length, key.length - suffix.length);
        if (_looksLikeYmd(ymd)) waterByDay[ymd] = prefs.getDouble(key) ?? waterByDay[ymd] ?? 0.0;
      }
      final totalPrefix = 'water_total_${email}_';
      if (key.startsWith(totalPrefix)) {
        final ymd = key.substring(totalPrefix.length);
        if (_looksLikeYmd(ymd)) waterByDay[ymd] = double.tryParse(prefs.getString(key) ?? '') ?? waterByDay[ymd] ?? 0.0;
      }
    }

    int writes = 0;
    final batcher = _FirestoreBatcher();
    final now = Timestamp.now();
    for (final e in waterByDay.entries) {
      final liters = e.value < 0 ? 0.0 : e.value;
      if (liters <= 0) continue;
      await batcher.set(userRef.collection('days').doc(e.key), {
        'date': e.key,
        'water': {
          'liters': liters,
          'updatedAt': now,
        },
        'updatedAt': now,
      }, SetOptions(merge: true));
      writes++;
    }

    await batcher.commit();
    return writes;
  }

  static Future<int> _uploadTrackingDays({
    required SharedPreferences prefs,
    required DocumentReference<Map<String, dynamic>> userRef,
    required String email,
  }) async {
    final payloadByDay = <String, Map<String, dynamic>>{};

    final weightList = _jsonList(prefs.getString('weight_log_$email'));
    for (final row in weightList) {
      final ymd = (row['date'] ?? '').toString();
      final kg = _toD(row['kg'] ?? row['weight']);
      if (_looksLikeYmd(ymd) && kg > 0) {
        payloadByDay.putIfAbsent(ymd, () => <String, dynamic>{})['tracking'] = {
          'weightKg': kg,
          'updatedAt': Timestamp.now(),
        };
        payloadByDay[ymd]!['currentWeightKg'] = kg;
      }
    }

    for (final key in prefs.getKeys()) {
      final activityPrefix = 'activity_';
      final healthPrefix = 'health_';
      final suffix = '_$email';
      if (key.startsWith(activityPrefix) && key.endsWith(suffix)) {
        final ymd = key.substring(activityPrefix.length, key.length - suffix.length);
        if (_looksLikeYmd(ymd)) {
          final activity = _jsonMap(prefs.getString(key)) ?? <String, dynamic>{};
          if (activity.isNotEmpty) {
            payloadByDay.putIfAbsent(ymd, () => <String, dynamic>{})['activity'] = {
              ...activity,
              'updatedAt': Timestamp.now(),
            };
          }
        }
      }
      if (key.startsWith(healthPrefix) && key.endsWith(suffix)) {
        final ymd = key.substring(healthPrefix.length, key.length - suffix.length);
        if (_looksLikeYmd(ymd)) {
          final health = _jsonMap(prefs.getString(key)) ?? <String, dynamic>{};
          if (health.isNotEmpty) {
            payloadByDay.putIfAbsent(ymd, () => <String, dynamic>{})['healthMetrics'] = {
              ...health,
              'updatedAt': Timestamp.now(),
            };
          }
        }
      }
    }

    int writes = 0;
    final batcher = _FirestoreBatcher();
    final now = Timestamp.now();
    for (final e in payloadByDay.entries) {
      final data = <String, dynamic>{
        'date': e.key,
        ...e.value,
        'updatedAt': now,
      };
      await batcher.set(userRef.collection('days').doc(e.key), data, SetOptions(merge: true));
      writes++;
    }

    await batcher.commit();
    return writes;
  }

  static Map<String, dynamic> _legacyDietTotals(String? raw) {
    final m = _jsonMap(raw) ?? <String, dynamic>{};
    return {
      'k': _toD(m['k'] ?? m['calories']),
      'p': _toD(m['p'] ?? m['protein']),
      'c': _toD(m['c'] ?? m['carb'] ?? m['carbs']),
      'f': _toD(m['f'] ?? m['fat']),
    };
  }

  static bool _isDietDayKey(String key) {
    if (!key.startsWith('diet_')) return false;
    final rest = key.substring('diet_'.length);
    return _looksLikeYmd(rest);
  }

  static bool _looksLikeYmd(String value) {
    if (value.length != 10) return false;
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    return re.hasMatch(value);
  }

  static Map<String, dynamic>? _jsonMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> _jsonList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static DateTime? _dateFromMillis(int? ms) {
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static DateTime? _readBestEntitlementExpiry(Map<String, dynamic>? data) {
    if (data == null) return null;

    DateTime? subscriptionExpiry;
    final subAny = data['subscription'];
    final sub = subAny is Map ? Map<String, dynamic>.from(subAny) : null;
    final source = (sub?['source'] ?? '').toString().toUpperCase();
    if (!source.contains('FALLBACK') && !source.contains('NO_APP_RECEIPT')) {
      subscriptionExpiry = _coerceDate(sub?['expiry'], alt: sub?['expiryMillis']);
    }

    DateTime? ownerGrantExpiry;
    final grantAny = data['ownerGrant'];
    final grant = grantAny is Map ? Map<String, dynamic>.from(grantAny) : null;
    ownerGrantExpiry = _coerceDate(grant?['expiry'], alt: grant?['expiryMillis']);

    if (subscriptionExpiry == null) return ownerGrantExpiry;
    if (ownerGrantExpiry == null) return subscriptionExpiry;
    return subscriptionExpiry.isAfter(ownerGrantExpiry) ? subscriptionExpiry : ownerGrantExpiry;
  }

  static DateTime? _coerceDate(dynamic value, {dynamic alt}) {
    for (final candidate in <dynamic>[value, alt]) {
      if (candidate is Timestamp) return candidate.toDate();
      if (candidate is int) return DateTime.fromMillisecondsSinceEpoch(candidate);
      if (candidate is num) return DateTime.fromMillisecondsSinceEpoch(candidate.toInt());
      if (candidate is String && candidate.trim().isNotEmpty) {
        final d = DateTime.tryParse(candidate.trim());
        if (d != null) return d;
      }
    }
    return null;
  }
}

class _FirestoreBatcher {
  WriteBatch? _batch;
  int _count = 0;

  Future<void> set(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data, SetOptions options) async {
    _batch ??= FirebaseFirestore.instance.batch();
    _batch!.set(ref, data, options);
    _count++;
    if (_count >= 450) {
      await commit();
    }
  }

  Future<void> commit() async {
    if (_batch == null || _count == 0) return;
    await _batch!.commit();
    _batch = null;
    _count = 0;
  }
}

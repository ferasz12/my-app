// lib/services/smart_cloud_sync_service.dart
// خدمة المزامنة السحابية اليدوية.
// يتم تشغيلها من صفحة الإعدادات فقط، مع منع تكرار العملية أثناء التنفيذ.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/session_manager.dart';
import '../core/data/wazen_identity_store.dart';
import '../shared/macro_targets_controller.dart';
import '../shared/weight_live_bus.dart';

class SmartCloudSyncProgress {
  const SmartCloudSyncProgress({
    required this.stage,
    required this.current,
    required this.total,
    required this.message,
  });

  final String stage;
  final int current;
  final int total;
  final String message;

  double get ratio {
    if (total <= 0) return 0;
    return (current / total).clamp(0.0, 1.0);
  }
}

class SmartCloudSyncResult {
  const SmartCloudSyncResult({
    required this.success,
    required this.message,
    required this.uploadedDays,
    required this.restoredDays,
    required this.writes,
    required this.startedAt,
    required this.finishedAt,
  });

  final bool success;
  final String message;
  final int uploadedDays;
  final int restoredDays;
  final int writes;
  final DateTime startedAt;
  final DateTime finishedAt;

  Duration get duration => finishedAt.difference(startedAt);
}

class SmartCloudSyncStatus {
  const SmartCloudSyncStatus({
    required this.enabled,
    required this.running,
    required this.lastUploadAt,
    required this.lastRestoreAt,
    required this.localDaysCount,
    required this.cloudDaysCount,
    required this.hasCloudBackup,
    required this.cloudLastUploadAt,
  });

  final bool enabled;
  final bool running;
  final DateTime? lastUploadAt;
  final DateTime? lastRestoreAt;
  final int localDaysCount;
  final int cloudDaysCount;
  final bool hasCloudBackup;
  final DateTime? cloudLastUploadAt;
}

class SmartCloudSyncException implements Exception {
  const SmartCloudSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SmartCloudSyncService {
  SmartCloudSyncService._();

  static final SmartCloudSyncService instance = SmartCloudSyncService._();

  static const int schemaVersion = 3;
  static const int defaultDayLimit = 90;
  static const int maxDayLimit = 180;
  static const String _deletedDaysKey = 'wazen_deleted_calorie_days';

  List<String> _safeStringList(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value == null) return <String>[];
    if (value is List<String>) return value;
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return <String>[];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
      return <String>[raw];
    }
    return <String>[];
  }

  bool _running = false;

  bool get isRunning => _running;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<T> _withFirestoreRetry<T>(
    Future<T> Function() task, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await task().timeout(timeout);
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (attempt == 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
  }

  User _requireUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SmartCloudSyncException('يرجى تسجيل الدخول قبل بدء المزامنة.');
    }
    return user;
  }

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  static double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static int _toI(dynamic v) {
    if (v is num) return v.toInt();
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> _decodeListOfMaps(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static bool _looksLikeYmd(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
  }

  static Iterable<String> _extractYmdsFromKey(String key) sync* {
    final rx = RegExp(r'(\d{4}-\d{2}-\d{2})');
    for (final m in rx.allMatches(key)) {
      final v = m.group(1);
      if (v != null && _looksLikeYmd(v)) yield v;
    }
  }


  Set<String> _readDeletedDays(SharedPreferences prefs) {
    return _safeStringList(prefs, _deletedDaysKey)
        .map((e) => e.trim())
        .where(_looksLikeYmd)
        .toSet();
  }

  Future<void> _writeDeletedDays(SharedPreferences prefs, Set<String> days) async {
    final list = days.where(_looksLikeYmd).toList()..sort((a, b) => b.compareTo(a));
    await prefs.setStringList(_deletedDaysKey, list);
  }

  Future<void> _deleteCloudDay(String uid, String ymd) async {
    final userRef = _db.collection('users').doc(uid);
    final batch = _db.batch();
    batch.delete(userRef.collection('days').doc(ymd));
    batch.set(
      userRef,
      {
        'cloudDeletedCalorieDays': FieldValue.arrayUnion([ymd]),
        'cloudSync': {
          'deletedDaysUpdatedAt': FieldValue.serverTimestamp(),
          'schema': schemaVersion,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<WazenIdentity> _identity(SharedPreferences prefs, User user) async {
    // لا نشغل mirrorKnownLocalKeys هنا حتى لا يمنع نسخ بيانات الاسترجاع بسبب مهلة الحماية.
    return WazenIdentityStore.syncFromFirebaseUser(user, prefs: prefs, migrate: false);
  }

  Future<List<String>> _aliasesForUser(SharedPreferences prefs, User user) async {
    final id = await WazenIdentityStore.currentIdentity(user: user, migrate: false);
    final sessionKey = await SessionManager.currentStorageKey();
    return <String>{
      id.storageKey.trim(),
      id.uid.trim(),
      id.email.trim(),
      id.emailKey.trim(),
      ...id.aliases.map((e) => e.trim()),
      (user.email ?? '').trim().toLowerCase(),
      sessionKey.trim(),
    }.where((e) => e.isNotEmpty && e != 'unknown_user').toList(growable: false);
  }

  Future<void> _setPrefForAliases(
    SharedPreferences prefs,
    Iterable<String> aliases,
    String Function(String alias) keyBuilder,
    Object? value, {
    required bool overwriteLocal,
    bool allowZeroDouble = false,
  }) async {
    if (value == null) return;
    for (final alias in aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet()) {
      final key = keyBuilder(alias);
      final existing = prefs.get(key);
      final hasExisting = existing != null && (!(existing is String) || existing.trim().isNotEmpty);
      if (!overwriteLocal && hasExisting) continue;
      if (value is String) {
        final s = value.trim();
        if (s.isNotEmpty) await prefs.setString(key, s);
      } else if (value is int) {
        if (value > 0 || allowZeroDouble) await prefs.setInt(key, value);
      } else if (value is double) {
        if (value > 0 || allowZeroDouble) await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      } else {
        await prefs.setString(key, value.toString());
      }
    }
  }

  Future<String> _emailKey(SharedPreferences prefs, User user) async {
    final id = await _identity(prefs, user);
    return id.emailKey;
  }

  Future<SmartCloudSyncStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    final days = _discoverLocalDays(prefs).length;
    var cloudDays = prefs.getInt('manual_cloud_sync_cloud_days_count') ?? 0;
    var cloudLastUpload = _parseDate(prefs.getString('manual_cloud_sync_cloud_last_upload_at'));
    var hasCloudBackup = prefs.getBool('manual_cloud_sync_has_cloud_backup') ?? false;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userSnap = await _db
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 8));
        final data = userSnap.data();
        if (data != null) {
          hasCloudBackup = true;
          final cloudSync = data['cloudSync'];
          dynamic lastRaw;
          if (cloudSync is Map) lastRaw = cloudSync['lastUploadAt'];
          cloudLastUpload = _dateFromCloud(lastRaw) ??
              _dateFromCloud(data['updatedAt']) ??
              cloudLastUpload;
        }
        final q = await _db
            .collection('users')
            .doc(user.uid)
            .collection('days')
            .orderBy('date', descending: true)
            .limit(maxDayLimit)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 8));
        cloudDays = q.docs.length;
        hasCloudBackup = hasCloudBackup || cloudDays > 0;
        await prefs.setInt('manual_cloud_sync_cloud_days_count', cloudDays);
        await prefs.setBool('manual_cloud_sync_has_cloud_backup', hasCloudBackup);
        if (cloudLastUpload != null) {
          await prefs.setString('manual_cloud_sync_cloud_last_upload_at', cloudLastUpload.toIso8601String());
        }
      } catch (_) {}
    }

    return SmartCloudSyncStatus(
      enabled: prefs.getBool('manual_cloud_sync_enabled') ?? false,
      running: _running,
      lastUploadAt: _parseDate(prefs.getString('manual_cloud_sync_last_upload_at')),
      lastRestoreAt: _parseDate(prefs.getString('manual_cloud_sync_last_restore_at')),
      localDaysCount: days,
      cloudDaysCount: cloudDays,
      hasCloudBackup: hasCloudBackup,
      cloudLastUploadAt: cloudLastUpload,
    );
  }

  DateTime? _dateFromCloud(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('manual_cloud_sync_enabled', value);
  }

  /// رفع يدوي لبيانات المستخدم من الجهاز إلى Firestore.
  Future<SmartCloudSyncResult> uploadLocalData({
    int dayLimit = defaultDayLimit,
    void Function(SmartCloudSyncProgress progress)? onProgress,
  }) async {
    if (_running) {
      throw const SmartCloudSyncException('توجد عملية مزامنة قيد التنفيذ. يرجى الانتظار حتى اكتمالها.');
    }

    final startedAt = DateTime.now();
    _running = true;
    try {
      final user = _requireUser();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('manual_cloud_sync_enabled', true);

      onProgress?.call(const SmartCloudSyncProgress(
        stage: 'prepare',
        current: 0,
        total: 1,
        message: 'جاري تجهيز البيانات المحلية...',
      ));

      final id = await _identity(prefs, user);
      final email = id.emailKey;
      final safeLimit = dayLimit.clamp(1, maxDayLimit).toInt();
      final deletedDays = _readDeletedDays(prefs).take(safeLimit).toList();
      final deletedSet = deletedDays.toSet();
      final localDays = _discoverLocalDays(prefs)
          .where((ymd) => !deletedSet.contains(ymd))
          .take(safeLimit)
          .toList();
      final profile = await _buildProfilePatch(prefs: prefs, user: user, email: email);

      onProgress?.call(SmartCloudSyncProgress(
        stage: 'profile',
        current: 0,
        total: math.max(1, localDays.length + deletedDays.length + 1),
        message: 'جاري رفع بيانات الحساب...',
      ));

      await _withFirestoreRetry<void>(() => _writeUserProfile(user.uid, profile));
      await Future<void>.delayed(Duration.zero);

      int uploaded = 0;
      int writes = 1;
      int step = 1;

      for (final ymd in deletedDays) {
        onProgress?.call(SmartCloudSyncProgress(
          stage: 'delete',
          current: step,
          total: localDays.length + deletedDays.length + 1,
          message: 'جاري حذف يوم $ymd من السحابة...',
        ));
        await _withFirestoreRetry<void>(() => _deleteCloudDay(user.uid, ymd));
        writes++;
        step++;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      for (final ymd in localDays) {
        onProgress?.call(SmartCloudSyncProgress(
          stage: 'days',
          current: step,
          total: localDays.length + deletedDays.length + 1,
          message: 'جاري مزامنة يوم $ymd...',
        ));

        final day = await _buildDaySnapshot(
          prefs: prefs,
          email: email,
          uid: user.uid,
          ymd: ymd,
        );
        if (day == null) {
          step++;
          continue;
        }

        await _withFirestoreRetry<void>(() async {
          final userRef = _db.collection('users').doc(user.uid);
          final batch = _db.batch();
          batch.set(userRef.collection('days').doc(ymd), day, SetOptions(merge: true));
          batch.set(
            userRef,
            {
              'cloudDeletedCalorieDays': FieldValue.arrayRemove([ymd]),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          await batch.commit();
        });
        uploaded++;
        writes++;
        step++;

        // إتاحة فرصة قصيرة للواجهة بين عمليات الرفع المتتالية.
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      final nowIso = DateTime.now().toIso8601String();
      await prefs.setString('manual_cloud_sync_last_upload_at', nowIso);
      await prefs.setString('manual_cloud_sync_cloud_last_upload_at', nowIso);
      await prefs.setBool('manual_cloud_sync_has_cloud_backup', true);
      await prefs.setInt('manual_cloud_sync_cloud_days_count', uploaded > 0 ? uploaded : localDays.length);
      await prefs.setString('manual_cloud_sync_last_result', 'uploaded:$uploaded,writes:$writes');

      onProgress?.call(SmartCloudSyncProgress(
        stage: 'done',
        current: localDays.length + deletedDays.length + 1,
        total: localDays.length + deletedDays.length + 1,
        message: uploaded == 0 && deletedDays.isEmpty ? 'لا توجد أيام محلية جديدة للرفع.' : 'تم رفع $uploaded يوم وحذف ${deletedDays.length} يوم من السحابة.',
      ));

      return SmartCloudSyncResult(
        success: true,
        message: uploaded == 0 && deletedDays.isEmpty ? 'تم تحديث بيانات الحساب. لا توجد أيام جديدة للرفع.' : 'تمت المزامنة بنجاح.',
        uploadedDays: uploaded,
        restoredDays: 0,
        writes: writes,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );
    } on SmartCloudSyncException {
      rethrow;
    } catch (e) {
      return SmartCloudSyncResult(
        success: false,
        message: 'تعذرت المزامنة حاليًا. تحقق من الاتصال وحاول مجددًا.',
        uploadedDays: 0,
        restoredDays: 0,
        writes: 0,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );
    } finally {
      _running = false;
    }
  }

  /// استرجاع اختياري من Firestore إلى التخزين المحلي.
  Future<SmartCloudSyncResult> restoreCloudData({
    int dayLimit = defaultDayLimit,
    bool overwriteLocal = false,
    void Function(SmartCloudSyncProgress progress)? onProgress,
  }) async {
    if (_running) {
      throw const SmartCloudSyncException('توجد عملية مزامنة قيد التنفيذ. يرجى الانتظار حتى اكتمالها.');
    }

    final startedAt = DateTime.now();
    _running = true;
    try {
      final user = _requireUser();
      final prefs = await SharedPreferences.getInstance();
      final id = await _identity(prefs, user);
      final email = id.emailKey;
      final aliases = await _aliasesForUser(prefs, user);
      final safeLimit = dayLimit.clamp(1, maxDayLimit).toInt();
      final deletedDays = _readDeletedDays(prefs);

      onProgress?.call(const SmartCloudSyncProgress(
        stage: 'download',
        current: 0,
        total: 1,
        message: 'جاري قراءة البيانات السحابية...',
      ));

      final userSnap = await _withFirestoreRetry<DocumentSnapshot<Map<String, dynamic>>>(
        () => _db.collection('users').doc(user.uid).get(const GetOptions(source: Source.serverAndCache)),
      );
      final userData = userSnap.data();
      if (userData != null) {
        await _applyProfileToPrefs(
          prefs: prefs,
          aliases: aliases,
          data: userData,
          overwriteLocal: overwriteLocal,
        );
      }

      final cloudDeleted = userData?['cloudDeletedCalorieDays'];
      if (cloudDeleted is List) {
        for (final item in cloudDeleted) {
          final ymd = item.toString().trim();
          if (_looksLikeYmd(ymd)) deletedDays.add(ymd);
        }
      }
      await _writeDeletedDays(prefs, deletedDays);

      final q = await _withFirestoreRetry<QuerySnapshot<Map<String, dynamic>>>(
        () => _db
            .collection('users')
            .doc(user.uid)
            .collection('days')
            .orderBy('date', descending: true)
            .limit(safeLimit)
            .get(const GetOptions(source: Source.serverAndCache)),
      );

      int restored = 0;
      int step = 0;
      final total = math.max(1, q.docs.length);
      for (final doc in q.docs) {
        if (deletedDays.contains(doc.id)) {
          unawaited(_deleteCloudDay(user.uid, doc.id).catchError((_) {}));
          continue;
        }
        step++;
        onProgress?.call(SmartCloudSyncProgress(
          stage: 'apply',
          current: step,
          total: total,
          message: 'جاري حفظ يوم ${doc.id} محليًا...',
        ));
        final didRestore = await _applyDayToPrefs(
          prefs: prefs,
          aliases: aliases,
          ymd: doc.id,
          data: doc.data(),
          overwriteLocal: overwriteLocal,
        );
        if (didRestore) restored++;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      final identityAfterRestore = await WazenIdentityStore.currentIdentity(user: user, migrate: false);
      // الاسترجاع الآن يكتب على كل مفاتيح المستخدم مباشرة، ثم نشغل mirror كتأمين فقط.
      await WazenIdentityStore.mirrorKnownLocalKeys(prefs, identityAfterRestore);
      MacroTargetsController.bump();
      WeightLiveBus.ping();
      await prefs.setString('manual_cloud_sync_last_restore_at', DateTime.now().toIso8601String());
      await prefs.setInt('manual_cloud_sync_cloud_days_count', q.docs.length);
      await prefs.setBool('manual_cloud_sync_has_cloud_backup', q.docs.isNotEmpty || userData != null);
      if (userData != null) {
        final cloudSync = userData['cloudSync'];
        final cloudUpload = cloudSync is Map ? _dateFromCloud(cloudSync['lastUploadAt']) : null;
        if (cloudUpload != null) {
          await prefs.setString('manual_cloud_sync_cloud_last_upload_at', cloudUpload.toIso8601String());
        }
      }

      return SmartCloudSyncResult(
        success: true,
        message: restored == 0 ? 'لا توجد بيانات سحابية جديدة للاسترجاع.' : 'تم استرجاع $restored يوم من السحابة.',
        uploadedDays: 0,
        restoredDays: restored,
        writes: restored,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );
    } on SmartCloudSyncException {
      rethrow;
    } catch (_) {
      return SmartCloudSyncResult(
        success: false,
        message: 'تعذر الاسترجاع حاليًا. تحقق من الاتصال وحاول مجددًا.',
        uploadedDays: 0,
        restoredDays: 0,
        writes: 0,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );
    } finally {
      _running = false;
    }
  }

  List<String> _discoverLocalDays(SharedPreferences prefs) {
    final deleted = _readDeletedDays(prefs);
    final days = <String>{};
    for (final key in prefs.getKeys()) {
      for (final ymd in _extractYmdsFromKey(key)) {
        days.add(ymd);
      }
      if (key.startsWith('dietCalories_')) {
        final ymd = key.replaceFirst('dietCalories_', '');
        if (_looksLikeYmd(ymd)) days.add(ymd);
      }
    }

    // تأكد من وجود اليوم الحالي حتى لو ما فيه إلا وجبات محفوظة بالمفتاح الحالي.
    days.add(_ymd(DateTime.now()));

    days.removeAll(deleted);
    final list = days.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Future<Map<String, dynamic>> _buildProfilePatch({
    required SharedPreferences prefs,
    required User user,
    required String email,
  }) async {
    final uid = user.uid;
    final aliases = await _aliasesForUser(prefs, user);
    final patch = <String, dynamic>{
      'uid': uid,
      'email': user.email ?? email,
      'emailKey': email,
      'localStorageKey': uid,
      'cloudSync': {
        'enabled': true,
        'schema': schemaVersion,
        'lastUploadAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    String? firstString(List<String> prefixes, {List<String> globals = const <String>[]}) {
      for (final alias in aliases) {
        for (final prefix in prefixes) {
          final v = prefs.getString('$prefix$alias');
          if (v != null && v.trim().isNotEmpty) return v.trim();
        }
      }
      for (final key in globals) {
        final v = prefs.getString(key);
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    double? firstDouble(List<String> prefixes, {List<String> globals = const <String>[]}) {
      for (final alias in aliases) {
        for (final prefix in prefixes) {
          final key = '$prefix$alias';
          final v = prefs.getDouble(key) ?? double.tryParse(prefs.getString(key) ?? '');
          if (v != null && v > 0) return v;
        }
      }
      for (final key in globals) {
        final v = prefs.getDouble(key) ?? double.tryParse(prefs.getString(key) ?? '');
        if (v != null && v > 0) return v;
      }
      return null;
    }

    int? firstInt(List<String> prefixes, {List<String> globals = const <String>[]}) {
      for (final alias in aliases) {
        for (final prefix in prefixes) {
          final key = '$prefix$alias';
          final v = prefs.getInt(key) ?? int.tryParse(prefs.getString(key) ?? '');
          if (v != null && v > 0) return v;
        }
      }
      for (final key in globals) {
        final v = prefs.getInt(key) ?? int.tryParse(prefs.getString(key) ?? '');
        if (v != null && v > 0) return v;
      }
      return null;
    }

    final name = firstString(const ['fullName_', 'displayName_', 'name_'], globals: const ['fullName', 'displayName', 'name']);
    final username = firstString(const ['username_', 'currentUsername_'], globals: const ['username']);
    final bio = firstString(const ['bio_'], globals: const ['bio']);
    final gender = firstString(const ['gender_'], globals: const ['gender']);
    final goal = firstString(const ['goal_', 'user_goal_'], globals: const ['goal', 'user_goal']);
    final weight = firstDouble(
      const ['current_weight_', 'weight_', 'currentWeight_', 'weightKg_', 'user_weight_', 'goal_current_'],
      globals: const ['weight', 'currentWeightKg', 'weightKg'],
    );
    final height = firstDouble(const ['height_', 'height_cm_', 'heightCm_'], globals: const ['height', 'heightCm']);
    final age = firstInt(const ['age_'], globals: const ['age']);

    if (name != null) {
      patch['displayName'] = name;
      patch['fullName'] = name;
      patch['name'] = name;
    }
    if (username != null) patch['username'] = username;
    if (bio != null) patch['bio'] = bio;
    if (gender != null) patch['gender'] = gender;
    if (goal != null) {
      patch['goal'] = goal;
      patch['userGoal'] = goal;
    }
    if (weight != null) {
      patch['currentWeightKg'] = weight;
      patch['weightKg'] = weight;
      patch['weight'] = weight;
      patch['profileUpdatedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (height != null) {
      patch['heightCm'] = height;
      patch['height'] = height;
    }
    if (age != null) patch['age'] = age;

    final nutrition = <String, dynamic>{};
    final calories = firstDouble(const ['caloriesNeeded_'], globals: const ['caloriesNeeded']);
    final maintenance = firstDouble(const ['maintenanceCalories_'], globals: const ['maintenanceCalories']);
    final protein = firstDouble(const ['protein_'], globals: const ['protein']);
    final carbs = firstDouble(const ['carbs_'], globals: const ['carbs']);
    final fat = firstDouble(const ['fat_'], globals: const ['fat']);
    if (calories != null && calories > 0) nutrition['calories'] = calories;
    if (maintenance != null && maintenance > 0) nutrition['maintenanceCalories'] = maintenance;
    if (protein != null && protein > 0) nutrition['protein'] = protein;
    if (carbs != null && carbs >= 0) nutrition['carbs'] = carbs;
    if (fat != null && fat >= 0) nutrition['fat'] = fat;
    if (nutrition.isNotEmpty) {
      patch['nutritionTargets'] = nutrition;
      patch['metrics'] = {
        'caloriesNeeded': calories,
        'maintenanceCalories': maintenance,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }

    return patch;
  }

  Future<void> _writeUserProfile(String uid, Map<String, dynamic> patch) async {
    await _db.collection('users').doc(uid).set(patch, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> _buildDaySnapshot({
    required SharedPreferences prefs,
    required String email,
    required String uid,
    required String ymd,
  }) async {
    if (_readDeletedDays(prefs).contains(ymd)) return null;
    final identity = await WazenIdentityStore.currentIdentity(migrate: false);
    final sessionKey = await SessionManager.currentStorageKey();
    final aliases = <String>{
      identity.storageKey.trim(),
      identity.emailKey.trim(),
      ...identity.aliases,
      email.trim(),
      uid.trim(),
      sessionKey.trim(),
      'unknown_user',
    }.where((e) => e.isNotEmpty).toList(growable: false);

    final totals = _readTotals(prefs, aliases, ymd);
    final entries = _firstListForKeys(prefs, aliases.map((a) => 'intake_entries_${a}_$ymd'));
    final waterLiters = _readWaterLiters(prefs, aliases, ymd);
    final activity = _firstMapForKeys(prefs, aliases.map((a) => 'activity_${ymd}_$a'));
    final steps = _toI(activity['steps']);
    final burned = _toI(activity['burned']);
    final weightKg = _readWeightKg(prefs, aliases, ymd);
    final meals = await _readMealsForDay(prefs, aliases, ymd);

    final hasData = _toD(totals['k']) > 0 ||
        _toD(totals['p']) > 0 ||
        _toD(totals['c']) > 0 ||
        _toD(totals['f']) > 0 ||
        entries.isNotEmpty ||
        meals.isNotEmpty ||
        waterLiters > 0 ||
        steps > 0 ||
        burned > 0 ||
        weightKg > 0;

    if (!hasData) return null;

    final now = FieldValue.serverTimestamp();
    final day = <String, dynamic>{
      'date': ymd,
      'schema': schemaVersion,
      'manualSync': {
        'uploadedAt': now,
        'source': 'manual_settings_button',
      },
      'intake': {
        'totals': totals,
        'entries': entries,
        'updatedAt': now,
      },
      'water': {
        'liters': waterLiters < 0 ? 0.0 : waterLiters,
        'updatedAt': now,
      },
      'activity': {
        'steps': steps < 0 ? 0 : steps,
        'burned': burned < 0 ? 0 : burned,
        'updatedAt': now,
      },
      'meals': meals,
      'updatedAt': now,
    };

    if (weightKg > 0) {
      day['tracking'] = {
        'weightKg': weightKg,
        'updatedAt': now,
      };
      day['currentWeightKg'] = weightKg;
    }

    return day;
  }

  Map<String, dynamic> _readTotals(SharedPreferences prefs, List<String> aliases, String ymd) {
    for (final key in aliases.map((a) => 'kcal_daytotals_${a}_$ymd')) {
      final modern = _decodeMap(prefs.getString(key));
      if (modern != null) {
        return {
          'k': _toD(modern['k'] ?? modern['calories']),
          'p': _toD(modern['p'] ?? modern['protein']),
          'c': _toD(modern['c'] ?? modern['carb'] ?? modern['carbs']),
          'f': _toD(modern['f'] ?? modern['fat']),
        };
      }
    }

    final legacy = _decodeMap(prefs.getString('diet_$ymd'));
    if (legacy != null) {
      return {
        'k': _toD(legacy['calories'] ?? legacy['k']),
        'p': _toD(legacy['protein'] ?? legacy['p']),
        'c': _toD(legacy['carb'] ?? legacy['carbs'] ?? legacy['c']),
        'f': _toD(legacy['fat'] ?? legacy['f']),
      };
    }

    return {
      'k': prefs.getDouble('dietCalories_$ymd') ?? 0.0,
      'p': prefs.getDouble('dietProtein_$ymd') ?? 0.0,
      'c': prefs.getDouble('dietCarb_$ymd') ?? 0.0,
      'f': prefs.getDouble('dietFat_$ymd') ?? 0.0,
    };
  }

  double _readWaterLiters(SharedPreferences prefs, List<String> aliases, String ymd) {
    for (final a in aliases) {
      final direct = prefs.getDouble('water_${ymd}_$a');
      if (direct != null && direct > 0) return direct;

      final waterString = prefs.getString('water_total_${a}_$ymd');
      final fromString = double.tryParse(waterString ?? '');
      if (fromString != null && fromString > 0) return fromString;

      final mlDouble = prefs.getDouble('water_ml_${ymd}_$a');
      if (mlDouble != null && mlDouble > 0) return mlDouble / 1000.0;

      final mlInt = prefs.getInt('water_ml_${ymd}_$a');
      if (mlInt != null && mlInt > 0) return mlInt / 1000.0;

      final log = _decodeMap(prefs.getString('water_log_$a')) ?? <String, dynamic>{};
      final fromLog = _toD(log[ymd]);
      if (fromLog > 0) return fromLog;
    }
    return 0.0;
  }

  double _readWeightKg(SharedPreferences prefs, List<String> aliases, String ymd) {
    for (final a in aliases) {
      final list = _decodeListOfMaps(prefs.getString('weight_log_$a'));
      for (final row in list) {
        if ((row['date'] ?? '').toString() == ymd) {
          final kg = _toD(row['kg'] ?? row['weight'] ?? row['weightKg']);
          if (kg > 0) return kg;
        }
      }
    }

    if (ymd == _ymd(DateTime.now())) {
      for (final a in aliases) {
        final kg = prefs.getDouble('current_weight_$a') ??
            prefs.getDouble('weight_$a') ??
            prefs.getDouble('goal_current_$a') ??
            0.0;
        if (kg > 0) return kg;
      }
    }
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> _readMealsForDay(SharedPreferences prefs, List<String> aliases, String ymd) async {
    for (final a in aliases) {
      final specific = _decodeListOfMaps(prefs.getString('meals_${a}_$ymd'));
      if (specific.isNotEmpty) return specific;
    }

    if (ymd == _ymd(DateTime.now())) {
      for (final a in aliases) {
        final current = _decodeListOfMaps(prefs.getString('meals_$a'));
        if (current.isNotEmpty) return current;
      }
      final storageKey = await SessionManager.currentStorageKey();
      final current = _decodeListOfMaps(prefs.getString('meals_$storageKey'));
      if (current.isNotEmpty) return current;
    }

    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _firstMapForKeys(SharedPreferences prefs, Iterable<String> keys) {
    for (final key in keys) {
      final map = _decodeMap(prefs.getString(key));
      if (map != null && map.isNotEmpty) return map;
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _firstListForKeys(SharedPreferences prefs, Iterable<String> keys) {
    for (final key in keys) {
      final list = _decodeListOfMaps(prefs.getString(key));
      if (list.isNotEmpty) return list;
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _applyProfileToPrefs({
    required SharedPreferences prefs,
    required Iterable<String> aliases,
    required Map<String, dynamic> data,
    required bool overwriteLocal,
  }) async {
    final safeAliases = aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList();

    Future<void> setStringAll(List<String> prefixes, dynamic v) async {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      for (final prefix in prefixes) {
        await _setPrefForAliases(prefs, safeAliases, (a) => '$prefix$a', s, overwriteLocal: overwriteLocal);
      }
    }

    Future<void> setDoubleAll(List<String> prefixes, dynamic v, {bool allowZero = false}) async {
      final d = _toD(v);
      if (d <= 0 && !allowZero) return;
      for (final prefix in prefixes) {
        await _setPrefForAliases(
          prefs,
          safeAliases,
          (a) => '$prefix$a',
          d,
          overwriteLocal: overwriteLocal,
          allowZeroDouble: allowZero,
        );
      }
    }

    Future<void> setIntAll(List<String> prefixes, dynamic v) async {
      final i = _toI(v);
      if (i <= 0) return;
      for (final prefix in prefixes) {
        await _setPrefForAliases(prefs, safeAliases, (a) => '$prefix$a', i, overwriteLocal: overwriteLocal);
      }
    }

    final displayName = data['fullName'] ?? data['displayName'] ?? data['name'];
    await setStringAll(const ['fullName_', 'displayName_', 'name_'], displayName);
    await setStringAll(const ['username_', 'currentUsername_'], data['username']);
    await setStringAll(const ['bio_'], data['bio']);
    await setStringAll(const ['gender_'], data['gender']);
    await setStringAll(const ['goal_', 'user_goal_'], data['goal'] ?? data['userGoal']);
    await setDoubleAll(
      const ['weight_', 'current_weight_', 'currentWeight_', 'weightKg_', 'user_weight_', 'goal_current_'],
      data['currentWeightKg'] ?? data['weightKg'] ?? data['weight'],
    );
    await setDoubleAll(const ['height_', 'height_cm_', 'heightCm_'], data['heightCm'] ?? data['height']);
    await setIntAll(const ['age_'], data['age']);

    final nutrition = data['nutritionTargets'];
    final metrics = data['metrics'];
    dynamic n(String key) {
      if (nutrition is Map && nutrition[key] != null) return nutrition[key];
      if (metrics is Map && metrics[key] != null) return metrics[key];
      return null;
    }

    await setDoubleAll(const ['caloriesNeeded_'], n('calories') ?? n('caloriesNeeded'));
    await setDoubleAll(const ['maintenanceCalories_'], n('maintenanceCalories'));
    await setDoubleAll(const ['protein_'], n('protein'));
    await setDoubleAll(const ['carbs_'], n('carbs'), allowZero: true);
    await setDoubleAll(const ['fat_'], n('fat'), allowZero: true);

    final stamp = _toI(data['profileUpdatedAtMs']);
    if (stamp > 0) {
      for (final alias in safeAliases) {
        final current = prefs.getInt('profileUpdatedAt_$alias') ?? 0;
        if (overwriteLocal || stamp >= current) {
          await prefs.setInt('profileUpdatedAt_$alias', stamp);
        }
      }
    }
  }

  Future<bool> _applyDayToPrefs({
    required SharedPreferences prefs,
    required Iterable<String> aliases,
    required String ymd,
    required Map<String, dynamic> data,
    required bool overwriteLocal,
  }) async {
    if (_readDeletedDays(prefs).contains(ymd)) return false;
    bool changed = false;
    final safeAliases = aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList();

    Future<void> setStringAll(String Function(String alias) keyBuilder, String value) async {
      if (value.trim().isEmpty) return;
      for (final alias in safeAliases) {
        final key = keyBuilder(alias);
        if (!overwriteLocal && (prefs.getString(key)?.trim().isNotEmpty ?? false)) continue;
        await prefs.setString(key, value);
        changed = true;
      }
    }

    Future<void> setDoubleAll(String Function(String alias) keyBuilder, double value) async {
      if (value <= 0) return;
      for (final alias in safeAliases) {
        final key = keyBuilder(alias);
        if (!overwriteLocal && (prefs.getDouble(key) ?? 0) > 0) continue;
        await prefs.setDouble(key, value);
        changed = true;
      }
    }

    final intake = data['intake'];
    if (intake is Map) {
      final totals = intake['totals'];
      if (totals is Map) {
        final safeTotals = {
          'k': _toD(totals['k'] ?? totals['calories']),
          'p': _toD(totals['p'] ?? totals['protein']),
          'c': _toD(totals['c'] ?? totals['carb'] ?? totals['carbs']),
          'f': _toD(totals['f'] ?? totals['fat']),
        };
        await setStringAll((a) => 'kcal_daytotals_${a}_$ymd', jsonEncode(safeTotals));
        if (overwriteLocal || (prefs.getDouble('dietCalories_$ymd') ?? 0) <= 0) {
          await prefs.setDouble('dietCalories_$ymd', _toD(safeTotals['k']));
          await prefs.setDouble('dietProtein_$ymd', _toD(safeTotals['p']));
          await prefs.setDouble('dietCarb_$ymd', _toD(safeTotals['c']));
          await prefs.setDouble('dietFat_$ymd', _toD(safeTotals['f']));
          changed = true;
        }
      }
      final entries = intake['entries'];
      if (entries is List && entries.isNotEmpty) {
        await setStringAll((a) => 'intake_entries_${a}_$ymd', jsonEncode(entries));
      }
    }

    final meals = data['meals'];
    if (meals is List && meals.isNotEmpty) {
      await setStringAll((a) => 'meals_${a}_$ymd', jsonEncode(meals));
      if (ymd == _ymd(DateTime.now())) {
        await setStringAll((a) => 'meals_$a', jsonEncode(meals));
      }
    }

    final water = data['water'];
    if (water is Map) {
      final liters = _toD(water['liters']);
      await setDoubleAll((a) => 'water_${ymd}_$a', liters);
      if (liters > 0) await setStringAll((a) => 'water_total_${a}_$ymd', liters.toString());
    }

    final activity = data['activity'];
    if (activity is Map) {
      final steps = _toI(activity['steps']);
      final burned = _toI(activity['burned']);
      if (steps > 0 || burned > 0) {
        await setStringAll((a) => 'activity_${ymd}_$a', jsonEncode({'steps': steps, 'burned': burned}));
      }
    }

    final tracking = data['tracking'];
    double weightKg = 0.0;
    if (tracking is Map) weightKg = _toD(tracking['weightKg']);
    weightKg = weightKg <= 0 ? _toD(data['currentWeightKg']) : weightKg;
    if (weightKg > 0) {
      for (final alias in safeAliases) {
        await _mergeWeightLog(prefs: prefs, email: alias, ymd: ymd, kg: weightKg, overwriteLocal: overwriteLocal);
      }
      if (ymd == _ymd(DateTime.now())) {
        for (final prefix in const ['weight_', 'current_weight_', 'currentWeight_', 'weightKg_', 'user_weight_', 'goal_current_']) {
          await setDoubleAll((a) => '$prefix$a', weightKg);
        }
      }
      changed = true;
    }

    return changed;
  }

  Future<void> _mergeWeightLog({
    required SharedPreferences prefs,
    required String email,
    required String ymd,
    required double kg,
    required bool overwriteLocal,
  }) async {
    final list = _decodeListOfMaps(prefs.getString('weight_log_$email'));
    final index = list.indexWhere((e) => (e['date'] ?? '').toString() == ymd);
    if (index >= 0) {
      if (!overwriteLocal) return;
      list[index] = {'date': ymd, 'kg': kg};
    } else {
      list.add({'date': ymd, 'kg': kg});
    }
    list.sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    await prefs.setString('weight_log_$email', jsonEncode(list));
  }
}

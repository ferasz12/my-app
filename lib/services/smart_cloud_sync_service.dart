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
  });

  final bool enabled;
  final bool running;
  final DateTime? lastUploadAt;
  final DateTime? lastRestoreAt;
  final int localDaysCount;
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
    return (prefs.getStringList(_deletedDaysKey) ?? const <String>[])
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
    return WazenIdentityStore.syncFromFirebaseUser(user, prefs: prefs);
  }

  Future<String> _emailKey(SharedPreferences prefs, User user) async {
    final id = await _identity(prefs, user);
    return id.emailKey;
  }

  Future<SmartCloudSyncStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    final days = _discoverLocalDays(prefs).length;
    return SmartCloudSyncStatus(
      enabled: prefs.getBool('manual_cloud_sync_enabled') ?? false,
      running: _running,
      lastUploadAt: _parseDate(prefs.getString('manual_cloud_sync_last_upload_at')),
      lastRestoreAt: _parseDate(prefs.getString('manual_cloud_sync_last_restore_at')),
      localDaysCount: days,
    );
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
        await _applyProfileToPrefs(prefs: prefs, email: email, data: userData, overwriteLocal: overwriteLocal);
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
          email: email,
          ymd: doc.id,
          data: doc.data(),
          overwriteLocal: overwriteLocal,
        );
        if (didRestore) restored++;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      final identityAfterRestore = await WazenIdentityStore.currentIdentity(user: user, migrate: false);
      await WazenIdentityStore.mirrorKnownLocalKeys(prefs, identityAfterRestore);
      await prefs.setString('manual_cloud_sync_last_restore_at', DateTime.now().toIso8601String());

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

    void putString(String field, List<String> keys) {
      for (final k in keys) {
        final v = prefs.getString(k);
        if (v != null && v.trim().isNotEmpty) {
          patch[field] = v.trim();
          return;
        }
      }
    }

    void putDouble(String field, List<String> keys) {
      for (final k in keys) {
        final v = prefs.getDouble(k) ?? double.tryParse(prefs.getString(k) ?? '');
        if (v != null && v > 0) {
          patch[field] = v;
          return;
        }
      }
    }

    void putInt(String field, List<String> keys) {
      for (final k in keys) {
        final v = prefs.getInt(k) ?? int.tryParse(prefs.getString(k) ?? '');
        if (v != null && v > 0) {
          patch[field] = v;
          return;
        }
      }
    }

    putString('displayName', ['displayName_$uid', 'displayName_$email', 'name_$email', 'name']);
    putString('username', ['username_$uid', 'username_$email', 'username']);
    putString('bio', ['bio_$uid', 'bio_$email', 'bio']);
    putString('gender', ['gender_$uid', 'gender_$email', 'gender']);
    putString('goal', ['goal_$uid', 'goal_$email', 'goal']);
    putDouble('currentWeightKg', ['weight_$uid', 'weight_$email', 'current_weight_$email', 'goal_current_$email']);
    putDouble('heightCm', ['height_$uid', 'height_$email', 'height']);
    putInt('age', ['age_$uid', 'age_$email', 'age']);

    final nutrition = <String, dynamic>{};
    final calories = prefs.getDouble('caloriesNeeded_$email') ?? prefs.getDouble('caloriesNeeded_$uid') ?? prefs.getDouble('caloriesNeeded');
    final maintenance = prefs.getDouble('maintenanceCalories_$email') ?? prefs.getDouble('maintenanceCalories_$uid') ?? prefs.getDouble('maintenanceCalories');
    final protein = prefs.getDouble('protein_$email') ?? prefs.getDouble('protein_$uid') ?? prefs.getDouble('protein');
    final carbs = prefs.getDouble('carbs_$email') ?? prefs.getDouble('carbs_$uid') ?? prefs.getDouble('carbs');
    final fat = prefs.getDouble('fat_$email') ?? prefs.getDouble('fat_$uid') ?? prefs.getDouble('fat');
    if (calories != null && calories > 0) nutrition['calories'] = calories;
    if (maintenance != null && maintenance > 0) nutrition['maintenanceCalories'] = maintenance;
    if (protein != null && protein > 0) nutrition['protein'] = protein;
    if (carbs != null && carbs >= 0) nutrition['carbs'] = carbs;
    if (fat != null && fat >= 0) nutrition['fat'] = fat;
    if (nutrition.isNotEmpty) patch['nutritionTargets'] = nutrition;

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
    required String email,
    required Map<String, dynamic> data,
    required bool overwriteLocal,
  }) async {
    Future<void> setStringIfUseful(String key, dynamic v) async {
      if (v == null) return;
      if (!overwriteLocal && (prefs.getString(key)?.trim().isNotEmpty ?? false)) return;
      final s = v.toString().trim();
      if (s.isNotEmpty) await prefs.setString(key, s);
    }

    Future<void> setDoubleIfUseful(String key, dynamic v) async {
      final d = _toD(v);
      if (d <= 0) return;
      if (!overwriteLocal && (prefs.getDouble(key) ?? 0) > 0) return;
      await prefs.setDouble(key, d);
    }

    Future<void> setIntIfUseful(String key, dynamic v) async {
      final i = _toI(v);
      if (i <= 0) return;
      if (!overwriteLocal && (prefs.getInt(key) ?? 0) > 0) return;
      await prefs.setInt(key, i);
    }

    await setStringIfUseful('name_$email', data['displayName'] ?? data['name']);
    await setStringIfUseful('username_$email', data['username']);
    await setStringIfUseful('bio_$email', data['bio']);
    await setStringIfUseful('gender_$email', data['gender']);
    await setStringIfUseful('goal_$email', data['goal']);
    await setDoubleIfUseful('weight_$email', data['currentWeightKg'] ?? data['weight']);
    await setDoubleIfUseful('height_$email', data['heightCm'] ?? data['height']);
    await setIntIfUseful('age_$email', data['age']);

    final nutrition = data['nutritionTargets'];
    if (nutrition is Map) {
      await setDoubleIfUseful('caloriesNeeded_$email', nutrition['calories']);
      await setDoubleIfUseful('maintenanceCalories_$email', nutrition['maintenanceCalories']);
      await setDoubleIfUseful('protein_$email', nutrition['protein']);
      await setDoubleIfUseful('carbs_$email', nutrition['carbs']);
      await setDoubleIfUseful('fat_$email', nutrition['fat']);
    }
  }

  Future<bool> _applyDayToPrefs({
    required SharedPreferences prefs,
    required String email,
    required String ymd,
    required Map<String, dynamic> data,
    required bool overwriteLocal,
  }) async {
    if (_readDeletedDays(prefs).contains(ymd)) return false;
    bool changed = false;

    Future<void> setStringIfAllowed(String key, String value) async {
      if (value.trim().isEmpty) return;
      if (!overwriteLocal && (prefs.getString(key)?.trim().isNotEmpty ?? false)) return;
      await prefs.setString(key, value);
      changed = true;
    }

    Future<void> setDoubleIfAllowed(String key, double value) async {
      if (value <= 0) return;
      if (!overwriteLocal && (prefs.getDouble(key) ?? 0) > 0) return;
      await prefs.setDouble(key, value);
      changed = true;
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
        await setStringIfAllowed('kcal_daytotals_${email}_$ymd', jsonEncode(safeTotals));
        await setDoubleIfAllowed('dietCalories_$ymd', _toD(safeTotals['k']));
        await setDoubleIfAllowed('dietProtein_$ymd', _toD(safeTotals['p']));
        await setDoubleIfAllowed('dietCarb_$ymd', _toD(safeTotals['c']));
        await setDoubleIfAllowed('dietFat_$ymd', _toD(safeTotals['f']));
      }
      final entries = intake['entries'];
      if (entries is List && entries.isNotEmpty) {
        await setStringIfAllowed('intake_entries_${email}_$ymd', jsonEncode(entries));
      }
    }

    final meals = data['meals'];
    if (meals is List && meals.isNotEmpty) {
      await setStringIfAllowed('meals_${email}_$ymd', jsonEncode(meals));
      if (ymd == _ymd(DateTime.now())) {
        final storageKey = await SessionManager.currentStorageKey();
        await setStringIfAllowed('meals_$storageKey', jsonEncode(meals));
      }
    }

    final water = data['water'];
    if (water is Map) {
      await setDoubleIfAllowed('water_${ymd}_$email', _toD(water['liters']));
      await setStringIfAllowed('water_total_${email}_$ymd', _toD(water['liters']).toString());
    }

    final activity = data['activity'];
    if (activity is Map) {
      final steps = _toI(activity['steps']);
      final burned = _toI(activity['burned']);
      if (steps > 0 || burned > 0) {
        await setStringIfAllowed('activity_${ymd}_$email', jsonEncode({'steps': steps, 'burned': burned}));
      }
    }

    final tracking = data['tracking'];
    double weightKg = 0.0;
    if (tracking is Map) weightKg = _toD(tracking['weightKg']);
    weightKg = weightKg <= 0 ? _toD(data['currentWeightKg']) : weightKg;
    if (weightKg > 0) {
      await _mergeWeightLog(prefs: prefs, email: email, ymd: ymd, kg: weightKg, overwriteLocal: overwriteLocal);
      if (ymd == _ymd(DateTime.now())) {
        await setDoubleIfAllowed('weight_$email', weightKg);
        await setDoubleIfAllowed('current_weight_$email', weightKg);
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

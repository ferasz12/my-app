// lib/core/data/wazen_identity_store.dart
// مصدر موحّد لهوية المستخدم داخل التطبيق.
// الهدف: نفصل بين البريد الإلكتروني كبيانات حساب، والـ UID كمفتاح تخزين رسمي.
// لا نحذف المفاتيح القديمة؛ نعمل لها Mirror حتى لا تتأثر بيانات المستخدمين الحاليين.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WazenIdentity {
  const WazenIdentity({
    required this.uid,
    required this.email,
    required this.emailKey,
    required this.storageKey,
    required this.aliases,
  });

  final String uid;
  final String email;
  final String emailKey;
  final String storageKey;
  final List<String> aliases;
}

class WazenIdentityStore {
  WazenIdentityStore._();

  static const String kCurrentUid = 'currentUid';
  static const String kCurrentEmail = 'currentEmail';
  static const String kCurrentEmailAddress = 'currentEmailAddress';
  static const String kCurrentStorageKey = 'wazen_current_storage_key';
  static const String kLastIdentityMigrationAt = 'wazen_identity_last_migration_at';

  static String _clean(String? value) => (value ?? '').trim();
  static String _cleanEmail(String? value) => _clean(value).toLowerCase();

  static WazenIdentity _identityFromPrefs(SharedPreferences prefs, {User? user}) {
    final uid = _clean(user?.uid).isNotEmpty
        ? _clean(user?.uid)
        : _clean(prefs.getString(kCurrentUid));
    final authEmail = _cleanEmail(user?.email);
    final storedEmail = _cleanEmail(prefs.getString(kCurrentEmailAddress));
    final legacyCurrentEmail = _cleanEmail(prefs.getString(kCurrentEmail));

    final email = authEmail.isNotEmpty
        ? authEmail
        : (storedEmail.isNotEmpty ? storedEmail : (legacyCurrentEmail.contains('@') ? legacyCurrentEmail : ''));
    final emailKey = email.isNotEmpty ? email : (uid.isNotEmpty ? uid : 'unknown_user');
    final storageKey = uid.isNotEmpty ? uid : emailKey;

    final aliases = <String>{
      storageKey,
      uid,
      email,
      emailKey,
      legacyCurrentEmail,
      _clean(prefs.getString(kCurrentStorageKey)),
    }..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');

    return WazenIdentity(
      uid: uid,
      email: email,
      emailKey: emailKey,
      storageKey: storageKey,
      aliases: aliases.toList(growable: false),
    );
  }

  static Future<WazenIdentity> currentIdentity({User? user, bool migrate = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final authUser = user ?? FirebaseAuth.instance.currentUser;
    final id = _identityFromPrefs(prefs, user: authUser);
    if (authUser != null) {
      await syncFromFirebaseUser(authUser, prefs: prefs, migrate: migrate);
      return _identityFromPrefs(prefs, user: authUser);
    }
    return id;
  }

  static Future<WazenIdentity> syncFromFirebaseUser(
    User user, {
    SharedPreferences? prefs,
    bool migrate = true,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final uid = _clean(user.uid);
    final email = _cleanEmail(user.email);
    final emailKey = email.isNotEmpty ? email : uid;

    if (uid.isNotEmpty) await p.setString(kCurrentUid, uid);
    if (email.isNotEmpty) await p.setString(kCurrentEmailAddress, email);
    // نبقي currentEmail بريدًا حقيقيًا للتوافق مع الصفحات القديمة التي تعرضه أو تخزّن به.
    await p.setString(kCurrentEmail, emailKey);
    // المفتاح الرسمي الجديد للتخزين المحلي هو UID.
    await p.setString(kCurrentStorageKey, uid.isNotEmpty ? uid : emailKey);
    await p.setBool('isLoggedIn', true);

    final id = _identityFromPrefs(p, user: user);
    if (migrate) {
      await mirrorKnownLocalKeys(p, id);
    }
    return id;
  }

  static Future<void> clearIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove(kCurrentUid);
    await prefs.remove(kCurrentEmail);
    await prefs.remove(kCurrentEmailAddress);
    await prefs.remove(kCurrentStorageKey);
  }

  static Future<String> currentStorageKey() async {
    final id = await currentIdentity(migrate: false);
    return id.storageKey.isNotEmpty ? id.storageKey : 'unknown_user';
  }

  static Future<List<String>> currentAliases({User? user}) async {
    final id = await currentIdentity(user: user, migrate: false);
    return id.aliases;
  }

  static Future<void> mirrorKnownLocalKeys(SharedPreferences prefs, WazenIdentity id) async {
    final aliases = id.aliases.where((e) => e.isNotEmpty && e != 'unknown_user').toSet().toList();
    if (aliases.length <= 1) return;

    // لا نعيد فحص كل شيء كل ثانية، لكن نجعلها آمنة إذا استدعيت أكثر من مرة.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(kLastIdentityMigrationAt) ?? 0;
    if (stamp - last < 1200) return;
    await prefs.setInt(kLastIdentityMigrationAt, stamp);

    final simplePrefixes = <String>[
      'displayName_', 'name_', 'fullName_', 'username_', 'currentUsername_', 'bio_',
      'photoUrl_', 'avatarUrl_', 'profileImageUrl_', 'profile_image_path_',
      'gender_', 'age_', 'height_', 'weight_', 'current_weight_', 'goal_current_',
      'goal_', 'goalFatShred_', 'lifestyleScore_', 'activityFactor_',
      'caloriesNeeded_', 'maintenanceCalories_', 'protein_', 'carbs_', 'fat_',
      'macroMode_', 'macroPlanId_', 'waterMlTarget_', 'stepsTarget_', 'sleepHoursTarget_',
      'profileUpdatedAt_', 'macrosUpdatedAt_', 'lastWeightChangeAt_',
      'dailyNutritionHistory_', 'lastSnapshotDate_', 'activeMealsDate_',
      'user_goal_', 'weight_log_', 'water_log_', 'streak_lastDate_', 'streak_count_',
      'streak_history_', 'points_total_', 'wazen_points_', 'guide_role_', 'cached_role_',
      'guide_badge_', 'badge_', 'support_badge_',
    ];

    for (final prefix in simplePrefixes) {
      await _mirrorSuffixKeyGroup(prefs, prefix, aliases);
    }

    // مفاتيح تحتوي التاريخ بعد/قبل هوية المستخدم.
    final keys = prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      for (final alias in aliases) {
        if (!key.contains(alias)) continue;
        for (final target in aliases) {
          if (target == alias) continue;
          final mirrored = key.replaceFirst(alias, target);
          await _copyPrefValueIfMissing(prefs, key, mirrored);
        }
      }
    }
  }

  static Future<void> writeToAllAliases(
    SharedPreferences prefs,
    Iterable<String> aliases,
    String Function(String alias) keyBuilder,
    Object? value,
  ) async {
    for (final a in aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet()) {
      final key = keyBuilder(a);
      await _setPrefValue(prefs, key, value);
    }
  }

  static Future<void> _mirrorSuffixKeyGroup(
    SharedPreferences prefs,
    String prefix,
    List<String> aliases,
  ) async {
    String? sourceKey;
    for (final a in aliases) {
      final k = '$prefix$a';
      if (_hasUsefulValue(prefs, k)) {
        sourceKey = k;
        break;
      }
    }
    if (sourceKey == null) return;
    for (final a in aliases) {
      await _copyPrefValueIfMissing(prefs, sourceKey, '$prefix$a');
    }
  }

  static bool _hasUsefulValue(SharedPreferences prefs, String key) {
    final v = prefs.get(key);
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    return true;
  }

  static Future<void> _copyPrefValueIfMissing(SharedPreferences prefs, String from, String to) async {
    if (from == to) return;
    if (!_hasUsefulValue(prefs, from)) return;
    if (_hasUsefulValue(prefs, to)) return;
    await _setPrefValue(prefs, to, prefs.get(from));
  }

  static Future<void> _setPrefValue(SharedPreferences prefs, String key, Object? value) async {
    if (value == null) return;
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    } else if (value is num) {
      await prefs.setDouble(key, value.toDouble());
    } else {
      await prefs.setString(key, value.toString());
    }
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/wazen_identity_store.dart';

/// Helper موحّد لقراءة/كتابة بيانات المستخدم الصحية من كل مفاتيح وازن.
///
/// الهدف: ما يكون فيه صفحة تعتمد على البريد فقط وصفحة تعتمد على UID فقط.
/// كل صفحة تقرأ بالترتيب من أحدث Alias وتكتب على كل Aliases.
class WazenProfilePrefs {
  WazenProfilePrefs._();

  static Future<List<String>> aliases(
    SharedPreferences prefs, {
    User? user,
    bool migrate = false,
  }) async {
    final authUser = user ?? FirebaseAuth.instance.currentUser;
    final id = authUser != null
        ? await WazenIdentityStore.currentIdentity(user: authUser, migrate: migrate)
        : await WazenIdentityStore.currentIdentity(migrate: migrate);

    final out = <String>{
      prefs.getString(WazenIdentityStore.kCurrentStorageKey) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentUid) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentEmail) ?? '',
      authUser?.uid ?? '',
      authUser?.email ?? '',
      id.storageKey,
      id.uid,
      id.email,
      id.emailKey,
      ...id.aliases,
    }..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');

    return out.toList(growable: false);
  }

  static String latestAlias(SharedPreferences prefs, List<String> aliases) {
    if (aliases.isEmpty) return 'unknown_user';
    var best = aliases.first;
    var bestStamp = -1;
    for (final alias in aliases) {
      final stamp = _maxInt([
        prefs.getInt('profileUpdatedAt_$alias') ?? 0,
        prefs.getInt('macrosUpdatedAt_$alias') ?? 0,
        prefs.getInt('lastWeightChangeAt_$alias') ?? 0,
      ]);
      if (stamp > bestStamp) {
        bestStamp = stamp;
        best = alias;
      }
    }
    return best;
  }

  static List<String> orderedAliases(List<String> aliases, {String preferred = ''}) {
    return <String>[
      if (preferred.trim().isNotEmpty && preferred != 'unknown_user') preferred,
      ...aliases,
    ].where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet().toList(growable: false);
  }

  static double? asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(
        value.trim().replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.'),
      );
    }
    return null;
  }

  static int? asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String? asString(dynamic value) {
    if (value == null) return null;
    final out = value.toString().trim();
    return out.isEmpty ? null : out;
  }

  static double? readDouble(
    SharedPreferences prefs,
    List<String> prefixes,
    List<String> aliases, {
    String preferred = '',
  }) {
    for (final alias in orderedAliases(aliases, preferred: preferred)) {
      for (final prefix in prefixes) {
        final v = asDouble(prefs.get('$prefix$alias'));
        if (v != null) return v;
      }
    }
    return null;
  }

  static int? readInt(
    SharedPreferences prefs,
    List<String> prefixes,
    List<String> aliases, {
    String preferred = '',
  }) {
    for (final alias in orderedAliases(aliases, preferred: preferred)) {
      for (final prefix in prefixes) {
        final v = asInt(prefs.get('$prefix$alias'));
        if (v != null) return v;
      }
    }
    return null;
  }

  static String? readString(
    SharedPreferences prefs,
    List<String> prefixes,
    List<String> aliases, {
    String preferred = '',
  }) {
    for (final alias in orderedAliases(aliases, preferred: preferred)) {
      for (final prefix in prefixes) {
        final v = asString(prefs.get('$prefix$alias'));
        if (v != null) return v;
      }
    }
    return null;
  }

  static bool? readBool(
    SharedPreferences prefs,
    List<String> prefixes,
    List<String> aliases, {
    String preferred = '',
  }) {
    for (final alias in orderedAliases(aliases, preferred: preferred)) {
      for (final prefix in prefixes) {
        final v = prefs.get('$prefix$alias');
        if (v is bool) return v;
      }
    }
    return null;
  }

  static Future<void> writeAll(
    SharedPreferences prefs,
    Iterable<String> aliases,
    String Function(String alias) keyBuilder,
    Object? value,
  ) async {
    for (final alias in aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet()) {
      await _setValue(prefs, keyBuilder(alias), value);
    }
  }

  static Future<void> writeCoreProfile({
    required SharedPreferences prefs,
    required Iterable<String> aliases,
    required String gender,
    required int age,
    required double heightCm,
    required double weightKg,
    required String goal,
    required int lifestyleScore,
    required double activityFactor,
    bool? goalFatShred,
    int? stamp,
  }) async {
    final now = stamp ?? DateTime.now().millisecondsSinceEpoch;
    for (final alias in aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet()) {
      await prefs.setString('gender_$alias', gender);
      await prefs.setInt('age_$alias', age);
      await prefs.setDouble('height_$alias', heightCm);
      await prefs.setDouble('height_cm_$alias', heightCm);
      await prefs.setDouble('heightCm_$alias', heightCm);
      await prefs.setDouble('weight_$alias', weightKg);
      await prefs.setDouble('current_weight_$alias', weightKg);
      await prefs.setDouble('currentWeight_$alias', weightKg);
      await prefs.setDouble('weightKg_$alias', weightKg);
      await prefs.setDouble('user_weight_$alias', weightKg);
      await prefs.setDouble('goal_current_$alias', weightKg);
      await prefs.setString('goal_$alias', goal);
      await prefs.setString('user_goal_$alias', goal);
      await prefs.setInt('lifestyleScore_$alias', lifestyleScore);
      await prefs.setDouble('activityFactor_$alias', activityFactor);
      if (goalFatShred != null) {
        await prefs.setBool('goal_fat_shred_$alias', goalFatShred);
        await prefs.setBool('goalFatShred_$alias', goalFatShred);
      }
      await prefs.setInt('profileUpdatedAt_$alias', now);
    }
  }

  static Future<void> writeMacroTargets({
    required SharedPreferences prefs,
    required Iterable<String> aliases,
    required double calories,
    required double maintenanceCalories,
    required double protein,
    required double carbs,
    required double fat,
    required double activityFactor,
    required String macroMode,
    required String macroPlanId,
    required String macroCalculationNote,
    String? lastUpdatedYmd,
    int? stamp,
  }) async {
    final now = stamp ?? DateTime.now().millisecondsSinceEpoch;
    for (final alias in aliases.where((e) => e.trim().isNotEmpty && e != 'unknown_user').toSet()) {
      await prefs.setDouble('caloriesNeeded_$alias', calories);
      await prefs.setDouble('maintenanceCalories_$alias', maintenanceCalories);
      await prefs.setDouble('protein_$alias', protein);
      await prefs.setDouble('carbs_$alias', carbs);
      await prefs.setDouble('fat_$alias', fat);
      await prefs.setDouble('activityFactor_$alias', activityFactor);
      await prefs.setString('macroMode_$alias', macroMode);
      await prefs.setString('macroPlanId_$alias', macroPlanId);
      await prefs.setString('macroCalculationNote_$alias', macroCalculationNote);
      if ((lastUpdatedYmd ?? '').trim().isNotEmpty) {
        await prefs.setString('lastUpdated_$alias', lastUpdatedYmd!.trim());
      }
      await prefs.setInt('macrosUpdatedAt_$alias', now);
    }
  }

  static int _maxInt(List<int> values) {
    var out = 0;
    for (final v in values) {
      if (v > out) out = v;
    }
    return out;
  }

  static Future<void> _setValue(SharedPreferences prefs, String key, Object? value) async {
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

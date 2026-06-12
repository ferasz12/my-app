import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/wazen_identity_store.dart';
import '../data/app_repository.dart';
import 'macro_targets_controller.dart';
import 'weight_live_bus.dart';

/// يحفظ الوزن الحالي في كل المفاتيح التي تقرأ منها صفحات وازن.
///
/// السبب: بعض الصفحات القديمة تقرأ بالـ email، وبعض الصفحات الجديدة تقرأ بالـ uid،
/// وصفحة التتبع تقرأ current_weight + weight_log. لذلك نوحّد الكتابة هنا.
class WeightSyncService {
  WeightSyncService._();

  static String _todayKey() => DateTime.now().toIso8601String().split('T').first;

  static double? _readKg(Map<dynamic, dynamic> data) {
    for (final key in const ['kg', 'weight', 'weightKg', 'currentWeight', 'value']) {
      final value = data[key];
      if (value is num && value > 0) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return null;
  }

  static String? _readDate(Map<dynamic, dynamic> data) {
    for (final key in const ['date', 'day', 'ymd']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toIso8601String().split('T').first;
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return value;
      }
    }
    return null;
  }

  static Future<void> _upsertWeightLog(
    SharedPreferences prefs,
    String alias,
    double kg,
  ) async {
    final today = _todayKey();
    final key = 'weight_log_$alias';
    final list = <Map<String, dynamic>>[];

    final raw = prefs.getString(key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final date = _readDate(item);
              final weight = _readKg(item);
              if (date != null && weight != null && weight > 0) {
                list.add({'date': date, 'kg': weight});
              }
            }
          }
        }
      } catch (_) {}
    }

    final index = list.indexWhere((item) => item['date'] == today);
    if (index >= 0) {
      list[index] = {'date': today, 'kg': kg};
    } else {
      list.add({'date': today, 'kg': kg});
    }
    list.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    await prefs.setString(key, jsonEncode(list));
  }

  static Future<void> saveCurrentWeight({
    required double kg,
    bool writeCloud = true,
  }) async {
    if (kg <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final id = await WazenIdentityStore.currentIdentity(migrate: false);
    final aliases = <String>{
      id.storageKey,
      id.uid,
      id.email,
      id.emailKey,
      ...id.aliases,
      prefs.getString(WazenIdentityStore.kCurrentUid) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentEmail) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentStorageKey) ?? '',
    }..removeWhere((alias) => alias.trim().isEmpty || alias == 'unknown_user');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final alias in aliases) {
      await prefs.setDouble('weight_$alias', kg);
      await prefs.setDouble('current_weight_$alias', kg);
      await prefs.setDouble('currentWeight_$alias', kg);
      await prefs.setDouble('weightKg_$alias', kg);
      await prefs.setDouble('user_weight_$alias', kg);
      await prefs.setInt('profileUpdatedAt_$alias', stamp);
      await _upsertWeightLog(prefs, alias, kg);
    }

    if (writeCloud) {
      unawaited(AppRepository.writeWeightKg(ymd: _todayKey(), kg: kg).catchError((_) {}));
    }

    WeightLiveBus.ping();
    // الوزن يغيّر بعض كروت التتبع/التحليلات والماكروز المقترحة،
    // لذلك نرسل نبضة الأهداف أيضًا حتى الصفحات داخل IndexedStack تتحدث فورًا.
    MacroTargetsController.bump();
  }
}

// =============================================================
// FILE: lib/notifications/notification_sync_service.dart
// خدمة تربط تفضيلات الإشعارات في Firestore مع الجدولة المحلية.
// - تشتغل تلقائيًا عند تسجيل الدخول (authStateChanges)
// - تستمع لتغير users/{uid}.prefs وتطبقها مباشرة
// - تجلب وتنظم عروض التسويق من Firestore
// =============================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/user_repository.dart';
import 'app_notifications.dart';
import 'firestore_broadcast_scheduler.dart';
import 'fcm_marketing_push.dart';

class NotificationSyncService {
  NotificationSyncService._();
  static final NotificationSyncService instance = NotificationSyncService._();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _broadcastSub;
  bool _started = false;

  final _repo = const UserRepository();

  void start() {
    if (_started) return;
    _started = true;

    // ✅ تهيئة إشعارات العروض عبر FCM بطريقة آمنة.
    // لا نترك Future بدون معالجة، لأن أي خطأ Native أثناء البداية ممكن يسقط التطبيق.
    unawaited(
      FcmMarketingPush.instance.init().catchError((_) {}),
    );

    // استمع لتغير حالة الدخول
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _onAuthChanged(u);
    });

    // حالة حالية
    _onAuthChanged(FirebaseAuth.instance.currentUser);
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _prefsSub?.cancel();
    await _broadcastSub?.cancel();
    _authSub = null;
    _prefsSub = null;
    _broadcastSub = null;
    _started = false;
  }

  Future<void> _onAuthChanged(User? u) async {
    await _prefsSub?.cancel();
    await _broadcastSub?.cancel();
    _prefsSub = null;
    _broadcastSub = null;

    if (u == null || u.isAnonymous) return;

    // 1) تطبيق فوري من Firestore (مرة)
    try {
      final prefs = await _repo.getPrefs();
      if (prefs != null) {
        await _applyRemotePrefs(prefs);
      }
    } catch (_) {}

    // 2) الاستماع المباشر لأي تغيير في prefs
    final userRef = FirebaseFirestore.instance.collection('users').doc(u.uid);
    _prefsSub = userRef.snapshots(includeMetadataChanges: true).listen((snap) async {
      final data = snap.data();
      final prefsAny = data?['prefs'];
      if (prefsAny is Map) {
        await _applyRemotePrefs(Map<String, dynamic>.from(prefsAny));
      }
    });

    // 3) الاستماع لتغيرات البث التسويقي (حتى يتم جدولة الجديد مباشرة)
    _broadcastSub = FirebaseFirestore.instance
        .collection('app_broadcasts')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((_) async {
      final sp = await SharedPreferences.getInstance();
      final allEnabled = sp.getBool(AppNotifications.kAll) ?? true;
      final marketingEnabled = sp.getBool(FirestoreBroadcastScheduler.kMarketingEnabledLocal) ?? true;
      await FirestoreBroadcastScheduler.instance.syncAndSchedule(
        enabled: allEnabled && marketingEnabled,
      );
    });
  }

  bool _toBool(dynamic v, {bool def = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return def;
  }

  int _toInt(dynamic v, {required int def, int? min, int? max}) {
    int out = def;
    if (v is int) out = v;
    if (v is num) out = v.toInt();
    if (v is String) out = int.tryParse(v.trim()) ?? def;
    if (min != null && out < min) out = min;
    if (max != null && out > max) out = max;
    return out;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<int> _toIntList(dynamic v) {
    if (v is List) {
      return v.map((e) => _toInt(e, def: -1)).where((e) => e >= 1 && e <= 7).toSet().toList()..sort();
    }
    return const <int>[];
  }

  Future<void> _applyRemotePrefs(Map<String, dynamic> prefs) async {
    // قراءات آمنة + توافق خلفي
    final water = _asMap(prefs['water']);
    final workout = _asMap(prefs['workout']);
    final tips = _asMap(prefs['tips']);
    final weight = _asMap(prefs['weight']);
    final calories = _asMap(prefs['calories']);

    final allEnabled = _toBool(prefs['push'], def: true);
    final marketingEnabled = _toBool(prefs['marketing'], def: true);

    // ✅ ربط تفضيلات المستخدم بـ Topics (FCM)
    await FcmMarketingPush.instance.applyPrefs(
      allEnabled: allEnabled,
      marketingEnabled: marketingEnabled,
    );

    final waterEnabled = _toBool(water?['enabled'], def: false);
    final wsH = _toInt(water?['startH'], def: 8, min: 0, max: 23);
    final wsM = _toInt(water?['startM'], def: 0, min: 0, max: 59);
    final weH = _toInt(water?['endH'], def: 22, min: 0, max: 23);
    final weM = _toInt(water?['endM'], def: 0, min: 0, max: 59);
    final interval = _toInt(water?['intervalMin'], def: 60, min: 10, max: 24 * 60);

    final workoutEnabled = _toBool(workout?['enabled'], def: false);
    final wH = _toInt(workout?['h'], def: 18, min: 0, max: 23);
    final wM = _toInt(workout?['m'], def: 0, min: 0, max: 59);
    final days = _toIntList(workout?['days']);

    // tips: لو غير موجودة، استخدم dailyTips القديمة
    final tipsEnabled = tips == null ? _toBool(prefs['dailyTips'], def: false) : _toBool(tips['enabled'], def: false);
    final tH = _toInt(tips?['h'], def: 9, min: 0, max: 23);
    final tM = _toInt(tips?['m'], def: 0, min: 0, max: 59);

    final weightEnabled = _toBool(weight?['enabled'], def: false);
    final wgH = _toInt(weight?['h'], def: 8, min: 0, max: 23);
    final wgM = _toInt(weight?['m'], def: 0, min: 0, max: 59);

    final caloriesEnabled = _toBool(calories?['enabled'], def: false);
    final cH = _toInt(calories?['h'], def: 21, min: 0, max: 23);
    final cM = _toInt(calories?['m'], def: 0, min: 0, max: 59);

    // 1) حفظ محلي حتى يبقى بعد إعادة التشغيل
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(AppNotifications.kAll, allEnabled);

    await sp.setBool(AppNotifications.kWaterEnabled, waterEnabled);
    await sp.setInt(AppNotifications.kWaterStartH, wsH);
    await sp.setInt(AppNotifications.kWaterStartM, wsM);
    await sp.setInt(AppNotifications.kWaterEndH, weH);
    await sp.setInt(AppNotifications.kWaterEndM, weM);
    await sp.setInt(AppNotifications.kWaterInterval, interval);

    await sp.setBool(AppNotifications.kWorkoutEnabled, workoutEnabled);
    await sp.setInt(AppNotifications.kWorkoutH, wH);
    await sp.setInt(AppNotifications.kWorkoutM, wM);
    await sp.setString(AppNotifications.kWorkoutDays, (days.isEmpty ? <int>[1, 3, 5] : days).join(','));

    await sp.setBool(AppNotifications.kTipsEnabled, tipsEnabled);
    await sp.setInt(AppNotifications.kTipsH, tH);
    await sp.setInt(AppNotifications.kTipsM, tM);

    await sp.setBool(AppNotifications.kWeightEnabled, weightEnabled);
    await sp.setInt(AppNotifications.kWeightH, wgH);
    await sp.setInt(AppNotifications.kWeightM, wgM);

    await sp.setBool(AppNotifications.kCaloriesEnabled, caloriesEnabled);
    await sp.setInt(AppNotifications.kCaloriesH, cH);
    await sp.setInt(AppNotifications.kCaloriesM, cM);

    await sp.setBool(FirestoreBroadcastScheduler.kMarketingEnabledLocal, marketingEnabled);

    // 2) تطبيق الجدولة
    await AppNotifications.instance.applySettings(
      allEnabled: allEnabled,
      waterEnabled: waterEnabled,
      waterStartHour: wsH,
      waterStartMinute: wsM,
      waterEndHour: weH,
      waterEndMinute: weM,
      waterIntervalMinutes: interval,
      workoutEnabled: workoutEnabled,
      workoutHour: wH,
      workoutMinute: wM,
      workoutWeekdays: days,
      tipsEnabled: tipsEnabled,
      tipsHour: tH,
      tipsMinute: tM,
      weightEnabled: weightEnabled,
      weightHour: wgH,
      weightMinute: wgM,
      caloriesEnabled: caloriesEnabled,
      caloriesHour: cH,
      caloriesMinute: cM,
    );

    // 3) مزامنة عروض التسويق
    await FirestoreBroadcastScheduler.instance.syncAndSchedule(
      enabled: allEnabled && marketingEnabled,
    );
  }
}

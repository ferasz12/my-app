// =============================================================
// FILE: lib/notifications/firestore_broadcast_scheduler.dart
// ربط إشعارات التسويق/العروض بـ Firestore (بدون FCM):
// - المدير يضيف وثائق في collection: app_broadcasts
// - التطبيق عند فتحه يعمل sync ويجدول الإشعارات المحلية القادمة
// - إذا كان وقت الإرسال في الماضي القريب ولم يظهر، يعرضه فورًا
//
// الشكل المقترح للوثيقة:
// {
//   "title": "عرض خاص",
//   "body": "خصم 30% اليوم فقط",
//   "scheduledAt": Timestamp,
//   "active": true
// }
// =============================================================

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'tz_config.dart';

class FirestoreBroadcastScheduler {
  // صوت إشعارات وازن (مخصص)
  static const String _androidSound = 'wazen_notif';
  static const String _iosSound = 'wazen_notif.wav';
  // Android 8+: قناة جديدة لضمان تطبيق الصوت فورًا
  static const String _chMarketing = 'wazen_marketing_local_v2';

  FirestoreBroadcastScheduler._();
  static final FirestoreBroadcastScheduler instance = FirestoreBroadcastScheduler._();

  static const String kMarketingEnabledLocal = 'notif_marketing_enabled';

  // نخزن mapping docId -> notifId لضمان إلغاء صحيح
  static const String _kMapJson = 'marketing_notif_map_json';
  static const String _kShownSet = 'marketing_notif_shown_set'; // StringList of docIds

  // نطاق IDs خاص بالتسويق
  static const int _base = 23000;
  static const int _range = 4000; // 23000..26999

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    // ضبط المنطقة الزمنية (لتفادي جدولة UTC بالخطأ)
    TzConfig.ensureInitialized();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chMarketing,
          'Wazen Marketing',
          description: 'تنبيهات العروض والتسويق',
          importance: Importance.high,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound(_androidSound),
        ),
      );
    }

    // Android 12+: بعض الأجهزة تحتاج إذن Exact Alarms حتى تعمل exactAllowWhileIdle
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    } catch (_) {
      // ignore
    }

    _ready = true;
  }

  Future<void> syncAndSchedule({required bool enabled}) async {
    if (!_ready) await init();
    final sp = await SharedPreferences.getInstance();

    if (!enabled) {
      await _cancelAllFromLocalMap(sp);
      await sp.setBool(kMarketingEnabledLocal, false);
      return;
    }

    await sp.setBool(kMarketingEnabledLocal, true);

    final map = _readMap(sp);
    final shown = (sp.getStringList(_kShownSet) ?? <String>[]).toSet();

    final now = Timestamp.now();
    final db = FirebaseFirestore.instance;

    // 1) بث عام
    final globalSnap = await db
        .collection('app_broadcasts')
        .where('active', isEqualTo: true)
        .limit(200)
        .get();

    // 2) بريد خاص للمستخدم (اختياري)
    final u = FirebaseAuth.instance.currentUser;
    QuerySnapshot<Map<String, dynamic>>? inboxSnap;
    if (u != null) {
      inboxSnap = await db
          .collection('users')
          .doc(u.uid)
          .collection('inbox_notifications')
          .where('active', isEqualTo: true)
          .limit(200)
          .get();
    }

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...globalSnap.docs,
      if (inboxSnap != null) ...inboxSnap.docs,
    ];

    // جدولة/عرض
    for (final d in docs) {
      final data = d.data();
      final title = (data['title'] ?? '').toString().trim();
      final body = (data['body'] ?? '').toString().trim();
      final scheduledAt = data['scheduledAt'];
      if (title.isEmpty || body.isEmpty) continue;
      if (scheduledAt is! Timestamp) continue;

      final docId = d.reference.path; // path لضمان عدم تعارض بين العام والخاص
      final at = scheduledAt.toDate();

      // إذا وثيقة قديمة جدًا تجاهل
      final age = DateTime.now().difference(at);
      if (age.inDays > 14) continue;

      // عند تفعيل التطبيق بعد موعد الإشعار بقليل: اعرض فورًا مرة واحدة
      final isPast = scheduledAt.compareTo(now) <= 0;
      if (isPast && !shown.contains(docId) && age.inHours <= 12) {
        final id = _idFor(docId, map);
        await _showNow(id: id, title: title, body: body);
        shown.add(docId);
        continue;
      }

      // مستقبل: جدولة إن لم تكن مجدولة
      if (scheduledAt.compareTo(now) > 0) {
        if (!map.containsKey(docId)) {
          final id = _idFor(docId, map);
          await _scheduleOnce(id: id, title: title, body: body, at: at);
        }
      }
    }

    // تنظيف mapping لو وثائق أُلغيت/تعطلت
    final activePaths = docs.map((e) => e.reference.path).toSet();
    final toRemove = <String>[];
    for (final entry in map.entries) {
      if (!activePaths.contains(entry.key)) {
        await _plugin.cancel(entry.value);
        toRemove.add(entry.key);
      }
    }
    for (final k in toRemove) {
      map.remove(k);
      shown.remove(k);
    }

    await _writeMap(sp, map);
    await sp.setStringList(_kShownSet, shown.toList());
  }

  // ----------------------------
  // Internal
  // ----------------------------

  Future<void> _cancelAllFromLocalMap(SharedPreferences sp) async {
    final map = _readMap(sp);
    for (final id in map.values) {
      await _plugin.cancel(id);
    }
    await _writeMap(sp, <String, int>{});
    await sp.setStringList(_kShownSet, <String>[]);
  }

  Map<String, int> _readMap(SharedPreferences sp) {
    final raw = sp.getString(_kMapJson);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, int>{};
        for (final e in decoded.entries) {
          final k = e.key.toString();
          final v = e.value;
          if (v is int) out[k] = v;
          if (v is num) out[k] = v.toInt();
        }
        return out;
      }
    } catch (_) {}
    return <String, int>{};
  }

  Future<void> _writeMap(SharedPreferences sp, Map<String, int> map) async {
    await sp.setString(_kMapJson, jsonEncode(map));
  }

  int _stableHash(String s) {
    // hash ثابت عبر التشغيلات والمنصات
    int h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  int _idFor(String docId, Map<String, int> existing) {
    // linear probing لتجنب collisions
    final start = _stableHash(docId) % _range;
    int cand = _base + start;
    final used = existing.values.toSet();
    int tries = 0;
    while (used.contains(cand) && tries < _range) {
      cand++;
      if (cand >= _base + _range) cand = _base;
      tries++;
    }
    existing[docId] = cand;
    return cand;
  }

  NotificationDetails _details() {
    final android = AndroidNotificationDetails(
      _chMarketing,
      'Marketing',
      channelDescription: 'تنبيهات العروض والتسويق',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_androidSound),
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: _iosSound,
    );
    return NotificationDetails(android: android, iOS: ios);
  }

  Future<void> _showNow({required int id, required String title, required String body}) async {
    await _plugin.show(id, title, body, _details());
  }

  Future<void> _scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    final tzAt = tz.TZDateTime.from(at, tz.local);
    final now = tz.TZDateTime.now(tz.local);
    if (tzAt.isBefore(now)) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzAt,
      _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    // Android 12+ قد يحتاج Exact alarm (حسب إعدادات الجهاز)،
    // لكن حتى لو أصبح Inexact سيظل يصل غالبًا حول الموعد.
    if (Platform.isAndroid) {
      // no-op
    }
  }
}

// =============================================================
// FILE: lib/fasting/fasting_service.dart
// إدارة حالة الصيام + إشعارات + مراحل + سجل الرجيم
// متوافق مع FastingNotifications (scheduleOnce / scheduleDaily)
// =============================================================
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fasting_notifications.dart';
import 'fasting_stage_engine.dart';

class FastingSession {
  final String ymd; // YYYY-MM-DD (محلي)
  final DateTime startAt;
  final DateTime plannedEndAt;
  final DateTime actualEndAt;
  final int durationSec;     // مدة الصيام الفعلية (ثواني)
  final double percentDone;  // 0..1

  FastingSession({
    required this.ymd,
    required this.startAt,
    required this.plannedEndAt,
    required this.actualEndAt,
    required this.durationSec,
    required this.percentDone,
  });

  Map<String, dynamic> toJson() => {
        'ymd': ymd,
        'startAt': startAt.toIso8601String(),
        'plannedEndAt': plannedEndAt.toIso8601String(),
        'actualEndAt': actualEndAt.toIso8601String(),
        'durationSec': durationSec,
        'percentDone': percentDone,
      };

  factory FastingSession.fromJson(Map<String, dynamic> m) => FastingSession(
        ymd: (m['ymd'] ?? '').toString(),
        startAt: DateTime.parse(m['startAt']),
        plannedEndAt: DateTime.parse(m['plannedEndAt']),
        actualEndAt: DateTime.parse(m['actualEndAt']),
        durationSec: (m['durationSec'] as num).toInt(),
        percentDone: (m['percentDone'] as num).toDouble(),
      );
}

class FastingService extends ChangeNotifier {
  static const _kActive  = 'fasting.active';
  static const _kStart   = 'fasting.startAt';
  static const _kEnd     = 'fasting.endAt';
  static const _kEnforce = 'fasting.enforce'; // منع إضافة وجبات أثناء الصيام
  static const _kHistory = 'fasting.history'; // قائمة الجلسات (JSON List)

  bool _active = false;
  DateTime? _startAt;
  DateTime? _endAt;
  bool _enforce = true;

  Timer? _ticker;

  final List<FastingSession> _history = [];
  List<FastingSession> get history => List.unmodifiable(_history);

  bool get isActive =>
      _active && _startAt != null && _endAt != null && DateTime.now().isBefore(_endAt!);
  DateTime? get startAt => _startAt;
  DateTime? get endAt => _endAt;
  bool get enforce => _enforce;

  Duration get total =>
      (_startAt != null && _endAt != null) ? _endAt!.difference(_startAt!) : Duration.zero;
  Duration get elapsed =>
      (_startAt != null) ? DateTime.now().difference(_startAt!) : Duration.zero;
  Duration get remaining =>
      (_endAt != null) ? _endAt!.difference(DateTime.now()) : Duration.zero;
  double get percent {
    final t = total.inSeconds;
    if (t <= 0) return 0;
    final used = elapsed.inSeconds.clamp(0, t);
    return used / t;
  }

  FastingStage get stage => FastingStageEngine.current(elapsed);

  static Future<FastingService> load() async {
    final s = FastingService();
    final p = await SharedPreferences.getInstance();

    s._active = p.getBool(_kActive) ?? false;
    final startMs = p.getInt(_kStart);
    final endMs   = p.getInt(_kEnd);
    s._startAt = startMs == null ? null : DateTime.fromMillisecondsSinceEpoch(startMs);
    s._endAt   = endMs   == null ? null : DateTime.fromMillisecondsSinceEpoch(endMs);
    s._enforce = p.getBool(_kEnforce) ?? true;

    // تحميل السجل
    final raw = p.getString(_kHistory);
    if (raw != null) {
      try {
        final list = json.decode(raw);
        if (list is List) {
          s._history
            ..clear()
            ..addAll(
              list.map((e) => FastingSession.fromJson(Map<String, dynamic>.from(e))),
            );
        }
      } catch (_) {}
    }

    s._startTicker();
    return s;
  }

  Future<void> setEnforce(bool v) async {
    _enforce = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnforce, v);
    notifyListeners();
  }

  /// بدء الصيام + جدولة الإشعارات (بداية/منتصف/نهاية/تذكير بعد 10 دقائق)
  Future<void> startFasting({
    required DateTime start,
    required DateTime end,
  }) async {
    _active = true;
    _startAt = start;
    _endAt   = end;

    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActive, true);
    await p.setInt(_kStart, start.millisecondsSinceEpoch);
    await p.setInt(_kEnd,   end.millisecondsSinceEpoch);

    // إشعارات — باستخدام الواجهة الجديدة
    await FastingNotifications.instance.init();
    await FastingNotifications.instance.cancelAll();

    // بداية
    await FastingNotifications.instance.scheduleOnce(
      id: 1001,
      title: 'بدأ الصيام',
      body: 'تم بدء صيامك — بالتوفيق 👌',
      at: start,
    );

    // منتصف
    final mid = start.add(
      Duration(milliseconds: (end.difference(start).inMilliseconds ~/ 2)),
    );
    await FastingNotifications.instance.scheduleOnce(
      id: 1002,
      title: 'منتصف المدة',
      body: 'وصلت لنقطة منتصف الصيام 🎯',
      at: mid,
    );

    // نهاية
    await FastingNotifications.instance.scheduleOnce(
      id: 1003,
      title: 'انتهاء الصيام',
      body: 'حان وقت إنهاء الصيام — لا تنسَ وجبة متوازنة 🥗',
      at: end,
    );

    // تذكير وجبة بعد 10 دقائق من الانتهاء
    await FastingNotifications.instance.scheduleOnce(
      id: 1004,
      title: 'تذكير وجبة',
      body: 'الموعد المقترح لوجبتك بعد الصيام',
      at: end.add(const Duration(minutes: 10)),
    );

    _startTicker();
    notifyListeners();
  }

  Future<void> stopFasting() async {
    // احفظ جلسة قبل الإطفاء
    if (_active && _startAt != null && _endAt != null) {
      final now = DateTime.now();
      final plannedEnd = _endAt!;
      final actualEnd  = now.isAfter(plannedEnd) ? plannedEnd : now;
      final totalSec   = plannedEnd.difference(_startAt!).inSeconds;
      final doneSec    = actualEnd.difference(_startAt!).inSeconds.clamp(0, totalSec);
      final percent    = totalSec == 0 ? 0.0 : (doneSec / totalSec);

      final ymd = DateTime(_startAt!.year, _startAt!.month, _startAt!.day)
          .toIso8601String()
          .split('T')
          .first;

      await _appendHistory(
        FastingSession(
          ymd: ymd,
          startAt: _startAt!,
          plannedEndAt: plannedEnd,
          actualEndAt: actualEnd,
          durationSec: doneSec,
          percentDone: percent,
        ),
      );
    }

    _active = false;
    _startAt = null;
    _endAt = null;

    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActive, false);
    await p.remove(_kStart);
    await p.remove(_kEnd);

    await FastingNotifications.instance.cancelAll();
    _ticker?.cancel();
    notifyListeners();
  }

  bool isWithinFasting(DateTime t) {
    if (!isActive) return false;
    return t.isAfter(_startAt!) && t.isBefore(_endAt!);
  }

  void _startTicker() {
    _ticker?.cancel();
    if (!isActive) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_endAt != null && DateTime.now().isAfter(_endAt!)) {
        // انتهى الصيام تلقائيًا → احفظ جلسة مكتملة ثم أوقف
        await stopFasting();
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> _appendHistory(FastingSession s) async {
    final p = await SharedPreferences.getInstance();
    // احتفظ بآخر 60 جلسة
    _history.insert(0, s);
    if (_history.length > 60) {
      _history.removeRange(60, _history.length);
    }
    await p.setString(
      _kHistory,
      json.encode(_history.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// حذف يوم من سجل الصيام عبر مفتاح التاريخ (YYYY-MM-DD)
  Future<void> deleteHistoryDay(String ymd) async {
    _history.removeWhere((e) => e.ymd == ymd);
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kHistory,
      json.encode(_history.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }
}

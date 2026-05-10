// lib/screens/home_screen.dart
// (Daily rollover + daily snapshots + day index internal + auto Kcal from macros)
// ✅ نظام النقاط (AchievementsStore) — مطالبة نهاية اليوم:
//   - إكمال السعرات اليوم ≥ 95% من الهدف + الماكروز قريبة (±20%) ⇒ +5 نقاط
//   - شرب ماء ≥ 3 لتر ⇒ +10 نقاط
// تُخزَّن "مكافآت معلّقة"، وتُعرض ورقة المطالبة (Claim) آخر الليل لنفس اليوم.
// ولو ما فتح التطبيق آخر الليل، تظهر صباح اليوم التالي كـ fallback.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/points_earned_toast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/session_manager.dart';
import 'package:health/health.dart';


import 'package:flutter/foundation.dart';
// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repos/points_repo.dart';

// Data layer (Firestore mirror)
import '../data/app_repository.dart';

// Screens
import 'food_camera_screen.dart';

import 'food_ai_screen.dart';
import 'barcode_scanner_page.dart';
import 'gemini_chat_screen.dart';
import 'ask_wazen_coach_screen.dart';
import 'calories_history_screen.dart';
import 'regimen_screen.dart' show DietBus; // ⬅️ نستخدم DietBus.addMeal
import '../services/barcode_service.dart' show FoodMacro;
// تدفّق القائمة الجاهزة (يحوي FoodItem, SelectedFood, showReadyListPicker)
import 'ready_foods_flow.dart';

import '../models/meal.dart';

// ✅ اختيار وجبة جاهزة من المطاعم لإضافتها مباشرة لليوم
import 'restaurants_page.dart';

// التخزين اليومي للاستهلاك
import '../services/tracker_store.dart';

// الماء
import '../water/water_store.dart';
import '../water/water_pages.dart';

// نصيحة اليوم
import 'package:my_app/core/daily_health_tips.dart';

// ✅ استدعاء مخزن الإنجازات (يُستخدم للـ total فقط)
import 'achievements_page.dart' show AchievementsStore;

// ✅ تنظيف المفاتيح التي خُزّنت بنوع خاطئ
import '../shared/safe_prefs.dart';
import '../shared/macro_targets_controller.dart';
import 'package:my_app/achievements/achievements_with_leaderboard.dart';

import '../features/meal_analysis/meal_analysis.dart';
//import '../achievements/achievements_with_leaderboard.dart' show AchievementsPage;
import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import '../shared/friendly_errors.dart';
import '../features/announcement/global_announcement_banner.dart';
import '../fasting/fasting_notifications.dart';
import '../notifications/app_notifications.dart';

// Meal details (pie chart + burn estimate)
import '../features/meals/ui/meal_details_sheet.dart';
// ===== Points awarding: immediate sync to Firestore (with guest fallback) =====
class _PointsClient {
  static final _auth = FirebaseAuth.instance;
  static final _fs = FirebaseFirestore.instance;

  static Future<int> award({
    required String eventKey,
    required int points,
    Map<String, dynamic>? meta,
    String? dedupeKey,
  }) async {
    // تاريخ اليوم
    final now = DateTime.now();
    final ymd = now.toIso8601String().split('T').first;

    // وضع الضيف (بدون uid): تخزين محلي لعمل الواجهة أثناء التطوير
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      final prefs = await SharedPreferences.getInstance();
      final dayKey = 'guest_day_${ymd}_awardedPoints';
      final totalKey = 'guest_points_total';

      final curDay = prefs.getInt(dayKey) ?? 0;
      await prefs.setInt(dayKey, curDay + points);

      final curTotal = prefs.getInt(totalKey) ?? 0;
      await prefs.setInt(totalKey, curTotal + points);

      return points;
    }

    // Firestore paths
    final userRef = _fs.collection('users').doc(uid);
    final dayRef  = userRef.collection('days').doc(ymd);
    final evRef   = userRef.collection('point_events')
      .doc('${ymd}_${eventKey}_${dedupeKey ?? '1'}');

    return await _fs.runTransaction<int>((tx) async {
      // منع التكرار
      final evSnap = await tx.get(evRef);
      if (evSnap.exists) {
        final d = evSnap.data() as Map<String, dynamic>?;
        return (d?['points'] as num?)?.toInt() ?? 0;
      }

      // قراءة نقاط اليوم الحالية
      final daySnap = await tx.get(dayRef);
      final baseDay = (daySnap.data() as Map<String, dynamic>?) ?? {};
      final baseRewards = (baseDay['rewards'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final current = (baseRewards['awardedPoints'] as num?)?.toInt() ?? 0;

      // سجل حدث النقاط
      tx.set(evRef, {
        'event': eventKey,
        'uid': uid,
        'ymd': ymd,
        'points': points,
        'meta': meta ?? const {},
        'createdAt': Timestamp.now(),
      });

      // حدّث نقاط اليوم
      final newTotal = current + points;
      final updatedRewards = Map<String, dynamic>.from(baseRewards)
        ..['awardedPoints'] = newTotal;

      tx.set(dayRef, {
        'rewards': updatedRewards,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      // زيادات التوتال
      tx.set(userRef.collection('achievements').doc('totals'), {
        'points_total': FieldValue.increment(points),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      return points;
    });
  }
}



// ===== نوع مساعد لعرض عناصر قائمة التجميع الفورية =====
class _InstantClaimItem {
  final String title;
  final int points;
  const _InstantClaimItem({required this.title, required this.points});
}

List<Map<String, dynamic>> _decodeFoodMaps(String response) {
  final data = json.decode(response) as List;
  return List<Map<String, dynamic>>.from(data);
}

extension _PositiveDoubleFallback on double {
  double takeIfPositiveOr(double fallback) => this > 0 ? this : fallback;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {

  // ===== Toast UI for points (Home) =====
  void _showPointsToast(int points, {String? reason, IconData icon = Icons.star_rounded}) {
    if (!mounted) return;
    try {
      PointsEarnedToast.show(
        context,
        points: points,
        title: 'كسبت نقاط 🎉',
        message: reason ?? 'أضفنا $points نقطة إلى رصيدك',
        icon: icon,
        withConfetti: true,
      );
    } catch (_) {}
  }



  // ====== Guard: show claim UI once per date (persists per day) ======
  Future<bool> _shouldShowClaimUI({required String forDate}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'claim_ui_shown_' + forDate; // e.g., 2025-10-01
      final shown = prefs.getBool(key) ?? false;
      return !shown;
    } catch (_) {
      return true; // fail-open to allow first showing
    }
  }

  Future<void> _markClaimUIShown({required String forDate}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'claim_ui_shown_' + forDate;
      await prefs.setBool(key, true);
    } catch (_) {}
  }



  // ===== Points helpers (safe, no UI changes) =====
  Future<void> _awardWaterPoints(double before, double after) async {
  try {
    final crossed = (before < 3.0) && (after >= 3.0);
    if (crossed) {
      final ymd = DateTime.now().toIso8601String().split('T').first;
      await _awardOnce(
        eventKey: 'water_3l',
        points: 5,
        dedupeKey: ymd,
        meta: {'message': 'شربت 3 لتر ماء اليوم (+5)'},
      );
    }
  } catch (_) {}
}



  /// إلحاق مكافأة معلّقة لليوم الحالي (مع إزالة التكرارات بالـ id)
  Future<void> _appendPendingToday(Map<String, dynamic> reward) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';
    final ymd = DateTime.now().toIso8601String().split('T').first;
    final pendingKey = 'pending_rewards_${email}_$ymd';
    List<Map<String, dynamic>> list = [];
    try {
      final raw = prefs.getString(pendingKey);
      if (raw != null) {
        final dec = json.decode(raw);
        if (dec is List) list = List<Map<String, dynamic>>.from(dec);
      }
    } catch (_) {}
    // إزالة أي عنصر سابق بنفس الـ id
    final id = (reward['id'] ?? '').toString();
    if (id.isNotEmpty) {
      list = [for (final r in list) if ((r['id'] ?? '') != id) r];
    }
    list.add(reward);
    await prefs.setString(pendingKey, json.encode(list));
    // مرآة لفايرستور بالخلفية حتى لا تتأخر الواجهة
    unawaited(AppRepository.putPendingRewards(ymd: ymd, pending: list).catchError((_) {}));
  }



  Future<void> _awardMealPoints(int mealIndex, int preTotalItems, int preSlotCount) async {
    try {
      // نقطة واحدة عند أول إضافة في كل وجبة (فطور/غداء/عشاء)
      final bool firstInSlot = preSlotCount == 0;
      if (firstInSlot) {
        final slot = mealIndex == 0 ? 'breakfast' : (mealIndex == 1 ? 'lunch' : 'dinner');
        await _awardOnce(eventKey: 'meal_slot_$slot', points: 1, dedupeKey: null, meta: {
          "message": "كسبت نقطة واحدة: أول وجبة لك اليوم — (${slot == 'breakfast' ? 'فطور' : slot == 'lunch' ? 'غداء' : 'عشاء'}) (+1)",
        }, showUI: false);
}
    } catch (_) {}
}

  // أهداف اليوم
  double caloriesNeeded = 0.0;
  double protein = 0.0;
  double fat = 0.0;
  double carbs = 0.0;

  // إجمالي النقاط (للاستعمال الداخلي فقط عند الحاجة) — لا نعرضه في الهوم
  int userPoints = 0;

  // ✅ نقاط اليوم (المطلوبة لعرض الهوم)
  int todayPoints = 0;
  // ✅ عدد أيام الستريك الحالية
  int _streakCount = 0;
  String? _streakLastDate;


// حالة المكافآت المحلية (fallback) لليوم
bool _resolvedLocalToday = false;
int _pendingLocalToday = 0;


  // نشاط Apple/Google Health
  int steps = 0;
  int burned = 0;

  // health ^13.x
  final Health health = Health();

  // الماء اليوم
  double todayWaterLiters = 0.0;

  // الوجبات لليوم الحالي فقط — تُصفّر عند دخول يوم جديد فقط
  List<Map<String, dynamic>> meals = [
    {'name': '🍳 الفطور', 'items': <Map<String, dynamic>>[]},
    {'name': '🍽️ الغداء', 'items': <Map<String, dynamic>>[]},
    {'name': '🌙 العشاء', 'items': <Map<String, dynamic>>[]},
  ];

  // مجاميع اليوم
  double totalCalories = 0.0;
  double totalProtein = 0.0;
  double totalCarbs = 0.0;
  double totalFat = 0.0;

  // أطعمتك من assets + نسخة محوّلة لـ FoodItem
  List<Map<String, dynamic>> predefinedFoods = [];
  List<FoodItem> readyFoods = [];

  // منع إعادة التوجيه والـ guard مرّات كثيرة
  // فهرس “سجل الأيام” (نحدّثه داخليًا فقط)
  final Map<String, double> _dailyTotals = {}; // date -> kcal
  List<String> _dailyDates = [];

  // تتبّع تاريخ الشاشة
  String _lastSeenDate = DateTime.now().toIso8601String().split('T').first;
  String? _activeMealsStoredDate;

  // مفاتيح PageStorage لمنع تعارض الأنواع
  static const _listKey = PageStorageKey<String>('home_list');

  // ===== إعدادات مكافآت اليوم =====
  static const double _kCalorieCompletionRatio = 0.95; // 95% من الهدف
  static const double _kWaterBonusLiters = 3.0;        // 3 لتر
  static const int _kCaloriesBonusPoints = 5;          // +5 نقاط
  static const int _kWaterBonusPoints = 10;            // +10 نقاط
  static const int _kClaimCutoffHour = 23;          // الساعة 23 = 11PM

  static const double _kMacroCloseTolerance = 0.20;    // ±20% قرب من الهدف
// ===== فحص ومنح مكافآت اليوم الكبرى فورًا (سعرات/ماكروز + ماء) =====
Future<void> _maybeAwardDailyBonusesNow() async {
  final prefs = await SharedPreferences.getInstance();
  final email = prefs.getString('currentEmail') ?? FirebaseAuth.instance.currentUser?.email ?? 'unknown_user';
  final ymd = DateTime.now().toIso8601String().split('T').first;

  Map<String, dynamic> totals = {};
  try { final raw = prefs.getString('kcal_daytotals_${email}_$ymd'); if (raw != null) totals = json.decode(raw); } catch (_) {}
  final double sumK = _toD(totals['k']);
  final double sumP = _toD(totals['p']);
  final double sumC = _toD(totals['c']);
  final double sumF = _toD(totals['f']);

  Map<String, dynamic> history = {};
  try { final rawHist = prefs.getString('dailyNutritionHistory_$email'); if (rawHist != null) history = json.decode(rawHist); } catch (_) {}
  final m = history[ymd] as Map?;
  final double tK = _toD(m?['calories']);
  final double tP = _toD(m?['protein']);
  final double tC = _toD(m?['carbs']);
  final double tF = _toD(m?['fat']);

  final String? waterStr = prefs.getString('water_total_${email}_$ymd');
  final double waterLiters = waterStr != null ? _parseLocalizedDouble(waterStr) : 0.0;

  final reachedCalories = (tK > 0) && (sumK >= (tK * _kCalorieCompletionRatio));
  final closeMacros = _macrosClose(targetP: tP, targetC: tC, targetF: tF, sumP: sumP, sumC: sumC, sumF: sumF);
  if (reachedCalories && closeMacros) {
    await _awardOnce(eventKey: 'daily_kcal_bonus', points: _kCaloriesBonusPoints, dedupeKey: ymd, showUI: false);
}

  if (waterLiters >= _kWaterBonusLiters) {
    await _awardOnce(eventKey: 'daily_water_bonus', points: _kWaterBonusPoints, dedupeKey: ymd, showUI: false);
}
}

  // لإظهار ورقة المطالبة مرة واحدة
  bool _claimSheetShown = false;

  // سِيد بسيط لتحفيز الأنيميشن عند تغيّر القيم
  int _animSeed = 0;

  // ===== Performance guards =====
  // نخلي الهوم محلي وسريع، والعمليات الثقيلة تصير مؤجلة أو بالخلفية.
  Timer? _homeDeferredTimer;
  Timer? _homePersistDebounce;
  DateTime? _lastHomeResumeWorkAt;
  DateTime? _lastTargetsRemoteFetchAt;
  bool _initialLoadDone = false;
  bool _homeBackgroundWorkRunning = false;

  // اشتراكات
  StreamSubscription? _achSub;       // (اختياري) لو حبيت تتابع الإجمالي
  StreamSubscription? _dayPointsSub; // نقاط اليوم (الهوم يعرضها)

  // ✅ تحديث فوري للأهداف عند تغييرها من صفحة "بياناتي"
  late final VoidCallback _macroTargetsListener;

  // ===== هامش سفلي ذكي يمنع تغطية المحتوى بالشريط/الـFAB =====
  double _homeBottomPadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    const navH = kBottomNavigationBarHeight; // ≈56
    const gap = 20.0; // مسافة تنفّس بسيطة
    return mq.padding.bottom + navH + gap;
  }

// ===== Helpers آمنة لأنواع SharedPreferences =====
  bool _prefBool(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    return raw is bool ? raw : false;
  }

  String _normalizeLocalizedNumberText(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';

    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      // ٠١٢٣٤٥٦٧٨٩
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + (rune - 0x0660));
        continue;
      }
      // ۰۱۲۳۴۵۶۷۸۹
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + (rune - 0x06F0));
        continue;
      }
      // 0-9
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.writeCharCode(rune);
        continue;
      }

      final ch = String.fromCharCode(rune);
      if (ch == '.' || ch == ',' || ch == '٫' || ch == '،') {
        buffer.write('.');
        continue;
      }

      // فواصل آلاف ومسافات
      if (ch == '٬' || ch == ' ' || ch == '\u00A0' || ch == '\u202F' || ch == '_') {
        continue;
      }

      // ناقص عربي/إنجليزي
      if ((ch == '-' || ch == '−') && buffer.isEmpty) {
        buffer.write('-');
      }
    }

    final canonical = buffer.toString();
    final sepPositions = <int>[];
    for (var i = 0; i < canonical.length; i++) {
      if (canonical[i] == '.') sepPositions.add(i);
    }

    if (sepPositions.isEmpty) return canonical;

    final lastSep = sepPositions.last;
    final digitsBefore = canonical
        .substring(0, lastSep)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    final digitsAfter = canonical
        .substring(lastSep + 1)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;

    // مثال: 1,200 أو ١٬٢٠٠ تعتبر فاصل آلاف، وليست 1.2
    final singleSeparatorLooksLikeThousands =
        sepPositions.length == 1 && digitsBefore > 0 && digitsAfter == 3;

    if (singleSeparatorLooksLikeThousands) {
      return canonical.replaceAll('.', '');
    }

    // إذا فيه أكثر من فاصل، خل آخر فاصل هو العشري واحذف الباقي.
    final out = StringBuffer();
    var decimalWritten = false;
    for (var i = 0; i < canonical.length; i++) {
      final ch = canonical[i];
      if (ch == '.') {
        if (i == lastSep && !decimalWritten) {
          out.write('.');
          decimalWritten = true;
        }
      } else {
        out.write(ch);
      }
    }
    return out.toString();
  }

  double? _tryParseLocalizedDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final normalized = _normalizeLocalizedNumberText(value);
    if (normalized.isEmpty || normalized == '-' || normalized == '.') return null;
    return double.tryParse(normalized);
  }

  double _parseLocalizedDouble(dynamic value) =>
      _tryParseLocalizedDouble(value) ?? 0.0;

  double _toD(dynamic v) => _parseLocalizedDouble(v);

  // ===== تحميل مُرتّب يمنع تصفير غير مقصود =====
  Future<void> _initialLoad() async {
    if (_initialLoadDone) return;
    _initialLoadDone = true;

    // المرحلة الأولى: محلي فقط وسريع حتى ترسم الصفحة بدون تعليق.
    await SafePrefs.fixKnownMismatches();
    await _ensurePrefsEmail();
    await _migrateLegacyMacrosToPerUser();
    await refreshTargets();
    await _ensureTodaySnapshot();
    await _rollToNewDayIfNeeded();
    await _loadTodayWater();
    await loadMeals();

    // المرحلة الثانية: أشياء غير ضرورية لأول فريم، نشغلها بعد ظهور الهوم.
    _runHomeDeferredWork();
  }

  void _runHomeDeferredWork({Duration delay = const Duration(milliseconds: 450)}) {
    _homeDeferredTimer?.cancel();
    _homeDeferredTimer = Timer(delay, () {
      if (!mounted || _homeBackgroundWorkRunning) return;
      _homeBackgroundWorkRunning = true;

      Future<void>(() async {
        try {
          await _refreshDailyLogIndex();
          await _loadAndShowPoints();
          await _recomputeLocalPendingToday();
          await _maybeAwardDailyBonusesNow();
          await _checkAndUpdateDailyStreak(showSnack: false);
        } catch (e) {
          debugPrint('[HomeScreen] deferred work failed: $e');
        } finally {
          _homeBackgroundWorkRunning = false;
        }
      });

      // الصحة وملف الأطعمة قد تكون أثقل، نخليها أبعد شوي عشان ما تضغط أول فتح.
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        unawaited(loadPredefinedFoods());
      });
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        unawaited(fetchHealthData());
      });
      Future.delayed(const Duration(milliseconds: 1700), () {
        if (!mounted) return;
        unawaited(DailyHealthTips.showTodayIfNeeded(context));
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _macroTargetsListener = () {
      if (!mounted) return;
      unawaited(refreshTargets());
      unawaited(_ensureTodaySnapshot());
    };
    MacroTargetsController.revision.addListener(_macroTargetsListener);

    // لا نربط Streams ثقيلة قبل رسم الهوم.
    _attachTodayPointsListener();

    Future.microtask(_initialLoad);
  }

  @override
  void dispose() {
    _homeDeferredTimer?.cancel();
    _homePersistDebounce?.cancel();
    _dayPointsSub?.cancel();
    _achSub?.cancel();
    MacroTargetsController.revision.removeListener(_macroTargetsListener);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  // ===== ربط نقاط اليوم من التخزين المحلي أولًا =====
  void _attachTodayPointsListener() async {
    _dayPointsSub?.cancel();
    try {
      final ymd = DateTime.now().toIso8601String().split('T').first;
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getInt('guest_day_${ymd}_awardedPoints') ?? todayPoints;
      if (mounted) setState(() => todayPoints = local);
    } catch (_) {}

    // تعمدًا لا نفتح Firestore stream في الهوم.
    // الستريم كان يسبب شغل شبكة مستمر وإعادة بناء غير ضرورية.
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final now = DateTime.now();
    final today = now.toIso8601String().split('T').first;
    final shouldThrottle = _lastHomeResumeWorkAt != null &&
        now.difference(_lastHomeResumeWorkAt!) < const Duration(seconds: 20);

    if (today != _lastSeenDate) {
      _lastSeenDate = today;
      _attachTodayPointsListener();
      unawaited(_rollToNewDayIfNeeded());
    }

    if (shouldThrottle) return;
    _lastHomeResumeWorkAt = now;

    // لا نوقف الواجهة عند الرجوع للتطبيق؛ كل شيء بالخلفية.
    unawaited(refreshTargets());
    unawaited(_ensureTodaySnapshot());
    unawaited(_loadTodayWater());
    _persistHomeSnapshotDebounced();
    _runHomeDeferredWork(delay: const Duration(milliseconds: 650));
  }

  // ===== Helpers =====

  Future<bool> _hasLocalMacros() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'local';
    final k = prefs.getDouble('caloriesNeeded_$email');
    final p = prefs.getDouble('protein_$email');
    final c = prefs.getDouble('carbs_$email');
    final f = prefs.getDouble('fat_$email');
    return k != null && p != null && c != null && f != null;
  }

  // ====== تأكيد وجود currentEmail بالشيرد ======
  Future<void> _ensurePrefsEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // لا يوجد مستخدم — تأكد من تنظيف مفاتيح الجلسة
      await SessionManager.clearSessionKeys();
      return;
    }

    // ✅ هذا يحل مشكلة تبديل الحسابات: يحدّث currentUid/currentEmail حتى لو كانت موجودة من قبل
    await SessionManager.syncFromFirebaseUser(user);
  }

  // ====== حارس الأونبوردنغ (مرن) ======


  // ====== رسائل إنجاز الخطوات (5000 / 10000) ======
  Future<void> _maybeCelebrateStepMilestone(int totalSteps) async {
    // نعرض رسائل اليوم مرة واحدة لكل مستوى (وحد أقصى مرة لـ 5000 ومرة لـ 10000)
    final now = DateTime.now();
    final ymd = now.toIso8601String().split('T').first;
    final prefs = await SharedPreferences.getInstance();
    final key = 'steps_milestone_notified_$ymd';
    final already = prefs.getInt(key) ?? 0;

    int milestone = 0;
    if (totalSteps >= 10000) {
      milestone = 10000;
    } else if (totalSteps >= 5000) {
      milestone = 5000;
    } else {
      return;
    }

    if (milestone <= already) return;

    await prefs.setInt(key, milestone);

    final title = milestone == 5000 ? 'ممتاز! 🎉' : 'إنجاز كبير! 🏆';
    final body = milestone == 5000
        ? 'وصلت $totalSteps خطوة اليوم — كمل للأفضل!'
        : 'وصلت $totalSteps خطوة اليوم — رهيب! استمر 💪';

    _showMilestoneSnack(title: title, message: body);

    // إشعار (يعرض حتى لو المستخدم طلع من الصفحة) — بدون تغيير منطق الصحة
    try {
      await FastingNotifications.instance.scheduleOnce(
        id: 700000 + milestone, // معرّف ثابت لتجنب التعارض
        title: title,
        body: body,
        at: DateTime.now().add(const Duration(seconds: 1)),
        androidChannelId: 'activity_channel',
        androidChannelName: 'Activity',
        androidChannelDescription: 'إنجازات النشاط اليومي',
      );
    } catch (_) {
      // لو فشل الإذن/المنصة، نكتفي برسالة داخل التطبيق
    }
  }

  void _showMilestoneSnack({required String title, required String message}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ),
      );
    });
  }


// ====== Apple/Google Health (اختياري) ======
  Future<void> fetchHealthData() async {
    final List<HealthDataType> types = <HealthDataType>[
      HealthDataType.STEPS,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    ];
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month, now.day);

    try {
      try {
        final cfg = (health as dynamic).configure();
        if (cfg is Future) await cfg;
      } catch (_) {}

      final bool granted = await health.requestAuthorization(types);
      if (!granted) return;

      final List<HealthDataPoint> healthData =
          await health.getHealthDataFromTypes(
        types: types,
        startTime: start,
        endTime: now,
      );

      // بعض إصدارات حزمة health ترجع value كـ NumericHealthValue بدل num،
      // لذلك نحولها بشكل آمن بدون كسر المنطق.
      double _asDouble(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();

        // NumericHealthValue: { numericValue: <num> }
        try {
          final nv = (v as dynamic).numericValue;
          if (nv is num) return nv.toDouble();
        } catch (_) {}

        // بعض الإصدارات تستخدم { value: <num> }
        try {
          final vv = (v as dynamic).value;
          if (vv is num) return vv.toDouble();
        } catch (_) {}

        // آخر محاولة عبر toJson()
        try {
          final m = (v as dynamic).toJson();
          if (m is Map) {
            final nv = m['numericValue'];
            if (nv is num) return nv.toDouble();
            final vv = m['value'];
            if (vv is num) return vv.toDouble();
          }
        } catch (_) {}

        return 0.0;
      }

      int totalSteps = 0;
      double totalBurned = 0.0;

      for (final HealthDataPoint point in healthData) {
        if (point.type == HealthDataType.STEPS) {
          totalSteps += _asDouble(point.value).toInt();
        } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          totalBurned += _asDouble(point.value);
        }
      }

      if (!mounted) return;
      setState(() {
        steps = totalSteps;
        burned = totalBurned.toInt();
      });

      await _maybeCelebrateStepMilestone(totalSteps);

      // خزن نشاط اليوم محليًا + فايرستور
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ?? 'unknown_user';
      final ymd = DateTime.now().toIso8601String().split('T').first;
      await prefs.setString(
        'activity_${ymd}_$email',
        jsonEncode({'steps': steps, 'burned': burned}),
      );

      // 🔗 مرآة لفايرستور بدون تعطيل الواجهة
      unawaited(
        AppRepository.writeActivity(ymd: ymd, steps: steps, burned: burned)
            .catchError((_) {}),
      );
    } catch (e) {
      debugPrint('fetchHealthData error: $e');
    }
  }

  // ====== ماء اليوم + تخزين لقطة اليوم ======
  Future<void> _loadTodayWater() async {
    final v = await WaterStore.todayLiters();
    if (!mounted) return;
    setState(() => todayWaterLiters = v);
    unawaited(_snapshotTodayForEOD());

    // لا نكتب الماء في Firestore عند كل تحميل؛ WaterStore.addLiters يزامن وقت الإضافة.
    // هذا كان يسبب بطءًا متكررًا في الهوم.
  }

  // نخزن الماء لليوم الحالي كي نستخدمه عند تقييم نهاية اليوم
  Future<void> _snapshotTodayForEOD() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ??
          FirebaseAuth.instance.currentUser?.email ??
          'unknown_user';
      final ymd = DateTime.now().toIso8601String().split('T').first;
      await prefs.setString('water_total_${email}_$ymd',
          (todayWaterLiters).toStringAsFixed(6));
    } catch (_) {}
  }
  // ====== ترحيل قديم -> المفاتيح الموحّدة لكل مستخدم ======
  Future<void> _migrateLegacyMacrosToPerUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email;
    if (email == null) { debugPrint('[FoodAnalyze] camera:cancelled'); return; }

    final hasNew = prefs.getDouble('protein_$email') != null ||
        prefs.getDouble('carbs_$email') != null ||
        prefs.getDouble('fat_$email') != null;

    if (hasNew) return;

    final legacyProtein = prefs.getDouble('protein');
    final legacyCarbs = prefs.getDouble('carbs');
    final legacyFat = prefs.getDouble('fat');
    final legacyCals = prefs.getDouble('caloriesNeeded');

    if (legacyProtein != null) {
      await prefs.setDouble('protein_$email', legacyProtein);
    }
    if (legacyCarbs != null) {
      await prefs.setDouble('carbs_$email', legacyCarbs);
    }
    if (legacyFat != null) {
      await prefs.setDouble('fat_$email', legacyFat);
    }
    if (legacyCals != null) {
      await prefs.setDouble('caloriesNeeded_$email', legacyCals);
    }
  }

  // ====== تحميل الأهداف: محلي فورًا، والسحابة بالخلفية عند الحاجة فقط ======
  Future<void> refreshTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email;

    if (email == null) {
      debugPrint('[HomeScreen] refreshTargets skipped: no email');
      return;
    }

    final k = prefs.getDouble('caloriesNeeded_$email');
    final p = prefs.getDouble('protein_$email');
    final c = prefs.getDouble('carbs_$email');
    final f = prefs.getDouble('fat_$email');

    if (!mounted) return;
    setState(() {
      caloriesNeeded = k ?? caloriesNeeded.takeIfPositiveOr(2000.0);
      protein = p ?? protein.takeIfPositiveOr(100.0);
      fat = f ?? fat.takeIfPositiveOr(60.0);
      carbs = c ?? carbs.takeIfPositiveOr(300.0);
    });

    final hasLocal = k != null && p != null && c != null && f != null;
    final now = DateTime.now();
    final recentlyFetched = _lastTargetsRemoteFetchAt != null &&
        now.difference(_lastTargetsRemoteFetchAt!) < const Duration(minutes: 10);

    // إذا القيم موجودة محليًا، لا ننتظر Firestore ولا نطلبه كل مرة.
    if (hasLocal || recentlyFetched) return;

    _lastTargetsRemoteFetchAt = now;
    unawaited(_refreshTargetsFromRemoteInBackground(email));
  }

  Future<void> _refreshTargetsFromRemoteInBackground(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fetched = await _tryFetchTargetsFromFirestore()
          .timeout(const Duration(seconds: 3));
      if (fetched == null) return;

      final fk = (fetched['k'] as double?) ?? 0.0;
      final fp = (fetched['p'] as double?) ?? 0.0;
      final fc = (fetched['c'] as double?) ?? 0.0;
      final ff = (fetched['f'] as double?) ?? 0.0;
      if (fk <= 0 || fp <= 0 || fc <= 0 || ff <= 0) return;

      await prefs.setDouble('caloriesNeeded_$email', fk);
      await prefs.setDouble('protein_$email', fp);
      await prefs.setDouble('carbs_$email', fc);
      await prefs.setDouble('fat_$email', ff);

      if (!mounted) return;
      setState(() {
        caloriesNeeded = fk;
        protein = fp;
        carbs = fc;
        fat = ff;
      });
      unawaited(_ensureTodaySnapshot());
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _tryFetchTargetsFromFirestore() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      if (data == null) return null;

      final metrics = data['metrics'];
      if (metrics is! Map) return null;

      final k = metrics['caloriesNeeded'] ?? metrics['kcal'];
      final p = metrics['protein'];
      final c = metrics['carbs'];
      final f = metrics['fat'];

      int updatedAtMs = 0;
      final ua = metrics['updatedAt'];
      if (ua is Timestamp) {
        updatedAtMs = ua.toDate().millisecondsSinceEpoch;
      } else if (ua is num) {
        updatedAtMs = ua.toInt();
      } else if (ua is String) {
        final dt = DateTime.tryParse(ua);
        if (dt != null) updatedAtMs = dt.millisecondsSinceEpoch;
      }

      if (k is num && p is num && c is num && f is num) {
        return {
          'k': k.toDouble(),
          'p': p.toDouble(),
          'c': c.toDouble(),
          'f': f.toDouble(),
          'updatedAtMs': updatedAtMs,
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ====== النقاط (تحميل إجمالي فقط، العرض في الهوم اليومي) ======
  Future<void> _loadAndShowPoints() async {
    final pts = await AchievementsStore.getPoints();
    if (!mounted) return;
    setState(() => userPoints = pts);
  }

  // ====== إنشاء لقطة اليوم (أهداف اليوم تحفظ في dailyNutritionHistory) ======
  Future<void> _ensureTodaySnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';

    final today = DateTime.now().toIso8601String().split('T').first;
    final last = prefs.getString('lastSnapshotDate_$email');
    if (last == today) return;

    final k = prefs.getDouble('caloriesNeeded_$email') ?? caloriesNeeded;
    final p = prefs.getDouble('protein_$email') ?? protein;
    final c = prefs.getDouble('carbs_$email') ?? carbs;
    final f = prefs.getDouble('fat_$email') ?? fat;

    final rawHistory = prefs.getString('dailyNutritionHistory_$email');
    Map<String, dynamic> history = {};
    if (rawHistory != null) {
      try {
        history = json.decode(rawHistory);
      } catch (_) {
        history = {};
      }
    }

    history[today] ??= {'calories': k, 'protein': p, 'carbs': c, 'fat': f};

    await prefs.setString('dailyNutritionHistory_$email', json.encode(history));
    await prefs.setString('lastSnapshotDate_$email', today);

    for (final key in [
      'consumed_cal_$email',
      'consumed_pro_$email',
      'consumed_carb_$email',
      'consumed_fat_$email',
    ]) {
      await prefs.remove(key);
    }
  }

  // ====== لفّ اليوم + توليد مكافآت أمس ======
  Future<void> _rollToNewDayIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'local';
    final today = DateTime.now().toIso8601String().split('T').first;

    final lastMealsDate = prefs.getString('activeMealsDate_$email');

    if (lastMealsDate == null) {
      await prefs.setString('activeMealsDate_$email', today);
      _activeMealsStoredDate = today;
      return;
    }

    if (lastMealsDate != today) {
      // قبل ما نصفر، قوّم مكافآت اليوم السابق
      await _queueEndOfDayRewardsFor(lastMealsDate);

      setState(() {
        meals = [
          {'name': '🍳 الفطور', 'items': <Map<String, dynamic>>[]},
          {'name': '🍽️ الغداء', 'items': <Map<String, dynamic>>[]},
          {'name': '🌙 العشاء', 'items': <Map<String, dynamic>>[]},
        ];
        totalCalories = 0.0;
        totalProtein = 0.0;
        totalCarbs = 0.0;
        totalFat = 0.0;
      });

      await saveMeals();
      await prefs.setString('activeMealsDate_$email', today);
      _activeMealsStoredDate = today;

      await _ensureTodaySnapshot();
      await _syncTodayEntriesAndTotals();
      _attachTodayPointsListener(); // اليوم تغيّر
      await _checkAndUpdateDailyStreak(showSnack: true);
    } else {
      _activeMealsStoredDate = today;
    }
  }

  // ====== حساب قرب الماكروز ======
  bool _macrosClose({
    required double targetP,
    required double targetC,
    required double targetF,
    required double sumP,
    required double sumC,
    required double sumF,
  }) {
    bool closeOne(double goal, double val) {
      if (goal <= 0) return true; // تجاهل هدف صفر
      final diff = (val - goal).abs() / goal;
      return diff <= _kMacroCloseTolerance;
    }

    return closeOne(targetP, sumP) &&
        closeOne(targetC, sumC) &&
        closeOne(targetF, sumF);
  }
  // ====== توليد مكافآت معلّقة ليوم معيّن ======
  Future<void> _queueEndOfDayRewardsFor(String ymd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';

    final claimedKey = 'rewards_resolved_${email}_$ymd';
    if (_prefBool(prefs, claimedKey)) return; // سبق معالجتها (جمع/رفض)

    // إجماليات اليوم (k,p,c,f)
    final totalsKey = 'kcal_daytotals_${email}_$ymd';
    Map<String, dynamic> totals = {};
    try {
      final rawTotals = prefs.getString(totalsKey);
      if (rawTotals != null) totals = json.decode(rawTotals);
    } catch (_) {}

    final double sumK = _toD(totals['k']);
    final double sumP = _toD(totals['p']);
    final double sumC = _toD(totals['c']);
    final double sumF = _toD(totals['f']);

    // أهداف اليوم
    Map<String, dynamic> history = {};
    try {
      final rawHist = prefs.getString('dailyNutritionHistory_$email');
      if (rawHist != null) history = json.decode(rawHist);
    } catch (_) {}
    final m = history[ymd] as Map?;
    final double tK = _toD(m?['calories']);
    final double tP = _toD(m?['protein']);
    final double tC = _toD(m?['carbs']);
    final double tF = _toD(m?['fat']);

    // ماء اليوم
    final String? waterStr = prefs.getString('water_total_${email}_$ymd');
    final double waterLiters =
        waterStr != null ? _parseLocalizedDouble(waterStr) : 0.0;

    final List<Map<String, dynamic>> pending = [];

    // شرط السعرات + قرب الماكروز
    final reachedCalories =
        (tK > 0) && (sumK >= (tK * _kCalorieCompletionRatio));
    final closeMacros = _macrosClose(
      targetP: tP, targetC: tC, targetF: tF,
      sumP: sumP, sumC: sumC, sumF: sumF,
    );

    if (reachedCalories && closeMacros) {
      pending.add({
        'id': 'kcal',
        'points': _kCaloriesBonusPoints,
        'message':
            'أحسنت! أكملت سعراتك اليوم وكانت قريبة من الماكروز. ربحت ${_kCaloriesBonusPoints} نقاط.',
      });
    }

    // شرط الماء
    if (waterLiters >= _kWaterBonusLiters) {
      pending.add({
        'id': 'water',
        'points': _kWaterBonusPoints,
        'message':
            'رائع! شربت ${_kWaterBonusLiters.toStringAsFixed(0)} لتر ماء أو أكثر. ربحت ${_kWaterBonusPoints} نقاط.',
      });
    }

    // خزّن المكافآت المعلّقة إن وُجدت + مرآة فايرستور
    final pendingKey = 'pending_rewards_${email}_$ymd';
    if (pending.isNotEmpty) {
      await prefs.setString(pendingKey, json.encode(pending));
      // 🔗 فايرستور
      unawaited(AppRepository.putPendingRewards(ymd: ymd, pending: pending).catchError((_) {}));
    } else {
      // لا مكافآت: علّمها كمنتهية محليًا + حدّث فايرستور (awarded=0)
      await prefs.setBool(claimedKey, true);
      unawaited(AppRepository.markRewardsResolved(
        ymd: ymd, claimed: false, awardedPoints: 0,
      ).catchError((_) {}));
    }
  }

  // ====== قراءة/حلّ مكافآت تاريخ معيّن ======
  Future<List<Map<String, dynamic>>> _loadPendingRewardsForDate(String ymd) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';
    final pendingKey = 'pending_rewards_${email}_$ymd';
    final resolvedKey = 'rewards_resolved_${email}_$ymd';
    if (_prefBool(prefs, resolvedKey)) return [];
    try {
      final raw = prefs.getString(pendingKey);
      if (raw == null) return [];
      final list = json.decode(raw);
      if (list is List) {
        return List<Map<String, dynamic>>.from(list);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _resolveRewardsForDate(String ymd, {required bool claim}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';
    final pendingKey = 'pending_rewards_${email}_$ymd';
    final resolvedKey = 'rewards_resolved_${email}_$ymd';

    int awarded = 0;
    if (claim) {
      final rewards = await _loadPendingRewardsForDate(ymd);
      for (final r in rewards) {
        final pts = (r['points'] is num) ? (r['points'] as num).toInt() : 0;
        if (pts > 0) awarded += pts;
      }
      if (awarded > 0) {
        // إجمالي النقاط (صفحة الإنجازات)
        await AchievementsStore.addPoints(awarded);
      }
      // نقاط اليوم (مرآة في days/{ymd})
      unawaited(AppRepository.markRewardsResolved(
        ymd: ymd, claimed: true, awardedPoints: awarded,
      ).catchError((_) {}));
    } else {
      unawaited(AppRepository.markRewardsResolved(
        ymd: ymd, claimed: false, awardedPoints: 0,
      ).catchError((_) {}));
    }

    await prefs.remove(pendingKey);
    await prefs.setBool(resolvedKey, true);

    // حدث عدّاد نقاط اليوم المحلي للعرض
    if (DateTime.now().toIso8601String().split('T').first == ymd) {
      setState(() => todayPoints = claim ? awarded : 0);
    }
  }



// أعِدّ حساب رصيد المكافآت المحلي المعلّق لليوم (fallback للهيدر)
Future<void> _recomputeLocalPendingToday() async {
  final prefs = await SharedPreferences.getInstance();
  final email = prefs.getString('currentEmail') ??
      FirebaseAuth.instance.currentUser?.email ??
      'unknown_user';
  final ymd = DateTime.now().toIso8601String().split('T').first;
  final pendingKey = 'pending_rewards_${email}_$ymd';
  final resolvedKey = 'rewards_resolved_${email}_$ymd';

  int sum = 0;
  bool resolved = _prefBool(prefs, resolvedKey);
  try {
    final raw = prefs.getString(pendingKey);
    if (raw != null && !resolved) {
      final dec = json.decode(raw);
      if (dec is List) {
        for (final e in dec) {
          final pts = (e is Map && e['points'] is num) ? (e['points'] as num).toInt() : 0;
          if (pts > 0) sum += pts;
        }
      }
    }
  } catch (_) {}
  if (!mounted) return;
  setState(() {
    _pendingLocalToday = sum;
    _resolvedLocalToday = resolved;
  });
}

// تجميع فوري من الهوم: يوسّط Firestore + يقلّص الرصيد المحلي
Future<void> _claimPendingNowFromHome(int pendingNow, String ymd) async {
  if (pendingNow <= 0) return;
  // زد الإجمالي ذرّياً
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) { debugPrint('[FoodAnalyze] camera:cancelled'); return; }
  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final achRef = userRef.collection('meta').doc('achievements');
  await FirebaseFirestore.instance.runTransaction((tx) async {
    tx.set(achRef, {
      'points_total': FieldValue.increment(pendingNow),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
    tx.set(userRef, {
      'points_total': FieldValue.increment(pendingNow),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
    // صفّر نقاط اليوم في وثيقة اليوم
    final dayRef = userRef.collection('days').doc(ymd);
    tx.set(dayRef, {
      'rewards': {
        'pendingPoints': 0,
        'claimed': true,
        'claimedAt': Timestamp.now(),
      },
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  });

  // علّم الرصيد المحلي كمحسوم
  final prefs = await SharedPreferences.getInstance();
  final email = prefs.getString('currentEmail') ??
      FirebaseAuth.instance.currentUser?.email ??
      'unknown_user';
  final resolvedKey = 'rewards_resolved_${email}_$ymd';
  await prefs.setBool(resolvedKey, true);

  // حدّث واجهة الهوم سريعًا
  if (!mounted) return;
  setState(() {
    _resolvedLocalToday = true;
    _pendingLocalToday = 0;
    todayPoints = 0;
  });
}

  // ====== عرض ورقة المطالبة آخر الليل لنفس اليوم ======
  Future<void> _maybeShowClaimSheetForTonight() async {
    if (!mounted || _claimSheetShown) return;

    final now = DateTime.now();
    if (now.hour < _kClaimCutoffHour) return; // لسه ما وصلنا آخر الليل

    final today = now.toIso8601String().split('T').first;

    // تأكد أن اللقطات محدثة قبل التقييم
    await _syncTodayEntriesAndTotals();
    await _snapshotTodayForEOD();

    // قيّم واستخرج/خزّن مكافآت هذا اليوم
    await _queueEndOfDayRewardsFor(today);

    final rewards = await _loadPendingRewardsForDate(today);
    if (rewards.isEmpty) return;

    _claimSheetShown = true;
    if (!mounted) return;
  // ====== Guard: show claim UI once per date (persists per day) ======
  Future<bool> _shouldShowClaimUI({required String forDate}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'claim_ui_shown_' + forDate; // e.g., 2025-10-01
      final shown = prefs.getBool(key) ?? false;
      // If already shown today, don't nag again
      return !shown;
    } catch (_) {
      return true; // fail-open to avoid blocking first show
    }
  }

  Future<void> _markClaimUIShown({required String forDate}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'claim_ui_shown_' + forDate;
      await prefs.setBool(key, true);
    } catch (_) {}
  }

    if (await _shouldShowClaimUI(forDate: today)) {
  _claimSheetShown = true;
  if (!mounted) return;
  _showRewardsClaimSheet(rewards, forDate: today);
  await _markClaimUIShown(forDate: today);
}
}

  // ====== Fallback: عرض مكافآت أمس عند فتح التطبيق ======
  Future<void> _maybeShowClaimSheetForYesterday() async {
    if (!mounted || _claimSheetShown) return;
    final ymdYesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;
    final rewards = await _loadPendingRewardsForDate(ymdYesterday);
    if (rewards.isEmpty) return;
    if (await _shouldShowClaimUI(forDate: ymdYesterday)) {
  _claimSheetShown = true;
  if (!mounted) return;
  _showRewardsClaimSheet(rewards, forDate: ymdYesterday);
  await _markClaimUIShown(forDate: ymdYesterday);
}
}

  void _showRewardsClaimSheet(List<Map<String, dynamic>> rewards, {required String forDate}) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.celebration, size: 18, color: cs.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('مكافآت اليوم ($forDate)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...rewards.map((r) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant.withOpacity(.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primary.withOpacity(.12),
                        child: const Icon(Icons.stars),
                      ),
                      title: Text(
                        r['message']?.toString() ?? 'مكافأة',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      subtitle: Text('النقاط: ${r['points'] ?? 0}'),
                    ),
                  )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _resolveRewardsForDate(forDate, claim: false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم رفض المكافآت لهذا اليوم.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _resolveRewardsForDate(forDate, claim: true);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم تجميع المكافآت 👏')),
                          );
                        }
                      },
                      icon: const Icon(Icons.savings_outlined),
                      label: const Text('تجميع'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _claimSheetShown = false;
    });
  }
  // ====== محوّل JSON -> FoodItem ======
  List<FoodItem> mapFoodsFromJson(List<Map<String, dynamic>> src) {
    double toD(dynamic v) =>
        (v is num) ? v.toDouble() : _parseLocalizedDouble(v);

    return src.map((m) {
      final id = (m['id'] ?? m['code'] ?? m['name'] ?? UniqueKey().toString())
          .toString();
      final name = (m['name'] ?? 'عنصر').toString();
      final category = (m['category'] ?? m['group'] ?? 'Other').toString();

      var kcal100 = toD(m['kcal_per_100g'] ??
          m['cal_per_100g'] ??
          m['kcal100'] ??
          m['cal']);
      var p100 = toD(m['protein_per_100g'] ?? m['protein100'] ?? m['protein']);
      var c100 = toD(m['carbs_per_100g'] ??
          m['carb_per_100g'] ??
          m['carb100'] ??
          m['carb']);
      var f100 = toD(m['fat_per_100g'] ?? m['fat100'] ?? m['fat']);

      final gramsPerUnit = toD(m['grams_per_unit']);
      final isPerUnit = gramsPerUnit > 0 &&
          (kcal100 == 0 && p100 == 0 && c100 == 0 && f100 == 0);

      if (isPerUnit) {
        final kcalPerUnit =
            toD(m['kcal'] ?? m['calories'] ?? m['cal_per_unit']);
        final pPerUnit = toD(m['protein'] ?? m['protein_per_unit']);
        final cPerUnit = toD(m['carb'] ?? m['carbs'] ?? m['carbs_per_unit']);
        final fPerUnit = toD(m['fat'] ?? m['fat_per_unit']);

        final factor = gramsPerUnit > 0 ? (100.0 / gramsPerUnit) : 1.0;
        kcal100 = (kcalPerUnit * factor);
        p100 = (pPerUnit * factor);
        c100 = (cPerUnit * factor);
        f100 = (fPerUnit * factor);
      }

      return FoodItem(
        id: id,
        name: name,
        category: category,
        unit: (m['unit'] ?? m['serving_unit'] ?? 'جرام').toString(),
        isPer100g: (() {
          final u = (m['unit'] ?? m['serving_unit'] ?? 'جرام').toString().trim();
          return u == 'جرام' || u == 'غ' || u == 'غرام' || u == 'g' || u == 'gram';
        })(),
        kcalPer100g: kcal100,
        proteinPer100g: p100,
        carbsPer100g: c100,
        fatPer100g: f100,
      );
    }).toList();
  }

  // ====== قراءة foods.json ======
  Future<void> loadPredefinedFoods() async {
    if (readyFoods.isNotEmpty || predefinedFoods.isNotEmpty) return;
    try {
      final String response = await rootBundle.loadString('assets/foods.json');
      final data = await compute(_decodeFoodMaps, response);
      if (!mounted) return;
      final foods = mapFoodsFromJson(data);
      if (!mounted) return;
      setState(() {
        predefinedFoods = data;
        readyFoods = foods;
      });
    } catch (e) {
      debugPrint('Failed to load assets/foods.json: $e');
    }
  }

  // ====== حفظ/تحميل الوجبات ======
  Future<void> saveMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();
    await prefs.setString('meals_$storageKey', json.encode(meals));

    // لا نكتب Firestore عند كل تغيير في الهوم.
    // النسخ السحابي صار نهاية اليوم/خلفية من خدمة منفصلة حتى تبقى الصفحة سلسة.
  }

  Future<void> loadMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();

    final legacy = prefs.getString('meals');
    final savedMeals = prefs.getString('meals_$storageKey') ?? legacy;

    if (savedMeals == null) {
      calculateTotals();
      if (mounted) setState(() {});
      return;
    }

    if (legacy != null && prefs.getString('meals_$storageKey') == null) {
      await prefs.setString('meals_$storageKey', legacy);
      await prefs.remove('meals');
    }

    try {
      final decoded = json.decode(savedMeals) as List;
      if (!mounted) return;
      setState(() {
        meals = List<Map<String, dynamic>>.from(decoded);
        calculateTotals();
      });
      _persistHomeSnapshotDebounced();
    } catch (e) {
      debugPrint('[HomeScreen] loadMeals failed: $e');
    }
  }

  // ====== حساب المجاميع ======
  void calculateTotals() {
    totalCalories = 0.0;
    totalProtein = 0.0;
    totalCarbs = 0.0;
    totalFat = 0.0;

    for (final meal in meals) {
      final items = (meal['items'] as List).cast<Map<String, dynamic>>();
      for (final item in items) {
        totalCalories += (item['cal'] as num).toDouble();
        totalProtein += (item['protein'] as num).toDouble();
        totalCarbs += (item['carb'] as num).toDouble();
        totalFat += (item['fat'] as num).toDouble();
      }
    }
  }

  Map<String, double> _sumMeal(List<Map<String, dynamic>> items) {
    double k = 0, p = 0, c = 0, f = 0;
    for (final it in items) {
      k += (it['cal'] as num).toDouble();
      p += (it['protein'] as num).toDouble();
      c += (it['carb'] as num).toDouble();
      f += (it['fat'] as num).toDouble();
    }
    return {'k': k, 'p': p, 'c': c, 'f': f};
  }

  // ====== (جديد) صندوق تأكيد موحّد قبل تجاوز السعرات ======
  Future<bool> _confirmExceedCalories(double calToAdd) async {
    // لو ما عندنا هدف معرّف، أو لن نتجاوز — لا حاجة للتأكيد
    if (caloriesNeeded <= 0) return true;
    final projected = totalCalories + calToAdd;
    if (projected <= caloriesNeeded) return true;

    final cs = Theme.of(context).colorScheme;
    final overBy = (projected - caloriesNeeded).clamp(0, double.infinity);

    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: false,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          builder: (_) => Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.red),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه تجاوز السعرات',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant.withOpacity(.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مع إضافة هذه الوجبة ستتجاوز هدف السعرات لليوم.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _pill('الحالي: ${totalCalories.toStringAsFixed(0)}'),
                            _pill('الإضافة: ${calToAdd.toStringAsFixed(0)}'),
                            _pill('المتوقّع: ${projected.toStringAsFixed(0)}'),
                            _pill('هدفك: ${caloriesNeeded.toStringAsFixed(0)}'),
                            _pill('تجاوز: +${overBy.toStringAsFixed(0)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text('لا'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.check),
                          label: const Text('نعم، أضف الوجبة'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ).then((v) => v ?? false);
  }

  // شارة صغيرة للأرقام داخل الصندوق
  Widget _pill(String text) {
    final on = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on.withOpacity(.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on.withOpacity(.12)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ====== إضافة العناصر + حفظ + TrackerStore + مرآة فايرستور ======
  Future<void> _addItemsToMealAndPersist(
    int mealIndex,
    List<Map<String, dynamic>> items,
  ) async {
    // حفظ حالة ما قبل الإضافة للنقاط
    final int _preTotalItems = meals.fold<int>(0, (acc, m) => acc + ((m['items'] as List).length));
    final int _preSlotCount  = (meals[mealIndex]['items'] as List).length;

    await _rollToNewDayIfNeeded();

    double cal = 0, p = 0, c = 0, f = 0;
    for (final it in items) {
      cal += (it['cal'] as num).toDouble();
      p += (it['protein'] as num).toDouble();
      c += (it['carb'] as num).toDouble();
      f += (it['fat'] as num).toDouble();
    }

    // 👇 (جديد) اطلب التأكيد قبل تجاوز السعرات
    final ok = await _confirmExceedCalories(cal);
    if (!ok) return;

    bool allow = true;
    try {
      final dynamic res = await DietBus.addMeal(
        calories: cal,
        proteinGrams: p,
        carbsGrams: c,
        fatGrams: f,
        at: DateTime.now(),
        context: context,
      );
      allow = (res is bool) ? res : true;
    } catch (_) {
      // إذا فشل DietBus لأي سبب، لا تمنع الإضافة (كان يسبب: ما يضيف الوجبات)
      allow = true;
    }

    if (!allow) {
      if (!mounted) return;
      
      return;
    }

    setState(() {
      (meals[mealIndex]['items'] as List).addAll(items);
      calculateTotals();
      _animSeed++; // 🔔 يحفّز الأنيميشن
    });

    // نبضة اهتزاز خفيفة بعد الإضافة
    HapticFeedback.selectionClick();

    
    // 🔄 حفظ محلي مؤجل فقط؛ بدون Firestore ولا فهرسة ثقيلة وقت الإضافة.
    Future.microtask(() async {
      try {
        await saveMeals();
        _persistHomeSnapshotDebounced();
      } catch (e) {
        debugPrint('[MealsPersist] background persist failed: $e');
      }
    });

    // نقاط الوجبة بالخلفية، لا نوقف الواجهة.
    unawaited(_awardMealPoints(mealIndex, _preTotalItems, _preSlotCount));
}

  // ====== نتيجة Food AI ======
  Future<void> _handleFoodAiResult(int mealIndex, dynamic result) async {
    try {
      if (result == null) { debugPrint('[FoodAnalyze] camera:cancelled'); return; }
      final map = (result is Map) ? result : null;
      if (map == null) { debugPrint('[FoodAnalyze] camera:cancelled'); return; }

      String name =
          (map['label'] ?? map['name'] ?? 'صنف من الصورة').toString();
      final serving = map['serving'];
      if (serving != null && '$serving'.trim().isNotEmpty) {
        name = '$name (${serving.toString()})';
      }

      final cal = _toD(map['calories'] ?? map['cal']);
      final p = _toD(map['protein']);
      final c = _toD(map['carbs'] ?? map['carb']);
      final f = _toD(map['fat']);

      if (cal <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ما وصلت بيانات صالحة من تحليل الصورة')),
        );
        return;
      }

      await _addItemsToMealAndPersist(mealIndex, [
        {'name': name, 'cal': cal, 'protein': p, 'carb': c, 'fat': f}
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('تمت إضافة "$name" إلى ${meals[mealIndex]['name']}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إضافة نتيجة تحليل الصورة: $e')),
      );
    }
  }

  // ====== ارتفاع خلايا خيارات الإضافة (متكيّف ويمنع overflow) ======
  double _optionTileHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final scale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.6);
    final double base = h < 700 ? 128.0 : 140.0;
    final double extra = (scale - 1.0) * 48.0;
    return (base + extra).clamp(124.0, 188.0);
  }

  // ====== خيارات الإضافة ======
  // ✅ تنبيه: تحليل الطعام بالنص تحت التحديث (زر مع علامة استفهام)
  void _showTextAnalysisComingSoon(BuildContext sheetCtx, BuildContext parentContext) {
    showDialog(
      context: sheetCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('قريباً'),
        content: const Text(
          '''ميزة تحليل الطعام النصي تحت التحديث.

يمكنك أخذ الماكروز من "مدرب وازن الذكي" إلى أن تعمل الميزة بشكل كامل.''',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              Navigator.of(sheetCtx).pop(); // close bottom sheet
              Navigator.of(parentContext).push(
                MaterialPageRoute(builder: (_) => const AskWazenCoachScreen()),
              );
            },
            child: const Text('مدرب وازن الذكي'),
          ),
        ],
      ),
    );
  }

  void addMealItem(int mealIndex) {
    final parentContext = context;
    final cs = Theme.of(parentContext).colorScheme;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true, // ← يسمح بارتفاع كبير مع تمرير
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView( // ← يمنع أي overflow ويتيح سكرول
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // عنوان صغير
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.add, size: 16, color: cs.primary),
                      ),
                      const SizedBox(width: 8),
                      Text('إضافة وجبة',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              )),
                    ],
                  ),
                  const SizedBox(height: 12),



                  // شبكة خيارات 2×2 بارتفاع ثابت آمن
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: _optionTileHeight(context), // ← أهم تعديل
                    ),
                    children: [
                      _AddOptionCard(
                        icon: Icons.create_rounded,
                        color: cs.primary,
                        title: 'إدخال يدوي',
                        subtitle: 'أدخل السعرات والماكروز',
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          showManualEntryForm(mealIndex);
                        },
                      ),
                      _AddOptionCard(
                        icon: Icons.fastfood_rounded,
                        color: cs.secondary,
                        title: 'من قائمة جاهزة',
                        subtitle: 'اختيار عناصر/وجبة محفوظة',
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          showReadyListPicker(
                            parentContext,
                            onAddItemsToToday: (selected) async {
                              final items = selected.map<Map<String, dynamic>>((e) {
                                final qty = e.qty;
                                final factor = e.item.isPer100g ? (qty / 100.0) : qty;

                                String fmtQty(double v) {
                                  final iv = v.roundToDouble();
                                  if ((v - iv).abs() < 0.00001) return iv.toStringAsFixed(0);
                                  return v.toStringAsFixed(1);
                                }

                                final qtyLabel = e.item.isPer100g
                                    ? '${qty.toStringAsFixed(0)}غ'
                                    : '${fmtQty(qty)} ${e.item.unit}';

                                final cal = e.item.kcalPer100g * factor;
                                final p = e.item.proteinPer100g * factor;
                                final c = e.item.carbsPer100g * factor;
                                final f = e.item.fatPer100g * factor;

                                return {
                                  'name': '${e.item.name} ($qtyLabel)',
                                  'cal': cal,
                                  'protein': p,
                                  'carb': c,
                                  'fat': f,
                                };
                              }).toList();
                              await _addItemsToMealAndPersist(mealIndex, items);
                            },
                            onSaveMealTemplate: (mealName, notes, selected) async {
                              final prefs = await SharedPreferences.getInstance();
                              final storageKey = await SessionManager.currentStorageKey();
                              final k = 'meal_templates_$storageKey';

                              // ✅ Migration: key القديم كان بدون suffix
                              final legacyRaw = prefs.getString('meal_templates');
                              if (legacyRaw != null && prefs.getString(k) == null) {
                                await prefs.setString(k, legacyRaw);
                                await prefs.remove('meal_templates');
                              }

                              final raw = prefs.getString(k);
                              List<Map<String, dynamic>> templates = raw != null
                                  ? List<Map<String, dynamic>>.from(json.decode(raw))
                                  : [];
                              templates.add({
                                'name': mealName,
                                'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
                                'items': selected
                                    .map((e) => {
                                          'id': e.item.id,
                                          'name': e.item.name,

                                          // ✅ جديد: يدعم جرام/وحدات (حبة/علبة/شريحة..)
                                          'qty': e.qty,
                                          'unit': e.item.unit,
                                          'per100g': e.item.isPer100g,

                                          // ✅ Base macros:
                                          // - إذا per100g=true => هذه القيم لكل 100غ
                                          // - إذا per100g=false => هذه القيم لكل 1 وحدة
                                          'kcalBase': e.item.kcalPer100g,
                                          'pBase': e.item.proteinPer100g,
                                          'cBase': e.item.carbsPer100g,
                                          'fBase': e.item.fatPer100g,

                                          // 🔁 توافق مع القوالب القديمة (جرام فقط)
                                          if (e.item.isPer100g) 'grams': e.qty,
                                          if (e.item.isPer100g) 'kcal100': e.item.kcalPer100g,
                                          if (e.item.isPer100g) 'p100': e.item.proteinPer100g,
                                          if (e.item.isPer100g) 'c100': e.item.carbsPer100g,
                                          if (e.item.isPer100g) 'f100': e.item.fatPer100g,
                                        })
                                    .toList(),
                              });
                              await prefs.setString(k, json.encode(templates));
                            },
                            foods: readyFoods,
                          );
                        },
                      ),
                      _AddOptionCard(
                        icon: Icons.notes_rounded,
                        color: cs.secondary,
                        title: 'التحليل بالنص',
                        subtitle: 'حلّل وصفك النصي للوجبة',
                        enabled: true,
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();
                          await _handleAddByText(mealIndex, parentContext);
                        },
                        onHelpTap: null,
                      ),

                      _AddOptionCard(
                        icon: Icons.camera_alt_rounded,
                        color: cs.tertiary,
                        title: 'تصوير الطعام',
                        subtitle: 'تحليل الصورة واستخراج القيم',
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();

                          // انتظر إغلاق الـ BottomSheet قبل فتح الكاميرا.
                          // هذا يمنع تعارض الـ Navigator/الكاميرا عند الفتح المتكرر.
                          await Future<void>.delayed(const Duration(milliseconds: 220));

                          if (!mounted) return;

                          try {
                            final result = await Navigator.of(parentContext).push(
                              MaterialPageRoute(builder: (_) => const FoodCameraScreen()),
                            );
                            await _handleFoodAiResult(mealIndex, result);
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(content: Text('تعذّر فتح الكاميرا: $e')),
                            );
                          }
                        },

                      ),

                      // ✅ زر جديد: إضافة وجبة من مطعم (اختيار وجبة جاهزة)
                      _AddOptionCard(
                        icon: Icons.restaurant_menu_rounded,
                        color: cs.primary,
                        title: 'إضافة من مطعم',
                        subtitle: 'اختر وجبة جاهزة من المطاعم',
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();

                          final Meal? picked = await Navigator.of(parentContext).push<Meal?>(
                            MaterialPageRoute(
                              builder: (_) => const RestaurantsPage(pickMealMode: true),
                            ),
                          );

                          if (picked == null) return;

                          try {
                            // picked هو Meal
                            final Meal m = picked;
                            await _addItemsToMealAndPersist(mealIndex, [
                              {
                                'name': '${m.name} — ${m.restaurant}',
                                'cal': m.calories.toDouble(),
                                'protein': m.protein,
                                'carb': m.carbs,
                                'fat': m.fat,
                              }
                            ]);

                            if (!mounted) return;
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(content: Text('تمت إضافة "${m.name}" من ${m.restaurant}')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(content: Text('تعذّر إضافة الوجبة من المطعم: $e')),
                            );
                          }
                        },
                      ),
                      _AddOptionCard(
                        icon: Icons.qr_code_scanner_rounded,
                        color: cs.error,
                        title: 'مسح باركود المنتج',
                        subtitle: 'جلب القيم الغذائية تلقائيًا',
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();

                          final dynamic result = await Navigator.of(parentContext).push(
                            MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
                          );

                          if (result == null) { debugPrint('[FoodAnalyze] camera:cancelled'); return; }

                          // 1) الشكل الجديد: FoodMacro
                          if (result is FoodMacro) {
                            await _addItemsToMealAndPersist(mealIndex, [
                              {
                                'name': result.name,
                                'cal': result.caloriesKcal,
                                'protein': result.proteinG,
                                'carb': result.carbsG,
                                'fat': result.fatG,
                              }
                            ]);
                            return;
                          }

                          // 2) الشكل القديم: خريطة OFF
                          if (result is Map && result['nutriments'] != null) {
                            final n = result['nutriments'] as Map;
                            final name = (result['product_name'] ?? 'منتج من الباركود').toString();
                            final cal = ((n['energy-kcal_100g'] ?? 0) as num).toDouble();
                            final p   = ((n['proteins_100g'] ?? 0) as num).toDouble();
                            final c   = ((n['carbohydrates_100g'] ?? 0) as num).toDouble();
                            final f   = ((n['fat_100g'] ?? 0) as num).toDouble();

                            await _addItemsToMealAndPersist(mealIndex, [
                              {'name': name, 'cal': cal, 'protein': p, 'carb': c, 'fat': f}
                            ]);
                            return;
                          }

                          // 3) إدخال يدوي
                          if (result is Map && result['barcode'] != null) {
                            showManualEntryForm(mealIndex, barcode: (result['barcode'] ?? '').toString());
                            return;
                          }

                          if (mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              const SnackBar(content: Text('تعذّر تفسير نتيجة الباركود')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ====== إدخال يدوي ======
  void showManualEntryForm(int mealIndex, {String? barcode}) {
    final nameController = TextEditingController();
    final calController = TextEditingController();
    final proteinController = TextEditingController();
    final carbController = TextEditingController();
    final fatController = TextEditingController();

    bool autoCalc = true;

    double _calcKcal() {
      final p = _parseLocalizedDouble(proteinController.text);
      final c = _parseLocalizedDouble(carbController.text);
      final f = _parseLocalizedDouble(fatController.text);
      return (p * 4) + (c * 4) + (f * 9);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void recomputeIfNeeded() {
            if (autoCalc) {
              final kcal = _calcKcal();
              calController.text = kcal > 0 ? kcal.toStringAsFixed(0) : '';
            }
          }

          final cs = Theme.of(context).colorScheme;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
              left: 16.0,
              right: 16.0,
              top: 16.0,
            ),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.create, size: 16, color: cs.primary),
                        ),
                        const SizedBox(width: 8),
                        Text('إدخال وجبة يدويًا',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم الوجبة (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: autoCalc,
                          onChanged: (v) {
                            setModalState(() {
                              autoCalc = v ?? true;
                              recomputeIfNeeded();
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('احسب السعرات تلقائيًا من الماكروز (4/4/9)'),
                        ),
                      ],
                    ),
                    TextField(
                      controller: calController,
                      enabled: !autoCalc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'السعرات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: proteinController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'بروتين (غ)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(recomputeIfNeeded),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: carbController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'كارب (غ)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(recomputeIfNeeded),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fatController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'دهون (غ)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(recomputeIfNeeded),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final enteredName = nameController.text.trim();
                          final mealName =
                              enteredName.isEmpty ? 'وجبة مخصصة' : enteredName;

                          double cal =
                              _parseLocalizedDouble(calController.text);
                          final double p =
                              _parseLocalizedDouble(proteinController.text);
                          final double c =
                              _parseLocalizedDouble(carbController.text);
                          final double f =
                              _parseLocalizedDouble(fatController.text);

                          if (autoCalc) cal = _calcKcal();

                          if (cal <= 0.0) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('يرجى إدخال بيانات صحيحة')),
                            );
                            return;
                          }

                          await _addItemsToMealAndPersist(mealIndex, [
                            {
                              'name': mealName,
                              'cal': cal,
                              'protein': p,
                              'carb': c,
                              'fat': f
                            }
                          ]);

                          

                          // ✅ حفظ المنتج في كاش الباركود (Firestore) إذا كان هذا الإدخال جاء من مسح باركود ولم يُوجد المنتج
                          final String bc = (barcode ?? '').trim();
                          if (bc.isNotEmpty) {
                            try {
                              await FirebaseFirestore.instance.collection('barcodes').doc(bc).set({
                                'name': mealName,
                                'brand': null,
                                'servingSizeG': null,
                                'caloriesKcal': cal,
                                'proteinG': p,
                                'carbsG': c,
                                'fatG': f,
                                'source': 'custom',
                              }, SetOptions(merge: true));
                            } catch (e) {
                              debugPrint('[BARCODE] custom cache write failed: $e');
                            }
                          }
if (mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.save),
                        label: const Text("حفظ"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // إجراءات سريعة: كاميرا / باركود / نص
  Future<void> _handleAddByCamera(int mealIndex, BuildContext parentContext) async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (pickedFile == null) return;
      if (!mounted) return;

      final result = await Navigator.of(parentContext).push(
        MaterialPageRoute(builder: (_) => FoodAiScreen(imageFile: pickedFile)),
      );
      await _handleFoodAiResult(mealIndex, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(content: Text('تعذّر فتح الكاميرا/التقاط الصورة: $e')),
      );
    }
  }

  Future<void> _handleAddByBarcode(int mealIndex, BuildContext parentContext) async {
    try {
      final dynamic result = await Navigator.of(parentContext).push(
        MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
      );
      if (result == null) return;

      if (result is FoodMacro) {
        await _addItemsToMealAndPersist(mealIndex, [
          {
            'name': result.name,
            'cal': result.caloriesKcal,
            'protein': result.proteinG,
            'carb': result.carbsG,
            'fat': result.fatG,
          }
        ]);
        return;
      }

      if (result is Map && result['nutriments'] != null) {
        final n = result['nutriments'] as Map;
        final name = (result['product_name'] ?? 'منتج من الباركود').toString();
        final cal = ((n['energy-kcal_100g'] ?? 0) as num).toDouble();
        final p   = ((n['proteins_100g'] ?? 0) as num).toDouble();
        final c   = ((n['carbohydrates_100g'] ?? 0) as num).toDouble();
        final f   = ((n['fat_100g'] ?? 0) as num).toDouble();

        await _addItemsToMealAndPersist(mealIndex, [
          {'name': name, 'cal': cal, 'protein': p, 'carb': c, 'fat': f}
        ]);
        return;
      }

      if (result is Map && result['barcode'] != null) {
        showManualEntryForm(mealIndex, barcode: (result['barcode'] ?? '').toString());
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          const SnackBar(content: Text('تعذّر تفسير نتيجة الباركود')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(content: Text('تعذّر مسح الباركود: $e')),
        );
      }
    }
  }

  Future<void> _handleAddByText(int mealIndex, BuildContext parentContext) async {
    try {
      final allowed = await PremiumAccess.ensureSubscribed(
        parentContext,
        feature: PremiumFeature.aiText,
      );
      if (!allowed) return;

      final payload = await AnalyzeMeal.launch(parentContext);
      if (!mounted || payload == null) return;

      num n(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;
      final item = <String, dynamic>{
        'name': (payload['name'] ?? payload['name_ar'] ?? payload['item'] ?? 'وجبة').toString(),
        'cal': n(payload['calories_kcal'] ?? payload['calories'] ?? payload['kcal']).toDouble(),
        'protein': n(payload['protein_g'] ?? payload['protein'] ?? payload['p']).toDouble(),
        'carb': n(payload['carbs_g'] ?? payload['carbs'] ?? payload['c']).toDouble(),
        'fat': n(payload['fat_g'] ?? payload['fat'] ?? payload['f']).toDouble(),
      };

      final kcal = (item['cal'] as double);
      final proteinVal = (item['protein'] as double);
      final carbsVal = (item['carb'] as double);
      final fatVal = (item['fat'] as double);
      if (kcal <= 0 && (proteinVal > 0 || carbsVal > 0 || fatVal > 0)) {
        item['cal'] = (proteinVal * 4 + carbsVal * 4 + fatVal * 9).roundToDouble();
      }

      await _addItemsToMealAndPersist(mealIndex, [item]);

      if (!mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(content: Text('تمت إضافة "${item['name']}" إلى ${meals[mealIndex]['name']}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(content: Text('تعذّر تحليل الوجبة بالنص: ${FriendlyErrors.message(e)}')),
      );
    }
  }


  // ====== هيدر فخم مدمج (Gradient) مع عدّاد متحرّك — يعرض نقاط اليوم ======
  Widget _fancyHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            cs.primary.withOpacity(0.85),
            cs.secondary.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            const Icon(Icons.dashboard_customize, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('لوحة اليوم',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  Row(
                    children: [
                      const Text('سعراتك: ',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      _Countup(
                        value: totalCalories,
                        decimals: 0,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const Text(' / ',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(
                        caloriesNeeded.toStringAsFixed(0),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.stars, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  _Countup(
                    value: todayPoints.toDouble(),
                    decimals: 0,
                    prefix: 'نقاط اليوم: ',
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== قسم الماكروز (Progress متحرّك + أرقام متحركة) ======
  Widget _buildMacrosSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SectionHeader(title: 'الماكروز', icon: Icons.restaurant_menu),
      const SizedBox(height: 8),
      _HomeMacrosCard(
        calories: totalCalories,
        caloriesGoal: caloriesNeeded,
        protein: totalProtein,
        carbs: totalCarbs,
        fat: totalFat,
        proteinGoal: protein,
        carbsGoal: carbs,
        fatGoal: fat,
      ),

    ],
  );
}

  void _persistHomeSnapshotDebounced() {
    _homePersistDebounce?.cancel();
    _homePersistDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      unawaited(_syncTodayEntriesAndTotals());
      unawaited(_snapshotTodayForEOD());
    });
  }

  // ====== مزامنة إدخالات اليوم + المجاميع (محلي فقط وسريع) ======
  Future<void> _syncTodayEntriesAndTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';
    final ymd = DateTime.now().toIso8601String().split('T').first;

    final entriesKey = 'intake_entries_${email}_$ymd';
    final List<Map<String, dynamic>> entries = [];
    double k = 0, p = 0, c = 0, f = 0;

    for (final meal in meals) {
      final rawItems = meal['items'];
      if (rawItems is! List) continue;
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final kk = _toD(item['cal']);
        final pp = _toD(item['protein']);
        final cc = _toD(item['carb']);
        final ff = _toD(item['fat']);
        k += kk;
        p += pp;
        c += cc;
        f += ff;
        entries.add({
          'name': item['name'],
          'k': kk,
          'p': pp,
          'c': cc,
          'f': ff,
        });
      }
    }

    await prefs.setString(entriesKey, jsonEncode(entries));
    await prefs.setString(
      'kcal_daytotals_${email}_$ymd',
      jsonEncode({'k': k, 'p': p, 'c': c, 'f': f}),
    );

    await TrackerStore.setDayTotals(
      ymd: ymd,
      cal: k,
      protein: p,
      carb: c,
      fat: f,
      entries: entries,
    );
  }

  // ====== فهرس أيام "سجل السعرات" (محلي فقط للعرض السريع) ======
  Future<void> _refreshDailyLogIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ??
        FirebaseAuth.instance.currentUser?.email ??
        'unknown_user';

    final rawHistory = prefs.getString('dailyNutritionHistory_$email');
    Map<String, dynamic> history = {};
    if (rawHistory != null) {
      try {
        history = json.decode(rawHistory);
      } catch (_) {
        history = {};
      }
    }

    final dates = history.keys.toList();
    dates.sort((a, b) => b.compareTo(a)); // أحدث أولاً

    for (final d in dates) {
      final totalsKey = 'kcal_daytotals_${email}_$d';
      double totalK = 0.0;

      final rawTotals = prefs.getString(totalsKey);
      if (rawTotals != null) {
        try {
          final m = json.decode(rawTotals);
          if (m is Map && m['k'] is num) {
            totalK = (m['k'] as num).toDouble();
          }
        } catch (_) {}
      }

      if (totalK == 0.0) {
        final entriesKey = 'intake_entries_${email}_$d';
        final raw = prefs.getString(entriesKey);
        if (raw != null) {
          try {
            final list = json.decode(raw) as List;
            for (final e in list) {
              final kk = e is Map ? (e['k'] ?? e['cal']) : 0;
              final kNum = (kk is num)
                  ? kk.toDouble()
                  : _parseLocalizedDouble(kk);
              totalK += kNum;
            }
          } catch (_) {}
        }
      }

      _dailyTotals[d] = totalK;
    }

    if (!mounted) return;
    setState(() {
      _dailyDates = dates; // لا نعرضه في الهوم، فقط لسجل السعرات
    });
  }
  
  void _bumpTodayPoints(int delta) { if (!mounted) return; setState(() { todayPoints = (todayPoints + delta); }); }
// ===== ستريك الدخول اليومي =====
  Future<void> _scheduleNextStreakWarning(int count) async {
    try {
      await AppNotifications.instance.scheduleStreakWarningForTomorrow(
        streakCount: count,
        hour: 21,
        minute: 0,
      );
    } catch (e) {
      debugPrint('[HomeScreen] schedule streak warning failed: $e');
    }
  }

  Future<void> _checkAndUpdateDailyStreak({bool showSnack = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ??
          FirebaseAuth.instance.currentUser?.email ??
          'local';
      final today = DateTime.now();
      final ymd = today.toIso8601String().split('T').first;

      final lastKey = 'streak_lastDate_' + email;
      final countKey = 'streak_count_' + email;

      final last = prefs.getString(lastKey);
      int count = prefs.getInt(countKey) ?? 0;

      if (last == ymd) {
        // نفس اليوم، لا شيء — فقط نضمن أن تذكير بكرة مجدول.
        if (mounted && _streakCount != count) setState(() => _streakCount = count);
        await _scheduleNextStreakWarning(count);
        return;
      }

      if (last == null) {
        // أول تسجيل
        count = 1;
      } else {
        final lastDate = DateTime.tryParse(last);
        if (lastDate == null) {
          count = 1;
        } else {
          final diff = today.difference(DateUtils.dateOnly(lastDate)).inDays;
          if (diff == 1) {
            count = (count + 1);
          } else if (diff >= 2) {
            // فات يوم أو أكثر -> نعيد من جديد
            count = 1;
          }
        }
      }

      await prefs.setString(lastKey, ymd);
      await prefs.setInt(countKey, count);

      // نلغي تذكير أمس ونجدول تذكير بكرة آخر اليوم.
      await _scheduleNextStreakWarning(count);

      if (mounted) {
        setState(() {
          _streakLastDate = ymd;
          _streakCount = count;
        });
      }

      // منح نقاط يومية بسبب الستريك (+2 نقطة) مرة واحدة لليوم
      final meta = {'source': 'daily_streak', 'streak': count};
      await _awardOnce(eventKey: 'daily_streak', points: 2, dedupeKey: ymd, meta: meta, showUI: false);
if (mounted) _bumpTodayPoints(2);
if (mounted && showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: const [
                Icon(Icons.local_fire_department),
                SizedBox(width: 8),
                Expanded(child: Text('كسبت نقاط بسبب الستريك اليومي! 🔥')),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  Widget _buildStreakPill() {
    final theme = Theme.of(context);
    final int c = _streakCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, size: 18),
          const SizedBox(width: 4),
          Text('$c'),
        ],
      ),
    );
  }
// ====== UI ======
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Text('الرئيسية'),
    const SizedBox(width: 8),
    _buildStreakPill(), // ← شارة الستريك 🔥
  ],
),


        actions: [
          // ✅ زر "اسأل وازن" (مدرب وازن الذكي)
          IconButton(
            tooltip: 'اسأل وازن',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AskWazenCoachScreen()),
              );
            },
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              alignment: Alignment.center,
              child: const Text('🧑‍🏫', style: TextStyle(fontSize: 18)),
            ),
          ),

IconButton(
            tooltip: 'تحديث',
            onPressed: () async {
              await _ensurePrefsEmail();
              await _rollToNewDayIfNeeded();
              await refreshTargets();
              await _ensureTodaySnapshot();
              await _loadTodayWater();
              await _syncTodayEntriesAndTotals();
              await _refreshDailyLogIndex();
              await _loadAndShowPoints();
              await _maybeShowClaimSheetForTonight();
              await _maybeShowClaimSheetForYesterday();
              _attachTodayPointsListener(); // تأكيد الاشتراك على وثيقة اليوم
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم التحديث')),
                );
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              final nameController = TextEditingController();
              return AlertDialog(
                title: const Text("إضافة وجبة جديدة"),
                content: TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: "اسم الوجبة"),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("إلغاء"),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        setState(() {
                          meals.add({
                            'name': name,
                            'items': <Map<String, dynamic>>[]
                          });
                          calculateTotals();
                          _animSeed++;
                        });
                        if (mounted) Navigator.pop(context);
                        unawaited(Future.microtask(() async {
                          await saveMeals();
                          await _syncTodayEntriesAndTotals();
                          await _refreshDailyLogIndex();
                        }));
                      }
                    },
                    child: const Text("إضافة"),
                  ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        bottom: true,
        child: RefreshIndicator(
          onRefresh: () async {
            await _ensurePrefsEmail();
            await _rollToNewDayIfNeeded();
            await refreshTargets();
            await _ensureTodaySnapshot();
            await _loadTodayWater();
            await loadMeals();
            _attachTodayPointsListener();
            _runHomeDeferredWork(delay: const Duration(milliseconds: 250));
          },
          child: ListView(
            key: _listKey,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              12, 12, 12,
              _homeBottomPadding(context),
            ),
            children: [
              const GlobalAnnouncementBanner(),
              const SizedBox(height: 8),
              _fancyHeader(context),
              const SizedBox(height: 12),

              // Banner: زر تجميع فوري (Stream + fallback محلي)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty(),
                builder: (context, snap) {
                  int pendingNow = 0;
                  bool claimed = false;
                  if (snap.hasData) {
                    final data = snap.data?.data();
                    final rewards = (data?['rewards'] as Map?)?.cast<String, dynamic>();
                    claimed = rewards?['claimed'] == true;
                    pendingNow = (rewards?['pendingPoints'] is num)
                        ? (rewards?['pendingPoints'] as num).toInt()
                        : ((rewards?['awardedPoints'] is num)
                            ? (rewards?['awardedPoints'] as num).toInt()
                            : 0);
                  }
                  // fallback محلي إذا Firestore ما فيه بيانات أو 0
                  if ((!snap.hasData || pendingNow <= 0) && !_resolvedLocalToday && _pendingLocalToday > 0) {
                    pendingNow = _pendingLocalToday;
                    claimed = false;
                  }
                  if (claimed || pendingNow <= 0) {
                    return const SizedBox.shrink();
                  }
                  final cs = Theme.of(context).colorScheme;
                  return Card(
                    elevation: 1.0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: cs.primary.withOpacity(.12),
                            child: const Icon(Icons.redeem),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('لديك $pendingNow نقطة بانتظار التجميع',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          FilledButton.icon(
                            onPressed: () async {
                              final y = DateTime.now().toIso8601String().split('T').first;
                              await _claimPendingNowFromHome(pendingNow, y);
                              unawaited(_recomputeLocalPendingToday());
                            },
                            icon: const Icon(Icons.check_circle),
                            label: const Text('تجميع الآن'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),


              _buildMacrosSection(),
              const SizedBox(height: 14),

              const _SectionHeader(title: 'السجلات'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CaloriesHistoryScreen()),
                        );
                      },
                      child: const Text('سجل السعرات'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const WaterHistoryPage()),
                        );
                      },
                      child: const Text('سجل الماء'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _MiniStatCard(
                title: 'الخطوات',
                value: '$steps',
                icon: Icons.directions_walk,
                color: Colors.green,
              ),
              const SizedBox(height: 6),
              _MiniStatCard(
                title: 'المحروق',
                value: '$burned',
                icon: Icons.local_fire_department_outlined,
                color: Colors.red,
              ),
              const SizedBox(height: 8),
              _WaterCompact(
                liters: todayWaterLiters,
                onAdd: () async {
                  final __before = todayWaterLiters;
      await showWaterQuickAddSheet(context);
      await _loadTodayWater();
      final __after = todayWaterLiters;
      await _awardWaterPoints(__before, __after);
// سيقوم أيضًا بتحديث لقطة الماء لليوم + فايرستور
                  setState(() => _animSeed++);
                },
              ),

              const SizedBox(height: 18),

              
              const SizedBox(height: 18),

              const _SectionHeader(title: 'وجباتي', icon: Icons.restaurant_menu),
              const SizedBox(height: 8),

              ...meals.asMap().entries.map((e) => _buildMealCard(context, e.key, e.value)),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(dynamic v) => (v is num)
      ? v.toStringAsFixed(0)
      : _tryParseLocalizedDouble(v)?.toStringAsFixed(0) ?? '0';

  /// قراءة وزن المستخدم (كجم) لاستخدامه في تقدير "كم خطوة لحرق الوجبة".
  /// نحاول عدة مفاتيح لأن التطبيق مرّ بعدة نسخ تخزين.
  Future<double> _readUserWeightKgSafe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = await SessionManager.currentStorageKey();
      final emailKey = (prefs.getString(SessionManager.kCurrentEmail) ?? '').trim();

      double? readAsDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        return _tryParseLocalizedDouble(v);
      }

      // أولوية: weight_<uid>
      final v1 = prefs.getDouble('weight_$storageKey') ?? readAsDouble(prefs.get('weight_$storageKey'));
      if (v1 != null && v1 > 20 && v1 < 400) return v1;

      // بديل: weight_<email>
      if (emailKey.isNotEmpty) {
        final v2 = prefs.getDouble('weight_$emailKey') ?? readAsDouble(prefs.get('weight_$emailKey'));
        if (v2 != null && v2 > 20 && v2 < 400) return v2;
      }

      // مفاتيح قديمة جدًا
      final v3 = prefs.getDouble('weight') ?? readAsDouble(prefs.get('weight'));
      if (v3 != null && v3 > 20 && v3 < 400) return v3;
    } catch (_) {}
    return 70.0;
  }

  Future<void> _openMealDetailsSheet({
    required BuildContext context,
    required String mealName,
    required List<Map<String, dynamic>> items,
    required double calories,
    required double protein,
    required double carb,
    required double fat,
  }) async {
    final w = await _readUserWeightKgSafe();
    if (!mounted) return;
    await showMealDetailsSheet(
      context,
      mealName: mealName,
      calories: calories,
      protein: protein,
      carb: carb,
      fat: fat,
      items: items,
      userWeightKg: w,
    );
  }

  // ====== بطاقة وجبة ======
  Widget _buildMealCard(BuildContext context, int index, Map<String, dynamic> meal) {
    final cs = Theme.of(context).colorScheme;
    final items = (meal['items'] as List).cast<Map<String, dynamic>>();
    final isDefault = ['🍳 الفطور', '🍽️ الغداء', '🌙 العشاء'].contains(meal['name'].toString());

    final totals = _sumMeal(items);
    final kcal = totals['k']!;
    final p = totals['p']!;
    final c = totals['c']!;
    final f = totals['f']!;

    final expKey = PageStorageKey<String>('meal_tile_${meal['name']}_$index');

    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: expKey,
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Row(
            children: [
              // اسم الوجبة + ملخص
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            meal['name'].toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _openMealDetailsSheet(
                            context: context,
                            mealName: meal['name'].toString(),
                            items: items,
                            calories: kcal,
                            protein: p,
                            carb: c,
                            fat: f,
                          ),
                          child: const Text('التفاصيل', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Text('س: ', style: TextStyle(fontSize: 11.5)),
                        _Countup(value: kcal, decimals: 0, style: TextStyle(fontSize: 11.5, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(.8))),
                        const SizedBox(width: 6),
                        const Text('• ب: ', style: TextStyle(fontSize: 11.5)),
                        _Countup(value: p, decimals: 0, style: const TextStyle(fontSize: 11.5, color: Colors.green)),
                        const SizedBox(width: 6),
                        const Text('• ك: ', style: TextStyle(fontSize: 11.5)),
                        _Countup(value: c, decimals: 0, style: const TextStyle(fontSize: 11.5, color: Colors.orange)),
                        const SizedBox(width: 6),
                        const Text('• د: ', style: TextStyle(fontSize: 11.5)),
                        _Countup(value: f, decimals: 0, style: const TextStyle(fontSize: 11.5, color: Colors.blue)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // شارة السعرات (بدون "ك.س")
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    _Countup(
                      value: kcal,
                      decimals: 0,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isDefault) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  tooltip: 'حذف الوجبة',
                  onPressed: () async {
                    setState(() {
                      meals.removeAt(index);
                      calculateTotals();
                      _animSeed++;
                    });
                    await saveMeals();
                    await _syncTodayEntriesAndTotals();
                    await _refreshDailyLogIndex();
                  },
                ),
              ],
            ],
          ),
          children: [
            // العناصر
            ...items.map<Widget>((item) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RepaintBoundary(
  key: ValueKey(item['id'] ?? item['name'] ?? ''),
  child: ListTile(
                  dense: true,
                  minLeadingWidth: 0,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    item['name'].toString(),
                    style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    "س: ${_fmt(item['cal'])} | ب: ${_fmt(item['protein'])} | ك: ${_fmt(item['carb'])} | د: ${_fmt(item['fat'])}",
                    style: const TextStyle(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.18)),
                    ),
                    child: InkWell(
                      onTap: () async {
                        setState(() {
                          items.remove(item);
                          calculateTotals();
                          _animSeed++;
                        });
                        await saveMeals();
                        await _syncTodayEntriesAndTotals();
                        await _refreshDailyLogIndex();
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red, size: 16),
                          SizedBox(width: 4),
                          Text('حذف', style: TextStyle(color: Colors.red, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ),
                )),
              );
            }).toList(),

            const SizedBox(height: 6),
            // زر إضافة عنصر (مضغوط)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: () => addMealItem(index),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("إضافة عنصر"),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }  // نهاية _buildMealCard

  // ===== منح نقاط فوري + عرض نافذة تأكيد/قائمة مصغّرة =====
  // ===== منح نقاط فوري + عرض Toast موحد =====
  Future<void> _awardOnce({
    required String eventKey,
    required int points,
    String? dedupeKey,
    Map<String, dynamic>? meta,
    bool showUI = true,
  }) async {
    try {
      final added = await _PointsClient.award(
        eventKey: eventKey,
        points: points,
        dedupeKey: dedupeKey,
        meta: meta,
      );
      if (!mounted) return;
      if (added > 0) {
        // حدّث عدّاد اليوم الظاهر في الهيدر
        // (no local increment) rely on Firestore listener for todayPoints;
        // setState(() => todayPoints = (todayPoints) + added);
        if (showUI) {
          _showPointsToast(added, reason: meta?['message']?.toString());
        }
      }
    } catch (_) {
      // يمكن عرض Snackbar لخطأ الشبكة
    }
  }
  String _prettyEventTitle(String key, int pts) {
    switch (key) {
      case 'meal_slot_breakfast':
        return 'كسبت $pts نقطة: أول وجبة لك اليوم (فطور)';
      case 'meal_slot_lunch':
        return 'كسبت $pts نقطة: أول وجبة لك اليوم (غداء)';
      case 'meal_slot_dinner':
        return 'كسبت $pts نقطة: أول وجبة لك اليوم (عشاء)';
      case 'daily_kcal_bonus':
        return 'كسبت $pts نقطة: أكملت هدف السعرات والماكروز';
      case 'daily_water_bonus':
        return 'كسبت $pts نقطة: أنهيت هدف الماء اليومي';
      case 'water_step':
        return 'كسبت $pts نقطة: شرب ماء (+500 مل)';
      default:
        return 'كسبت $pts نقطة';
    }
  }
  void _showInstantClaimSheet({
    required String title,
    required List<_InstantClaimItem> details,
    VoidCallback? onOpenAchievements,
  }) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                ],
              ),
              const SizedBox(height: 12),
              ...details.map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(e.title),
                    trailing: Text('+${e.points}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('إغلاق'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        if (onOpenAchievements != null) onOpenAchievements();
                      },
                      child: const Text('افتح الإنجازات'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}  
// ====== عناصر UI مصغّرة ======

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  const _SectionHeader({required this.title, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 16, color: cs.primary),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Text(value, style: const TextStyle(fontSize: 13.5)),
        ],
      ),
    );
  }
}

// ====== بطاقة ماء مع شريط تقدّم متحرّك ======
class _WaterCompact extends StatelessWidget {
  final double liters;
  final Future<void> Function() onAdd;
  const _WaterCompact({required this.liters, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    const kGoal = 3.0; // لتر
    final percent = (kGoal > 0) ? (liters / kGoal).clamp(0.0, 1.0) : 0.0;
    final enough = liters >= kGoal;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop, color: Colors.teal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Text('الماء اليوم: ',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    _Countup(
                      value: liters,
                      decimals: 2,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const Text(' لتر', style: TextStyle(fontSize: 13.5)),
                    if (enough) const Text(' • شرب كثير ✅',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('إضافة'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedBar(
            percent: percent,
            height: 10,
            background: Colors.teal.withOpacity(0.15),
            color: Colors.teal,
            curve: Curves.easeOutCubic,
            duration: const Duration(milliseconds: 900),
          ),
        ],
      ),
    );
  }
}

// ====== بطاقة ماكروز مع Progress متحرك ======
class _MacroTile extends StatelessWidget {
  final String title;
  final String unit;
  final IconData icon;
  final double consumed;
  final double total;

  const _MacroTile({
    required this.title,
    required this.unit,
    required this.icon,
    required this.consumed,
    required this.total,
  });

  Color _color(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (title.contains('سعرات')) return cs.primary;
    if (title.contains('بروتين')) return Colors.pink;
    if (title.contains('دهون')) return Colors.blue;
    return Colors.orange; // كارب
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = Theme.of(context).textTheme.bodyMedium?.color ?? cs.onSurface;

    final percent = total > 0 ? (consumed / total).clamp(0.0, 1.0) : 0.0;
    final remaining = (total - consumed).clamp(0.0, double.infinity);
    final color = _color(context);
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';

    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Countup(
                    value: consumed,
                    decimals: 0,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: onSurface.withOpacity(0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(' / ${total.toStringAsFixed(0)}$unitSuffix', style: TextStyle(fontSize: 12.5, color: onSurface.withOpacity(0.7))),
                ],
              ),
              const SizedBox(height: 8),
              _AnimatedBar(
                percent: percent,
                height: 10,
                background: color.withOpacity(0.15),
                color: color,
                curve: Curves.easeOutCubic,
                duration: const Duration(milliseconds: 900),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'المتبقي: ${remaining.toStringAsFixed(0)}$unitSuffix',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====== بطاقة خيار داخل أسفلية "إضافة وجبة" ======
class _AddOptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// إذا enabled=false يصبح الكرت غير قابل للضغط (مقفول).
  final bool enabled;

  /// onTap يمكن أن يكون null (مقفول).
  final VoidCallback? onTap;

  /// عند توفيره يظهر زر علامة استفهام في زاوية الكرت.
  final VoidCallback? onHelpTap;

  const _AddOptionCard({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.onTap,
    this.onHelpTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final base = onSurface.withOpacity(0.06);

    final double dim = enabled ? 1.0 : 0.55;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(enabled ? 0.14 : 0.08),
                cs.surface.withOpacity(enabled ? 0.6 : 0.55),
              ],
            ),
            border: Border.all(color: base),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(enabled ? 0.10 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Opacity(
                opacity: dim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withOpacity(.7),
                          height: 1.25,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        enabled ? Icons.chevron_left : Icons.lock_outline_rounded,
                        size: 18,
                        color: onSurface.withOpacity(.6),
                      ),
                    ),
                  ],
                ),
              ),

              if (onHelpTap != null)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onHelpTap,
                      borderRadius: BorderRadius.circular(999),
                      child: Ink(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.80),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: base),
                        ),
                        child: Icon(
                          Icons.help_outline_rounded,
                          size: 18,
                          color: onSurface.withOpacity(0.75),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


// زر شريحة صغير للإجراءات السريعة
class _QuickAddChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAddChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withOpacity(0.25)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

// ====== ودجت: شريط تقدّم متحرّك بعرض ملس ======
class _AnimatedBar extends StatelessWidget {
  final double percent; // 0..1
  final double height;
  final Color background;
  final Color color;
  final Curve curve;
  final Duration duration;

  const _AnimatedBar({
    required this.percent,
    required this.height,
    required this.background,
    required this.color,
    this.curve = Curves.easeOutCubic,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth;
          return Stack(
            children: [
              Container(
                height: height,
                width: double.infinity,
                color: background,
              ),
              AnimatedContainer(
                duration: duration,
                curve: curve,
                height: height,
                width: maxW * p,
                decoration: BoxDecoration(
                  color: color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ====== ودجت: عدّاد أرقام متحرك ======
class _Countup extends StatefulWidget {
  final double value;
  final int decimals;
  final TextStyle? style;
  final String? prefix;
  final String? suffix;
  final Duration duration;
  final Curve curve;

  const _Countup({
    required this.value,
    this.decimals = 0,
    this.style,
    this.prefix,
    this.suffix,
    this.duration = const Duration(milliseconds: 700),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<_Countup> createState() => _CountupState();
}

class _CountupState extends State<_Countup> {

// removed duplicated helper
void _showPointsToast_DELETED(int points, {String? reason, IconData icon = Icons.star_rounded}) {
  if (!mounted) return;
  try {
    PointsEarnedToast.show(
      context,
      points: points,
      title: 'كسبت نقاط 🎉',
      message: reason != null ? reason : 'أضفنا $points نقطة إلى رصيدك',
      icon: icon,
      withConfetti: true,
    );
  } catch (_) {}
}

  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _to = widget.value;
  }

  @override
  void didUpdateWidget(covariant _Countup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      setState(() {
        _from = oldWidget.value;
        _to = widget.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _from, end: _to),
      duration: widget.duration,
      curve: widget.curve,
      builder: (context, val, _) {
        final s = val.toStringAsFixed(widget.decimals);
        return Text(
          '${widget.prefix ?? ''}$s${widget.suffix ?? ''}',
          style: widget.style,
        );
      },
    );
  }
}

// ====== نهاية الملف ======


// --- Meal Analysis Card (top-level) ---
class _MealAnalysisCard extends StatelessWidget {
  final List<Map<String, dynamic>>? meals;
  final Future<void> Function(int mealIndex, List<Map<String, dynamic>> items)? onAdd;

  /// ✅ بدّلها إلى true لما تجهّز ميزة التحليل النصي بالكامل.
  static const bool _textAnalyzeEnabled = true;

  const _MealAnalysisCard({Key? key, this.meals, this.onAdd}) : super(key: key);

  Future<void> _runTextAnalyze(BuildContext context) async {
    final home = context.findAncestorStateOfType<_HomeScreenState>();
    final mealList = meals ?? home?.meals;
    final addFn = onAdd ?? home?._addItemsToMealAndPersist;

    final allowed = await PremiumAccess.ensureSubscribed(
      context,
      feature: PremiumFeature.aiText,
    );
    if (!allowed) return;

    try {
      final payload = await AnalyzeMeal.launch(context);
      if (!context.mounted || payload == null) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => MealTextUI.sheetFromMap(
          payload,
          meals: mealList,
          onAdd: addFn,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحليل الوجبة بالنص: ${FriendlyErrors.message(e)}')),
      );
    }
  }

  void _showUnderUpdateMessage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ميزة تحت التحديث'),
          content: const Text(
            '''ميزة تحليل الطعام النصي تحت التحديث.

يمكنك أخذ الماكروز من "مدرب وازن الذكي" إلى أن تعمل الميزة بشكل كامل.''',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('تمام'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AskWazenCoachScreen()),
                );
              },
              child: const Text('افتح مدرب وازن'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Opacity(
          opacity: _textAnalyzeEnabled ? 1.0 : 0.65,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _textAnalyzeEnabled ? () => _runTextAnalyze(context) : null,
            child: Card(
              elevation: 1.0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: const [
                    Icon(Icons.restaurant_menu, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'تحليل وجبة',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'اكتب وصف الوجبة واحصل على ماكروز وسعرات تقريبية',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ✅ علامة الاستفهام (تظهر فقط لما تكون الميزة مقفلة)
        if (!_textAnalyzeEnabled)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: cs.primaryContainer,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _showUnderUpdateMessage(context),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.help_outline,
                    size: 18,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}



// ====== Meal Text Analyze UI Helpers (static) ======
class MealTextUI {
  static Future<String?> prompt(BuildContext context) async {
    final c = TextEditingController();

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return Directionality(
          textDirection: TextDirection.ltr,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (sheetCtx, scrollCtrl) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    left: 16,
                    right: 16,
                    top: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'التحليل بالنص',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(ctx).pop(null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'اكتب وصفًا واضحًا لوجبتك (المكونات + الكمية إن أمكن) للحصول على ماكروز وسعرات تقريبية.',
                        style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: c,
                        autofocus: true,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 10,
                        maxLines: 16,
                        decoration: InputDecoration(
                          hintText: 'مثال:\n'
                              '• ساندويتش شاورما دجاج متوسط\n'
                              '• بطاطس صغيرة\n'
                              '• كولا دايت',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          filled: true,
                          fillColor: cs.surface,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(null),
                              child: const Text('إلغاء'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('تحليل الوجبة'),
                              onPressed: () => Navigator.of(ctx).pop(c.text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Widget loadingDialog({String message = 'يتم تحليل وجبتك الآن...'}) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget sheetFromMap(
    Map<String, dynamic> data, {
    int? preferredMealIndex,
    List<Map<String, dynamic>>? meals,
    Future<void> Function(int mealIndex, List<Map<String, dynamic>> items)? onAdd,
  }) {
    num _n(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;

    // قيم التحليل (افتراضية)
    String _pickName() {
      final nAr = (data['name_ar'] ?? data['nameAr'] ?? '').toString().trim();
      if (nAr.isNotEmpty) return nAr;
      final n0 = (data['name'] ?? data['item'] ?? '').toString().trim();
      final input = (data['_input_desc'] ?? data['description'] ?? '').toString().trim();
      final hasArabic = RegExp('[ء-ي]').hasMatch(n0);
      if (n0.isNotEmpty && (hasArabic || input.isEmpty)) return n0;
      if (input.isNotEmpty) {
        // خذ أول 5 كلمات كعنوان
        final parts = input
            .split(RegExp('\\s+'))
            .where((e) => e.trim().isNotEmpty)
            .toList();
        return parts.take(5).join(' ');
      }
      return 'وجبة';
    }

    final initialName = _pickName();
    final initialKcal = _n(data['calories_kcal'] ?? data['calories'] ?? data['kcal']).toDouble();
    final initialProtein = _n(data['protein_g'] ?? data['protein'] ?? data['p']).toDouble();
    final initialCarbs = _n(data['carbs_g'] ?? data['carbs'] ?? data['c']).toDouble();
    final initialFat = _n(data['fat_g'] ?? data['fat'] ?? data['f']).toDouble();

    // قيم إضافية للعرض فقط
    final fiber = _n(data['fiber_g']).toDouble();
    final sugar = _n(data['sugar_g']).toDouble();
    final sodium = _n(data['sodium_mg']).toInt();
    final conf = (_n(data['confidence']) * 100).toDouble();
    final notes = data['notes']?.toString() ?? '';

final breakdownRaw = data['ingredients_breakdown'];
final List<Map<String, dynamic>> breakdownList = (breakdownRaw is List)
    ? breakdownRaw
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
    : <Map<String, dynamic>>[];

final clarRaw = data['clarifications'];
final List<Map<String, dynamic>> clarificationsList = (clarRaw is List)
    ? clarRaw
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
    : <Map<String, dynamic>>[];


    String fmt0(num v) => v.toStringAsFixed(0);

    // متغيّرات قابلة للتعديل داخل الـ BottomSheet
    String editedName = initialName;
    double editedKcal = initialKcal;
    double editedProtein = initialProtein;
    double editedCarbs = initialCarbs;
    double editedFat = initialFat;

    Future<void> _openEditDialog(BuildContext ctx, void Function(void Function()) setModalState) async {
      final nameCtrl = TextEditingController(text: editedName);
      final kcalCtrl = TextEditingController(text: fmt0(editedKcal));
      final pCtrl = TextEditingController(text: fmt0(editedProtein));
      final cCtrl = TextEditingController(text: fmt0(editedCarbs));
      final fCtrl = TextEditingController(text: fmt0(editedFat));

      double? _parseNum(String s) {
        var v = s.trim();
        if (v.isEmpty) return null;

        const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
        const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
        final b = StringBuffer();

        for (var i = 0; i < v.length; i++) {
          final ch = v[i];
          final ai = arabicDigits.indexOf(ch);
          if (ai >= 0) {
            b.write(ai);
            continue;
          }
          final pi = persianDigits.indexOf(ch);
          if (pi >= 0) {
            b.write(pi);
            continue;
          }
          if (ch == '٫' || ch == ',') {
            b.write('.');
            continue;
          }
          if (ch == '٬' || ch == ' ') {
            continue;
          }
          b.write(ch);
        }

        v = b.toString();
        final lastDot = v.lastIndexOf('.');
        if (lastDot >= 0) {
          final out = StringBuffer();
          for (var i = 0; i < v.length; i++) {
            final ch = v[i];
            if (ch == '.' && i != lastDot) continue;
            out.write(ch);
          }
          v = out.toString();
        }

        return double.tryParse(v);
      }

      final saved = await showDialog<bool>(
        context: ctx,
        builder: (dctx) {
          return AlertDialog(
            title: const Text('تعديل القيم'),
            content: Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'اسم الوجبة'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: kcalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'السعرات (kcal)'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'بروتين (غ)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: cCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'كارب (غ)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: fCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'دهون (غ)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dctx).pop(true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      );

      if (saved != true) return;

      final newName = nameCtrl.text.trim();
      final newKcal = _parseNum(kcalCtrl.text);
      final newP = _parseNum(pCtrl.text);
      final newC = _parseNum(cCtrl.text);
      final newF = _parseNum(fCtrl.text);

      setModalState(() {
        if (newName.isNotEmpty) editedName = newName;
        if (newKcal != null && newKcal >= 0) editedKcal = newKcal;
        if (newP != null && newP >= 0) editedProtein = newP;
        if (newC != null && newC >= 0) editedCarbs = newC;
        if (newF != null && newF >= 0) editedFat = newF;
      });
    }

    return Builder(
      builder: (ctx) {
final cs = Theme.of(ctx).colorScheme;
final confClamped = conf.clamp(0, 100).toDouble();

double _calcKcal(double kcal, double p, double c, double f) {
  if (kcal > 0) return kcal;
  final v = p * 4 + c * 4 + f * 9;
  return v > 0 ? v : 0;
}

String _fmtNum(double v, {int decimals = 0}) {
  if (v.isNaN || v.isInfinite) return '0';
  if (decimals <= 0) return v.round().toString();
  final r = double.parse(v.toStringAsFixed(decimals));
  return (r % 1 == 0) ? r.toStringAsFixed(0) : r.toStringAsFixed(decimals);
}

Widget macroLine({
  required String label,
  required String emoji,
  required String value,
  required String unit,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              Text(emoji, style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
        Text(
          '$value $unit',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: cs.primary,
          ),
        ),
      ],
    ),
  );
}

Widget macroTile({

          required String label,
          required String value,
          required IconData icon,
        }) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor)),
                      const SizedBox(height: 4),
                      Text(value,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final extraChips = <Widget>[];
        if (fiber > 0) extraChips.add(Chip(label: Text('ألياف: ${fmt0(fiber)} g')));
        if (sugar > 0) extraChips.add(Chip(label: Text('سكر: ${fmt0(sugar)} g')));
        if (sodium > 0) extraChips.add(Chip(label: Text('صوديوم: $sodium mg')));

        final home = ctx.findAncestorStateOfType<_HomeScreenState>();

        final mealList = meals ?? home?.meals ?? const <Map<String, dynamic>>[];
        final addFn = onAdd ?? home?._addItemsToMealAndPersist;

        final preferredLabel = (preferredMealIndex != null &&
                preferredMealIndex! >= 0 &&
                preferredMealIndex! < mealList.length)
            ? (mealList[preferredMealIndex!]['name']?.toString() ?? '')
            : null;

        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (ctx2, setModalState) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'نتيجة التحليل',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx2).hintColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        editedName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      if (confClamped > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text('الثقة: ${confClamped.toStringAsFixed(0)}%',
                                style: TextStyle(color: Theme.of(ctx2).hintColor)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: (confClamped / 100).clamp(0, 1),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
Column(
  children: [
    macroLine(
      label: 'السعرات',
      emoji: '🔥',
      value: _fmtNum(_calcKcal(editedKcal, editedProtein, editedCarbs, editedFat)),
      unit: 'kcal',
    ),
    Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
    macroLine(
      label: 'البروتين',
      emoji: '🥩',
      value: _fmtNum(editedProtein, decimals: 1),
      unit: 'غ',
    ),
    Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
    macroLine(
      label: 'الكارب',
      emoji: '🍞',
      value: _fmtNum(editedCarbs, decimals: 1),
      unit: 'غ',
    ),
    Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
    macroLine(
      label: 'الدهون',
      emoji: '🥑',
      value: _fmtNum(editedFat, decimals: 1),
      unit: 'غ',
    ),
  ],
),

const SizedBox(height: 14),

                      // ✅ المكونات (إن وجدت)
                      if (breakdownList.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'المكونات',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...breakdownList.map((b) {
                          final nAr = (b['name_ar'] ?? b['nameAr'] ?? b['name'] ?? '').toString().trim();
                          final grams = _n(b['grams']).toDouble();
                          final ml = _n(b['ml']).toDouble();
                          final qtyLabel =
                              (b['quantity_label'] ?? b['portion_desc_ar'] ?? '').toString().trim().isNotEmpty
                                  ? (b['quantity_label'] ?? b['portion_desc_ar']).toString().trim()
                                  : (grams > 0
                                      ? '${grams.toStringAsFixed(0)}غ'
                                      : (ml > 0 ? '${ml.toStringAsFixed(0)}مل' : 'حصة تقديرية'));
                          final kcal = _n(b['calories_kcal']).toDouble();
                          final p = _n(b['protein_g']).toDouble();
                          final c = _n(b['carbs_g']).toDouble();
                          final f = _n(b['fat_g']).toDouble();
                          final ms = _n(b['match_score']).toDouble();
                          final ic = _n(b['ingredient_confidence']).toDouble();
                          final needs = (b['needs_confirmation'] == true) || (ms > 0 && ms < 0.55);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nAr.isEmpty ? 'مكوّن' : nAr,
                                        style: const TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    Text(
                                      qtyLabel,
                                      style: TextStyle(color: Theme.of(ctx2).hintColor, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    Text('🔥 ${kcal.toStringAsFixed(0)} kcal'),
                                    Text('🥩 ${p.toStringAsFixed(1)}غ'),
                                    Text('🍞 ${c.toStringAsFixed(1)}غ'),
                                    Text('🥑 ${f.toStringAsFixed(1)}غ'),
                                  ],
                                ),
                                if (ms > 0 || ic > 0) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'مطابقة USDA: ${(ms * 100).clamp(0, 100).toStringAsFixed(0)}%  •  ثقة التعرف: ${(ic * 100).clamp(0, 100).toStringAsFixed(0)}%'
                                        '${needs ? '  •  يحتاج تأكيد' : ''}',
                                    style: TextStyle(fontSize: 11, color: Theme.of(ctx2).hintColor),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ],

                      // ✅ أسئلة توضيح (إن وجدت)
                      if (clarificationsList.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'أسئلة توضيح',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...clarificationsList.map((q) {
                          final ing = (q['ingredient'] ?? '').toString().trim();
                          final question = (q['question'] ?? '').toString().trim();
                          final sug = _n(q['suggested_grams']).toDouble();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withOpacity(0.20),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant.withOpacity(0.20)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.help_outline, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (ing.isNotEmpty)
                                        Text(ing, style: const TextStyle(fontWeight: FontWeight.w900)),
                                      if (question.isNotEmpty) Text(question),
                                      if (sug > 0)
                                        Text('اقتراح: ${sug.toStringAsFixed(0)}غ', style: TextStyle(fontSize: 11, color: Theme.of(ctx2).hintColor)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],

                      if (preferredLabel != null && preferredLabel.isNotEmpty)
                        Text(
                          'سيتم الإضافة إلى: $preferredLabel',
                          style: TextStyle(fontSize: 12, color: Theme.of(ctx2).hintColor),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.edit),
                              label: const Text('تعديل القيم'),
                              onPressed: () => _openEditDialog(ctx2, setModalState),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: Text(preferredLabel != null && preferredLabel.isNotEmpty
                                  ? 'إضافة'
                                  : 'إضافة للسجل'),
                              onPressed: () async {
                                // نبني عنصر وجبة واحد من نتيجة التحليل (بعد التعديل)
                                final items = <Map<String, dynamic>>[
                                  {
                                    'name': editedName,
                                    'cal': editedKcal,
                                    'protein': editedProtein,
                                    'carb': editedCarbs,
                                    'fat': editedFat,
                                  }
                                ];

                                if (addFn == null) {
                                  ScaffoldMessenger.of(ctx2).showSnackBar(
                                    const SnackBar(content: Text('تعذّر إضافة الوجبة هنا')),
                                  );
                                  return;
                                }

                                if (mealList.isEmpty) {
                                  ScaffoldMessenger.of(ctx2).showSnackBar(
                                    const SnackBar(content: Text('لا توجد وجبات متاحة للإضافة')),
                                  );
                                  return;
                                }

                                int? mealIndex;
                                if (preferredMealIndex != null &&
                                    preferredMealIndex! >= 0 &&
                                    preferredMealIndex! < mealList.length) {
                                  mealIndex = preferredMealIndex;
                                } else {
                                  if (mealList.isEmpty) {
                                    ScaffoldMessenger.of(ctx2).showSnackBar(
                                      const SnackBar(content: Text('لا توجد وجبات متاحة للإضافة')),
                                    );
                                    return;
                                  }
                                  mealIndex = await showModalBottomSheet<int>(
                                    context: ctx2,
                                    builder: (pickCtx) {
                                      return SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(mealList.length, (i) {
                                            final m = mealList[i];
                                            return ListTile(
                                              title: Text("إضافة إلى ${m['name']}"),
                                              onTap: () => Navigator.of(pickCtx).pop(i),
                                            );
                                          }),
                                        ),
                                      );
                                    },
                                  );
                                }

                                if (mealIndex == null) return;

                                try {
                                  await addFn(mealIndex, items);

                                  ScaffoldMessenger.of(ctx2).showSnackBar(
                                    const SnackBar(content: Text('تمت إضافة الوجبة إلى سجلك')),
                                  );
                                  if (Navigator.of(ctx2).canPop()) Navigator.of(ctx2).pop();
                                } catch (e) {
                                  ScaffoldMessenger.of(ctx2).showSnackBar(
                                    SnackBar(content: Text('تعذّرت الإضافة: $e')),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

}


//
// ================= Home Macros Card (mirrors SummaryPage style) ================= (mirrors SummaryPage style) =================


class _HomeMacrosCard extends StatelessWidget {
  final double calories;
  final double caloriesGoal;
  final double protein;
  final double carbs;
  final double fat;
  final double proteinGoal;
  final double carbsGoal;
  final double fatGoal;

  const _HomeMacrosCard({
    Key? key,
    required this.calories,
    required this.caloriesGoal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.proteinGoal,
    required this.carbsGoal,
    required this.fatGoal,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const spacing = 8.0;

    return Column(
      children: [
        // الصف الأول: السعرات + البروتين
        Row(
          children: [
            Expanded(
              child: MacroCard(
                title: 'السعرات',
                emoji: '🔥',
                value: calories,
                goal: caloriesGoal,
                unit: 'kcal',
                color: theme.colorScheme.primary,
                barColor: theme.colorScheme.primary,
                bg: theme.colorScheme.primaryContainer.withOpacity(0.15),
                emphasizeOver: true,
              ),
            ),
            const SizedBox(width: spacing),
            Expanded(
              child: MacroCard(
                title: 'البروتين',
                emoji: '🥩',
                value: protein,
                goal: proteinGoal,
                unit: 'غ',
                // أزرق هادئ للبروتين
                color: const Color(0xFF2563EB),
                barColor: const Color(0xFF2563EB),
                bg: const Color(0xFFE0ECFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: spacing),
        // الصف الثاني: الكارب + الدهون
        Row(
          children: [
            Expanded(
              child: MacroCard(
                title: 'الكربوهيدرات',
                emoji: '🍞',
                value: carbs,
                goal: carbsGoal,
                unit: 'غ',
                // برتقالي لطيف للكارب
                color: const Color(0xFFF97316),
                barColor: const Color(0xFFF97316),
                bg: const Color(0xFFFFF7ED),
              ),
            ),
            const SizedBox(width: spacing),
            Expanded(
              child: MacroCard(
                title: 'الدهون',
                emoji: '🥑',
                value: fat,
                goal: fatGoal,
                unit: 'غ',
                // أخضر ناعم للدهون الصحية
                color: const Color(0xFF22C55E),
                barColor: const Color(0xFF22C55E),
                bg: const Color(0xFFEAFBF1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Reusable stat card with unified layout
class MacroCard extends StatelessWidget {
  final bool emphasizeOver;
  final String title;
  final String emoji;
  final double value;
  final double goal;
  final String unit;
  final Color color;
  final Color barColor;
  final Color bg;

  const MacroCard({
    Key? key,
    required this.title,
    required this.emoji,
    required this.value,
    required this.goal,
    required this.unit,
    required this.color,
    required this.barColor,
    required this.bg,
    this.emphasizeOver = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pct = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
    final remaining = (goal - value).clamp(0, double.infinity);
    final isOver = value > goal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // العنوان + الإيموجي في الأعلى
          Row(
            children: [
              _EmojiPill(emoji: emoji, tint: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // شريط التقدم
          _ProgressBar(value: pct, color: barColor),
          const SizedBox(height: 8),
          // الأرقام (مستهلك / هدف + المتبقي)
          Row(
            children: [
              Expanded(
                child: Text(
                  'المتبقي: ${remaining.toStringAsFixed(0)} $unit',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: (emphasizeOver && isOver)
                        ? Colors.red
                        : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)} $unit',
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmojiPill extends StatelessWidget {
  final String emoji;
  final Color tint;
  const _EmojiPill({required this.emoji, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tint.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final fill = w * value;
        return Container(
          height: 9,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                width: fill,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


enum ChipTone { success, warning, neutral }

class _Chip extends StatelessWidget {
  final ChipTone tone;
  final String label;
  const _Chip({required this.label, this.tone = ChipTone.neutral, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tone) {
      case ChipTone.success:
        bg = const Color(0xFFE9F7EF);
        fg = const Color(0xFF1E7E34);
        break;
      case ChipTone.warning:
        bg = const Color(0xFFFFF4E5);
        fg = const Color(0xFF8A5A12);
        break;
      default:
        bg = const Color(0xFFEFF3F8);
        fg = const Color(0xFF2F3A4A);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
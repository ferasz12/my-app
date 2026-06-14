// lib/screens/ask_wazen_coach_screen.dart
// شاشة "مدرب وازن الذكي" — دردشة + زر إرسال تقرير اليوم (مرة واحدة يوميًا).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';

import '../services/ask_wazen_coach_api.dart';
import '../services/ask_wazen_report.dart';
import '../services/coach_workout_plan_local_store.dart';
import '../shared/wazen_coach_avatar.dart';
import '../shared/macro_targets_controller.dart';
import '../shared/weight_sync_service.dart';
import '../core/data/wazen_identity_store.dart';
import '../shared/user_profile_source.dart' show getCurrentUserView;
import '../utils/calorie_calculator.dart';
import '../utils/macro_plan_engine.dart';

class AskWazenCoachScreen extends StatefulWidget {
  const AskWazenCoachScreen({super.key});

  @override
  State<AskWazenCoachScreen> createState() => _AskWazenCoachScreenState();
}

class _ChatMsg {
  final String role; // 'user' | 'assistant'
  final String text;
  final DateTime at;
  final List<CoachAction> actions;
  final List<CoachRecipeCard> recipes;
  final List<CoachWorkoutPlan> workoutPlans;

  _ChatMsg({
    required this.role,
    required this.text,
    DateTime? at,
    this.actions = const <CoachAction>[],
    this.recipes = const <CoachRecipeCard>[],
    this.workoutPlans = const <CoachWorkoutPlan>[],
  }) : at = at ?? DateTime.now();
}

class _AskWazenCoachScreenState extends State<AskWazenCoachScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMsg> _msgs = [];

  bool _sending = false;
  bool _typingIntro = false;
  bool _dailyLocked = false;
  String _userPhotoPath = '';
  String _todayYmd = DateTime.now().toIso8601String().split('T').first;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _welcomeText =>
      'أهلًا 👋\nأنا مدرب وازن الذكي.\n\n'
      'اسألني مباشرة عن أكلك، وصفاتك، أو جدولك؛ أقرأ تقريرًا خفيفًا مع رسالتك.\n'
      'وأقدر أرشح لك وصفات، أو أنشئ لك جدول تمارين وأحفظه محليًا في صفحة الجداول.';

  Future<String> _currentEmail(SharedPreferences prefs) async {
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            'unknown_user')
        .trim()
        .toLowerCase();
  }

  String _chatKey(String email) => 'ask_wazen_chat_v3_$email';


  Future<void> _loadUserPhotoPath() async {
    String path = '';
    try {
      final view = await getCurrentUserView();
      path = (view.imagePath ?? '').trim();
    } catch (_) {
      path = '';
    }
    path = path.isNotEmpty
        ? path
        : (FirebaseAuth.instance.currentUser?.photoURL ?? '').trim();
    if (!mounted) return;
    setState(() => _userPhotoPath = path);
  }

  Map<String, dynamic> _msgToMap(_ChatMsg m) => <String, dynamic>{
        'role': m.role,
        'text': m.text,
        'at': m.at.toIso8601String(),
        'actions': m.actions.map((e) => e.toMap()).toList(),
        'recipes': m.recipes.map((e) => e.toMap()).toList(),
        'workoutPlans': m.workoutPlans.map((e) => e.toMap()).toList(),
      };

  _ChatMsg? _msgFromMap(Map<String, dynamic> map) {
    final role = (map['role'] ?? '').toString();
    final msgText = (map['text'] ?? '').toString();
    if (role.isEmpty || msgText.isEmpty) return null;
    final rawAt = (map['at'] ?? '').toString();
    return _ChatMsg(
      role: role,
      text: msgText,
      at: DateTime.tryParse(rawAt) ?? DateTime.now(),
      actions: (map['actions'] is List)
          ? (map['actions'] as List)
              .whereType<Map>()
              .map((e) => CoachAction.fromMap(e))
              .toList()
          : const <CoachAction>[],
      recipes: (map['recipes'] is List)
          ? (map['recipes'] as List)
              .whereType<Map>()
              .map((e) => CoachRecipeCard.fromMap(e))
              .toList()
          : const <CoachRecipeCard>[],
      workoutPlans: (map['workoutPlans'] is List)
          ? (map['workoutPlans'] as List)
              .whereType<Map>()
              .map((e) => CoachWorkoutPlan.fromMap(e))
              .toList()
          : const <CoachWorkoutPlan>[],
    );
  }

  Future<void> _saveChatLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail(prefs);
    await prefs.setString(
      _chatKey(email),
      jsonEncode(_msgs.map(_msgToMap).toList()),
    );
  }

  Future<void> _loadChatLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail(prefs);
    final raw = prefs.getString(_chatKey(email));
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = decoded
          .whereType<Map>()
          .map((e) => _msgFromMap(Map<String, dynamic>.from(e)))
          .whereType<_ChatMsg>()
          .toList();
      if (loaded.isEmpty) return;
      _msgs
        ..clear()
        ..addAll(loaded);
    } catch (_) {
      // تجاهل أي محادثة محلية تالفة.
    }
  }

  Future<void> _showIntroIfNeeded() async {
    if (_msgs.isNotEmpty) return;
    if (!mounted) return;

    setState(() => _typingIntro = true);
    await Future<void>.delayed(const Duration(milliseconds: 850));

    if (!mounted) return;
    setState(() {
      _typingIntro = false;
      _msgs.add(_ChatMsg(role: 'assistant', text: _welcomeText));
    });
    await _saveChatLocal();
    _scrollToBottom();
  }

  Future<void> _startFreshConversation() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail(prefs);
    await prefs.remove(_chatKey(email));

    if (!mounted) return;
    setState(() {
      _msgs.clear();
      _typingIntro = false;
    });
    await _showIntroIfNeeded();
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail(prefs);
    final ymd = DateTime.now().toIso8601String().split('T').first;
    final last = prefs.getString('ask_wazen_last_ymd_$email');

    await _loadChatLocal();
    await _loadUserPhotoPath();

    if (!mounted) return;
    setState(() {
      _todayYmd = ymd;
      _dailyLocked = (last == ymd);
    });

    await _showIntroIfNeeded();
    _scrollToBottom();
  }

  void _snack(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  List<Map<String, String>> _historyForServer({int max = 12}) {
    final out = <Map<String, String>>[];
    for (final m in _msgs.reversed) {
      if (out.length >= max) break;
      if (m.role != 'user' && m.role != 'assistant') continue;
      out.insert(0, {'role': m.role, 'text': m.text});
    }
    return out;
  }

  Future<void> _sendDailyReport() async {
    if (_sending) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('سجّل الدخول أولًا لاستخدام مدرب وازن الذكي.');
      return;
    }

    if (_dailyLocked) {
      _snack('تم إرسال تقرير اليوم مسبقًا. تقدر ترسل مرة ثانية بكرة.');
      return;
    }

    _dismissKeyboard();

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: 'user', text: 'أرسل تقريري اليومي الآن.'));
    });
    await _saveChatLocal();
    _scrollToBottom();

    try {
      final report = await AskWazenReportBuilder.build(days: 7);
      final response = await AskWazenCoachApi.sendDailyReport(report: report);

      // قفل محلي (حتى لو فشل الربط مع جهاز ثاني، السيرفر يطبق القفل أيضًا)
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
      await prefs.setString('ask_wazen_last_ymd_$email', _todayYmd);

      if (!mounted) return;
      setState(() {
        _dailyLocked = true;
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: response.reply.isEmpty ? 'تم.' : response.reply,
          actions: response.actions,
          recipes: response.recipes,
          workoutPlans: response.workoutPlans,
        ));
      });
      await _saveChatLocal();
      _scrollToBottom();
    } on CoachApiException catch (e) {
      if (!mounted) return;
      final msg = e.message.trim();
      setState(() {
        if (e.code == 'resource-exhausted') _dailyLocked = true;
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: msg.isNotEmpty ? msg : 'تعذّر إرسال التقرير الآن. حاول لاحقًا.',
        ));
      });
      await _saveChatLocal();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: 'صار خطأ أثناء إرسال التقرير: $e',
        ));
      });
      await _saveChatLocal();
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendChat() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    await _sendChatText(text);
  }



  String _normalizeArabicNumbers(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var out = input;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    return out
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ـ', '')
        .toLowerCase();
  }

  double? _toCoachNum(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  double? _extractNumberAfterKeyword(String text, List<String> keywords) {
    final s = _normalizeArabicNumbers(text);
    for (final keyword in keywords) {
      final k = RegExp.escape(_normalizeArabicNumbers(keyword));
      final after = RegExp('$k[^0-9]{0,24}([0-9]{2,3}(?:[\.,][0-9]{1,2})?)')
          .firstMatch(s);
      if (after != null) return _toCoachNum(after.group(1));

      final before = RegExp('([0-9]{2,3}(?:[\.,][0-9]{1,2})?)[^0-9]{0,24}$k')
          .firstMatch(s);
      if (before != null) return _toCoachNum(before.group(1));
    }
    return null;
  }

  double? _extractHeightCm(String text) {
    final s = _normalizeArabicNumbers(text);
    final byKeyword = _extractNumberAfterKeyword(text, const [
      'طولي',
      'الطول',
      'طول',
      'height',
    ]);
    if (byKeyword != null) return byKeyword;

    final byUnit = RegExp(r'([0-9]{2,3}(?:[\.,][0-9]{1,2})?)\s*(?:سم|سنتي|سنتيمتر|cm)')
        .firstMatch(s);
    return _toCoachNum(byUnit?.group(1));
  }

  double? _extractTargetWeightKg(String text) {
    return _extractNumberAfterKeyword(text, const [
      'وزني المستهدف',
      'الوزن المستهدف',
      'هدف الوزن',
      'target weight',
      'target',
    ]);
  }

  double? _extractCurrentWeightKg(String text) {
    final s = _normalizeArabicNumbers(text);
    if (RegExp(r'(وزني\s+المستهدف|الوزن\s+المستهدف|هدف\s+الوزن|target)')
        .hasMatch(s)) {
      return null;
    }
    final byKeyword = _extractNumberAfterKeyword(text, const [
      'وزني',
      'الوزن',
      'وزن',
      'weight',
    ]);
    if (byKeyword != null) return byKeyword;

    final byUnit = RegExp(r'([0-9]{2,3}(?:[\.,][0-9]{1,2})?)\s*(?:كجم|كيلو|kg)')
        .firstMatch(s);
    return _toCoachNum(byUnit?.group(1));
  }

  bool _hasHeightIntent(String text) {
    final s = _normalizeArabicNumbers(text);
    return RegExp(r'(طولي|الطول|(?:^|\s)طول(?:\s|$)|height|سم|سنتيمتر|cm)').hasMatch(s);
  }

  bool _hasTargetWeightIntent(String text) {
    final s = _normalizeArabicNumbers(text);
    return RegExp(r'(وزني\s+المستهدف|الوزن\s+المستهدف|هدف\s+الوزن|target)').hasMatch(s);
  }

  bool _hasCurrentWeightIntent(String text) {
    final s = _normalizeArabicNumbers(text);
    if (_hasTargetWeightIntent(text)) return false;
    final hasWeightWord = RegExp(r'(وزني|الوزن|current\s*weight|weight|كجم|كيلو|kg)').hasMatch(s);
    if (!hasWeightWord) return false;
    final explicitWeight = RegExp(r'(وزني|الوزن|current\s*weight|weight|كجم|كيلو|kg)').hasMatch(s);
    final heightOnly = _hasHeightIntent(text) &&
        !RegExp(r'(وزني|الوزن|current\s*weight|weight|كجم|كيلو|kg)').hasMatch(s);
    return explicitWeight && !heightOnly;
  }

  bool _looksLikeUpdateCommand(String s) {
    return RegExp(r'(غير|غيّر|عدل|عدّل|حدث|حدّث|خلي|خلّ|خل|حط|سجل|سجّل)', caseSensitive: false)
        .hasMatch(s);
  }

  String _fmtNum(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  double _activityFromScore(int s) {
    if (s <= 8) return 1.2;
    if (s <= 16) return 1.375;
    if (s <= 24) return 1.55;
    if (s <= 30) return 1.725;
    return 1.9;
  }

  Set<String> _coachAliases(SharedPreferences prefs, WazenIdentity identity) {
    return <String>{
      identity.storageKey,
      identity.emailKey,
      identity.email,
      identity.uid,
      FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '',
      FirebaseAuth.instance.currentUser?.uid ?? '',
      prefs.getString(WazenIdentityStore.kCurrentStorageKey) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentEmail) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ?? '',
      prefs.getString(WazenIdentityStore.kCurrentUid) ?? '',
    }..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
  }

  double? _readDoubleFromPrefs(
    SharedPreferences prefs,
    Iterable<String> aliases,
    List<String> names,
  ) {
    for (final alias in aliases) {
      for (final name in names) {
        final direct = prefs.getDouble('${name}_$alias');
        if (direct != null && direct.isFinite && direct > 0) return direct;
        final raw = prefs.getString('${name}_$alias');
        if (raw != null) {
          final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
          if (parsed != null && parsed.isFinite && parsed > 0) return parsed;
        }
      }
    }
    return null;
  }

  int? _readIntFromPrefs(
    SharedPreferences prefs,
    Iterable<String> aliases,
    List<String> names,
  ) {
    for (final alias in aliases) {
      for (final name in names) {
        final direct = prefs.getInt('${name}_$alias');
        if (direct != null && direct > 0) return direct;
        final raw = prefs.getString('${name}_$alias');
        if (raw != null) {
          final parsed = int.tryParse(raw.trim());
          if (parsed != null && parsed > 0) return parsed;
        }
      }
    }
    return null;
  }

  String? _readStringFromPrefs(
    SharedPreferences prefs,
    Iterable<String> aliases,
    List<String> names,
  ) {
    for (final alias in aliases) {
      for (final name in names) {
        final value = prefs.getString('${name}_$alias')?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  int _coachWeightDaysLeft(SharedPreferences prefs, WazenIdentity identity) {
    const sevenMs = 7 * 24 * 60 * 60 * 1000;
    final now = DateTime.now().millisecondsSinceEpoch;
    final aliases = _coachAliases(prefs, identity);
    int? newest;
    for (final alias in aliases) {
      for (final key in <String>[
        'lastWeightChangeAt_$alias',
        'lastWeightChangeAtMs_$alias',
        'weightChangedAt_$alias',
      ]) {
        final stamp = prefs.getInt(key);
        if (stamp != null && stamp > 0 && (newest == null || stamp > newest)) {
          newest = stamp;
        }
      }
    }
    if (newest == null) return 0;
    final elapsed = now - newest;
    if (elapsed >= sevenMs) return 0;
    return ((sevenMs - elapsed) / (24 * 60 * 60 * 1000)).ceil();
  }

  Map<String, dynamic> _buildCoachMacroPlan({
    required SharedPreferences prefs,
    required WazenIdentity identity,
    double? heightCm,
    double? weightKg,
    String? goal,
  }) {
    final aliases = _coachAliases(prefs, identity);
    final nextHeight = heightCm ??
        _readDoubleFromPrefs(prefs, aliases, const ['height', 'heightCm', 'user_height']) ??
        170.0;
    final nextWeight = weightKg ??
        _readDoubleFromPrefs(prefs, aliases, const [
          'weight',
          'current_weight',
          'currentWeight',
          'weightKg',
          'user_weight',
        ]) ??
        70.0;
    final nextGoal = (goal ??
            _readStringFromPrefs(prefs, aliases, const ['goal', 'goalType']) ??
            'نمط حياة صحي')
        .trim();
    final gender = _readStringFromPrefs(prefs, aliases, const ['gender']) ?? 'ذكر';
    final age = _readIntFromPrefs(prefs, aliases, const ['age']) ?? 25;
    final lifestyleScore = _readIntFromPrefs(prefs, aliases, const ['lifestyleScore']) ?? 50;
    final activityFactor = _readDoubleFromPrefs(prefs, aliases, const ['activityFactor']) ??
        _activityFromScore(lifestyleScore);

    final maintenance = calculateCalories(
      age: age,
      gender: gender,
      weight: nextWeight,
      height: nextHeight,
      activityFactor: activityFactor,
      goal: 'نمط حياة صحي',
    );
    final bmr = (gender.trim() == 'ذكر')
        ? (10 * nextWeight + 6.25 * nextHeight - 5 * age + 5)
        : (10 * nextWeight + 6.25 * nextHeight - 5 * age - 161);
    final effectiveGoal = MacroPlanEngine.normalizeGoal(nextGoal);
    final defaultPlan = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
    final storedPlan = _readStringFromPrefs(prefs, aliases, const ['macroPlanId']);
    final planId = (storedPlan == null || storedPlan.trim().isEmpty) ? defaultPlan : storedPlan.trim();
    final options = MacroPlanEngine.buildOptions(
      goal: effectiveGoal,
      maintenanceCalories: maintenance,
      weightKg: nextWeight,
      gender: gender,
      bmr: bmr,
    );
    final selected = options.firstWhere(
      (o) => o.id == planId,
      orElse: () => options.firstWhere((o) => o.id == defaultPlan, orElse: () => options.first),
    );

    return <String, dynamic>{
      'caloriesNeeded': selected.calories,
      'maintenanceCalories': maintenance,
      'protein': selected.proteinG,
      'carbs': selected.carbsG,
      'fat': selected.fatG,
      'activityFactor': activityFactor,
      'macroMode': MacroPlanEngine.modeAuto,
      'macroPlanId': selected.id,
    };
  }

  Future<void> _mirrorCoachMacrosPrefs({
    required SharedPreferences prefs,
    required WazenIdentity identity,
    required Map<String, dynamic> macros,
  }) async {
    final aliases = _coachAliases(prefs, identity);
    for (final alias in aliases) {
      await prefs.setDouble('caloriesNeeded_$alias', (macros['caloriesNeeded'] as num).toDouble());
      await prefs.setDouble('maintenanceCalories_$alias', (macros['maintenanceCalories'] as num).toDouble());
      await prefs.setDouble('protein_$alias', (macros['protein'] as num).toDouble());
      await prefs.setDouble('carbs_$alias', (macros['carbs'] as num).toDouble());
      await prefs.setDouble('fat_$alias', (macros['fat'] as num).toDouble());
      await prefs.setDouble('activityFactor_$alias', (macros['activityFactor'] as num).toDouble());
      await prefs.setString('macroMode_$alias', (macros['macroMode'] ?? MacroPlanEngine.modeAuto).toString());
      await prefs.setString('macroPlanId_$alias', (macros['macroPlanId'] ?? '').toString());
      await prefs.setInt('macrosUpdatedAt_$alias', DateTime.now().millisecondsSinceEpoch);
    }
    MacroTargetsController.bump();
  }

  Future<void> _mirrorCoachProfilePrefs({
    required SharedPreferences prefs,
    required WazenIdentity identity,
    double? heightCm,
    double? weightKg,
    double? targetWeightKg,
    String? goal,
    int? lastWeightChangeAtMs,
    Map<String, dynamic>? macros,
  }) async {
    final keys = <String>{
      identity.storageKey,
      identity.emailKey,
      identity.email,
      identity.uid,
      FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '',
      FirebaseAuth.instance.currentUser?.uid ?? '',
    }..removeWhere((e) => e.trim().isEmpty || e == 'unknown_user');
    final stamp = DateTime.now().millisecondsSinceEpoch;

    for (final key in keys) {
      if (heightCm != null) {
        await prefs.setDouble('height_$key', heightCm);
        await prefs.setDouble('heightCm_$key', heightCm);
        await prefs.setDouble('user_height_$key', heightCm);
      }
      if (weightKg != null) {
        await prefs.setDouble('weight_$key', weightKg);
        await prefs.setDouble('current_weight_$key', weightKg);
        await prefs.setDouble('currentWeight_$key', weightKg);
        await prefs.setDouble('weightKg_$key', weightKg);
        await prefs.setDouble('user_weight_$key', weightKg);
        await prefs.setDouble('goal_current_$key', weightKg);
      }
      if (targetWeightKg != null) {
        await prefs.setDouble('goal_target_$key', targetWeightKg);
        await prefs.setDouble('targetWeight_$key', targetWeightKg);
        await prefs.setDouble('targetWeightKg_$key', targetWeightKg);
        await prefs.setDouble('target_weight_$key', targetWeightKg);
      }
      if (goal != null && goal.trim().isNotEmpty) {
        await prefs.setString('goal_$key', goal.trim());
        await prefs.setString('goalType_$key', goal.trim());
      }
      if (lastWeightChangeAtMs != null) {
        await prefs.setInt('lastWeightChangeAt_$key', lastWeightChangeAtMs);
        await prefs.setInt('lastWeightChangeAtMs_$key', lastWeightChangeAtMs);
      }
      if (macros != null) {
        final kcal = macros['caloriesNeeded'];
        final maintenance = macros['maintenanceCalories'];
        final protein = macros['protein'];
        final carbs = macros['carbs'];
        final fat = macros['fat'];
        if (kcal is num) await prefs.setDouble('caloriesNeeded_$key', kcal.toDouble());
        if (maintenance is num) {
          await prefs.setDouble('maintenanceCalories_$key', maintenance.toDouble());
        }
        if (protein is num) await prefs.setDouble('protein_$key', protein.toDouble());
        if (carbs is num) await prefs.setDouble('carbs_$key', carbs.toDouble());
        if (fat is num) await prefs.setDouble('fat_$key', fat.toDouble());
        await prefs.setString('macroMode_$key', (macros['macroMode'] ?? MacroPlanEngine.modeAuto).toString());
        await prefs.setString('macroPlanId_$key', (macros['macroPlanId'] ?? '').toString());
      }
      await prefs.setInt('profileUpdatedAt_$key', stamp);
      await prefs.setInt('macrosUpdatedAt_$key', stamp);
    }

    await prefs.setString('currentEmail', identity.emailKey);
    await prefs.setString(WazenIdentityStore.kCurrentStorageKey, identity.storageKey);
    if (identity.uid.isNotEmpty) await prefs.setString('currentUid', identity.uid);
    await WazenIdentityStore.mirrorKnownLocalKeys(prefs, identity);

    if (weightKg != null) {
      await WeightSyncService.saveCurrentWeight(kg: weightKg);
    }
    MacroTargetsController.bump();
  }

  Future<String?> _tryHandleLocalAccountCommand(String text) async {
    final s = text.trim();
    if (!_looksLikeUpdateCommand(s)) return null;

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final identity = user != null
        ? await WazenIdentityStore.syncFromFirebaseUser(user, prefs: prefs)
        : await WazenIdentityStore.currentIdentity(migrate: false);
    final changed = <String>[];
    double? heightCm;
    double? weightKg;
    double? targetWeightKg;
    String? newGoal;

    if (_hasHeightIntent(s)) {
      final h = _extractHeightCm(s);
      if (h == null) {
        return 'اكتب الطول برقم واضح، مثل: غير طولي إلى 174.';
      }
      if (h < 80 || h > 230) {
        return 'الطول لازم يكون رقم منطقي بالسنتيمتر، مثل: غير طولي إلى 174.';
      }
      heightCm = h;
      changed.add('الطول إلى ${_fmtNum(h)} سم');
    }

    if (_hasTargetWeightIntent(s)) {
      final tw = _extractTargetWeightKg(s);
      if (tw == null) {
        return 'اكتب الوزن المستهدف برقم واضح، مثل: غير وزني المستهدف إلى 72.';
      }
      if (tw < 30 || tw > 250) {
        return 'الوزن المستهدف لازم يكون رقم منطقي، مثل: غير وزني المستهدف إلى 72.';
      }
      targetWeightKg = tw;
      changed.add('الوزن المستهدف إلى ${_fmtNum(tw)} كجم');
    } else if (_hasCurrentWeightIntent(s)) {
      final w = _extractCurrentWeightKg(s);
      if (w == null) {
        return 'اكتب الوزن برقم واضح، مثل: غير وزني إلى 78.';
      }
      if (w < 30 || w > 250) {
        return 'الوزن لازم يكون رقم منطقي، مثل: غير وزني إلى 78.';
      }
      final daysLeft = _coachWeightDaysLeft(prefs, identity);
      if (daysLeft > 0) {
        return 'ما أقدر أغير الوزن الآن. تقدر تعدله بعد $daysLeft يوم من آخر تعديل.';
      }
      weightKg = w;
      changed.add('الوزن الحالي إلى ${_fmtNum(w)} كجم');
    }

    if (RegExp(r'(هدفي|الهدف|goal)', caseSensitive: false).hasMatch(s)) {
      if (RegExp(r'(انقاص|إنقاص|نزول|تنزيل|تخسيس|loss|cut)', caseSensitive: false).hasMatch(s)) {
        newGoal = 'إنقاص الوزن';
      } else if (RegExp(r'(زيادة|تضخيم|رفع|gain|bulk)', caseSensitive: false).hasMatch(s)) {
        newGoal = 'زيادة الوزن';
      } else if (RegExp(r'(ثبات|محافظة|حفاظ|maintenance)', caseSensitive: false).hasMatch(s)) {
        newGoal = 'المحافظة على الوزن';
      }
      if (newGoal != null) changed.add('الهدف إلى $newGoal');
    }

    if (changed.isEmpty) return null;

    final macros = (heightCm != null || weightKg != null || newGoal != null)
        ? _buildCoachMacroPlan(
            prefs: prefs,
            identity: identity,
            heightCm: heightCm,
            weightKg: weightKg,
            goal: newGoal,
          )
        : null;
    final weightStamp = weightKg != null ? DateTime.now().millisecondsSinceEpoch : null;
    final fields = <String, dynamic>{
      if (heightCm != null) 'heightCm': heightCm,
      if (weightKg != null) 'currentWeightKg': weightKg,
      if (weightStamp != null) 'lastWeightChangeAtMs': weightStamp,
      if (targetWeightKg != null) 'targetWeightKg': targetWeightKg,
      if (newGoal != null) 'goal': newGoal,
      if (macros != null) 'metrics': macros,
    };

    try {
      await AskWazenCoachApi.updateUserProfile(fields: fields);
      await _mirrorCoachProfilePrefs(
        prefs: prefs,
        identity: identity,
        heightCm: heightCm,
        weightKg: weightKg,
        targetWeightKg: targetWeightKg,
        goal: newGoal,
        lastWeightChangeAtMs: weightStamp,
        macros: macros,
      );
      if (macros != null) {
        await _mirrorCoachMacrosPrefs(prefs: prefs, identity: identity, macros: macros);
      }
      return 'تم ✅\nعدّلت ${changed.join(' و ')} في السحابة، وحدثت التطبيق عندك مباشرة.';
    } on CoachApiException catch (e) {
      return e.message.isNotEmpty
          ? e.message
          : 'تعذر تعديل بياناتك في السحابة الآن. حاول مرة ثانية.';
    } catch (_) {
      return 'تعذر تعديل بياناتك في السحابة الآن. حاول مرة ثانية.';
    }
  }

  Future<void> _sendChatText(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _sending) return;

    _dismissKeyboard();

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: 'user', text: clean));
    });
    await _saveChatLocal();
    _scrollToBottom();

    final localReply = await _tryHandleLocalAccountCommand(clean);
    if (localReply != null) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(role: 'assistant', text: localReply));
        _sending = false;
      });
      await _saveChatLocal();
      _scrollToBottom();
      return;
    }

    try {
      final response = await AskWazenCoachApi.chat(
        message: clean,
        history: _historyForServer(max: 12),
      );
      var reply = response.reply.isEmpty ? 'تمام.' : response.reply;
      if (response.workoutPlans.isNotEmpty) {
        final savedNames = await CoachWorkoutPlanLocalStore.saveAndSelectAll(
          response.workoutPlans,
        );
        if (savedNames.isNotEmpty) {
          reply = '$reply\n\n✅ حفظت واعتمدت لك محليًا: ${savedNames.first}';
        }
      }

      if (!mounted) return;
      setState(() => _msgs.add(_ChatMsg(
            role: 'assistant',
            text: reply,
            actions: response.actions,
            recipes: response.recipes,
            workoutPlans: response.workoutPlans,
          )));
      await _saveChatLocal();
      _scrollToBottom();
    } on CoachApiException catch (e) {
      if (!mounted) return;
      final msg = e.message.trim();
      setState(() {
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: msg.isNotEmpty ? msg : 'تعذّر إرسال الرسالة الآن (${e.code}).',
        ));
      });
      await _saveChatLocal();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_ChatMsg(role: 'assistant', text: 'صار خطأ: $e')));
      await _saveChatLocal();
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _profileImageOrIcon(ThemeData theme) {
    final path = _userPhotoPath.trim();
    if (path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return Image.network(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person,
            size: 18,
            color: theme.colorScheme.onPrimary,
          ),
        );
      }
      try {
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person,
            size: 18,
            color: theme.colorScheme.onPrimary,
          ),
        );
      } catch (_) {
        // fallback below
      }
    }
    return Icon(
      Icons.person,
      size: 18,
      color: theme.colorScheme.onPrimary,
    );
  }

  Widget _roleAvatar({required bool isMe}) {
    final theme = Theme.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: isMe
          ? _profileImageOrIcon(theme)
          : const WazenCoachAvatar(size: 38, headOnly: true, withCircle: false),
    );
  }

  void _openCoachRoute(String route) {
    final r = route.trim();
    if (r.isEmpty) return;
    try {
      Navigator.of(context).pushNamed(r);
    } catch (_) {
      _snack('تعذر فتح الصفحة الآن.');
    }
  }

  Future<void> _handleCoachAction(CoachAction action) async {
    final type = action.type.trim().toLowerCase();
    final payloadMessage = (action.payload['message'] ?? action.payload['text'] ?? '')
        .toString()
        .trim();
    if ((type == 'send_message' || type == 'coach_message') && payloadMessage.isNotEmpty) {
      await _sendChatText(payloadMessage);
      return;
    }
    if (payloadMessage.isNotEmpty && action.route.trim().isEmpty) {
      await _sendChatText(payloadMessage);
      return;
    }
    if (action.route.trim().isNotEmpty) {
      _openCoachRoute(action.route);
    }
  }

  IconData _actionIcon(CoachAction action) {
    final type = action.type.trim().toLowerCase();
    if (type == 'send_message' || type == 'coach_message') {
      return Icons.chat_bubble_outline_rounded;
    }
    return Icons.arrow_back_rounded;
  }

  Widget _actionButtons(List<CoachAction> actions) {
    final visible = actions.where((a) => a.label.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: visible.map((a) {
          return FilledButton.tonalIcon(
            onPressed: _sending ? null : () => _handleCoachAction(a),
            icon: Icon(_actionIcon(a), size: 18),
            label: Text(a.label),
          );
        }).toList(),
      ),
    );
  }

  Widget _recipeCards(List<CoachRecipeCard> recipes) {
    if (recipes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: recipes.take(3).map((r) {
          final ingredients = r.ingredients.take(5).join('، ');
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Text(
                        r.title,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: theme.colorScheme.primary.withOpacity(0.10),
                      ),
                      child: Text(
                        r.goal.isEmpty ? 'وصفة' : r.goal,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '🔥 ${r.calories} كالوري  •  🥩 ${r.protein}g  •  🍞 ${r.carbs}g  •  🧈 ${r.fat}g',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                if (ingredients.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    ingredients,
                    textDirection: TextDirection.rtl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openCoachRoute(r.route.isEmpty ? '/recipes' : r.route),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('اذهب للوصفة'),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }


  Widget _workoutPlanCards(List<CoachWorkoutPlan> plans) {
    if (plans.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: plans.take(2).map((p) {
          final exercisesCount = p.days.fold<int>(0, (sum, d) => sum + d.items.length);
          final firstDay = p.days.isNotEmpty ? p.days.first : null;
          final preview = firstDay == null
              ? ''
              : firstDay.items.take(3).map((e) => e.name).join('، ');

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.secondary.withOpacity(0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: theme.colorScheme.secondary.withOpacity(0.10),
                      ),
                      child: Text(
                        '${p.days.length} أيام',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '🏋️ $exercisesCount تمرين  •  ${p.goal.isEmpty ? 'هدفك الحالي' : p.goal}',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'أول يوم: $preview',
                    textDirection: TextDirection.rtl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openCoachRoute('/schedulePicker'),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('اذهب لجدولك'),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    final isMe = m.role == 'user';
    final theme = Theme.of(context);

    final bubbleBg = isMe
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    final bubbleFg = isMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _roleAvatar(isMe: false),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 6),
                  bottomRight: Radius.circular(isMe ? 6 : 18),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    color: Colors.black.withOpacity(0.06),
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SelectableText(
                    m.text,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: bubbleFg, height: 1.4, fontSize: 15),
                  ),
                  if (!isMe) _recipeCards(m.recipes),
                  if (!isMe) _workoutPlanCards(m.workoutPlans),
                  if (!isMe) _actionButtons(m.actions),
                  const SizedBox(height: 6),
                  Text(
                    _fmtTime(m.at),
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: bubbleFg.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            _roleAvatar(isMe: true),
          ],
        ],
      ),
    );
  }

  Widget _dailyButton() {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dailyLocked
                  ? '✅ تم إرسال تقرير اليوم ($_todayYmd)'
                  : 'ارسل تقرير اليوم (مرة واحدة يوميًا) عشان أحلّل بياناتك وأعطيك خطة واضحة.',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: (_dailyLocked || _sending) ? null : _sendDailyReport,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: const Text('إرسال'),
          ),
        ],
      ),
    );
  }



  void _showCoachHelp() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final items = <String>[
          'اسألني: وش آكل اليوم حسب هدفي ووجباتي؟',
          'اطلب: رشّح لي وصفة من وصفات وازن.',
          'اطلب: سو لي وصفة جديدة واحفظها باسمي.',
          'اسألني: كم باقي لي بروتين أو سعرات اليوم؟',
          'قل: سو لي جدول تمارين 4 أيام، وأحفظه لك محليًا في صفحة الجداول.',
          'عدّل بياناتك بوضوح: غير وزني إلى 78، غير طولي إلى 174، غير وزني المستهدف إلى 72.',
          'غيّر هدفك: غير هدفي إلى إنقاص الوزن / زيادة الوزن / المحافظة.',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    const WazenCoachAvatar(size: 48, headOnly: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'وش تقدر تسأل وازن؟',
                        textDirection: TextDirection.rtl,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...items.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composer() {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.92),
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              color: Colors.black.withOpacity(0.06),
              offset: const Offset(0, -8),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textDirection: TextDirection.rtl,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'اسأل مدرب وازن عن أكلك، وصفاتك، أو جدولك…',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.55), width: 1.3),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _sendChat(),
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, v, _) {
                final canSend = v.text.trim().isNotEmpty && !_sending;
                return IconButton.filled(
                  onPressed: canSend ? _sendChat : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  tooltip: 'إرسال',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg1 = theme.colorScheme.primary.withOpacity(0.08);
    final bg2 = theme.colorScheme.secondary.withOpacity(0.06);

    return PremiumGate(
      feature: PremiumFeature.coach,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('مدرب وازن الذكي'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'وش أقدر أسأل؟',
            onPressed: _showCoachHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            tooltip: 'محادثة جديدة',
            onPressed: _sending ? null : _startFreshConversation,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard, // اضغط فوق/على الشات لإخفاء الكيبورد
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bg1, bg2, theme.colorScheme.surface],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (n) {
                    if (n.direction != ScrollDirection.idle) _dismissKeyboard();
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 10),
                    itemCount: _msgs.length + (_sending ? 1 : 0) + (_typingIntro ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_typingIntro && i == _msgs.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                          child: Row(
                            children: [
                              _roleAvatar(isMe: false),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    _TypingDots(),
                                    SizedBox(width: 10),
                                    Text('مدرب وازن يكتب الآن', textDirection: TextDirection.rtl),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (_sending && i == _msgs.length + (_typingIntro ? 1 : 0)) {
                        // مؤشر "يكتب..." بسيط أثناء الإرسال
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                          child: Row(
                            children: [
                              _roleAvatar(isMe: false),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    _TypingDots(),
                                    SizedBox(width: 10),
                                    Text('مدرب وازن يجهز لك الرد', textDirection: TextDirection.rtl),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return _bubble(_msgs[i]);
                    },
                  ),
                ),
              ),
              _composer(),
            ],
          ),
        ),
      ),
    ),
    );
  }
}


class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> {
  int _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted) setState(() => _tick = (_tick + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final dots = '.'.padRight(_tick == 0 ? 1 : _tick, '.');
    return SizedBox(
      width: 28,
      child: Text(
        dots,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 20,
          height: 1,
        ),
      ),
    );
  }
}

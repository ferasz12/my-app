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
      'أقرأ بياناتك الصحية الحالية فقط عشان أعطيك نصائح أدق، لكن ما أعدل وزنك أو طولك أو هدفك من هنا.\n'
      'اسألني عن أكلك، وصفاتك، أو جدولك؛ إذا طلبت وصفة بخيّرك بين وصفات وازن الموجودة أو وصفة جديدة من مدرب وازن مصممة على بياناتك، وأقدر أنشئ لك جدول تمارين وأحفظه محليًا في صفحة الجداول.';

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
      heightCm: nextHeight,
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
      'macroCalculationNote': selected.calculationNote,
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
      await prefs.setString(
        'macroCalculationNote_$alias',
        (macros['macroCalculationNote'] ?? '').toString(),
      );
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
    final s = _normalizeArabicNumbers(text);
    final wantsProfileEdit = _looksLikeUpdateCommand(s) &&
        RegExp(
          r'(وزني|الوزن|طولي|الطول|هدف|هدفي|target|weight|height|goal|كجم|كيلو|سم|cm)',
          caseSensitive: false,
        ).hasMatch(s);

    if (!wantsProfileEdit) return null;

    return 'ما أقدر أعدل وزنك أو طولك أو هدفك من مدرب وازن ✅\n\n'
        'أنا أقرأ بياناتك فقط عشان أبني لك نصيحة أو جدول تمارين أو وصفة مناسبة. '
        'تعديل المعلومات يكون من صفحة "بياناتي" أو صفحة إدخال البيانات فقط، عشان تبقى حساباتك دقيقة وآمنة.';
  }

  bool _looksLikeRecipeRequest(String text) {
    final s = _normalizeArabicNumbers(text);
    return RegExp(
      r'(وصفه|وصفة|وصفات|وجبه|وجبة|اكله|أكله|طبخه|طبخة|سناك|فطور|غداء|عشاء|شاورما|سلطه|سلطة|باول|ساندويتش|ساندوتش|meal|recipe)',
      caseSensitive: false,
    ).hasMatch(s);
  }

  bool _isExplicitCoachRecipeRequest(String text) {
    final s = _normalizeArabicNumbers(text);
    final hasRecipe = _looksLikeRecipeRequest(text);
    final hasCoach = RegExp(
      r'(مدرب وازن|وصفات المدرب|وصفات مدرب|من عندك|انت سو|انت تسوي|اخترت وصفات مدرب|coach recipe|generated recipe)',
      caseSensitive: false,
    ).hasMatch(s);
    final hasWazenOnly = RegExp(
      r'(وصفات وازن|من وصفات وازن|وصفات التطبيق|الموجوده|الموجودة)',
      caseSensitive: false,
    ).hasMatch(s);
    return hasRecipe && hasCoach && !hasWazenOnly;
  }

  bool _isExplicitWazenRecipeRequest(String text) {
    final s = _normalizeArabicNumbers(text);
    return _looksLikeRecipeRequest(text) &&
        RegExp(
          r'(وصفات وازن|من وصفات وازن|وصفات التطبيق|الموجوده|الموجودة)',
          caseSensitive: false,
        ).hasMatch(s);
  }

  List<CoachAction> _recipeSourceActions(String originalPrompt) {
    return <CoachAction>[
      CoachAction(
        type: 'recipe_source_choice',
        label: 'وصفات وازن',
        payload: <String, dynamic>{
          'source': 'wazen',
          'originalPrompt': originalPrompt,
        },
      ),
      CoachAction(
        type: 'recipe_source_choice',
        label: 'وصفات مدرب وازن',
        payload: <String, dynamic>{
          'source': 'coach',
          'originalPrompt': originalPrompt,
        },
      ),
    ];
  }

  Future<bool> _tryOfferRecipeSourceChoice(String clean) async {
    if (!_looksLikeRecipeRequest(clean)) return false;
    if (_isExplicitCoachRecipeRequest(clean) || _isExplicitWazenRecipeRequest(clean)) {
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _msgs.add(_ChatMsg(
        role: 'assistant',
        text: 'تبغاني أجيب لك وصفات من أي مصدر؟\n\n'
            '• وصفات وازن: أرشح لك من الوصفات الموجودة في التطبيق.\n'
            '• وصفات مدرب وازن: أصمم لك وصفة جديدة من عندي حسب وزنك وهدفك وسعراتك وماكروزك.',
        actions: _recipeSourceActions(clean),
      ));
      _sending = false;
    });
    await _saveChatLocal();
    _scrollToBottom();
    return true;
  }

  double _coachReportNum(Map<dynamic, dynamic> map, String key) {
    final v = map[key];
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.replaceAll(',', '.')) ?? 0.0;
  }

  int _roundCoachMacro(double value, {int min = 0, int max = 9999}) {
    if (!value.isFinite) return min;
    final rounded = value.round();
    if (rounded < min) return min;
    if (rounded > max) return max;
    return rounded;
  }

  String _goalFromReport(Map<String, dynamic> report) {
    final goal = report['goal'];
    if (goal is Map) {
      final name = (goal['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return 'هدفك الحالي';
  }

  CoachRecipeCard _buildLocalCoachRecipe({
    required String originalPrompt,
    required Map<String, dynamic> report,
  }) {
    final normalized = _normalizeArabicNumbers(originalPrompt);
    final targets = report['targets'] is Map
        ? Map<String, dynamic>.from(report['targets'] as Map)
        : <String, dynamic>{};
    final profile = report['profile'] is Map
        ? Map<String, dynamic>.from(report['profile'] as Map)
        : <String, dynamic>{};

    final goalName = _goalFromReport(report);
    final goalNorm = _normalizeArabicNumbers(goalName);
    final caloriesTarget = _coachReportNum(targets, 'calories');
    final proteinTarget = _coachReportNum(targets, 'protein');
    final weightKg = _coachReportNum(profile, 'current_weight_kg');

    final isGain = RegExp(r'(زياده|زيادة|تضخيم|عضل|بناء|gain|bulk)').hasMatch(goalNorm);
    final isLoss = RegExp(r'(انقاص|تنزيل|نزول|خساره|خسارة|تنشيف|دهون|loss|cut)').hasMatch(goalNorm);
    final isLowCarb = RegExp(r'(كيتو|لو كارب|منخفض الكارب|low.?carb|keto)').hasMatch(goalNorm);

    final mealCal = caloriesTarget > 0
        ? (isGain ? caloriesTarget * 0.34 : isLoss ? caloriesTarget * 0.26 : caloriesTarget * 0.30)
        : (isGain ? 650.0 : isLoss ? 430.0 : 520.0);
    final kcal = _roundCoachMacro(
      mealCal,
      min: isGain ? 560 : isLoss ? 330 : 420,
      max: isGain ? 850 : isLoss ? 560 : 700,
    );

    final wantedProtein = proteinTarget > 0
        ? proteinTarget * (isGain ? 0.30 : 0.28)
        : (weightKg > 0 ? weightKg * 0.45 : 38.0);
    final protein = _roundCoachMacro(
      wantedProtein,
      min: isGain ? 38 : 30,
      max: isGain ? 65 : 55,
    );
    final fatTarget = isLoss
        ? kcal * 0.22 / 9.0
        : isGain
            ? kcal * 0.28 / 9.0
            : kcal * 0.25 / 9.0;
    final fat = _roundCoachMacro(fatTarget, min: isLoss ? 8 : 12, max: isGain ? 28 : 22);
    final carbsCalories = kcal - (protein * 4) - (fat * 9);
    final carbs = isLowCarb
        ? _roundCoachMacro(carbsCalories / 4, min: 8, max: 28)
        : _roundCoachMacro(
            carbsCalories / 4,
            min: isGain ? 55 : 25,
            max: isGain ? 120 : isLoss ? 65 : 90,
          );

    final isShawarma = RegExp(r'(شاورما|shawarma)').hasMatch(normalized);
    final isBreakfast = RegExp(r'(فطور|صبح|breakfast|افطار)').hasMatch(normalized);
    final isSnack = RegExp(r'(سناك|تحليه|حلى|حلويات|dessert|snack)').hasMatch(normalized);

    String title;
    String caption;
    List<String> ingredients;
    String method;

    if (isShawarma) {
      final chickenG = protein >= 45 ? 170 : 140;
      title = 'شاورما دجاج صحية من مدرب وازن';
      caption = isLoss
          ? 'نسخة عالية البروتين وخفيفة الدهون مناسبة للتنشيف أو نزول الوزن.'
          : isGain
              ? 'نسخة مشبعة بطاقة أعلى وبروتين مناسب لبناء العضلات.'
              : 'وصفة متوازنة تناسب هدفك الحالي بدون صوصات دسمة.';
      ingredients = <String>[
        'صدر دجاج مشوي $chickenG غرام',
        isLowCarb ? 'خس روماني كبير بدل الخبز' : 'خبز صاج أو تورتيلا بر متوسط',
        'زبادي يوناني 60 غرام',
        'ليمون وخل وبهارات شاورما',
        'خس وخيار ومخلل خفيف',
        isGain ? 'بطاطس مشوية 120 غرام أو رز أبيض 100 غرام' : 'رشة ثوم بودرة بدون مايونيز',
      ];
      method = 'تبّل الدجاج بالليمون والبهارات ثم اشوه على حرارة عالية. '
          'اخلط الزبادي مع الثوم والليمون كصوص خفيف. '
          'لف الدجاج مع الخضار في الخبز أو الخس، وقدّمها بدون صوصات عالية الدهون.';
    } else if (isBreakfast) {
      title = 'فطور بروتين متوازن من مدرب وازن';
      caption = 'فطور سريع يحافظ على الشبع ويرفع بروتين يومك.';
      ingredients = <String>[
        'بيضتان كاملتان أو بيضة كاملة مع 3 بياض',
        isLowCarb ? 'أفوكادو 50 غرام' : 'شريحة توست بر أو شوفان 40 غرام',
        'لبنة أو زبادي يوناني 80 غرام',
        'خيار وطماطم وخس',
        'رشة ملح وفلفل وليمون',
      ];
      method = 'اطبخ البيض بدون زيت كثير، ثم قدّمه مع الخضار ومصدر الكارب أو الدهون حسب نظامك. '
          'خلّ الزبادي أو اللبنة بجانب الطبق لرفع البروتين.';
    } else if (isSnack) {
      title = 'سناك زبادي بروتين من مدرب وازن';
      caption = 'سناك خفيف يعطيك حلاوة وبروتين بدون سعرات مبالغ فيها.';
      ingredients = <String>[
        'زبادي يوناني 170 غرام',
        'توت أو فراولة 80 غرام',
        isGain ? 'شوفان 35 غرام' : 'شوفان 15 غرام أو بدون',
        'قرفة أو فانيلا',
        'ملعقة صغيرة عسل اختياري',
      ];
      method = 'اخلط الزبادي مع الفانيلا والقرفة، ثم أضف التوت والشوفان. '
          'لو هدفك نزول الوزن قلّل العسل، ولو هدفك زيادة الوزن ارفع الشوفان قليلًا.';
    } else {
      title = isGain ? 'باول دجاج ورز لبناء العضلات' : 'باول دجاج صحي من مدرب وازن';
      caption = isGain
          ? 'وجبة عالية الطاقة تساعدك ترفع السعرات والبروتين بشكل نظيف.'
          : 'وجبة مشبعة ومتوازنة مناسبة لهدفك الحالي وتخلي البروتين واضح.';
      ingredients = <String>[
        'صدر دجاج مشوي ${protein >= 45 ? 170 : 140} غرام',
        isLowCarb ? 'خضار ورقية وخيار وفلفل رومي' : 'رز أبيض أو بطاطس مشوية ${isGain ? 180 : 120} غرام',
        'زبادي يوناني 50 غرام كصوص',
        'خضار مشكلة',
        'ليمون وبهارات وملح خفيف',
        isGain ? 'ملعقة صغيرة زيت زيتون' : 'رشة سماق أو فلفل أسود',
      ];
      method = 'اشوِ الدجاج بالبهارات، وجهّز الرز أو البطاطس بالكمية المناسبة، ثم رتب الطبق مع الخضار والصوص الخفيف. '
          'لو بقي عندك كارب قليل في يومك استبدل الرز بخضار أكثر.';
    }

    final noteParts = <String>[
      'مصممة حسب $goalName',
      if (caloriesTarget > 0) 'هدفك اليومي ${caloriesTarget.round()} سعرة',
      if (proteinTarget > 0) 'بروتينك اليومي ${proteinTarget.round()}غ',
    ];

    return CoachRecipeCard(
      id: 'coach_recipe_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      calories: kcal,
      protein: protein,
      carbs: carbs,
      fat: fat,
      goal: 'وصفة مدرب وازن',
      ingredients: ingredients,
      method: method,
      caption: '${noteParts.join(' • ')}. $caption',
      route: '/recipes',
    );
  }

  Future<bool> _tryGenerateLocalCoachRecipe(String clean) async {
    if (!_isExplicitCoachRecipeRequest(clean)) return false;

    Map<String, dynamic> report;
    try {
      report = await AskWazenReportBuilder.build(days: 7);
    } catch (_) {
      report = <String, dynamic>{};
    }

    final recipe = _buildLocalCoachRecipe(
      originalPrompt: clean,
      report: report,
    );

    if (!mounted) return true;
    setState(() {
      _msgs.add(_ChatMsg(
        role: 'assistant',
        text: 'جهزت لك وصفة جديدة من مدرب وازن، مب من وصفات التطبيق ✅\n'
            'الوصفة مبنية على بياناتك وهدفك الحالي قدر الإمكان، وتقدر تستخدمها كفكرة وتعدل كمياتها من سجل السعرات إذا احتجت.',
        recipes: <CoachRecipeCard>[recipe],
      ));
      _sending = false;
    });
    await _saveChatLocal();
    _scrollToBottom();
    return true;
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

    if (await _tryOfferRecipeSourceChoice(clean)) return;
    if (await _tryGenerateLocalCoachRecipe(clean)) return;

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

    if (type == 'recipe_source_choice') {
      final source = (action.payload['source'] ?? '').toString().trim().toLowerCase();
      final originalPrompt = (action.payload['originalPrompt'] ?? '').toString().trim();
      if (source == 'coach') {
        await _sendChatText(
          'وصفات مدرب وازن: صمم لي وصفة جديدة من عندك، مناسبة لبياناتي وهدفي، '
          'واعرضها كبطاقة وصفة كاملة. طلبي الأساسي: $originalPrompt',
        );
        return;
      }
      if (source == 'wazen') {
        await _sendChatText(
          'وصفات وازن: رشح لي من وصفات التطبيق الموجودة ما يناسب هدفي. '
          'طلبي الأساسي: $originalPrompt',
        );
        return;
      }
    }

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
    if (type == 'recipe_source_choice') {
      final source = (action.payload['source'] ?? '').toString().trim().toLowerCase();
      return source == 'coach' ? Icons.auto_awesome_rounded : Icons.restaurant_menu_rounded;
    }
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

  Widget _coachMacroTile({
    required String emoji,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
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
          final ingredients = r.ingredients.take(6).join('، ');
          final hasImage = r.imageUrl.trim().isNotEmpty;
          final methodPreview = r.method.trim();
          final caption = r.caption.trim();

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.16)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 16,
                  color: Colors.black.withOpacity(0.06),
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasImage)
                  AspectRatio(
                    aspectRatio: 16 / 7,
                    child: Image.network(
                      r.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        alignment: Alignment.center,
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.60),
                        child: const Text('🍽️', style: TextStyle(fontSize: 30)),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
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
                                fontSize: 15.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: theme.colorScheme.primary.withOpacity(0.10),
                            ),
                            child: Text(
                              r.goal.isEmpty ? 'وصفة وازن' : r.goal,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      if (caption.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          caption,
                          textDirection: TextDirection.rtl,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: theme.colorScheme.onSurface.withOpacity(0.72),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        alignment: WrapAlignment.end,
                        textDirection: TextDirection.rtl,
                        children: [
                          _coachMacroTile(emoji: '🔥', label: 'السعرات', value: '${r.calories} kcal'),
                          _coachMacroTile(emoji: '🥩', label: 'بروتين', value: '${r.protein}g'),
                          _coachMacroTile(emoji: '🍞', label: 'كارب', value: '${r.carbs}g'),
                          _coachMacroTile(emoji: '🥑', label: 'دهون', value: '${r.fat}g'),
                        ],
                      ),
                      if (ingredients.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'المكونات: $ingredients',
                          textDirection: TextDirection.rtl,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: theme.colorScheme.onSurface.withOpacity(0.78),
                          ),
                        ),
                      ],
                      if (methodPreview.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'الطريقة: $methodPreview',
                          textDirection: TextDirection.rtl,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: theme.colorScheme.onSurface.withOpacity(0.78),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _openCoachRoute(r.route.isEmpty ? '/recipes' : r.route),
                            icon: const Icon(Icons.arrow_back_rounded, size: 18),
                            label: const Text('صفحة الوصفات'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _sending
                                ? null
                                : () => _sendChatText('سو لي وصفة مشابهة لـ ${r.title} ومناسبة لهدفي'),
                            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                            label: const Text('وصفة مشابهة'),
                          ),
                        ],
                      ),
                    ],
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
          'اطلب أي وصفة، وبخيّرك بين وصفات وازن أو وصفات مدرب وازن.',
          'اختر وصفات مدرب وازن عشان أصمم لك وصفة جديدة حسب وزنك وهدفك وسعراتك.',
          'اسألني: كم باقي لي بروتين أو سعرات اليوم؟',
          'قل: سو لي جدول تمارين 4 أيام، وأحفظه لك محليًا في صفحة الجداول.',
          'أقرأ وزنك وطولك وهدفك للتخصيص فقط، ولا أعدل بياناتك من داخل المدرب.',
          'لتعديل الوزن أو الطول أو الهدف استخدم صفحة بياناتي أو صفحة إدخال البيانات.',
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

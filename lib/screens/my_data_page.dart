// lib/screens/my_data_page.dart — نسخة محدثة (تصغير بطاقات الماكروز + توحيد ستايل البطاقة الصحية)
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/legacy_user_repository.dart';

import '../utils/calorie_calculator.dart'; // calculateCalories(...)
import '../utils/macro_plan_engine.dart';
import '../shared/macro_targets_controller.dart';

class MyDataPage extends StatefulWidget {
  const MyDataPage({super.key});
  @override
  State<MyDataPage> createState() => _MyDataPageState();
}

class _MyDataPageState extends State<MyDataPage> {
  // بيانات أساسية
  String gender = 'ذكر';
  int age = 25;
  double height = 170;
  double weight = 70;
  String goal = 'نمط حياة صحي';
  bool goalFatShred = false;
  int lifestyleScore = 50;

  // نواتج
  double maintenanceCalories = 0;
  double targetCalories = 0;
  double proteinG = 0;
  double carbsG = 0;
  double fatG = 0;

  // خطة الماكروز
  String macroMode = MacroPlanEngine.modeAuto; // auto | custom
  String macroPlanId = '';

  int _lastMacrosUpdatedAtMs = 0;
  int _lastProfileUpdatedAtMs = 0;

  // أهداف يومية
  int waterMlTarget = 2000;
  int stepsTarget = 8000;
  double sleepHoursTarget = 7.5;

  // حسابات إضافية
  String? email;
  String? displayName;
  String? _livePhotoUrl;

  // منع تغيير الوزن قبل 7 أيام
  int? _lastWeightChangeAtMs;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  VoidCallback? _macroRevListener;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listenUserDoc();
    _bootstrap();

    // ✅ تحديث فوري إذا تغيّرت أهداف الماكروز من صفحة ثانية (مثل الملخص الصحي)
    _macroRevListener = () {
      _refreshMacrosFromPrefs(force: true);
    };
    MacroTargetsController.revision.addListener(_macroRevListener!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // إذا تغيّر اختيار خطة الماكروز من صفحة ثانية (مثل الملخص)، نحدثها هنا.
    _refreshMacrosFromPrefs();
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    if (_macroRevListener != null) {
      MacroTargetsController.revision.removeListener(_macroRevListener!);
    }
    super.dispose();
  }

  void _listenUserDoc() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _userDocSub?.cancel();
    _userDocSub = _db.collection('users').doc(uid).snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) return;

      final dn = (data['displayName'] ?? '').toString().trim();
      final un = (data['username'] ?? '').toString().trim();
      final pu = (data['photoUrl'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        // الأولوية: displayName من Firestore، ثم username، ثم الموجود سابقًا
        if (dn.isNotEmpty) {
          displayName = dn;
        } else if ((displayName ?? '').trim().isEmpty && un.isNotEmpty) {
          displayName = un;
        }

        // لو تم حذف الصورة نرجّعها null عشان يظهر الافتراضي
        _livePhotoUrl = pu.isNotEmpty ? pu : null;
      });
    }, onError: (e) {
      debugPrint('[MyDataPage] user doc stream error: $e');
    });
  }


  // ===== توحيد البيانات بين الأجهزة (السحابة ← الجهاز) =====

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static int _timestampToMs(dynamic v) {
    if (v == null) return 0;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  Future<void> _mirrorCorePrefs(
    SharedPreferences prefs,
    String storageKey, {
    required int stamp,
  }) async {
    if (storageKey.trim().isEmpty || storageKey == 'unknown_user') return;
    await prefs.setString('${_Prefs.gender}_$storageKey', gender);
    await prefs.setInt('${_Prefs.age}_$storageKey', age);
    await prefs.setDouble('${_Prefs.height}_$storageKey', height);
    await prefs.setDouble('${_Prefs.weight}_$storageKey', weight);
    await prefs.setString('${_Prefs.goal}_$storageKey', goal);
    await prefs.setBool('${_Prefs.goalFatShred}_$storageKey', goalFatShred);
    await prefs.setInt('${_Prefs.lifestyleScore}_$storageKey', lifestyleScore);
    await prefs.setDouble('${_Prefs.caloriesNeeded}_$storageKey', targetCalories);
    await prefs.setDouble('${_Prefs.maintenanceCalories}_$storageKey', maintenanceCalories);
    await prefs.setDouble('${_Prefs.protein}_$storageKey', proteinG);
    await prefs.setDouble('${_Prefs.carbs}_$storageKey', carbsG);
    await prefs.setDouble('${_Prefs.fat}_$storageKey', fatG);
    await prefs.setString('macroMode_$storageKey', macroMode);
    await prefs.setString('macroPlanId_$storageKey', macroPlanId);
    await prefs.setInt('${_Prefs.waterMlTarget}_$storageKey', waterMlTarget);
    await prefs.setInt('${_Prefs.stepsTarget}_$storageKey', stepsTarget);
    await prefs.setDouble('${_Prefs.sleepHoursTarget}_$storageKey', sleepHoursTarget);
    if (_lastWeightChangeAtMs != null) {
      await prefs.setInt('${_Prefs.lastWeightChangeAt}_$storageKey', _lastWeightChangeAtMs!);
    }
    await prefs.setInt('profileUpdatedAt_$storageKey', stamp);
    await prefs.setInt('macrosUpdatedAt_$storageKey', stamp);
  }

  /// يسحب أحدث بيانات من users/{uid} ويخزنها في SharedPreferences
  /// عشان تكون الأرقام ثابتة بين الأجهزة (Mac / iPhone / iPad…)
  Future<void> _seedFromCloud(SharedPreferences prefs, String storageKey) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null) return;

      final metrics = (data['metrics'] is Map)
          ? Map<String, dynamic>.from(data['metrics'] as Map)
          : <String, dynamic>{};

      final cloudStamp = math.max(
        _timestampToMs(data['updatedAt']),
        math.max(
          _timestampToMs(metrics['updatedAt']),
          _timestampToMs(metrics['updatedAtMs'] ?? data['profileUpdatedAtMs']),
        ),
      );
      final localStamp = math.max(
        prefs.getInt('profileUpdatedAt_$storageKey') ?? 0,
        prefs.getInt('macrosUpdatedAt_$storageKey') ?? 0,
      );

      // أهم إصلاح: لا تخلي بيانات Firestore القديمة ترجع وتغطي حفظ المستخدم المحلي.
      // إذا حفظ المستخدم بيانات جديدة ثم رجع للتطبيق، القديم ما راح يرجع يطغى عليه.
      if (localStamp > 0 && cloudStamp > 0 && cloudStamp < localStamp) return;
      if (localStamp > 0 && cloudStamp == 0) return;

      final lifestyleMap = (data['lifestyle'] is Map)
          ? Map<String, dynamic>.from(data['lifestyle'] as Map)
          : <String, dynamic>{};

      // --- مدخلات الحساب ---
      final cloudGender = (data['gender'] ?? '').toString().trim();
      final cloudAge = _toInt(data['age']);
      final cloudHeight = _toDouble(data['heightCm'] ?? data['height']);
      final cloudWeight = _toDouble(data['currentWeightKg'] ?? data['weightKg'] ?? data['weight']);
      final cloudGoal = (data['goal'] ?? '').toString().trim();

      final cloudLifestyleScore = _toInt(metrics['lifestyleScore'] ?? lifestyleMap['score']);

      // --- أهداف محفوظة سابقًا (لتثبيت الهوم أيضًا) ---
      final cloudCalories = _toDouble(metrics['caloriesNeeded']);
      final cloudMaint = _toDouble(metrics['maintenanceCalories']);
      final cloudP = _toDouble(metrics['protein']);
      final cloudC = _toDouble(metrics['carbs']);
      final cloudF = _toDouble(metrics['fat']);

      final cloudMacroMode = (metrics['macroMode'] ?? '').toString().trim();
      final cloudMacroPlanId = (metrics['macroPlanId'] ?? '').toString().trim();

      // نطبّق السحابة فقط إذا عندها قيم منطقية
      if (cloudGender.isNotEmpty) {
        gender = cloudGender;
        await prefs.setString('${_Prefs.gender}_$storageKey', cloudGender);
      }
      if (cloudAge != null && cloudAge > 0) {
        age = cloudAge;
        await prefs.setInt('${_Prefs.age}_$storageKey', cloudAge);
      }
      if (cloudHeight != null && cloudHeight > 0) {
        height = cloudHeight;
        await prefs.setDouble('${_Prefs.height}_$storageKey', cloudHeight);
      }
      if (cloudWeight != null && cloudWeight > 0) {
        weight = cloudWeight;
        await prefs.setDouble('${_Prefs.weight}_$storageKey', cloudWeight);
      }
      if (cloudGoal.isNotEmpty) {
        goal = cloudGoal;
        await prefs.setString('${_Prefs.goal}_$storageKey', cloudGoal);
      }

      if (cloudLifestyleScore != null && cloudLifestyleScore >= 0) {
        lifestyleScore = cloudLifestyleScore;
        await prefs.setInt('${_Prefs.lifestyleScore}_$storageKey', cloudLifestyleScore);
        await prefs.setInt('lifestyleScore_$storageKey', cloudLifestyleScore);
      }

      // Seed targets (اختياري لكن مهم للصفحة الرئيسية)
      if (cloudCalories != null && cloudCalories > 0) {
        targetCalories = cloudCalories;
        await prefs.setDouble('${_Prefs.caloriesNeeded}_$storageKey', cloudCalories);
        await prefs.setDouble('caloriesNeeded_$storageKey', cloudCalories);
      }
      if (cloudMaint != null && cloudMaint > 0) {
        maintenanceCalories = cloudMaint;
        await prefs.setDouble('${_Prefs.maintenanceCalories}_$storageKey', cloudMaint);
        await prefs.setDouble('maintenanceCalories_$storageKey', cloudMaint);
      }
      if (cloudP != null && cloudP > 0) {
        proteinG = cloudP;
        await prefs.setDouble('${_Prefs.protein}_$storageKey', cloudP);
        await prefs.setDouble('protein_$storageKey', cloudP);
      }
      if (cloudC != null && cloudC >= 0) {
        carbsG = cloudC;
        await prefs.setDouble('${_Prefs.carbs}_$storageKey', cloudC);
        await prefs.setDouble('carbs_$storageKey', cloudC);
      }
      if (cloudF != null && cloudF >= 0) {
        fatG = cloudF;
        await prefs.setDouble('${_Prefs.fat}_$storageKey', cloudF);
        await prefs.setDouble('fat_$storageKey', cloudF);
      }

      if (cloudMacroMode.isNotEmpty) {
        macroMode = cloudMacroMode;
        await prefs.setString('macroMode_$storageKey', cloudMacroMode);
      }
      if (cloudMacroPlanId.isNotEmpty) {
        macroPlanId = cloudMacroPlanId;
        await prefs.setString('macroPlanId_$storageKey', cloudMacroPlanId);
      }
      if (cloudStamp > 0) {
        _lastProfileUpdatedAtMs = cloudStamp;
        _lastMacrosUpdatedAtMs = math.max(_lastMacrosUpdatedAtMs, cloudStamp);
        await prefs.setInt('profileUpdatedAt_$storageKey', cloudStamp);
        await prefs.setInt('macrosUpdatedAt_$storageKey', cloudStamp);
      }
    } catch (e) {
      debugPrint('[MyDataPage] cloud seed skipped: $e');
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final authEmail = (_auth.currentUser?.email ?? '').trim();
      final uid = (_auth.currentUser?.uid ?? '').trim();
      final legacyKey = (prefs.getString(_Prefs.currentEmail) ?? '').trim();
      final candidates = <String>[authEmail, uid, legacyKey]
        ..removeWhere((k) => k.trim().isEmpty || k == 'unknown_user');

      bool hasSavedData(String k) {
        return prefs.getDouble('${_Prefs.height}_$k') != null ||
            prefs.getDouble('${_Prefs.weight}_$k') != null ||
            prefs.getDouble('${_Prefs.caloriesNeeded}_$k') != null ||
            prefs.getString('macroMode_$k') != null;
      }

      int savedStamp(String k) => math.max(
            prefs.getInt('profileUpdatedAt_$k') ?? 0,
            prefs.getInt('macrosUpdatedAt_$k') ?? 0,
          );

      String storageKey = candidates.isNotEmpty ? candidates.first : 'unknown_user';
      for (final k in candidates) {
        final currentHas = hasSavedData(storageKey);
        final nextStamp = savedStamp(k);
        final currentStamp = savedStamp(storageKey);
        if ((!currentHas && hasSavedData(k)) || nextStamp > currentStamp) {
          storageKey = k;
        }
      }

      // نخلي المفتاح ثابت ونحفظ UID كذلك حتى لا تضيع القيم بين تسجيل الدخول/الخروج.
      if (prefs.getString(_Prefs.currentEmail) != storageKey) {
        await prefs.setString(_Prefs.currentEmail, storageKey);
      }
      if (uid.isNotEmpty) await prefs.setString('currentUid', uid);

      email = authEmail.isNotEmpty ? authEmail : storageKey;
      displayName = _auth.currentUser?.displayName ?? email;
      gender = prefs.getString('${_Prefs.gender}_$storageKey') ?? gender;
      age = prefs.getInt('${_Prefs.age}_$storageKey') ?? age;
      height = prefs.getDouble('${_Prefs.height}_$storageKey') ?? height;
      weight = prefs.getDouble('${_Prefs.weight}_$storageKey') ?? weight;
      goal = prefs.getString('${_Prefs.goal}_$storageKey') ?? goal;
      goalFatShred = prefs.getBool('${_Prefs.goalFatShred}_$storageKey') ?? false;
      lifestyleScore =
          prefs.getInt('${_Prefs.lifestyleScore}_$storageKey') ?? lifestyleScore;

      macroMode = prefs.getString('macroMode_$storageKey') ?? macroMode;
      macroPlanId = prefs.getString('macroPlanId_$storageKey') ?? macroPlanId;
      _lastWeightChangeAtMs =
          prefs.getInt('${_Prefs.lastWeightChangeAt}_$storageKey');

      // سحب بيانات السحابة (إن وجدت) لتوحيد القيم بين الأجهزة
      await _seedFromCloud(prefs, storageKey);

      // لو ما فيه plan id محفوظ، استخدم الافتراضي حسب الهدف.
      final effectiveGoal = (goalFatShred || goal.trim() == 'تنشيف الدهون') ? 'تنشيف الدهون' : goal;
      macroPlanId = (macroPlanId.trim().isEmpty)
          ? MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal)
          : macroPlanId;

      await _recalculate(useStoredIfAvailable: true);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل البيانات: $e';
      });
    }
  }


  Future<void> _refreshMacrosFromPrefs({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ✅ نختار أفضل مفتاح تخزين متاح (Email/UID/legacy) حتى تتزامن القيم فورًا.
      final emailKey = (email ?? '').trim();
      final legacyEmail = (prefs.getString(_Prefs.currentEmail) ?? '').trim();
      final uidKey = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      final legacyUid = (prefs.getString('currentUid') ?? '').trim();
      final candidates = <String>[emailKey, uidKey, legacyEmail, legacyUid]
        ..removeWhere((k) => k.isEmpty || k == 'unknown_user');
      String storageKey = candidates.isNotEmpty ? candidates.first : 'unknown_user';
      int stamp = prefs.getInt('macrosUpdatedAt_$storageKey') ?? 0;
      for (final k in candidates) {
        final s = prefs.getInt('macrosUpdatedAt_$k') ?? 0;
        if (s > stamp) {
          stamp = s;
          storageKey = k;
        }
      }

      if (!force && stamp <= _lastMacrosUpdatedAtMs) return;

      final newTarget = prefs.getDouble('${_Prefs.caloriesNeeded}_$storageKey') ?? targetCalories;
      final newP = prefs.getDouble('${_Prefs.protein}_$storageKey') ?? proteinG;
      final newC = prefs.getDouble('${_Prefs.carbs}_$storageKey') ?? carbsG;
      final newF = prefs.getDouble('${_Prefs.fat}_$storageKey') ?? fatG;

      final newMode = prefs.getString('macroMode_$storageKey') ?? macroMode;
      final newPlanId = prefs.getString('macroPlanId_$storageKey') ?? macroPlanId;

      if (!mounted) return;
      setState(() {
        _lastMacrosUpdatedAtMs = stamp;
        targetCalories = newTarget;
        proteinG = newP;
        carbsG = newC;
        fatG = newF;
        macroMode = newMode;
        macroPlanId = newPlanId;
      });
    } catch (_) {}
  }

  Future<void> _recalculate({bool useStoredIfAvailable = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final activityKey = prefs.getString(_Prefs.currentEmail) ?? email ?? 'unknown_user';
    final activityFactor = prefs.getDouble('activityFactor_$activityKey') ?? _activityFromScore(lifestyleScore);

    maintenanceCalories = calculateCalories(
      age: age,
      gender: gender,
      weight: weight,
      height: height,
      activityFactor: activityFactor,
      goal: 'نمط حياة صحي',
    );

    final effectiveGoal = (goalFatShred || goal.trim() == 'تنشيف الدهون') ? 'تنشيف الدهون' : goal;

    // إذا الوضع "تخصيص"، لا نعيد حساب الماكروز (نستخدم قيم المستخدم).
    if (macroMode == MacroPlanEngine.modeCustom) {
      // fallback لو القيم غير موجودة
      if (targetCalories <= 0 || proteinG <= 0 || fatG < 0 || carbsG < 0) {
        final bmr = (gender.trim() == 'ذكر')
            ? (10 * weight + 6.25 * height - 5 * age + 5)
            : (10 * weight + 6.25 * height - 5 * age - 161);
        final opts = MacroPlanEngine.buildOptions(
          goal: effectiveGoal,
          maintenanceCalories: maintenanceCalories,
          weightKg: weight,
          gender: gender,
          bmr: bmr,
        );
        final fallbackId = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
        final selected = opts.firstWhere((o) => o.id == fallbackId, orElse: () => opts.first);
        targetCalories = selected.calories;
        proteinG = selected.proteinG;
        carbsG = selected.carbsG;
        fatG = selected.fatG;
        macroMode = MacroPlanEngine.modeAuto;
        macroPlanId = selected.id;
      }
    } else {
      // auto: اختيارات 3 خطط لكل هدف
      final bmr = (gender.trim() == 'ذكر')
          ? (10 * weight + 6.25 * height - 5 * age + 5)
          : (10 * weight + 6.25 * height - 5 * age - 161);

      if (macroPlanId.trim().isEmpty) {
        macroPlanId = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
      }

      final opts = MacroPlanEngine.buildOptions(
        goal: effectiveGoal,
        maintenanceCalories: maintenanceCalories,
        weightKg: weight,
        gender: gender,
        bmr: bmr,
      );
      final selected = opts.firstWhere(
        (o) => o.id == macroPlanId,
        orElse: () {
          final def = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
          return opts.firstWhere((o) => o.id == def, orElse: () => opts.first);
        },
      );

      targetCalories = selected.calories;
      proteinG = selected.proteinG;
      carbsG = selected.carbsG;
      fatG = selected.fatG;
    }

    waterMlTarget = math.max((weight * 35).round(), 2000);
    stepsTarget = _stepsFromLifestyle(lifestyleScore);
    sleepHoursTarget = 7.5;

    if (useStoredIfAvailable) {
      final prefs = await SharedPreferences.getInstance();
      final currentEmail = prefs.getString(_Prefs.currentEmail) ?? email ?? 'unknown_user';
      targetCalories =
          prefs.getDouble('${_Prefs.caloriesNeeded}_$currentEmail') ?? targetCalories;
      proteinG = prefs.getDouble('${_Prefs.protein}_$currentEmail') ?? proteinG;
      carbsG = prefs.getDouble('${_Prefs.carbs}_$currentEmail') ?? carbsG;
      fatG = prefs.getDouble('${_Prefs.fat}_$currentEmail') ?? fatG;

      macroMode = prefs.getString('macroMode_$currentEmail') ?? macroMode;
      macroPlanId = prefs.getString('macroPlanId_$currentEmail') ?? macroPlanId;
    }
    if (mounted) setState(() {});
  }

  double _activityFromScore(int s) {
    // يدعم نظامين: القديم (0–100 تقريباً) والجديد (0–34 تقريباً من أسئلة نمط الحياة)
    if (s <= 34) {
      if (s <= 10) return 1.2;
      if (s <= 18) return 1.375;
      if (s <= 26) return 1.55;
      if (s <= 30) return 1.725;
      return 1.9;
    }
    if (s <= 20) return 1.2;
    if (s <= 40) return 1.375;
    if (s <= 60) return 1.55;
    if (s <= 80) return 1.725;
    return 1.9;
  }

  int _stepsFromLifestyle(int s) {
    // نفس منطق النشاط: يدعم نظامين للسكور
    if (s <= 34) {
      if (s <= 10) return 5000;
      if (s <= 18) return 7000;
      if (s <= 26) return 9000;
      if (s <= 30) return 11000;
      return 13000;
    }
    if (s <= 20) return 5000;
    if (s <= 40) return 7000;
    if (s <= 60) return 9000;
    if (s <= 80) return 11000;
    return 13000;
  }

  Future<void> _persistAll() async {
    final prefs = await SharedPreferences.getInstance();
    final currentEmail = prefs.getString(_Prefs.currentEmail) ?? email ?? 'unknown_user';
    final uid = (_auth.currentUser?.uid ?? '').trim();
    final authEmail = (_auth.currentUser?.email ?? '').trim();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    _lastProfileUpdatedAtMs = stamp;
    _lastMacrosUpdatedAtMs = stamp;

    await prefs.setString(_Prefs.currentEmail, currentEmail);
    if (uid.isNotEmpty) await prefs.setString('currentUid', uid);
    await prefs.setString('${_Prefs.gender}_$currentEmail', gender);
    await prefs.setInt('${_Prefs.age}_$currentEmail', age);
    await prefs.setDouble('${_Prefs.height}_$currentEmail', height);
    await prefs.setDouble('${_Prefs.weight}_$currentEmail', weight);
    await prefs.setString('${_Prefs.goal}_$currentEmail', goal);
    await prefs.setBool('${_Prefs.goalFatShred}_$currentEmail', goalFatShred);
    await prefs.setInt('${_Prefs.lifestyleScore}_$currentEmail', lifestyleScore);
    await prefs.setDouble('activityFactor_$currentEmail', prefs.getDouble('activityFactor_$currentEmail') ?? _activityFromScore(lifestyleScore));
    await prefs.setDouble('${_Prefs.caloriesNeeded}_$currentEmail', targetCalories);
    await prefs.setDouble('${_Prefs.protein}_$currentEmail', proteinG);
    await prefs.setDouble('${_Prefs.carbs}_$currentEmail', carbsG);
    await prefs.setDouble('${_Prefs.fat}_$currentEmail', fatG);
    await prefs.setString('macroMode_$currentEmail', macroMode);
    await prefs.setString('macroPlanId_$currentEmail', macroPlanId);
    // "نبضة" محلية لتحديد الأحدث عند المقارنة مع Firestore
    await prefs.setInt('profileUpdatedAt_$currentEmail', stamp);
    await prefs.setInt('macrosUpdatedAt_$currentEmail', stamp);
    await prefs.setInt('${_Prefs.waterMlTarget}_$currentEmail', waterMlTarget);
    await prefs.setInt('${_Prefs.stepsTarget}_$currentEmail', stepsTarget);
    await prefs.setDouble('${_Prefs.sleepHoursTarget}_$currentEmail', sleepHoursTarget);

    // مرايا للمفاتيح المهمة: بعض الصفحات تقرأ بالإيميل وبعضها بالـ UID.
    if (authEmail.isNotEmpty && authEmail != currentEmail) {
      await _mirrorCorePrefs(prefs, authEmail, stamp: stamp);
    }
    if (uid.isNotEmpty && uid != currentEmail) {
      await _mirrorCorePrefs(prefs, uid, stamp: stamp);
    }

    try {
      if (uid.isNotEmpty) {
        // ✅ Legacy root (users/{uid}) هو المصدر الأساسي
        final now = Timestamp.now();
        final activityFactor = prefs.getDouble('activityFactor_$currentEmail') ?? _activityFromScore(lifestyleScore);

        final patch = <String, dynamic>{
          // ✅ حتى لو تغيّر الاسم من أي مكان، نخليه محفوظ في users/{uid}
          if ((displayName ?? '').trim().isNotEmpty)
            'displayName': (displayName ?? '').trim(),
          'gender': gender,
          'age': age,
          'heightCm': height,
          'height': height,
          'currentWeightKg': weight,
          'weightKg': weight,
          'weight': weight,
          'goal': goal,
          'goalType': goal,
          'profileUpdatedAtMs': stamp,
          'updatedAt': now,
          // ✅ نحدّث مفاتيح metrics بدون استبدال كامل الماب
          'metrics.caloriesNeeded': targetCalories,
          'metrics.maintenanceCalories': maintenanceCalories,
          'metrics.protein': proteinG,
          'metrics.carbs': carbsG,
          'metrics.fat': fatG,
          'metrics.lifestyleScore': lifestyleScore,
          'metrics.activityFactor': activityFactor,
          'metrics.macroMode': macroMode,
          'metrics.macroPlanId': macroPlanId,
          'metrics.updatedAtMs': stamp,
          if (_lastWeightChangeAtMs != null)
            'metrics.lastWeightChangeAtMs': _lastWeightChangeAtMs,
          'metrics.updatedAt': now,
          'flags.userDataEntered': true,
          'flags.updatedAt': now,
        };

        await const LegacyUserRepository().updateLegacyUserRoot(
          patch: patch,
          stepAtLeast: 2,
        );

        // ضمان إضافي مباشر: لو الريبو القديم ما كتب لأي سبب، هذا يحفظ القيم في users/{uid}
        // بصيغة Map متداخلة حتى لا تُحفظ مفاتيح metrics كنص فيه نقاط.
        await _db.collection('users').doc(uid).set({
          if ((displayName ?? '').trim().isNotEmpty)
            'displayName': (displayName ?? '').trim(),
          'gender': gender,
          'age': age,
          'heightCm': height,
          'height': height,
          'currentWeightKg': weight,
          'weightKg': weight,
          'weight': weight,
          'goal': goal,
          'goalType': goal,
          'profileUpdatedAtMs': stamp,
          'updatedAt': now,
          'metrics': {
            'caloriesNeeded': targetCalories,
            'maintenanceCalories': maintenanceCalories,
            'protein': proteinG,
            'carbs': carbsG,
            'fat': fatG,
            'lifestyleScore': lifestyleScore,
            'activityFactor': activityFactor,
            'macroMode': macroMode,
            'macroPlanId': macroPlanId,
            'updatedAtMs': stamp,
            if (_lastWeightChangeAtMs != null)
              'lastWeightChangeAtMs': _lastWeightChangeAtMs,
            'updatedAt': now,
          },
          'flags': {
            'userDataEntered': true,
            'updatedAt': now,
          },
        }, SetOptions(merge: true));

        // ✅ ضمان انعكاس الاسم/الصورة فورًا في الصفحات اللي تعتمد على users/{uid}
        final profilePatch = <String, dynamic>{};
        final dn = (displayName ?? '').trim();
        if (dn.isNotEmpty) profilePatch['displayName'] = dn;
        final pu = (_livePhotoUrl ?? _auth.currentUser?.photoURL ?? '').trim();
        if (pu.isNotEmpty) profilePatch['photoUrl'] = pu;
        if (profilePatch.isNotEmpty) {
          profilePatch['updatedAt'] = Timestamp.now();
          profilePatch['profileUpdatedAtMs'] = stamp;
          await _db.collection('users').doc(uid).set(profilePatch, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('[MyDataPage] Firestore persist failed: $e');
    }

    // ✅ إشعار بقية الصفحات (خصوصًا الهوم) بأن الأهداف تغيّرت.
    // هذا مهم لأن التنقل يستخدم IndexedStack.
    MacroTargetsController.bump();
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بياناتي'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _loading
              ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 10),
                  Text('جاري تحميل بياناتك...', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            )
              : _error != null
                  ? _Error(message: _error!, onRetry: _bootstrap)
                  : LayoutBuilder(builder: (ctx, box) {
                      final w = box.maxWidth;
                      final columns = w >= 1100 ? 3 : w >= 700 ? 2 : 1;
                      final gutter = 12.0;
                      final padH = w < 380 ? 10.0 : 16.0;
                      final bmiVal = _bmi(weight, height);
                      final bmiClass = _bmiClass(bmiVal);

                      final mq = MediaQuery.of(ctx);
                      final scale = w < 320 ? 0.85 : w < 360 ? 0.90 : w < 390 ? 0.95 : 1.0;
                      final scaledText = (mq.textScaleFactor * scale).clamp(0.85, 1.15);

                      return MediaQuery(
                        data: mq.copyWith(textScaleFactor: scaledText),
                        child: ListView(
                        padding: EdgeInsets.fromLTRB(padH, 10, padH, 20),
                        children: [
                          _ProfileSummaryCard(
                            name: displayName ?? email ?? 'مستخدم',
                            email: email,
                            photoUrl: _livePhotoUrl ?? _auth.currentUser?.photoURL,
                            goal: goal,
                            gender: gender,
                            age: age,
                            height: height,
                            weight: weight,
                            bmiClass: bmiClass,
                            onEdit: _openEditBottomSheet,
                            onShowHealthCard: _openHealthCard,
                          ),
                          const SizedBox(height: 12),

                          // السعرات والماكروز
                          _Section(
                            title: 'السعرات والماكروز',
                            icon: Icons.local_fire_department_rounded,
                            action: PopupMenuButton<String>(
                              tooltip: 'إدارة الخطة',
                              icon: const Icon(Icons.more_horiz_rounded),
                              onSelected: (v) {
                                if (v == 'custom') _openSmartMacrosBottomSheet();
                                if (v == 'targets') _openTargetsBottomSheet();
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'custom',
                                  child: Text('تخصيص الماكروز'),
                                ),
                                PopupMenuItem(
                                  value: 'targets',
                                  child: Text('خيارات الأهداف اليومية'),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _CaloriesCardSimple(
                                    total: targetCalories, maintenance: maintenanceCalories),
                                const SizedBox(height: 8),
                                // بطاقات ماكروز مضغوطة
                                _AdaptiveGrid(
                                  columns: columns,
                                  gutter: gutter,
                                  children: [
                                    _MacroCardView.compact(
                                      title: 'بروتين',
                                      grams: proteinG,
                                      kcal: proteinG * 4,
                                      emoji: '🥩',
                                    ),
                                    _MacroCardView.compact(
                                      title: 'كارب',
                                      grams: carbsG,
                                      kcal: carbsG * 4,
                                      emoji: '🍞',
                                    ),
                                    _MacroCardView.compact(
                                      title: 'دهون',
                                      grams: fatG,
                                      kcal: fatG * 9,
                                      emoji: '🥑',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _PlanActionsBar(
                                  isCustom: macroMode == MacroPlanEngine.modeCustom,
                                  onCustom: _openSmartMacrosBottomSheet,
                                  onTargets: _openTargetsBottomSheet,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // أهداف يومية
                          _Section(
                            title: 'أهداف يومية',
                            icon: Icons.flag_rounded,
                            action: TextButton(
                              onPressed: _openTargetsBottomSheet,
                              child: const Text('تعديل'),
                            ),
                            child: _AdaptiveGrid(
                              columns: columns,
                              gutter: gutter,
                              children: [
                                _GoalPill(
                                    onTap: _openTargetsBottomSheet,
                                    icon: Icons.water_drop_rounded,
                                    title: 'الماء',
                                    value:
                                        '${(waterMlTarget ~/ 250)} × 250مل (${waterMlTarget}مل)'),
                                _GoalPill(
                                    onTap: _openTargetsBottomSheet,
                                    icon: Icons.directions_walk_rounded,
                                    title: 'الخطوات',
                                    value: '$stepsTarget خطوة'),
                                _GoalPill(
                                    onTap: _openTargetsBottomSheet,
                                    icon: Icons.nightlight_round,
                                    title: 'النوم',
                                    value:
                                        '${sleepHoursTarget.toStringAsFixed(1)} ساعة'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // BMI + دهون تقديري
                          _Section(
                            title: 'ملخص بيولوجي',
                            icon: Icons.insights_rounded,
                            child: _AdaptiveGrid(
                              columns: columns,
                              gutter: gutter,
                              children: [
                                BMICard(value: bmiVal, label: bmiClass),
                                BodyFatCard(
                                    gender: gender, bmi: bmiVal, age: age),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
        ),
      ),
    );
  }

  // إجراءات
  Future<void> _openEditBottomSheet() async {
    // منع تعديل الوزن قبل مرور 7 أيام (يوضح للمستخدم داخل صفحة التعديل)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const sevenMs = 7 * 24 * 60 * 60 * 1000;
    final weightLockedGate =
        _lastWeightChangeAtMs != null && (nowMs - _lastWeightChangeAtMs!) < sevenMs;
    final weightDaysLeft = weightLockedGate
        ? ((sevenMs - (nowMs - _lastWeightChangeAtMs!)) / (24 * 60 * 60 * 1000)).ceil()
        : 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EditBasicsSheet(
        weightLocked: weightLockedGate,
        weightDaysLeft: weightDaysLeft,
        initial: BasicsData(
            name: displayName,
            gender: gender,
            goal: goal,
            age: age,
            height: height,
            weight: weight,
            lifestyleScore: lifestyleScore),
        onSubmit: (upd) async {
          // يسمح فقط بتعديل: العمر/الطول/الوزن (الاسم/الجنس/نمط الحياة لا تُعدل من هنا)
          age = upd.age;
          height = upd.height;

          if (upd.goal.trim().isNotEmpty && upd.goal != goal) {
            goal = upd.goal;
            goalFatShred = upd.goal == 'تنشيف الدهون';
            macroMode = MacroPlanEngine.modeAuto;
            final effectiveGoal =
                (goalFatShred || goal.trim() == 'تنشيف الدهون') ? 'تنشيف الدهون' : goal;
            macroPlanId = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
          }

          // قفل تغيير الوزن 7 أيام (نفس منطقك السابق)
          final now = DateTime.now().millisecondsSinceEpoch;
          const seven = 7 * 24 * 60 * 60 * 1000;
          if ((upd.weight - weight).abs() > 0.01) {
            if (_lastWeightChangeAtMs != null && now - _lastWeightChangeAtMs! < seven) {
              if (mounted) {
                final days =
                    ((seven - (now - (_lastWeightChangeAtMs ?? now))) / (24 * 60 * 60 * 1000))
                        .ceil();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('يمكن تعديل الوزن بعد $days يوم')));
              }
            } else {
              weight = upd.weight;
              _lastWeightChangeAtMs = now;
              final prefs = await SharedPreferences.getInstance();
              final currentEmail =
                  prefs.getString(_Prefs.currentEmail) ?? email ?? 'unknown_user';
              await prefs.setInt(
                  '${_Prefs.lastWeightChangeAt}_$currentEmail', _lastWeightChangeAtMs!);
            }
          }

          await _recalculate();
          await _persistAll();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _openSmartMacrosBottomSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = prefs.getString(_Prefs.currentEmail) ?? email ?? 'unknown_user';

    final kcalCtrl = TextEditingController(
      text: (targetCalories > 0 ? targetCalories : 0).toStringAsFixed(0),
    );
    final proCtrl = TextEditingController(
      text: (proteinG > 0 ? proteinG : 0).toStringAsFixed(0),
    );
    final fatCtrl = TextEditingController(
      text: (fatG >= 0 ? fatG : 0).toStringAsFixed(0),
    );
    final carbCtrl = TextEditingController(
      text: (carbsG >= 0 ? carbsG : 0).toStringAsFixed(0),
    );

    bool autoCarbs = true;
    bool internal = false;
    bool saving = false;

    double readNum(String s) => double.tryParse(s.trim()) ?? 0;

    void balanceCarbs(StateSetter setModalState) {
      final kcal = readNum(kcalCtrl.text);
      final p = readNum(proCtrl.text);
      final f = readNum(fatCtrl.text);
      final c = ((kcal - (p * 4) - (f * 9)) / 4);
      internal = true;
      carbCtrl.text = math.max(0, c.isFinite ? c : 0).round().toString();
      internal = false;
      setModalState(() {});
    }

    void syncUI(StateSetter setModalState) {
      if (!autoCarbs || internal) {
        setModalState(() {});
        return;
      }
      balanceCarbs(setModalState);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        Widget macroField({
          required TextEditingController controller,
          required String label,
          required String unit,
          required IconData icon,
          required ValueChanged<String> onChanged,
          bool enabled = true,
        }) {
          return TextField(
            enabled: enabled,
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            textAlign: TextAlign.right,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: label,
              suffixText: unit,
              prefixIcon: Icon(icon, size: 20),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cs.primary, width: 1.4),
              ),
            ),
          );
        }

        return StatefulBuilder(builder: (ctx, setModalState) {
          final kcal = readNum(kcalCtrl.text);
          final p = readNum(proCtrl.text);
          final c = readNum(carbCtrl.text);
          final f = readNum(fatCtrl.text);
          final macroKcal = (p * 4) + (c * 4) + (f * 9);
          final diff = kcal - macroKcal;
          final balanced = diff.abs() < 20;

          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 34,
                  offset: const Offset(0, -12),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.tune_rounded, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تخصيص الماكروز',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'رتّب سعراتك وبروتينك ودهونك، ووازن يحسب الكارب لك.',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          cs.primaryContainer.withOpacity(0.70),
                          cs.surfaceContainerHighest,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('معاينة الخطة', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text('${kcal.toStringAsFixed(0)} سعرة', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(
                                'P ${p.toStringAsFixed(0)}g • C ${c.toStringAsFixed(0)}g • F ${f.toStringAsFixed(0)}g',
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: balanced ? cs.primary.withOpacity(0.14) : cs.errorContainer.withOpacity(0.60),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            balanced ? 'متوازن' : 'فرق ${diff.toStringAsFixed(0)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: balanced ? cs.primary : cs.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.70),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: autoCarbs,
                      onChanged: (v) {
                        setModalState(() => autoCarbs = v);
                        syncUI(setModalState);
                      },
                      title: const Text('حساب الكارب تلقائيًا'),
                      subtitle: const Text('الأفضل عند تحديد السعرات والبروتين والدهون.'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  macroField(
                    controller: kcalCtrl,
                    label: 'السعرات اليومية',
                    unit: 'kcal',
                    icon: Icons.local_fire_department_rounded,
                    onChanged: (_) => syncUI(setModalState),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: macroField(
                          controller: proCtrl,
                          label: 'البروتين',
                          unit: 'جم',
                          icon: Icons.fitness_center_rounded,
                          onChanged: (_) => syncUI(setModalState),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: macroField(
                          controller: fatCtrl,
                          label: 'الدهون',
                          unit: 'جم',
                          icon: Icons.spa_rounded,
                          onChanged: (_) => syncUI(setModalState),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  macroField(
                    controller: carbCtrl,
                    label: 'الكارب',
                    unit: 'جم',
                    icon: Icons.bakery_dining_rounded,
                    enabled: !autoCarbs,
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => balanceCarbs(setModalState),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: const Text('وازن الكارب'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          kcalCtrl.text = macroKcal.isFinite ? macroKcal.round().toString() : '0';
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.calculate_rounded, size: 18),
                        label: const Text('اجعل السعرات = الماكروز'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final kcal = readNum(kcalCtrl.text);
                              final p = readNum(proCtrl.text);
                              final c = readNum(carbCtrl.text);
                              final f = readNum(fatCtrl.text);

                              if (kcal <= 0 || p <= 0 || c < 0 || f < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تأكد من إدخال قيم صحيحة.')),
                                );
                                return;
                              }

                              setModalState(() => saving = true);
                              setState(() {
                                macroMode = MacroPlanEngine.modeCustom;
                                macroPlanId = 'custom_smart';
                                targetCalories = kcal;
                                proteinG = p;
                                carbsG = c;
                                fatG = f;
                              });

                              final stamp = DateTime.now().millisecondsSinceEpoch;
                              await prefs.setDouble('${_Prefs.caloriesNeeded}_$storageKey', kcal);
                              await prefs.setDouble('${_Prefs.protein}_$storageKey', p);
                              await prefs.setDouble('${_Prefs.carbs}_$storageKey', c);
                              await prefs.setDouble('${_Prefs.fat}_$storageKey', f);
                              await prefs.setString('macroMode_$storageKey', macroMode);
                              await prefs.setString('macroPlanId_$storageKey', macroPlanId);
                              await prefs.setInt('profileUpdatedAt_$storageKey', stamp);
                              await prefs.setInt('macrosUpdatedAt_$storageKey', stamp);

                              await _persistAll();
                              if (mounted) await _refreshMacrosFromPrefs(force: true);
                              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                            },
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('اعتماد التخصيص'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    kcalCtrl.dispose();
    proCtrl.dispose();
    fatCtrl.dispose();
    carbCtrl.dispose();
  }


  Future<void> _openTargetsBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final effectiveGoal = (goalFatShred || goal.trim() == 'تنشيف الدهون') ? 'تنشيف الدهون' : goal;
        final bmr = (gender.trim() == 'ذكر')
            ? (10 * weight + 6.25 * height - 5 * age + 5)
            : (10 * weight + 6.25 * height - 5 * age - 161);

        return _TargetsSheet(
          goal: effectiveGoal,
          gender: gender,
          weightKg: weight,
          maintenanceCalories: maintenanceCalories,
          bmr: bmr,
          macroMode: macroMode,
          macroPlanId: macroPlanId,
          calories: targetCalories,
          protein: proteinG,
          carbs: carbsG,
          fat: fatG,
          waterMl: waterMlTarget,
          steps: stepsTarget,
          sleepHours: sleepHoursTarget,
          onSubmit: (mode, planId, kcal, p, c, f, w, s, h) async {
            macroMode = mode;
            macroPlanId = planId;
            targetCalories = kcal;
            proteinG = p;
            carbsG = c;
            fatG = f;
            waterMlTarget = w;
            stepsTarget = s;
            sleepHoursTarget = h;
            await _persistAll();
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  Future<void> _openHealthCard() async {
    final bmiVal = _bmi(weight, height);
    final bmiClass = _bmiClass(bmiVal);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _HealthCardSheet(
        photoUrl: _livePhotoUrl ?? _auth.currentUser?.photoURL,
        name: displayName ?? email ?? 'مستخدم',
        gender: gender,
        age: age,
        height: height,
        weight: weight,
        goal: goal,
        calories: targetCalories,
        protein: proteinG,
        carbs: carbsG,
        fat: fatG,
        waterMl: waterMlTarget,
        steps: stepsTarget,
        sleepH: sleepHoursTarget,
        bmi: bmiVal,
        bmiClass: bmiClass,
      ),
    );
  }

  // Export/Import JSON
}

// ====== Widgets ======

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.icon,
    this.action,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon ?? Icons.widgets_rounded, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.right,
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
    required this.name,
    required this.goal,
    required this.gender,
    required this.age,
    required this.height,
    required this.weight,
    required this.bmiClass,
    this.email,
    this.photoUrl,
    this.onEdit,
    this.onShowHealthCard,
  });

  final String name;
  final String goal;
  final String gender;
  final int age;
  final double height;
  final double weight;
  final String bmiClass;
  final String? email;
  final String? photoUrl;
  final VoidCallback? onEdit;
  final VoidCallback? onShowHealthCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final displayEmail = (email ?? '').trim();
    final trimmedName = name.trim();
    final initials = trimmedName.isNotEmpty ? trimmedName.substring(0, 1) : 'و';

    Widget primaryAction({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required bool filled,
    }) {
      final child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );

      if (filled) {
        return SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: child,
          ),
        );
      }

      return SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            side: BorderSide(color: cs.outlineVariant),
            backgroundColor: cs.surface.withOpacity(0.62),
          ),
          child: child,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.16),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primaryContainer.withOpacity(0.98),
            cs.surfaceContainerHighest,
            cs.surface,
          ],
          stops: const [0.0, 0.58, 1.0],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.38)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -38,
              start: -26,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withOpacity(0.09),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -52,
              end: -18,
              child: Container(
                width: 162,
                height: 162,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.secondary.withOpacity(0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: cs.primary.withOpacity(0.14)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.eco_rounded, size: 16, color: cs.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'بطاقة وازن الصحية',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                                height: 1.05,
                              ),
                            ),
                            if (displayEmail.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                displayEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.62),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 78,
                        height: 96,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.95),
                              Colors.white.withOpacity(0.40),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withOpacity(0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(21),
                            ),
                            child: hasPhoto
                                ? Image.network(
                                    photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _ProfileInitialAvatar(
                                      initials: initials,
                                    ),
                                  )
                                : _ProfileInitialAvatar(initials: initials),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.30),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.20)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(Icons.flag_rounded, color: cs.primary, size: 21),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الهدف الحالي',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(0.58),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                goal,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 430;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: compact ? 2 : 4,
                        childAspectRatio: compact ? 1.42 : 1.32,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: [
                          _ProfileStatCard(
                            icon: Icons.wc_rounded,
                            label: 'الجنس',
                            value: gender,
                          ),
                          _ProfileStatCard(
                            icon: Icons.cake_rounded,
                            label: 'العمر',
                            value: '$age سنة',
                          ),
                          _ProfileStatCard(
                            icon: Icons.height_rounded,
                            label: 'الطول',
                            value: '${height.toStringAsFixed(0)} سم',
                          ),
                          _ProfileStatCard(
                            icon: Icons.monitor_weight_rounded,
                            label: 'الوزن',
                            value: '${weight.toStringAsFixed(1)} كجم',
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surface.withOpacity(0.76),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.82)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.tertiary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(Icons.favorite_rounded, color: cs.tertiary, size: 21),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تصنيف الحالة الحالية',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(0.60),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                bmiClass,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onShowHealthCard != null || onEdit != null) ...[
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 390;
                        final buttons = <Widget>[
                          if (onEdit != null)
                            primaryAction(
                              icon: Icons.edit_note_rounded,
                              label: 'تعديل القياسات والهدف',
                              onTap: onEdit!,
                              filled: true,
                            ),
                          if (onShowHealthCard != null)
                            primaryAction(
                              icon: Icons.badge_rounded,
                              label: 'عرض البطاقة',
                              onTap: onShowHealthCard!,
                              filled: false,
                            ),
                        ];

                        if (stacked) {
                          return Column(
                            children: [
                              for (int i = 0; i < buttons.length; i++) ...[
                                SizedBox(width: double.infinity, child: buttons[i]),
                                if (i != buttons.length - 1) const SizedBox(height: 8),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            for (int i = 0; i < buttons.length; i++) ...[
                              Expanded(child: buttons[i]),
                              if (i != buttons.length - 1) const SizedBox(width: 10),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileInitialAvatar extends StatelessWidget {
  const _ProfileInitialAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withOpacity(0.16),
            cs.secondary.withOpacity(0.10),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  const _ProfileStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.60),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaloriesCardSimple extends StatelessWidget {
  const _CaloriesCardSimple({required this.total, required this.maintenance});
  final double total;
  final double maintenance;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _macroBg(context, 'السعرات'),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: cs.onSecondaryContainer.withOpacity(0.08),
                  shape: BoxShape.circle),
              child: const Text('🔥', style: TextStyle(fontSize: 16))),
          const SizedBox(width: 8),
          Text('السعرات',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${total.toStringAsFixed(0)}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('kcal', style: theme.textTheme.labelLarge)),
              ],
            ),
          ),
        ),
]),
    );
  }
}

/// بطاقة ماكروز مضغوطة (أصغر بكثير)


Color _macroBg(BuildContext context, String title){
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  if (title.contains('السعرات')) {
    // primaryContainer مع شفافية خفيفة مثل الهوم
    return cs.primaryContainer.withOpacity(0.15);
  }
  if (title.contains('البروتين') || title.contains('بروتين')) {
    return const Color(0xFFE0ECFF); // أزرق فاتح
  }
  if (title.contains('الكرب') || title.contains('الكربوهيدرات') || title.contains('كارب')) {
    return const Color(0xFFFFF7ED); // برتقالي فاتح
  }
  if (title.contains('الدهون') || title.contains('دهون')) {
    return const Color(0xFFEAFBF1); // أخضر فاتح
  }
  return cs.surfaceContainer;
}

class _MacroCardView extends StatelessWidget {
  const _MacroCardView._({
    required this.title,
    required this.grams,
    required this.kcal,
    required this.emoji,
  });

  factory _MacroCardView.compact({
    required String title,
    required double grams,
    required double kcal,
    required String emoji,
  }) => _MacroCardView._(title: title, grams: grams, kcal: kcal, emoji: emoji);

  final String title;
  final double grams;
  final double kcal;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _macroBg(context, title),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45),
            shape: BoxShape.circle,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              LayoutBuilder(builder: (context, box) {
                final tight = box.maxWidth < 230;
                final numStyle = (tight ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w900);

                final gramsLine = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(grams.toStringAsFixed(0), style: numStyle),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('غ', style: theme.textTheme.labelMedium),
                    ),
                  ],
                );

                if (tight) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      gramsLine,
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _KcalChip(value: kcal),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    gramsLine,
                    const Spacer(),
                    _KcalChip(value: kcal),
                  ],
                );
              }),
            ],
          ),
        ),
      ]),
    );
  }
}

class _KcalChip extends StatelessWidget {
  const _KcalChip({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _macroBg(context, 'السعرات'),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${value.toStringAsFixed(0)} كال',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}


class _PlanActionsBar extends StatelessWidget {
  const _PlanActionsBar({
    required this.isCustom,
    required this.onCustom,
    required this.onTargets,
  });

  final bool isCustom;
  final VoidCallback onCustom;
  final VoidCallback onTargets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isCustom ? Icons.edit_rounded : Icons.auto_awesome_rounded,
                color: cs.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCustom ? 'الخطة الحالية: تخصيص يدوي' : 'الخطة الحالية: تلقائية حسب الهدف',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onCustom,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('تخصيص'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTargets,
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const Text('الأهداف'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _GoalPill extends StatelessWidget {
  const _GoalPill({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  Color _accent(ColorScheme cs) {
    if (title.contains('الماء')) return cs.primary;
    if (title.contains('الخطوات')) return cs.tertiary;
    if (title.contains('النوم')) return cs.secondary;
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = _accent(cs);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left_rounded, color: cs.onSurface.withOpacity(0.35)),
          ],
        ),
      ),
    );
  }
}

// BMI + BodyFat
double _bmi(double wKg, double hCm) {
  final hM = hCm / 100.0;
  if (hM <= 0) return 0;
  return wKg / (hM * hM);
}

String _bmiClass(double bmi) {
  if (bmi < 18.5) return 'نحافة';
  if (bmi < 25) return 'طبيعي';
  if (bmi < 30) return 'زيادة وزن';
  return 'سمنة';
}

class BMICard extends StatelessWidget {
  const BMICard({required this.value, required this.label});
  final double value;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (value / 35).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(value: pct, strokeWidth: 6)),
        const SizedBox(width: 10),
        Expanded(
            child: Text('BMI ${value.toStringAsFixed(1)} • $label',
                style: Theme.of(context).textTheme.titleSmall)),
      ]),
    );
  }
}

class BodyFatCard extends StatelessWidget {
  const BodyFatCard({required this.gender, required this.bmi, required this.age});
  final String gender;
  final double bmi;
  final int age;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final est = _bodyFatRange(gender, bmi, age);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        Icon(Icons.monitor_heart_rounded, color: cs.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text('نسبة دهون تقديرية: $est', maxLines: 2)),
      ]),
    );
  }
}

String _bodyFatRange(String gender, double bmi, int age) {
  if (gender == 'أنثى') {
    if (bmi < 21) return '18–25%';
    if (bmi < 25) return '22–30%';
    if (bmi < 30) return '28–36%';
    return '35–45%';
  } else {
    if (bmi < 21) return '10–18%';
    if (bmi < 25) return '14–22%';
    if (bmi < 30) return '20–28%';
    return '27–38%';
  }
}

// Health Card – متوافقة مع جميع المظاهر (Material 3)
class _HealthCardSheet extends StatelessWidget {
  const _HealthCardSheet({
    required this.name,
    required this.gender,
    required this.age,
    required this.height,
    required this.weight,
    required this.goal,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.waterMl,
    required this.steps,
    required this.sleepH,
    required this.bmi,
    required this.bmiClass,
    this.photoUrl,
  });

  final String name, gender, goal, bmiClass;
  final String? photoUrl;
  final int age, steps, waterMl;
  final double height, weight, calories, protein, carbs, fat, sleepH, bmi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final initials = name.trim().isNotEmpty ? name.trim().substring(0, 1) : 'و';
    final bmiPct = (bmi / 35).clamp(0.0, 1.0).toDouble();

    Widget avatar({double size = 74}) {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Colors.white.withOpacity(0.96),
              Colors.white.withOpacity(0.45),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: Container(
            color: cs.surface,
            child: hasPhoto
                ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ProfileInitialAvatar(initials: initials),
                  )
                : _ProfileInitialAvatar(initials: initials),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'إغلاق',
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Text(
                    'بطاقتي الصحية',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 10),

            // ===== بطاقة صحية فخمة =====
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.20),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color.lerp(cs.primary, Colors.black, 0.18)!,
                    Color.lerp(cs.primary, Colors.black, 0.38)!,
                    Color.lerp(cs.primary, Colors.black, 0.55)!,
                  ],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  children: [
                    PositionedDirectional(
                      top: -34,
                      end: -16,
                      child: Container(
                        width: 148,
                        height: 148,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: -52,
                      start: -24,
                      child: Container(
                        width: 172,
                        height: 172,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              avatar(size: 76),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.eco_rounded, color: Colors.white.withOpacity(0.92), size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          'بطاقة وازن الصحية',
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            color: Colors.white.withOpacity(0.90),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        height: 1.05,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _HealthGlassPill(
                                      icon: Icons.flag_rounded,
                                      label: goal,
                                      foreground: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _HealthHeroMetric(
                                  label: 'السعرات',
                                  value: calories.toStringAsFixed(0),
                                  unit: 'كال',
                                  icon: Icons.local_fire_department_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _HealthHeroMetric(
                                  label: 'BMI',
                                  value: bmi.toStringAsFixed(1),
                                  unit: bmiClass,
                                  icon: Icons.monitor_heart_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children: [
                              _HealthGlassPill(icon: Icons.wc_rounded, label: gender, foreground: Colors.white),
                              _HealthGlassPill(icon: Icons.cake_rounded, label: '$age سنة', foreground: Colors.white),
                              _HealthGlassPill(icon: Icons.height_rounded, label: '${height.toStringAsFixed(0)} سم', foreground: Colors.white),
                              _HealthGlassPill(icon: Icons.monitor_weight_rounded, label: '${weight.toStringAsFixed(1)} كجم', foreground: Colors.white),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            _HealthPremiumSection(
              title: 'هدف السعرات والماكروز',
              icon: Icons.pie_chart_rounded,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _macroBg(context, 'السعرات'),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: 0.72,
                            strokeWidth: 7,
                            backgroundColor: cs.surface.withOpacity(0.70),
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'السعرات اليومية المستهدفة',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.onSurface.withOpacity(0.68),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${calories.toStringAsFixed(0)} كال',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _AdaptiveGrid(
                    columns: 3,
                    gutter: 10,
                    children: [
                      _MacroCardView.compact(title: 'بروتين', grams: protein, kcal: protein * 4, emoji: '🥩'),
                      _MacroCardView.compact(title: 'كارب', grams: carbs, kcal: carbs * 4, emoji: '🍞'),
                      _MacroCardView.compact(title: 'دهون', grams: fat, kcal: fat * 9, emoji: '🥑'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _HealthPremiumSection(
              title: 'مؤشرات الجسم',
              icon: Icons.favorite_rounded,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: CircularProgressIndicator(
                        value: bmiPct,
                        strokeWidth: 7,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مؤشر كتلة الجسم',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${bmi.toStringAsFixed(1)} • $bmiClass',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'معلومة تقديرية تساعدك على متابعة التقدم، وليست تشخيصًا طبيًا.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            _HealthPremiumSection(
              title: 'أهداف اليوم',
              icon: Icons.flag_rounded,
              child: _AdaptiveGrid(
                columns: 3,
                gutter: 10,
                children: [
                  _HealthGoalTile(icon: Icons.water_drop_rounded, title: 'الماء', value: '${waterMl} مل'),
                  _HealthGoalTile(icon: Icons.directions_walk_rounded, title: 'الخطوات', value: '$steps'),
                  _HealthGoalTile(icon: Icons.nightlight_round, title: 'النوم', value: '${sleepH.toStringAsFixed(1)} س'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthPremiumSection extends StatelessWidget {
  const _HealthPremiumSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _HealthHeroMetric extends StatelessWidget {
  const _HealthHeroMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.88), size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withOpacity(0.72),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    unit,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withOpacity(0.78),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthGlassPill extends StatelessWidget {
  const _HealthGlassPill({
    required this.icon,
    required this.label,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground.withOpacity(0.92)),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _HealthGoalTile extends StatelessWidget {
  const _HealthGoalTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Sheets & Dialogs
class BasicsData {
  final String? name;
  final String gender;
  final String goal;
  final int age;
  final double height;
  final double weight;
  final int lifestyleScore;
  const BasicsData({
    required this.name,
    required this.gender,
    required this.goal,
    required this.age,
    required this.height,
    required this.weight,
    required this.lifestyleScore,
  });
}

class _EditBasicsSheet extends StatefulWidget {
  const _EditBasicsSheet({
    required this.initial,
    required this.onSubmit,
    this.weightLocked = false,
    this.weightDaysLeft = 0,
  });

  final BasicsData initial;
  final Future<void> Function(BasicsData) onSubmit;

  /// إذا true: يتم تعطيل حقل الوزن (منع تعديل الوزن قبل مرور 7 أيام)
  final bool weightLocked;
  final int weightDaysLeft;

  @override
  State<_EditBasicsSheet> createState() => _EditBasicsSheetState();
}

class _EditBasicsSheetState extends State<_EditBasicsSheet> {
  final _formKey = GlobalKey<FormState>();

  static const _goalItems = [
    'إنقاص الوزن',
    'تنشيف الدهون',
    'بناء العضلات',
    'زيادة الوزن',
    'نمط حياة صحي',
    'زيادة النشاط اليومي',
    'ضبط مستوى السكر في الدم',
  ];

  late int age;
  late double height;
  late double weight;
  late String selectedGoal;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    age = widget.initial.age;
    height = widget.initial.height;
    weight = widget.initial.weight;
    final rawGoal = widget.initial.goal.trim();
    selectedGoal = _goalItems.contains(rawGoal)
        ? rawGoal
        : rawGoal.contains('سكر')
            ? 'ضبط مستوى السكر في الدم'
            : rawGoal.isNotEmpty && rawGoal.contains('صحي')
                ? 'نمط حياة صحي'
                : 'نمط حياة صحي';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    // إبقاء الاسم/الجنس/نمط الحياة كما هي، وتعديل القياسات والهدف من مكان واحد.
    final next = BasicsData(
      name: widget.initial.name,
      gender: widget.initial.gender,
      goal: selectedGoal,
      age: age,
      height: height,
      weight: widget.weightLocked ? widget.initial.weight : weight,
      lifestyleScore: widget.initial.lifestyleScore,
    );

    setState(() => _saving = true);
    try {
      await widget.onSubmit(next);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locked = widget.weightLocked == true;
    final daysLeft = widget.weightDaysLeft;

    InputDecoration fieldDecoration({
      required String label,
      required IconData icon,
      String? helper,
    }) {
      return InputDecoration(
        labelText: label,
        helperText: helper,
        helperStyle: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurface.withOpacity(0.65),
        ),
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withOpacity(0.68),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary, width: 1.4),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'إغلاق',
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'تعديل القياسات والهدف',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'عدّل الطول والوزن والهدف من مكان واحد. بعد الحفظ يعيد وازن حساب السعرات والماكروز تلقائيًا.',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedGoal,
                    isExpanded: true,
                    decoration: fieldDecoration(
                      label: 'الهدف الحالي',
                      icon: Icons.flag_rounded,
                    ),
                    items: _goalItems
                        .map(
                          (g) => DropdownMenuItem<String>(
                            value: g,
                            child: Text(g, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => selectedGoal = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: age.toString(),
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration(
                      label: 'العمر (سنة)',
                      icon: Icons.cake_rounded,
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 8 || n > 120) return 'أدخل عمرًا واقعيًا (8 - 120)';
                      return null;
                    },
                    onSaved: (v) => age = int.parse(v!.trim()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: height.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          decoration: fieldDecoration(
                            label: 'الطول (سم)',
                            icon: Icons.height_rounded,
                          ),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null || n < 100 || n > 250) {
                              return 'طول غير صحيح';
                            }
                            return null;
                          },
                          onSaved: (v) => height = double.parse(v!.trim()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          enabled: !locked,
                          initialValue: weight.toStringAsFixed(1),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: fieldDecoration(
                            label: 'الوزن (كجم)',
                            icon: Icons.monitor_weight_rounded,
                            helper: locked && daysLeft > 0
                                ? 'بعد $daysLeft يوم'
                                : null,
                          ),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null || n < 25 || n > 400) {
                              return 'وزن غير صحيح';
                            }
                            return null;
                          },
                          onSaved: (v) {
                            if (!locked) weight = double.parse(v!.trim());
                          },
                        ),
                      ),
                    ],
                  ),
                  if (locked && daysLeft > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_clock_rounded, color: cs.tertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تعديل الوزن مقفل مؤقتًا للحفاظ على دقة التتبع. تقدر تعدله بعد $daysLeft يوم.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onTertiaryContainer,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('حفظ التعديلات'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


class _TargetsSheet extends StatefulWidget {
  const _TargetsSheet(
      {required this.goal,
      required this.gender,
      required this.weightKg,
      required this.maintenanceCalories,
      required this.bmr,
      required this.macroMode,
      required this.macroPlanId,
      required this.calories,
      required this.protein,
      required this.carbs,
      required this.fat,
      required this.waterMl,
      required this.steps,
      required this.sleepHours,
      required this.onSubmit});

  final String goal;
  final String gender;
  final double weightKg;
  final double maintenanceCalories;
  final double bmr;

  final String macroMode;
  final String macroPlanId;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  final int waterMl;
  final int steps;
  final double sleepHours;

  final Future<void> Function(
    String macroMode,
    String macroPlanId,
    double calories,
    double protein,
    double carbs,
    double fat,
    int waterMl,
    int steps,
    double sleepH,
  ) onSubmit;
  @override
  State<_TargetsSheet> createState() => _TargetsSheetState();
}

class _TargetsSheetState extends State<_TargetsSheet> {
  late int water = widget.waterMl;
  late int steps = widget.steps;
  late double sleepH = widget.sleepHours;

  late bool custom = widget.macroMode == MacroPlanEngine.modeCustom;
  late String planId = widget.macroPlanId;
  late double kcal = widget.calories;
  late double pro = widget.protein;
  late double carb = widget.carbs;
  late double fat = widget.fat;

  late final List<MacroPlanOption> options = MacroPlanEngine.buildOptions(
    goal: widget.goal,
    maintenanceCalories: widget.maintenanceCalories,
    weightKg: widget.weightKg,
    gender: widget.gender,
    bmr: widget.bmr,
  );

  late final TextEditingController kcalCtrl = TextEditingController(text: kcal.toStringAsFixed(0));
  late final TextEditingController proCtrl = TextEditingController(text: pro.toStringAsFixed(0));
  late final TextEditingController carbCtrl = TextEditingController(text: carb.toStringAsFixed(0));
  late final TextEditingController fatCtrl = TextEditingController(text: fat.toStringAsFixed(0));

  @override
  void dispose() {
    kcalCtrl.dispose();
    proCtrl.dispose();
    carbCtrl.dispose();
    fatCtrl.dispose();
    super.dispose();
  }

  void _applyAutoPlan(String id) {
    final selected = options.firstWhere(
      (o) => o.id == id,
      orElse: () => options.first,
    );
    planId = selected.id;
    kcal = selected.calories;
    pro = selected.proteinG;
    carb = selected.carbsG;
    fat = selected.fatG;

    // sync controllers preview
    kcalCtrl.text = kcal.toStringAsFixed(0);
    proCtrl.text = pro.toStringAsFixed(0);
    carbCtrl.text = carb.toStringAsFixed(0);
    fatCtrl.text = fat.toStringAsFixed(0);
  }

  bool _readCustomFields() {
    final k = double.tryParse(kcalCtrl.text.trim());
    final p = double.tryParse(proCtrl.text.trim());
    final c = double.tryParse(carbCtrl.text.trim());
    final f = double.tryParse(fatCtrl.text.trim());
    if (k == null || p == null || c == null || f == null) return false;
    if (k <= 0 || p < 0 || c < 0 || f < 0) return false;
    kcal = k.roundToDouble();
    pro = p.roundToDouble();
    carb = c.roundToDouble();
    fat = f.roundToDouble();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

    // Ensure a valid auto plan selection when entering the sheet.
    if (!custom && planId.trim().isNotEmpty) {
      final exists = options.any((o) => o.id == planId);
      if (!exists) {
        _applyAutoPlan(MacroPlanEngine.defaultPlanIdForGoal(widget.goal));
      }
    } else if (!custom && planId.trim().isEmpty) {
      _applyAutoPlan(MacroPlanEngine.defaultPlanIdForGoal(widget.goal));
    }

    return Padding(
      padding: EdgeInsets.only(bottom: view),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: const [
            Icon(Icons.settings_suggest_rounded),
            SizedBox(width: 8),
            Text('ضبط الأهداف والماكروز', style: TextStyle(fontWeight: FontWeight.w800))
          ]),
          const SizedBox(height: 10),

          // ===== خطة السعرات/الماكروز =====
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_fire_department_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'خطة السعرات والماكروز',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: custom,
                    onChanged: (v) {
                      setState(() {
                        custom = v;
                        if (!custom) {
                          // رجوع للوضع التلقائي
                          final def = MacroPlanEngine.defaultPlanIdForGoal(widget.goal);
                          _applyAutoPlan(options.any((o) => o.id == planId) ? planId : def);
                        }
                      });
                    },
                    title: const Text('تخصيص يدوي للماكروز'),
                    subtitle: Text(
                      custom
                          ? 'أدخل القيم بنفسك وسيتم اعتمادها بكل مكان.'
                          : 'فعّلها إذا تبغى تحدد السعرات والماكروز يدويًا.',
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(height: 6),

                  if (!custom) ...[
                    Text(
                      'اختر خيار من 3 (حسب هدفك: ${widget.goal})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: options.map((o) {
                        final selected = o.id == planId;
                        return _PlanChipCard(
                          title: o.title,
                          subtitle: o.subtitle,
                          kcal: o.calories,
                          protein: o.proteinG,
                          carbs: o.carbsG,
                          fat: o.fatG,
                          selected: selected,
                          onTap: () => setState(() => _applyAutoPlan(o.id)),
                        );
                      }).toList(),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    _NumField(label: 'السعرات (kcal)', controller: kcalCtrl),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _NumField(label: 'بروتين (جم)', controller: proCtrl)),
                        const SizedBox(width: 10),
                        Expanded(child: _NumField(label: 'كارب (جم)', controller: carbCtrl)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _NumField(label: 'دهون (جم)', controller: fatCtrl),
                  ],

                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surface,
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${kcal.toStringAsFixed(0)} kcal', style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text('P ${pro.toStringAsFixed(0)}g  •  C ${carb.toStringAsFixed(0)}g  •  F ${fat.toStringAsFixed(0)}g',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                            ],
                          ),
                        ),
                        Icon(Icons.check_circle_rounded, color: cs.primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          _StepperField(
              label: 'الماء (مل)',
              value: water.toDouble(),
              min: 1000,
              max: 6000,
              step: 250,
              onChanged: (v) => setState(() => water = v.round())),
          const SizedBox(height: 6),
          _StepperField(
              label: 'الخطوات (يوم)',
              value: steps.toDouble(),
              min: 2000,
              max: 20000,
              step: 500,
              onChanged: (v) => setState(() => steps = v.round())),
          const SizedBox(height: 6),
          _StepperField(
              label: 'النوم (ساعة)',
              value: sleepH,
              min: 4,
              max: 10,
              step: 0.5,
              onChanged: (v) => setState(() => sleepH = v)),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () async {
                if (custom) {
                  final ok = _readCustomFields();
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تأكد من إدخال أرقام صحيحة للماكروز')),
                    );
                    return;
                  }
                  await widget.onSubmit(
                    MacroPlanEngine.modeCustom,
                    'custom',
                    kcal,
                    pro,
                    carb,
                    fat,
                    water,
                    steps,
                    sleepH,
                  );
                } else {
                  // auto: خذ القيم من الخطة المختارة
                  _applyAutoPlan(planId);
                  await widget.onSubmit(
                    MacroPlanEngine.modeAuto,
                    planId,
                    kcal,
                    pro,
                    carb,
                    fat,
                    water,
                    steps,
                    sleepH,
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('حفظ')),
        ]),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _NumField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }
}

class _PlanChipCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final bool selected;
  final VoidCallback onTap;

  const _PlanChipCard({
    required this.title,
    required this.subtitle,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.10) : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w900, color: selected ? cs.primary : cs.onSurface),
                  ),
                ),
                Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 18, color: selected ? cs.primary : cs.outline),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text('${kcal.toStringAsFixed(0)} kcal', style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('P ${protein.toStringAsFixed(0)}g • C ${carbs.toStringAsFixed(0)}g • F ${fat.toStringAsFixed(0)}g',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _StepperField extends StatelessWidget {
  const _StepperField(
      {required this.label,
      required this.value,
      required this.min,
      required this.max,
      required this.step,
      required this.onChanged});
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
        Text(value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1))
      ]),
      Slider(
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          value: value.clamp(min, max),
          onChanged: onChanged),
    ]);
  }
}



/// ويدجت خطأ بسيطة مع زر إعادة المحاولة (UI فقط)
class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'تعذر تحميل بياناتك',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شبكة مرنة بعرض ثابت للأعمدة (تتعامل مع اختلاف ارتفاع البطاقات)
class _AdaptiveGrid extends StatelessWidget {
  final int columns;
  final double gutter;
  final List<Widget> children;

  const _AdaptiveGrid({
    required this.columns,
    required this.gutter,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final col = columns < 1 ? 1 : columns;
      final maxW = box.maxWidth;
      final totalGutter = gutter * (col - 1);
      final itemW = ((maxW - totalGutter) / col).clamp(0.0, maxW);

      return Wrap(
        spacing: gutter,
        runSpacing: gutter,
        children: [
          for (final child in children)
            SizedBox(
              width: itemW,
              child: child,
            ),
        ],
      );
    });
  }
}

// مفاتيح التخزين
class _Prefs {
  static const currentEmail = 'currentEmail';
  static const gender = 'gender';
  static const age = 'age';
  static const height = 'height';
  static const weight = 'weight';
  static const goal = 'goal';
  static const goalFatShred = 'goal_fat_shred';
  static const lifestyleScore = 'lifestyleScore';
  static const caloriesNeeded = 'caloriesNeeded';
  static const maintenanceCalories = 'maintenanceCalories';
  static const protein = 'protein';
  static const carbs = 'carbs';
  static const fat = 'fat';
  static const lastWeightChangeAt = 'lastWeightChangeAt';
  static const waterMlTarget = 'waterMlTarget';
  static const stepsTarget = 'stepsTarget';
  static const sleepHoursTarget = 'sleepHoursTarget';
}

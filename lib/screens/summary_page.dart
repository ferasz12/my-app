import 'dart:math';
import 'dart:async'; // ⬅️ للـ Timeout
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ⬇️ لإتمام تعليم الأونبوردنغ في السحابة
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/legacy_user_repository.dart';

import '../utils/calorie_calculator.dart';
import '../utils/macro_plan_engine.dart';
import '../shared/macro_targets_controller.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _loading = true;
  bool _finishing = false; // ⬅️ لمنع النقر المكرر على زر "ابدأ"

  // --- user data ---
  String gender = 'غير محدد';
  int age = 0;
  double weight = 0;
  double height = 0;
  String goal = 'غير محدد';

  // --- activity ---
  String activityLevel = 'moderate';
  int? lifestyleScore;
  double activityFactor = 1.55;

  // --- calories ---
  double bmr = 0;
  double maintenanceCalories = 0;
  double adjustedCalories = 0;
  double? lastSavedCalories;
  String? lastUpdatedDate;

  // --- macro plan ---
  String macroMode = MacroPlanEngine.modeAuto;
  String macroPlanId = '';
  List<MacroPlanOption> planOptions = const [];
  bool _savingPlan = false;

  // --- macros ---
  double protein = 0;
  double fat = 0;
  double carbs = 0;

  // --- analysis text ---
  String analysisText = '';
  String macroCalculationNote = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // مطابق لصفحتك القديمة
  double _activityFactorFromScore(int score) {
    if (score <= 6) return 1.2;
    if (score <= 12) return 1.375;
    if (score <= 16) return 1.55;
    if (score <= 19) return 1.725;
    return 1.9;
  }

  // مطابق لصفحتك القديمة
  double _factorFromLevel(String level) {
    switch (level) {
      case 'sedentary':
        return 1.2;
      case 'light':
        return 1.375;
      case 'moderate':
        return 1.55;
      case 'active':
        return 1.725;
      case 'very_active':
        return 1.9;
      default:
        return 1.55;
    }
  }

  String _activityLabel(double f) {
    if (f <= 1.2) return 'خفيف جدًا (عمل مكتبي مع نشاط محدود)';
    if (f <= 1.375) return 'خفيف (نشاط بسيط/تمارين 1-3 أيام)';
    if (f <= 1.55) return 'متوسط (تمارين 3-5 أيام)';
    if (f <= 1.725) return 'عالي (تمارين 6-7 أيام)';
    return 'عالي جدًا (نشاط مكثف/عمل شاق)';
  }

  // نُطبّع فقط أهداف “النشاط اليومي/السكر” إلى “محافظة” مثل القديم
  String _goalForCalc(String g) {
    if (g == 'زيادة النشاط اليومي' || g == 'ضبط مستوى السكر في الدم') {
      return 'نمط حياة صحي'; // صيانة
    }
    return g;
  }

    Future<void> _loadAll() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    // == للتوافق مع النسخ القديمة التي كانت تعتمد على currentEmail ==
    final email = prefs.getString('currentEmail') ?? 'unknown_user';

    // 1) نحاول نقرأ من Firestore (Legacy root users/{uid}) أولاً
    if (user != null) {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      Future<DocumentSnapshot<Map<String, dynamic>>> _getRoot() async {
        final ref = db.doc('users/$uid');
        try {
          final snap = await ref.get(const GetOptions(source: Source.cache));
          if (snap.exists) return snap;
        } catch (_) {}
        return ref.get();
      }

      try {
        // تأكيد وجود الجذر + محاولة مهاجرة حقول ناقصة (Best-effort)
        try {
          await const LegacyUserRepository().ensureLegacyUserDocExists();
        } catch (_) {}

        final rootSnap = await _getRoot();
        final root = rootSnap.data();

        if (root != null) {
          final g = root['gender'];
          if (g != null && g.toString().trim().isNotEmpty) gender = g.toString();

          final a = root['age'];
          if (a is num) age = a.toInt();

          final hc = root['heightCm'];
          if (hc is num) height = hc.toDouble();

          final wk = root['currentWeightKg'] ?? root['weightKg'];
          if (wk is num) weight = wk.toDouble();

          // goal (root)
          final gg = root['goal'];
          if (gg != null && gg.toString().trim().isNotEmpty) goal = gg.toString();

          // metrics (nested map)
          final metrics = (root['metrics'] is Map) ? Map<String, dynamic>.from(root['metrics'] as Map) : null;
          if (metrics != null) {
            final ls = metrics['lifestyleScore'];
            if (ls is num) lifestyleScore = ls.toInt();

            final af = metrics['activityFactor'];
            if (af is num) activityFactor = af.toDouble();

            final mc = metrics['maintenanceCalories'];
            if (mc is num) maintenanceCalories = mc.toDouble();

            final cn = metrics['caloriesNeeded'];
            if (cn is num) {
              adjustedCalories = cn.toDouble();
              lastSavedCalories = adjustedCalories;
            }

            final mm = metrics['macroMode'];
            if (mm != null && mm.toString().trim().isNotEmpty) {
              macroMode = mm.toString();
            }
            final mp = metrics['macroPlanId'];
            if (mp != null && mp.toString().trim().isNotEmpty) {
              macroPlanId = mp.toString();
            }

            final p = metrics['protein'];
            if (p is num) protein = p.toDouble();

            final f = metrics['fat'];
            if (f is num) fat = f.toDouble();

            final c = metrics['carbs'];
            if (c is num) carbs = c.toDouble();

            // إذا الهدف موجود داخل metrics.goalType استخدمه كـ fallback
            final gt = metrics['goalType'];
            if ((goal.trim().isEmpty || goal == 'نمط حياة صحي') &&
                gt != null &&
                gt.toString().trim().isNotEmpty) {
              goal = gt.toString();
            }
          }

          // lifestyle (nested map) كـ fallback للـ score/factor
          final lifestyle = (root['lifestyle'] is Map) ? Map<String, dynamic>.from(root['lifestyle'] as Map) : null;
          if (lifestyle != null) {
            final sc = lifestyle['score'];
            if (lifestyleScore == 0 && sc is num) lifestyleScore = sc.toInt();
            final af = lifestyle['activityFactor'];
            if (af is num) activityFactor = af.toDouble();
          }
        }
      } catch (e, st) {
        debugPrint('[SummaryPage] load from Firestore failed: $e\n$st');
      }
    }

    // 2) fallback: SharedPreferences (للتوافق/لو ما توفر Firestore)
    gender = prefs.getString('gender_$email') ?? gender;
    age = prefs.getInt('age_$email') ?? age;

    // بعض الأجهزة تخزن أحياناً كـ int؛ نضمن التحويل إلى double
    final w = prefs.getDouble('weight_$email');
    final h = prefs.getDouble('height_$email');
    if (weight <= 0) weight = w ?? (prefs.getInt('weight_$email')?.toDouble() ?? weight);
    if (height <= 0) height = h ?? (prefs.getInt('height_$email')?.toDouble() ?? height);

    if (goal == 'غير محدد') goal = prefs.getString('goal_$email') ?? goal;

    activityLevel = prefs.getString('activityLevel_$email') ?? activityLevel;
    lifestyleScore ??= prefs.getInt('lifestyleScore_$email');

    // إذا ما جتنا من Firestore نحسبها من نفس منطقك القديم
    if (activityFactor <= 0) {
      activityFactor = (lifestyleScore != null)
          ? _activityFactorFromScore(lifestyleScore!)
          : _factorFromLevel(activityLevel);
    }

    lastSavedCalories ??= prefs.getDouble('caloriesNeeded_$email');
    lastUpdatedDate ??= prefs.getString('lastUpdated_$email');

    // Macro plan (prefs overrides cloud)
    macroMode = prefs.getString('macroMode_$email') ?? macroMode;
    macroPlanId = prefs.getString('macroPlanId_$email') ?? macroPlanId;

    // Cached local targets (can be newer than Firestore while onboarding screens are open)
    final String _todayKey = DateTime.now().toIso8601String().split('T').first;
    final double? _prefsK = prefs.getDouble('caloriesNeeded_$email');
    final double? _prefsP = prefs.getDouble('protein_$email');
    final double? _prefsC = prefs.getDouble('carbs_$email');
    final double? _prefsF = prefs.getDouble('fat_$email');
    final String? _prefsUpdated = prefs.getString('lastUpdated_$email');
    final String? _prefsMacroNote = prefs.getString('macroCalculationNote_$email');

    // --- BMR (Mifflin–St Jeor) بنفس صيغتك ---
    if (gender == 'ذكر') {
      bmr = 10 * weight + 6.25 * height - 5 * age + 5;
    } else if (gender == 'أنثى') {
      bmr = 10 * weight + 6.25 * height - 5 * age - 161;
    } else {
      bmr = 10 * weight + 6.25 * height - 5 * age + 5;
    }

    if (maintenanceCalories <= 0) {
      maintenanceCalories = (bmr * activityFactor).roundToDouble();
    }

    // --- خيارات السعرات/الماكروز (3 خيارات لكل هدف) ---
    planOptions = MacroPlanEngine.buildOptions(
      goal: goal,
      maintenanceCalories: maintenanceCalories,
      weightKg: weight,
      heightCm: height,
      gender: gender,
      bmr: bmr,
    );

    if (macroPlanId.trim().isEmpty) {
      macroPlanId = MacroPlanEngine.defaultPlanIdForGoal(goal);
    }

    // --- السعرات/الماكروز حسب الخطة ---
    if (macroMode != MacroPlanEngine.modeCustom) {
      final selected = planOptions.firstWhere(
        (o) => o.id == macroPlanId,
        orElse: () => planOptions.first,
      );
      adjustedCalories = selected.calories;
      protein = selected.proteinG;
      carbs = selected.carbsG;
      fat = selected.fatG;
      macroCalculationNote = selected.calculationNote;
    } else {
      // تخصيص يدوي: نستخدم المحفوظ (إذا موجود) أو fallback
      if (adjustedCalories <= 0) {
        adjustedCalories = calculateCalories(
          age: age,
          gender: gender,
          weight: weight,
          height: height,
          activityFactor: activityFactor,
          goal: _goalForCalc(goal),
        ).roundToDouble();
      }
    }

    // --- إن كان فيه قيم محلية محدثة اليوم، نعتمدها (تضمن تطابق الهوم/الملخص) ---
    // (هذه القيم تُكتب عند اختيار خطة/تخصيص من صفحات الإعداد.)
    final pPref = prefs.getDouble('protein_$email');
    final fPref = prefs.getDouble('fat_$email');
    final cPref = prefs.getDouble('carbs_$email');
    final kPref = prefs.getDouble('caloriesNeeded_$email');

    // If local targets were updated today (e.g., after SetGoalPage recalculation),
    // prefer them so Summary and Home stay identical even if Firestore is still catching up.
    if (_prefsUpdated == _todayKey && _prefsK != null && _prefsP != null && _prefsC != null && _prefsF != null) {
      adjustedCalories = _prefsK;
      protein = _prefsP;
      carbs = _prefsC;
      fat = _prefsF;
      lastSavedCalories = _prefsK;
      lastUpdatedDate = _prefsUpdated;
      macroCalculationNote = _prefsMacroNote ?? macroCalculationNote;
    } else {
      // لو كان عندنا قيم محفوظة (غير اليوم) ولا نستخدم تخصيص، نأخذها كـ fallback.
      if (macroMode == MacroPlanEngine.modeCustom && kPref != null && pPref != null && cPref != null && fPref != null) {
        adjustedCalories = kPref;
        protein = pPref;
        carbs = cPref;
        fat = fPref;
      }
    }

    analysisText = _buildAnalysis();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _applyPlan(MacroPlanOption opt) async {
    if (_savingPlan) return;
    setState(() {
      _savingPlan = true;
      macroMode = MacroPlanEngine.modeAuto;
      macroPlanId = opt.id;
      adjustedCalories = opt.calories;
      protein = opt.proteinG;
      carbs = opt.carbsG;
      fat = opt.fatG;
      macroCalculationNote = opt.calculationNote;
    });

    final prefs = await SharedPreferences.getInstance();
    final legacyKey = prefs.getString('currentEmail') ?? 'unknown_user';
    final user = FirebaseAuth.instance.currentUser;
    final raw = legacyKey == 'unknown_user' ? (user?.email ?? 'unknown_user') : legacyKey;
    final uid = user?.uid;
    final storageKey = (raw == 'unknown_user' || raw.trim().isEmpty) ? (uid ?? raw) : raw;

    final today = DateTime.now().toIso8601String().split('T').first;

    // ✅ احفظ الأهداف بنفس القيم على أكثر من مفتاح (UID + Email + legacy)
    // حتى تعتمد في "الرئيسية" و"بياناتي" وكل الصفحات بدون اختلاف.
    final emailKey = (user?.email ?? '').trim();
    final uidKey = (user?.uid ?? '').trim();

    // ثبّت currentUid لو متوفر (بدون لمس currentEmail لتفادي خلط المفاتيح)
    if (uidKey.isNotEmpty) {
      await prefs.setString('currentUid', uidKey);
    }

    final keys = <String>{
      storageKey,
      legacyKey,
      if (emailKey.isNotEmpty) emailKey,
      if (uidKey.isNotEmpty) uidKey,
    }..removeWhere((k) => k.trim().isEmpty || k == 'unknown_user');

    for (final k in keys) {
      await prefs.setDouble('caloriesNeeded_$k', adjustedCalories);
      await prefs.setDouble('protein_$k', protein);
      await prefs.setDouble('carbs_$k', carbs);
      await prefs.setDouble('fat_$k', fat);
      await prefs.setString('macroMode_$k', macroMode);
      await prefs.setString('macroPlanId_$k', macroPlanId);
      await prefs.setString('macroCalculationNote_$k', macroCalculationNote);
      await prefs.setString('lastUpdated_$k', today);
      await prefs.setInt('macrosUpdatedAt_$k', DateTime.now().millisecondsSinceEpoch);
    }

    // ✅ حدث باقي الصفحات فورًا
    MacroTargetsController.bump();

    // Best-effort cloud sync

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final now = Timestamp.now();
        await const LegacyUserRepository().updateLegacyUserRoot(
          patch: {
            'metrics.caloriesNeeded': adjustedCalories,
            'metrics.maintenanceCalories': maintenanceCalories,
            'metrics.protein': protein,
            'metrics.carbs': carbs,
            'metrics.fat': fat,
            'metrics.activityFactor': activityFactor,
            'metrics.macroMode': macroMode,
            'metrics.macroPlanId': macroPlanId,
            'metrics.macroCalculationNote': macroCalculationNote,
            'metrics.updatedAt': now,
            'flags.userDataEntered': true,
            'flags.updatedAt': now,
          },
          stepAtLeast: 2,
        );
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _savingPlan = false;
        lastSavedCalories = adjustedCalories;
        lastUpdatedDate = today;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم اعتماد خيار: ${opt.title}')),
      );
    }
  }


  String _buildAnalysis() {
    if (height <= 0 || weight <= 0) {
      return 'أكمل بيانات الطول والوزن لنظهر لك تحليلاً أدق.';
    }
    final bmi = weight / pow(height / 100.0, 2);
    final label = (bmi < 18.5)
        ? 'نقص وزن'
        : (bmi < 25)
            ? 'وزن طبيعي'
            : (bmi < 30)
                ? 'وزنك فوق الطبيعي قليلًا'
                : 'سمنة';
    return '$label (BMI: ${bmi.toStringAsFixed(1)})\n'
        'مستوى النشاط: ${_activityLabel(activityFactor)}\n'
        'الهدف: $goal';
  }

  String _motivation(String g) {
    switch (g) {
      case 'بناء العضلات':
        return ' كل تكرار يقوّيك. استمر وبتشوف الفرق بالأداء والشكل!';
      case 'إنقاص الوزن':
        return 'هدفك سهل تحققه التزم بخطة وازن وامورك طيبه';
      case 'زيادة الوزن':
        return '🍽️ وجباتك المتوازنة + تدريب و مقاومة = بناء وزن صحي.';
      case 'نمط حياة صحي':
        return '🌿 قراراتك الصغيرة اليوم تصنع جودة حياتك غدًا. استمر!';
      case 'زيادة النشاط اليومي':
        return '🏃‍♂️ الحركة حياة! 10 دقائق إضافية اليوم تصنع عادة قوية غدًا.';
      case 'ضبط مستوى السكر في الدم':
        return '🩸 خياراتك الذكية اليوم تساعد على استقرار سكر الدم وتحسين طاقتك.';
      case 'تنشيف الدهون':
        return '🔥 شدّ التغذية والتزامك بيخلّي التفاصيل تطلع. بروتينك فوق، دهونك محسوبة، والباقي على ثباتك!';
      default:
        return '✨ كل بداية مهمة… وهدفك دليل على وعيك وقوتك.';
    }
  }

    Future<void> _finishAndStart() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    // علّم الأونبوردنغ مكتمل في السحابة (Legacy root users/{uid})
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        Timer? slowTimer;
        slowTimer = Timer(const Duration(seconds: 8), () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('المزامنة بطيئة قليلًا… جاري الإنهاء')),
          );
        });

        try {
          await const LegacyUserRepository()
              .finishOnboarding()
              .timeout(const Duration(seconds: 20));
        } finally {
          slowTimer.cancel();
        }
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتمل الإعداد محليًا، وتعذّرت مزامنة السحابة الآن (Timeout)')),
        );
      }
    } on FirebaseException catch (e, st) {
      debugPrint('[SummaryPage] Firestore onboarding done failed: ${e.code} ${e.message}\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('اكتمل الإعداد محليًا، وتعذّرت مزامنة السحابة الآن: ${e.code}')),
        );
      }
    } catch (e, st) {
      debugPrint('[SummaryPage] Firestore onboarding done failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتمل الإعداد محليًا، وتعذّرت مزامنة السحابة الآن')),
        );
      }
    }

    if (!mounted) return;
    // ✅ دخول التطبيق بدون ترك صفحات الأونبوردنغ في الستاك
    // هذا يمنع ظهور زر الرجوع في أغلب الصفحات بعد تسجيل الدخول/إنشاء الحساب.
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);

    if (mounted) setState(() => _finishing = false);
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final scale = (w / 375).clamp(0.92, 1.12).toDouble();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final base16 = TextStyle(
      fontSize: 15.5 * scale,
      height: 1.45,
      fontWeight: FontWeight.w600,
      color: cs.onSurface.withOpacity(isDark ? 0.86 : 0.78),
    );
    final base14Muted = TextStyle(
      fontSize: 13.5 * scale,
      height: 1.45,
      color: cs.onSurface.withOpacity(isDark ? 0.64 : 0.56),
      fontWeight: FontWeight.w500,
    );
    final titleStyle = TextStyle(
      fontSize: 22 * scale,
      height: 1.18,
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );

    final diff = (adjustedCalories - maintenanceCalories).round();
    final isDeficit = diff < 0;
    final diffLabel = isDeficit ? 'عجز' : (diff > 0 ? 'فائض' : 'محافظة');
    final totalMacros = protein + fat + carbs;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'ملخصك الصحي',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: cs.surface.withOpacity(isDark ? 0.58 : 0.70)),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تعديل الهدف',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {
              // ✅ من داخل الأونبوردنغ: الأفضل يرجّعك للصفحة السابقة لتعديل الهدف.
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushNamed(context, '/set-goal');
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(isDark ? 0.84 : 0.92),
          border: Border(top: BorderSide(color: cs.primary.withOpacity(0.08))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.22 : 0.07),
              blurRadius: 24,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          minimum: EdgeInsets.fromLTRB(16, 10, 16, 16 * (scale > 1 ? scale : 1)),
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: (_loading || _finishing) ? null : _finishAndStart,
              icon: _finishing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.rocket_launch_rounded),
              label: Text(_finishing ? 'جارٍ الإنهاء…' : 'ابدأ استخدام التطبيق'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                textStyle: TextStyle(fontSize: 15.5 * scale, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: _OnbDecorations.background(context),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Directionality(
                textDirection: TextDirection.rtl,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 92, 16, 22),
                  children: [
                    _SummaryHeroCard(
                      titleStyle: titleStyle,
                      mutedStyle: base14Muted,
                      goal: goal.isEmpty ? 'هدف غير محدد' : goal,
                      activityLabel: _activityLabel(activityFactor),
                      caloriesLabel: diff == 0 ? 'سعرات محافظة' : '$diffLabel ${diff.abs()}',
                      isDeficit: isDeficit,
                      isSurplus: diff > 0,
                      motivation: _motivation(goal),
                    ),

                    _SectionCard(
                      title: 'السعرات اليومية',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (lastSavedCalories != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SoftInfoBanner(
                                icon: Icons.verified_rounded,
                                text: 'آخر قيمة محفوظة: ${lastSavedCalories!.toStringAsFixed(0)}'
                                    '${lastUpdatedDate != null ? ' — آخر تحديث: $lastUpdatedDate' : ''}',
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(child: _KpiBox(title: 'المحافظة', value: maintenanceCalories.toStringAsFixed(0))),
                              const SizedBox(width: 12),
                              Expanded(child: _KpiBox(title: 'هدفك اليومي', value: adjustedCalories.toStringAsFixed(0))),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: (maintenanceCalories == 0 ? 0 : (adjustedCalories / maintenanceCalories)).clamp(0.0, 1.0).toDouble(),
                              minHeight: 10,
                              backgroundColor: cs.primary.withOpacity(0.09),
                              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('مقارنة هدفك اليومي بسعرات المحافظة.', style: base14Muted),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'اختر الخطة المناسبة لك',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('اختر الخطة الأقرب لأسلوبك، ووازن يحدث توزيع الماكروز تلقائيًا.', style: base14Muted),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: planOptions.map((o) {
                              final selected = macroMode != MacroPlanEngine.modeCustom && o.id == macroPlanId;
                              return _PlanCard(
                                option: o,
                                selected: selected,
                                onTap: _savingPlan ? null : () => _applyPlan(o),
                              );
                            }).toList(),
                          ),
                          if (macroMode == MacroPlanEngine.modeCustom) ...[
                            const SizedBox(height: 12),
                            _SoftInfoBanner(
                              icon: Icons.tune_rounded,
                              text: 'مفعّل حاليًا: تخصيص يدوي. تقدر تغيّره من صفحة بياناتي.',
                            ),
                          ],
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'طريقة الحساب',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FormulaLine(
                            title: 'معدل الحرق الأساسي',
                            value: bmr.toStringAsFixed(0),
                            helper: 'BMR',
                          ),
                          const SizedBox(height: 10),
                          _FormulaLine(
                            title: 'عامل النشاط',
                            value: activityFactor.toStringAsFixed(3),
                            helper: _activityLabel(activityFactor),
                          ),
                          const SizedBox(height: 10),
                          _FormulaLine(
                            title: 'سعرات المحافظة',
                            value: maintenanceCalories.toStringAsFixed(0),
                            helper: 'BMR × عامل النشاط',
                          ),
                          const SizedBox(height: 10),
                          _FormulaLine(
                            title: 'هدفك بعد التعديل',
                            value: adjustedCalories.toStringAsFixed(0),
                            helper: goal,
                          ),
                          const SizedBox(height: 8),
                          Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                              title: Text(
                                'التحليل والشرح',
                                style: base16.copyWith(fontWeight: FontWeight.w900),
                              ),
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    analysisText.isEmpty
                                        ? 'نستخدم معادلات قياسية لحساب معدل الأيض الأساسي، ثم نضربه بعامل نشاطك اليومي للوصول لسعرات المحافظة. بعدها نعدّلها حسب هدفك.'
                                        : analysisText,
                                    style: base14Muted,
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                                if (macroCalculationNote.trim().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      macroCalculationNote,
                                      style: base14Muted.copyWith(fontWeight: FontWeight.w700),
                                      textAlign: TextAlign.start,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'توزيع الماكروز',
                      child: Column(
                        children: [
                          _MacroRow(
                            label: 'البروتين',
                            grams: protein,
                            emoji: '🥩',
                            total: totalMacros,
                            color: const Color(0xFF2563EB),
                          ),
                          const SizedBox(height: 12),
                          _MacroRow(
                            label: 'الكربوهيدرات',
                            grams: carbs,
                            emoji: '🍞',
                            total: totalMacros,
                            color: const Color(0xFFF97316),
                          ),
                          const SizedBox(height: 12),
                          _MacroRow(
                            label: 'الدهون',
                            grams: fat,
                            emoji: '🥑',
                            total: totalMacros,
                            color: const Color(0xFF22C55E),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
enum ChipTone { neutral, success, warning }

class _SummaryHeroCard extends StatelessWidget {
  final TextStyle titleStyle;
  final TextStyle mutedStyle;
  final String goal;
  final String activityLabel;
  final String caloriesLabel;
  final bool isDeficit;
  final bool isSurplus;
  final String motivation;

  const _SummaryHeroCard({
    required this.titleStyle,
    required this.mutedStyle,
    required this.goal,
    required this.activityLabel,
    required this.caloriesLabel,
    required this.isDeficit,
    required this.isSurplus,
    required this.motivation,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(isDark ? 0.22 : 0.13),
            cs.surface.withOpacity(isDark ? 0.82 : 0.92),
            cs.secondaryContainer.withOpacity(isDark ? 0.14 : 0.20),
          ],
        ),
        border: Border.all(color: cs.primary.withOpacity(isDark ? 0.16 : 0.12)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(isDark ? 0.18 : 0.12),
            blurRadius: 30,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.primary.withOpacity(0.14)),
                ),
                child: Icon(Icons.monitor_heart_rounded, color: cs.primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('خطة وازن جاهزة لك', style: titleStyle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'راجع هدفك اليومي وتوزيع الماكروز قبل ما تبدأ رحلتك.',
            style: mutedStyle,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(label: goal, tone: ChipTone.success),
              _Chip(label: activityLabel),
              _Chip(
                label: caloriesLabel,
                tone: isDeficit ? ChipTone.warning : (isSurplus ? ChipTone.success : ChipTone.neutral),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(isDark ? 0.54 : 0.70),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.primary.withOpacity(0.08)),
            ),
            child: Text(motivation, style: mutedStyle.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  const _SectionCard({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.primary.withOpacity(isDark ? 0.13 : 0.09)),
        color: cs.surface.withOpacity(isDark ? 0.72 : 0.86),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.055),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title!,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftInfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SoftInfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.70),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormulaLine extends StatelessWidget {
  final String title;
  final String value;
  final String helper;
  const _FormulaLine({required this.title, required this.value, required this.helper});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.42)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(helper, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.56), height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

class _KpiBox extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;

  const _KpiBox({required this.title, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.095),
            cs.surface.withOpacity(0.86),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.58), fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.44), fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final MacroPlanOption option;
  final bool selected;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.option,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primary.withOpacity(0.10) : cs.surface.withOpacity(0.70);
    final border = selected ? cs.primary.withOpacity(0.70) : cs.outlineVariant.withOpacity(0.45);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 185,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border, width: selected ? 1.4 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    option.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? cs.primary : cs.outline,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(option.subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35)),
            const SizedBox(height: 12),
            Text(
              option.calories.toStringAsFixed(0),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
            const SizedBox(height: 9),
            _miniRow('🥩', 'P', option.proteinG),
            const SizedBox(height: 5),
            _miniRow('🍞', 'C', option.carbsG),
            const SizedBox(height: 5),
            _miniRow('🥑', 'F', option.fatG),
          ],
        ),
      ),
    );
  }

  Widget _miniRow(String emoji, String tag, double grams) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(tag, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${grams.toStringAsFixed(0)} جم', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double grams;
  final double? total;
  final String emoji;
  final Color color;

  const _MacroRow({
    required this.label,
    required this.grams,
    required this.emoji,
    required this.color,
    this.total,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = (total == null || total == 0) ? 0.0 : (grams / total!).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 19))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
              Text(
                '${grams.toStringAsFixed(0)} جم',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cs.onSurface.withOpacity(0.82)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: color.withOpacity(0.13),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final ChipTone tone;
  const _Chip({required this.label, this.tone = ChipTone.neutral});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    BorderSide border;
    switch (tone) {
      case ChipTone.success:
        bg = cs.primary.withOpacity(0.10);
        fg = cs.primary;
        border = BorderSide(color: cs.primary.withOpacity(0.18));
        break;
      case ChipTone.warning:
        bg = const Color(0xFFFFF4E5);
        fg = const Color(0xFF8A5A12);
        border = BorderSide(color: fg.withOpacity(0.12));
        break;
      default:
        bg = cs.surface.withOpacity(0.72);
        fg = cs.onSurface.withOpacity(0.70);
        border = BorderSide(color: cs.outlineVariant.withOpacity(0.38));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.fromBorderSide(border),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w900, height: 1.1)),
    );
  }
}

// ==============================
// خلفية متدرجة (مناسبة لتطبيق صحي)
// ==============================
class _OnbDecorations {
  static BoxDecoration background(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          cs.primary.withOpacity(isDark ? 0.20 : 0.105),
          cs.secondaryContainer.withOpacity(isDark ? 0.10 : 0.20),
          cs.surface,
        ],
        stops: const [0.0, 0.42, 1.0],
      ),
    );
  }
}

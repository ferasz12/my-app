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
    final scale = (w / 375).clamp(0.92, 1.12);

    final base16 = TextStyle(fontSize: 16 * scale);
    final base18 = TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w600);
    final base14Muted = TextStyle(fontSize: 14 * scale, color: Colors.grey[700]);
    final titleStyle = TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.bold);

    final diff = (adjustedCalories - maintenanceCalories).round();
    final isDeficit = diff < 0;
    final diffLabel = isDeficit ? 'عجز' : (diff > 0 ? 'فائض' : 'محافظة');

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('ملخصك الصحي'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: cs.surface.withOpacity(0.55)),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تعديل الهدف',
            icon: const Icon(Icons.track_changes),
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
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(16, 8, 16, 16 * (scale > 1 ? scale : 1)),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: (_loading || _finishing) ? null : _finishAndStart,
            icon: _finishing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.rocket_launch),
            label: Text(_finishing ? 'جارٍ الإنهاء…' : 'ابدأ استخدام التطبيق'),
          ),
        ),
      ),
      body: Container(
        decoration: _OnbDecorations.background(context),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Directionality(
                textDirection: TextDirection.ltr,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 88, 16, 16),
                  children: [
                  // رأس صفحة أنيق
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.favorite, size: 26),
                            const SizedBox(width: 8),
                            Text('مرحبا! هذا ملخصك الصحي', style: titleStyle),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Chip(label: goal.isEmpty ? 'هدف غير محدد' : goal),
                            _Chip(label: _activityLabel(activityFactor)),
                            _Chip(
                              label: diff == 0 ? 'سعرات محافظة' : '$diffLabel ${diff.abs()} ك.س',
                              tone: isDeficit ? ChipTone.warning : (diff > 0 ? ChipTone.success : ChipTone.neutral),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(_motivation(goal), style: base14Muted),
                      ],
                    ),
                  ),

                  // السعرات الأساسية والهدف + آخر قيمة محفوظة
                  _SectionCard(
                    title: 'السعرات اليومية',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lastSavedCalories != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'آخر قيمة محفوظة: ${lastSavedCalories!.toStringAsFixed(0)}'
                              '${lastUpdatedDate != null ? ' (آخر تحديث: $lastUpdatedDate)' : ''}',
                              style: base14Muted,
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(child: _KpiBox(title: 'المحافظة', value: maintenanceCalories.toStringAsFixed(0), unit: 'ك.س')),
                            const SizedBox(width: 12),
                            Expanded(child: _KpiBox(title: 'الهدف', value: adjustedCalories.toStringAsFixed(0), unit: 'ك.س')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: (maintenanceCalories == 0 ? 0 : (adjustedCalories / maintenanceCalories)).clamp(0.0, 2.0).toDouble(),
                          minHeight: 10,
                          backgroundColor: Colors.grey[300],
                        ),
                        const SizedBox(height: 6),
                        Text('مقارنة الهدف بالمحافظة', style: base14Muted),
                      ],
                    ),
                  ),

                  // اختيار خطة السعرات/الماكروز
                  _SectionCard(
                    title: 'اختر الخطة المناسبة لك',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اختر أحد الخيارات (يتغير معها توزيع الماكروز تلقائيًا).',
                          style: base14Muted,
                        ),
                        const SizedBox(height: 10),
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
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.tune_rounded, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'مفعّل حاليًا: تخصيص يدوي (يمكن تغييره من صفحة "بياناتي").',
                                  style: base14Muted,
                                ),
                              ),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),

                  // تفاصيل الحساب
                  _SectionCard(
                    title: 'طريقة الحساب',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BMR: ${bmr.toStringAsFixed(0)}  |  عامل النشاط: ${activityFactor.toStringAsFixed(3)} (${_activityLabel(activityFactor)})', style: base16),
                        const SizedBox(height: 6),
                        Text('المحافظة = BMR × عامل النشاط = ${maintenanceCalories.toStringAsFixed(0)}', style: base14Muted),
                        Text('الهدف بعد التعديل = ${adjustedCalories.toStringAsFixed(0)}', style: base14Muted),
                        const SizedBox(height: 6),
                        ExpansionTile(
                          title: const Text('التحليل والشرح'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
                              child: Text(
                                analysisText.isEmpty
                                    ? 'نستخدم معادلات قياسية لحساب معدل الأيض الأساسي (BMR) ثم نضربه بعامل نشاطك اليومي للوصول لسعرات المحافظة. بعدها نعدّل للأعلى/الأسفل حسب الهدف.'
                                    : analysisText,
                                style: base14Muted.copyWith(height: 1.4),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // الماكروز (نفس القيم/المعادلات)
                  _SectionCard(
                    title: 'توزيع الماكروز',
                    child: Column(
                      children: [
                        _MacroRow(label: 'البروتين', grams: protein, emoji: '🍗', total: (protein + fat + carbs)),
                        const SizedBox(height: 8),
                        _MacroRow(label: 'الدهون', grams: fat, emoji: '🥑', total: (protein + fat + carbs)),
                        const SizedBox(height: 8),
                        _MacroRow(label: 'الكربوهيدرات', grams: carbs, emoji: '🍚', total: (protein + fat + carbs)),
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

class _SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  const _SectionCard({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
        color: cs.surface.withOpacity(0.78),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
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

class _KpiBox extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;

  const _KpiBox({required this.title, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: const TextStyle(fontSize: 14, color: Colors.black45)),
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
    final bg = selected ? cs.primary.withOpacity(0.10) : cs.surface;
    final border = selected ? cs.primary : cs.outlineVariant.withOpacity(0.6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 185,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
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
                      fontWeight: FontWeight.w800,
                      color: selected ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? cs.primary : cs.outline,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(option.subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(
              '${option.calories.toStringAsFixed(0)} ك.س',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _miniRow('🍗', 'P', option.proteinG),
            const SizedBox(height: 4),
            _miniRow('🍚', 'C', option.carbsG),
            const SizedBox(height: 4),
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
        Text(tag, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text('${grams.toStringAsFixed(0)}g', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double grams;
  final double? total;
  final String emoji;

  const _MacroRow({required this.label, required this.grams, required this.emoji, this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = (total == null || total == 0) ? 0.0 : (grams / total!).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Text('${grams.toStringAsFixed(0)} جم', style: const TextStyle(fontSize: 15, color: Colors.black87)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: Colors.grey[300],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final ChipTone tone;
  const _Chip({required this.label, this.tone = ChipTone.neutral});

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

// ==============================
// خلفية متدرجة (مناسبة لتطبيق صحي)
// ==============================
class _OnbDecorations {
  static BoxDecoration background(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          cs.primary.withOpacity(0.10),
          cs.secondary.withOpacity(0.06),
          cs.surface,
        ],
      ),
    );
  }
}

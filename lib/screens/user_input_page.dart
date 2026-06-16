// lib/screens/user_input_page.dart — نسخة فخمة + بايو محفوظ + روابط سوشيال (إنستا/سناب/تيك توك)
// - نفس المنطق تمامًا (حفظ محلي + مزامنة Cloud Firestore + انتقال إلى /set-goal)
// - البايو يُحفَظ محليًا وفي Firestore داخل الجذر users/{uid}.bio
// - إضافة اختيار شبكات اجتماعية (Instagram/Snapchat/TikTok) + حفظ اليوزرات محليًا وفي Firestore داخل الجذر users/{uid}.social
// - واجهة متناسقة مع صفحات التسجيل/الدخول (خلفية متدرجة + Card وسط الشاشة)

import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../data/legacy_user_repository.dart';
import '../data/app_repository.dart';

import '../utils/calorie_calculator.dart';
import '../utils/macro_plan_engine.dart';

// ✅ مهم: الـ enum يجب أن يكون Top-level (خارج الكلاس)
enum _Social { instagram, snapchat, tiktok }

class UserInputPage extends StatefulWidget {
  final int lifestyleScore;
  const UserInputPage({super.key, required this.lifestyleScore});

  @override
  State<UserInputPage> createState() => _UserInputPageState();
}

class _UserInputPageState extends State<UserInputPage> {
  final _formKey = GlobalKey<FormState>();

  // ===== Profile =====
  final bioController = TextEditingController();

  // ===== Health fields =====
  final weightController = TextEditingController();
  final heightController = TextEditingController();
  String? gender; // 'ذكر' | 'أنثى' | null
  int age = 25;

  // ===== Goals =====
  static const List<String> _goalOptions = [
    'إنقاص الوزن',
    'تنشيف الدهون',
    'بناء العضلات',
    'زيادة الوزن',
    'نمط حياة صحي',
    'زيادة النشاط اليومي',
    'ضبط مستوى السكر في الدم',
  ];
  String? selectedGoal = _goalOptions.first;

  // ===== Social =====
  final Map<_Social, TextEditingController> _socialCtrls = {
    _Social.instagram: TextEditingController(),
    _Social.snapchat: TextEditingController(),
    _Social.tiktok: TextEditingController(),
  };
  final Set<_Social> _selectedSocials = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefillFromStorage();
    _loadSuggestedGoalIfAccepted();
  }

  @override
  void dispose() {
    bioController.dispose();
    weightController.dispose();
    heightController.dispose();
    for (final c in _socialCtrls.values) c.dispose();
    super.dispose();
  }

  String? _normalizeGender(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v == 'male' || v == 'ذكر') return 'ذكر';
    if (v == 'female' || v == 'أنثى' || v == 'انثى') return 'أنثى';
    return null;
  }

  Future<void> _prefillFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';

    // Profile
    bioController.text = prefs.getString('bio_$email') ?? '';

    // Health
    final savedWeight = prefs.getDouble('weight_$email');
    final savedHeight = prefs.getDouble('height_$email');
    final savedGender = prefs.getString('gender_$email');
    final savedAge = prefs.getInt('age_$email');
    final savedGoal = prefs.getString('goal_$email');

    if (savedWeight != null) weightController.text = savedWeight.toString();
    if (savedHeight != null) heightController.text = savedHeight.toString();
    gender = _normalizeGender(savedGender);
    if (savedAge != null) {
      age = math.max(16, math.min(99, savedAge));
    }
    if (savedGoal != null && _goalOptions.contains(savedGoal)) {
      selectedGoal = savedGoal;
    }

    // Social (إن وُجدت قيم، نفعّل الخيار تلقائيًا)
    final ig = prefs.getString('social_instagram_$email');
    final sc = prefs.getString('social_snapchat_$email');
    final tk = prefs.getString('social_tiktok_$email');
    if (ig != null && ig.isNotEmpty) {
      _selectedSocials.add(_Social.instagram);
      _socialCtrls[_Social.instagram]!.text = ig;
    }
    if (sc != null && sc.isNotEmpty) {
      _selectedSocials.add(_Social.snapchat);
      _socialCtrls[_Social.snapchat]!.text = sc;
    }
    if (tk != null && tk.isNotEmpty) {
      _selectedSocials.add(_Social.tiktok);
      _socialCtrls[_Social.tiktok]!.text = tk;
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadSuggestedGoalIfAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    final accepted = prefs.getBool('acceptedSmartGoal_$email') ?? false;
    if (accepted) {
      final goal = prefs.getString('smartGoal_$email');
      if (goal != null && _goalOptions.contains(goal)) {
        if (mounted) setState(() => selectedGoal = goal);
      }
    }
  }

  double _activityFromScore(int score) {
    // يدعم نظامين: القديم (0–100 تقريباً) والجديد (0–34 تقريباً من أسئلة نمط الحياة)
    if (score <= 34) {
      if (score <= 10) return 1.2;
      if (score <= 18) return 1.375;
      if (score <= 26) return 1.55;
      if (score <= 30) return 1.725;
      return 1.9;
    }
    if (score <= 20) return 1.2;
    if (score <= 40) return 1.375;
    if (score <= 60) return 1.55;
    if (score <= 80) return 1.725;
    return 1.9;
  }

  String _goalForCalc(String g) {
    if (g == 'زيادة النشاط اليومي' || g == 'ضبط مستوى السكر في الدم') {
      return 'نمط حياة صحي';
    }
    return g;
  }

  bool _isFatShred(String g) => g == 'تنشيف الدهون';
  Future<void> _saveAll() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    setState(() => _saving = true);

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;

    if (user == null || !user.emailVerified) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لازم تفعل البريد قبل المتابعة')),
        );
      }
      setState(() => _saving = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? (user.email ?? 'unknown_user');

    // حفظ البايو والصورة (محليًا)
    await prefs.setString('bio_$email', bioController.text.trim());

    // حفظ القياسات محليًا — parsing آمن
    final w = double.tryParse(weightController.text);
    final h = double.tryParse(heightController.text);
    if (w == null || h == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تحقق من صحة إدخال الوزن والطول')),
        );
      }
      setState(() => _saving = false);
      return;
    }
    final weight = w;
    final height = h;

    await prefs.setDouble('weight_$email', weight);
    await prefs.setDouble('height_$email', height);

    final storeGender = (gender == 'أنثى') ? 'أنثى' : 'ذكر';
    await prefs.setString('gender_$email', storeGender);
    await prefs.setInt('age_$email', age);

    final goalToStore = (selectedGoal != null && _goalOptions.contains(selectedGoal))
        ? selectedGoal!
        : _goalOptions.first;
    await prefs.setString('goal_$email', goalToStore);

    await prefs.setInt('lifestyleScore_$email', widget.lifestyleScore);
    await prefs.setInt('lifestyleScore', widget.lifestyleScore);

    final activityFactor = _activityFromScore(widget.lifestyleScore);
    await prefs.setDouble('activityFactor_$email', activityFactor);

    // ===== الحساب الموحد: الصيانة + خطة ماكروز من MacroPlanEngine =====
    final maintenanceCalories = calculateCalories(
      age: age,
      gender: storeGender,
      weight: weight,
      height: height,
      activityFactor: activityFactor,
      goal: 'نمط حياة صحي',
    );

    final bmr = calculateBmr(
      age: age,
      gender: storeGender,
      weight: weight,
      height: height,
    );

    final effectiveGoal = _isFatShred(goalToStore) ? 'تنشيف الدهون' : goalToStore;
    final macroPlanId = MacroPlanEngine.defaultPlanIdForGoal(effectiveGoal);
    final planOptions = MacroPlanEngine.buildOptions(
      goal: effectiveGoal,
      maintenanceCalories: maintenanceCalories,
      weightKg: weight,
      heightCm: height,
      gender: storeGender,
      bmr: bmr,
    );
    final selectedPlan = planOptions.firstWhere(
      (o) => o.id == macroPlanId,
      orElse: () => planOptions.first,
    );

    final calculatedCalories = selectedPlan.calories;
    final protein = selectedPlan.proteinG;
    final carbs = selectedPlan.carbsG;
    final fat = selectedPlan.fatG;
    final macroCalculationNote = selectedPlan.calculationNote;

    final today = DateTime.now().toIso8601String().split('T').first;

    // حفظ القيم النهائية محليًا
    await prefs.setDouble('caloriesNeeded_$email', calculatedCalories);
    await prefs.setDouble('maintenanceCalories_$email', maintenanceCalories);
    await prefs.setDouble('protein_$email', protein);
    await prefs.setDouble('fat_$email', fat);
    await prefs.setDouble('carbs_$email', carbs);
    await prefs.setString('macroMode_$email', MacroPlanEngine.modeAuto);
    await prefs.setString('macroPlanId_$email', macroPlanId);
    await prefs.setString('macroCalculationNote_$email', macroCalculationNote);
    await prefs.setInt('macrosUpdatedAt_$email', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('lastUpdated_$email', today);
    await prefs.setBool('goal_fat_shred_$email', _isFatShred(goalToStore));

    // سجل الوزن اليومي محليًا + سحابيًا حتى لا يضيع بعد حذف التطبيق
    final historyKey = 'weightHistory_$email';
    final history = prefs.getStringList(historyKey) ?? [];
    final newEntry = {'date': today, 'weight': weight};
    history.removeWhere((item) {
      try {
        return json.decode(item)['date'] == today;
      } catch (_) {
        return false;
      }
    });
    history.add(json.encode(newEntry));
    await prefs.setStringList(historyKey, history);

    final weightLogKey = 'weight_log_$email';
    final weightLogRaw = prefs.getString(weightLogKey);
    final List<Map<String, dynamic>> weightLog = [];
    if (weightLogRaw != null) {
      try {
        final decoded = json.decode(weightLogRaw);
        if (decoded is List) {
          weightLog.addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
      } catch (_) {}
    }
    weightLog.removeWhere((e) => (e['date'] ?? '').toString() == today);
    weightLog.add({'date': today, 'kg': weight});
    weightLog.sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    await prefs.setString(weightLogKey, json.encode(weightLog));

    unawaited(AppRepository.writeWeightKg(ymd: today, kg: weight).catchError((_) {}));

    // ===== Social — حفظ محلي =====
    final ig = _selectedSocials.contains(_Social.instagram)
        ? _socialCtrls[_Social.instagram]!.text.trim()
        : '';
    final sc = _selectedSocials.contains(_Social.snapchat)
        ? _socialCtrls[_Social.snapchat]!.text.trim()
        : '';
    final tk = _selectedSocials.contains(_Social.tiktok)
        ? _socialCtrls[_Social.tiktok]!.text.trim()
        : '';

    await prefs.setString('social_instagram_$email', ig);
    await prefs.setString('social_snapchat_$email', sc);
    await prefs.setString('social_tiktok_$email', tk);

    // ====== كتابة على Firestore (Legacy root: users/{uid}) ======
    try {
      // تنبيه "بطيء" بدون ما نقطع العملية
      final slowTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المزامنة بطيئة قليلًا… جاري الحفظ على السحابة')),
        );
      });

      try {
        final social = <String, dynamic>{};
        if (ig.isNotEmpty) social['instagram'] = ig;
        if (sc.isNotEmpty) social['snapchat'] = sc;
        if (tk.isNotEmpty) social['tiktok'] = tk;

        await const LegacyUserRepository()
            .saveUserInputStep(
              gender: storeGender,
              age: age,
              heightCm: height,
              currentWeightKg: weight,
              bio: bioController.text.trim(),
              social: social,
              goal: goalToStore,
              goalType: goalToStore,
              caloriesNeeded: calculatedCalories,
              maintenanceCalories: maintenanceCalories,
              protein: protein,
              carbs: carbs,
              fat: fat,
              lifestyleScore: widget.lifestyleScore,
              activityFactor: activityFactor,
              macroCalculationNote: macroCalculationNote,
            )
            .timeout(const Duration(seconds: 45));
      } finally {
        slowTimer.cancel();
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'انتهى الوقت أثناء الحفظ على السحابة. إذا استمرت، غالبًا المشكلة من Firestore Rules أو App Check.',
            ),
          ),
        );
        setState(() => _saving = false);
      }
      return;
    } catch (e) {
      final raw = e.toString();
      if (kDebugMode) debugPrint('[UserInputPage] Firestore save failed: $raw');
      final hint = raw.contains('permission-denied')
          ? ' (غالبًا Firestore Rules تمنع الكتابة على users/{uid})'
          : '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ في السحابة: $raw$hint')),
        );
        setState(() => _saving = false);
      }
      return;
    }

    await prefs.setBool('lifestyleDone', true);
    await prefs.setBool('userDataEntered_$email', true);
    await prefs.setBool('lifestyleAssessmentCompleted_$email', true);

    if (!mounted) return;
    // ✅ مهم: نستخدم push بدل pushReplacement حتى تقدر ترجع وتعدّل بياناتك بسهولة.
    Navigator.pushNamed(context, '/set-goal');
    if (mounted) setState(() => _saving = false);
  }

  // ========= UI =========
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('بياناتك'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: cs.onSurface,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: cs.surface.withOpacity(0.54)),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(0.16),
                cs.primaryContainer.withOpacity(0.06),
                cs.surface,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -88,
                right: -70,
                child: _DecorativeOrb(color: cs.primary.withOpacity(0.20), size: 210),
              ),
              Positioned(
                top: 150,
                left: -96,
                child: _DecorativeOrb(color: cs.secondary.withOpacity(0.14), size: 230),
              ),
              SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 104, 16, 22),
                        children: [
                          _HeroProfileCard(
                            title: 'خلّ وازن يفهمك أكثر',
                            subtitle:
                                'هذه البيانات تساعد وازن يحسب السعرات والماكروز بطريقة أدق وتناسب هدفك الصحي.',
                            score: widget.lifestyleScore,
                          ),
                          const SizedBox(height: 14),

                          _SoftNotice(
                            text:
                                'اكتب بياناتك بدقة. تقدر تعدّلها لاحقًا من صفحة بياناتي بدون ما نخرب سجلك.',
                          ),
                          const SizedBox(height: 14),

                          _SectionCard(
                            title: 'بياناتك الصحية',
                            subtitle: 'الأساس اللي يُبنى عليه هدفك اليومي في وازن',
                            leading: Icons.monitor_heart_outlined,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _input(
                                        label: 'الوزن',
                                        controller: weightController,
                                        suffix: 'كجم',
                                        helperText: 'مثال: 78.5',
                                        validator: (val) {
                                          if (val == null || val.trim().isEmpty) {
                                            return 'يرجى إدخال الوزن';
                                          }
                                          final v = double.tryParse(val);
                                          if (v == null || v < 30 || v > 400) {
                                            return 'الوزن يجب أن يكون بين 30 و 400 كجم';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _input(
                                        label: 'الطول',
                                        controller: heightController,
                                        suffix: 'سم',
                                        helperText: 'مثال: 172',
                                        validator: (val) {
                                          if (val == null || val.trim().isEmpty) {
                                            return 'يرجى إدخال الطول';
                                          }
                                          final v = double.tryParse(val);
                                          if (v == null || v < 100 || v > 230) {
                                            return 'الطول يجب أن يكون بين 100 و 230 سم';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _dropdown<String>(
                                        label: 'الجنس',
                                        value: gender,
                                        options: const ['ذكر', 'أنثى'],
                                        onChanged: (val) => setState(() => gender = val),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _dropdown<int>(
                                        label: 'العمر',
                                        value: age,
                                        options: List<int>.generate(84, (i) => 16 + i),
                                        onChanged: (val) => setState(() => age = (val ?? 16)),
                                      ),
                                    ),
                                  ],
                                ),
                                _dropdown<String>(
                                  label: 'هدفك الصحي',
                                  value: selectedGoal,
                                  options: _goalOptions,
                                  onChanged: (val) => setState(() => selectedGoal = val),
                                  trailingIcon: Icons.keyboard_arrow_down_rounded,
                                ),
                                const SizedBox(height: 8),
                                _MiniHealthPreview(
                                  age: age,
                                  gender: gender,
                                  goal: selectedGoal,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          _SectionCard(
                            title: 'ملفك في وازن',
                            subtitle: 'نبذة بسيطة تظهر في صفحات المجتمع والوصفات لاحقًا',
                            leading: Icons.person_outline_rounded,
                            child: TextFormField(
                              controller: bioController,
                              maxLines: 4,
                              minLines: 3,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                labelText: 'النبذة (اختياري)',
                                hintText: 'مثال: هدفي أنزل دهون وأثبت على نمط صحي.',
                                alignLabelWithHint: true,
                                filled: true,
                                fillColor: cs.surface.withOpacity(0.72),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.70)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          _SectionCard(
                            title: 'حسابات التواصل',
                            subtitle: 'اختيارية، وتفيد لاحقًا في صفحة المجتمع أو الوصفات',
                            leading: Icons.alternate_email_rounded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _socialChip(_Social.instagram, 'Instagram', FontAwesomeIcons.instagram),
                                    _socialChip(_Social.snapchat, 'Snapchat', FontAwesomeIcons.snapchatGhost),
                                    _socialChip(_Social.tiktok, 'TikTok', FontAwesomeIcons.tiktok),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: Column(
                                    key: ValueKey(_selectedSocials.length),
                                    children: [
                                      if (_selectedSocials.contains(_Social.instagram))
                                        _socialField(_Social.instagram, '@username (Instagram)'),
                                      if (_selectedSocials.contains(_Social.snapchat))
                                        _socialField(_Social.snapchat, '@username (Snapchat)'),
                                      if (_selectedSocials.contains(_Social.tiktok))
                                        _socialField(_Social.tiktok, '@username (TikTok)'),
                                      if (_selectedSocials.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            'تقدر تتخطاها الآن وتضيفها لاحقًا من الملف الشخصي.',
                                            style: tt.bodySmall?.copyWith(
                                              color: cs.onSurface.withOpacity(0.58),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: _saving ? null : _saveAll,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text(
                                      'حفظ ومتابعة',
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                            ),
                          ),
                        ],
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

  // ========= Widgets =========
  Widget _socialChip(_Social s, String label, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedSocials.contains(s);
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 15),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (v) => setState(() {
        if (v) {
          _selectedSocials.add(s);
        } else {
          _selectedSocials.remove(s);
          _socialCtrls[s]!.clear();
        }
      }),
      selectedColor: cs.primary.withOpacity(0.14),
      backgroundColor: cs.surface.withOpacity(0.72),
      checkmarkColor: cs.primary,
      side: BorderSide(
        color: selected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.70),
      ),
      labelStyle: TextStyle(
        color: selected ? cs.primary : cs.onSurface,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }

  Widget _socialField(_Social s, String hint) {
    final cs = Theme.of(context).colorScheme;
    final icon = s == _Social.instagram
        ? FontAwesomeIcons.instagram
        : s == _Social.snapchat
            ? FontAwesomeIcons.snapchatGhost
            : FontAwesomeIcons.tiktok;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _socialCtrls[s],
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'اسم المستخدم',
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FaIcon(icon, size: 18, color: cs.primary),
          ),
          filled: true,
          fillColor: cs.surface.withOpacity(0.72),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.70)),
          ),
        ),
      ),
    );
  }

  Widget _input({
    required String label,
    required TextEditingController controller,
    String? suffix,
    String? helperText,
    TextInputType keyboardType = const TextInputType.numberWithOptions(decimal: true),
    String? Function(String?)? validator,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: helperText,
          filled: true,
          fillColor: cs.surface.withOpacity(0.72),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.70)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: cs.primary, width: 1.3),
          ),
        ),
        validator: validator,
      ),
    );
  }

  // Dropdown آمن — بدون رموز العمر والطول داخل الحقول
  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> options,
    required ValueChanged<T?> onChanged,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final filtered = options.where((e) => e != null).cast<T>().toList();
    final seen = <T>{};
    final unique = <T>[];
    for (final o in filtered) {
      if (seen.add(o)) unique.add(o);
    }
    final hasValue = value != null && unique.contains(value);
    final T? effectiveValue = hasValue ? value as T : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: DropdownButtonFormField<T>(
        value: effectiveValue,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: leadingIcon == null ? null : Icon(leadingIcon),
          suffixIcon: trailingIcon == null ? null : Icon(trailingIcon, color: cs.primary),
          filled: true,
          fillColor: cs.surface.withOpacity(0.72),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.70)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: cs.primary, width: 1.3),
          ),
        ),
        items: unique
            .map((opt) => DropdownMenuItem<T>(
                  value: opt,
                  child: Text(opt.toString()),
                ))
            .toList(),
        onChanged: onChanged,
        hint: Text('اختر $label'),
      ),
    );
  }
}

// ==============================
// تصميم فخم لصفحة بيانات المستخدم
// ==============================
class _HeroProfileCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int score;

  const _HeroProfileCard({
    required this.title,
    required this.subtitle,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.surface.withOpacity(isDark ? 0.78 : 0.94),
            cs.primary.withOpacity(isDark ? 0.14 : 0.075),
            cs.surface.withOpacity(isDark ? 0.70 : 0.88),
          ],
        ),
        border: Border.all(color: cs.primary.withOpacity(isDark ? 0.18 : 0.12)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(isDark ? 0.10 : 0.13),
            blurRadius: 34,
            spreadRadius: -8,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -72,
              end: -52,
              child: _DecorativeOrb(color: cs.primary.withOpacity(0.10), size: 168),
            ),
            PositionedDirectional(
              bottom: -96,
              start: -72,
              child: _DecorativeOrb(color: cs.secondary.withOpacity(0.08), size: 190),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 19, 18, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: cs.primary.withOpacity(0.12)),
                        ),
                        child: Text(
                          'إعداد خطتك في وازن',
                          style: tt.labelMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.66),
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.surface.withOpacity(isDark ? 0.45 : 0.68),
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(color: cs.primary.withOpacity(0.10)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'جاهزية نمط الحياة محفوظة، وباقي نضبط أرقامك النهائية بدقة.',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.72),
                                fontWeight: FontWeight.w800,
                                height: 1.45,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.095),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cs.primary.withOpacity(0.13)),
                            ),
                            child: Text(
                              score.toString(),
                              style: tt.titleMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftNotice extends StatelessWidget {
  final String text;
  const _SoftNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withOpacity(0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.54)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, color: cs.onTertiaryContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData leading;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(leading, color: cs.primary, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.58),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MiniHealthPreview extends StatelessWidget {
  final int age;
  final String? gender;
  final String? goal;

  const _MiniHealthPreview({
    required this.age,
    required this.gender,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withOpacity(0.10)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InfoPill(label: 'العمر', value: '$age سنة'),
          _InfoPill(label: 'الجنس', value: gender ?? 'غير محدد'),
          _InfoPill(label: 'الهدف', value: goal ?? 'غير محدد'),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.60)),
      ),
      child: RichText(
        text: TextSpan(
          style: tt.labelMedium?.copyWith(color: cs.onSurface),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: cs.onSurface.withOpacity(0.55)),
            ),
            TextSpan(
              text: value,
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecorativeOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _DecorativeOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  const _GlassCard({required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.58)),
        color: cs.surface.withOpacity(0.82),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: child,
        ),
      ),
    );
  }
}

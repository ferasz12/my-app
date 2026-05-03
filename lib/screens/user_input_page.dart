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

    final today = DateTime.now().toIso8601String().split('T').first;

    // حفظ القيم النهائية محليًا
    await prefs.setDouble('caloriesNeeded_$email', calculatedCalories);
    await prefs.setDouble('maintenanceCalories_$email', maintenanceCalories);
    await prefs.setDouble('protein_$email', protein);
    await prefs.setDouble('fat_$email', fat);
    await prefs.setDouble('carbs_$email', carbs);
    await prefs.setString('macroMode_$email', MacroPlanEngine.modeAuto);
    await prefs.setString('macroPlanId_$email', macroPlanId);
    await prefs.setInt('macrosUpdatedAt_$email', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('lastUpdated_$email', today);
    await prefs.setBool('goal_fat_shred_$email', _isFatShred(goalToStore));

    // سجل الوزن اليومي محليًا
    final historyKey = 'weightHistory_$email';
    final history = prefs.getStringList(historyKey) ?? [];
    final newEntry = {'date': today, 'weight': weight};
    history.removeWhere((item) => json.decode(item)['date'] == today);
    history.add(json.encode(newEntry));
    await prefs.setStringList(historyKey, history);

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
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بياناتك'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.55),
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(0.06),
                cs.surface,
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _GlassCard(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        children: [
                          Text('أدخل بياناتك',
                              textAlign: TextAlign.center,
                              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),

                          // تنبيه
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Text(
                              'يرجى الإجابة على جميع البيانات بشكل صحيح.',
                              style: tt.titleSmall?.copyWith(
                                color: cs.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ===== ملف شخصي =====
                          Text('كمل ملفك الشخصي', style: tt.titleMedium),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: bioController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'النبذة (اختياري)',
                              prefixIcon: Icon(Icons.info_outline),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ===== سوشيال =====
                          Text('حسابات التواصل (اختياري)', style: tt.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _socialChip(_Social.instagram, 'Instagram', FontAwesomeIcons.instagram),
                              _socialChip(_Social.snapchat, 'Snapchat', FontAwesomeIcons.snapchatGhost),
                              _socialChip(_Social.tiktok, 'TikTok', FontAwesomeIcons.tiktok),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_selectedSocials.contains(_Social.instagram))
                            _socialField(_Social.instagram, '@username (Instagram)'),
                          if (_selectedSocials.contains(_Social.snapchat))
                            _socialField(_Social.snapchat, '@username (Snapchat)'),
                          if (_selectedSocials.contains(_Social.tiktok))
                            _socialField(_Social.tiktok, '@username (TikTok)'),

                          const SizedBox(height: 16),

                          // ===== بياناتك الصحية =====
                          Text('بياناتك الصحية', style: tt.titleMedium),
                          _input(
                            label: 'الوزن (كجم)',
                            controller: weightController,
                            suffix: 'كجم',
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
                          _input(
                            label: 'الطول (سم)',
                            controller: heightController,
                            suffix: 'سم',
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
                          _dropdown<String>(
                            label: 'الجنس',
                            value: gender,
                            options: const ['ذكر', 'أنثى'],
                            onChanged: (val) => setState(() => gender = val),
                            icon: Icons.transgender,
                          ),
                          _dropdown<int>(
                            label: 'العمر',
                            value: age,
                            options: List<int>.generate(84, (i) => 16 + i),
                            onChanged: (val) => setState(() => age = (val ?? 16)),
                            icon: Icons.cake_outlined,
                          ),
                          _dropdown<String>(
                            label: 'هدفك الصحي',
                            value: selectedGoal,
                            options: _goalOptions,
                            onChanged: (val) => setState(() => selectedGoal = val),
                            icon: Icons.track_changes,
                          ),

                          const SizedBox(height: 20),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _saving ? null : _saveAll,
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('حفظ ومتابعة'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
        children: [FaIcon(icon, size: 16), const SizedBox(width: 6), Text(label)],
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
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: _socialCtrls[s],
        decoration: InputDecoration(
          labelText: 'اسم المستخدم',
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FaIcon(icon, size: 18, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _input({
    required String label,
    required TextEditingController controller,
    String? suffix,
    TextInputType keyboardType = const TextInputType.numberWithOptions(decimal: true),
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.start,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          prefixIcon: const Icon(Icons.edit_outlined),
        ),
        validator: validator,
      ),
    );
  }

  // Dropdown آمن
  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> options,
    required ValueChanged<T?> onChanged,
    IconData icon = Icons.arrow_drop_down,
  }) {
    final filtered = options.where((e) => e != null).cast<T>().toList();
    final seen = <T>{};
    final unique = <T>[];
    for (final o in filtered) {
      if (seen.add(o)) unique.add(o);
    }
    final hasValue = value != null && unique.contains(value);
    final T? effectiveValue = hasValue ? value as T : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<T>(
        value: effectiveValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
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
// تصميم Glass Card (فخم + ثابت)
// ==============================
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
        color: cs.surface.withOpacity(0.80),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: child,
        ),
      ),
    );
  }
}

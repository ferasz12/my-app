// lib/screens/my_data_page.dart — نسخة محدثة (تصغير بطاقات الماكروز + توحيد ستايل البطاقة الصحية)
import 'dart:async';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/legacy_user_repository.dart';

import '../utils/calorie_calculator.dart'; // calculateCalories(...)

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

  // أهداف يومية
  int waterMlTarget = 2000;
  int stepsTarget = 8000;
  double sleepHoursTarget = 7.5;

  // حسابات إضافية
  String? email;
  String? displayName;

  // منع تغيير الوزن قبل 7 أيام
  int? _lastWeightChangeAtMs;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentEmail =
          prefs.getString(_Prefs.currentEmail) ?? _auth.currentUser?.email ?? 'unknown_user';
      email = currentEmail;
      displayName = _auth.currentUser?.displayName ?? currentEmail;

      gender = prefs.getString('${_Prefs.gender}_$currentEmail') ?? gender;
      age = prefs.getInt('${_Prefs.age}_$currentEmail') ?? age;
      height = prefs.getDouble('${_Prefs.height}_$currentEmail') ?? height;
      weight = prefs.getDouble('${_Prefs.weight}_$currentEmail') ?? weight;
      goal = prefs.getString('${_Prefs.goal}_$currentEmail') ?? goal;
      goalFatShred = prefs.getBool('${_Prefs.goalFatShred}_$currentEmail') ?? false;
      lifestyleScore =
          prefs.getInt('${_Prefs.lifestyleScore}_$currentEmail') ?? lifestyleScore;
      _lastWeightChangeAtMs =
          prefs.getInt('${_Prefs.lastWeightChangeAt}_$currentEmail');

      _recalculate(useStoredIfAvailable: true);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل البيانات: $e';
      });
    }
  }

  void _recalculate({bool useStoredIfAvailable = false}) async {
    final activityFactor = _activityFromScore(lifestyleScore);

    maintenanceCalories = calculateCalories(
      age: age,
      gender: gender,
      weight: weight,
      height: height,
      activityFactor: activityFactor,
      goal: 'نمط حياة صحي',
    );

    if (goalFatShred || goal.trim() == 'تنشيف الدهون') {
      targetCalories = (maintenanceCalories * 0.78).roundToDouble();
      proteinG = (weight * 2.2).roundToDouble();
      fatG = (weight * 0.6).roundToDouble();
      carbsG =
          ((targetCalories - (proteinG * 4 + fatG * 9)) / 4).clamp(0, 9999).roundToDouble();
    } else {
      targetCalories = calculateCalories(
        age: age,
        gender: gender,
        weight: weight,
        height: height,
        activityFactor: activityFactor,
        goal: goal,
      );
      switch (goal) {
        case 'بناء العضلات':
          proteinG = (weight * 2.2).roundToDouble();
          fatG = (weight * 0.9).roundToDouble();
          break;
        case 'زيادة الوزن':
          proteinG = (weight * 1.8).roundToDouble();
          fatG = (weight * 1.0).roundToDouble();
          break;
        case 'إنقاص الوزن':
          proteinG = (weight * 2.0).roundToDouble();
          fatG = (weight * 0.8).roundToDouble();
          break;
        case 'ضبط مستوى السكر في الدم':
          final carbsKcal = targetCalories * 0.35;
          carbsG = (carbsKcal / 4).roundToDouble();
          final fatKcal = (targetCalories - carbsKcal) * 0.4;
          fatG = (fatKcal / 9).roundToDouble();
          final protKcal = targetCalories - carbsKcal - fatKcal;
          proteinG = (protKcal / 4).roundToDouble();
          break;
        default:
          proteinG = (weight * 2.0).roundToDouble();
          fatG = (weight * 0.8).roundToDouble();
      }
      if (goal != 'ضبط مستوى السكر في الدم') {
        carbsG =
            ((targetCalories - (proteinG * 4 + fatG * 9)) / 4).clamp(0, 9999).roundToDouble();
      }
    }

    waterMlTarget = math.max((weight * 35).round(), 2000);
    stepsTarget = _stepsFromLifestyle(lifestyleScore);
    sleepHoursTarget = 7.5;

    if (useStoredIfAvailable) {
      final prefs = await SharedPreferences.getInstance();
      final currentEmail = email ?? prefs.getString(_Prefs.currentEmail) ?? 'unknown_user';
      targetCalories =
          prefs.getDouble('${_Prefs.caloriesNeeded}_$currentEmail') ?? targetCalories;
      proteinG = prefs.getDouble('${_Prefs.protein}_$currentEmail') ?? proteinG;
      carbsG = prefs.getDouble('${_Prefs.carbs}_$currentEmail') ?? carbsG;
      fatG = prefs.getDouble('${_Prefs.fat}_$currentEmail') ?? fatG;
    }
    if (mounted) setState(() {});
  }

  double _activityFromScore(int s) {
    if (s <= 20) return 1.2;
    if (s <= 40) return 1.375;
    if (s <= 60) return 1.55;
    if (s <= 80) return 1.725;
    return 1.9;
  }

  int _stepsFromLifestyle(int s) {
    if (s <= 20) return 5000;
    if (s <= 40) return 7000;
    if (s <= 60) return 9000;
    if (s <= 80) return 11000;
    return 13000;
  }

  Future<void> _persistAll() async {
    final prefs = await SharedPreferences.getInstance();
    final currentEmail = email ?? prefs.getString(_Prefs.currentEmail) ?? 'unknown_user';

    await prefs.setString(_Prefs.currentEmail, currentEmail);
    await prefs.setString('${_Prefs.gender}_$currentEmail', gender);
    await prefs.setInt('${_Prefs.age}_$currentEmail', age);
    await prefs.setDouble('${_Prefs.height}_$currentEmail', height);
    await prefs.setDouble('${_Prefs.weight}_$currentEmail', weight);
    await prefs.setString('${_Prefs.goal}_$currentEmail', goal);
    await prefs.setBool('${_Prefs.goalFatShred}_$currentEmail', goalFatShred);
    await prefs.setInt('${_Prefs.lifestyleScore}_$currentEmail', lifestyleScore);
    await prefs.setDouble('${_Prefs.caloriesNeeded}_$currentEmail', targetCalories);
    await prefs.setDouble('${_Prefs.protein}_$currentEmail', proteinG);
    await prefs.setDouble('${_Prefs.carbs}_$currentEmail', carbsG);
    await prefs.setDouble('${_Prefs.fat}_$currentEmail', fatG);
    await prefs.setInt('${_Prefs.waterMlTarget}_$currentEmail', waterMlTarget);
    await prefs.setInt('${_Prefs.stepsTarget}_$currentEmail', stepsTarget);
    await prefs.setDouble('${_Prefs.sleepHoursTarget}_$currentEmail', sleepHoursTarget);

    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        // ✅ Legacy root (users/{uid}) هو المصدر الأساسي
        final now = Timestamp.now();
        final activityFactor = _activityFromScore(lifestyleScore);

        await const LegacyUserRepository().updateLegacyUserRoot(
          patch: {
            'gender': gender,
            'age': age,
            'heightCm': height,
            'currentWeightKg': weight,
            'goal': goal,
            'goalType': goal,
            'metrics.caloriesNeeded': targetCalories,
            'metrics.maintenanceCalories': maintenanceCalories,
            'metrics.protein': proteinG,
            'metrics.carbs': carbsG,
            'metrics.fat': fatG,
            'metrics.lifestyleScore': lifestyleScore,
            'metrics.activityFactor': activityFactor,
            if (_lastWeightChangeAtMs != null) 'metrics.lastWeightChangeAtMs': _lastWeightChangeAtMs,
            'metrics.updatedAt': now,
            'flags.userDataEntered': true,
            'flags.updatedAt': now,
            'updatedAt': now,
          },
          stepAtLeast: 2,
        );
      }
    } catch (e) {
      debugPrint('[MyDataPage] Firestore persist failed: $e');
    }
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
          actions: [
            TextButton(onPressed: _openHealthCard, child: const Text('عرض البطاقة الصحية')),
            IconButton(onPressed: _openEditBottomSheet, icon: const Icon(Icons.edit_rounded)),
            PopupMenuButton<String>(
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'goal', child: Text('تغيير الهدف')),
                PopupMenuItem(value: 'targets', child: Text('ضبط الأهداف')),
                PopupMenuItem(value: 'export', child: Text('تصدير JSON')),
                PopupMenuItem(value: 'import', child: Text('استيراد JSON')),
              ],
              onSelected: (v) async {
                if (v == 'goal') _openGoalSelector();
                if (v == 'targets') _openTargetsBottomSheet();
                if (v == 'export') await _exportJson();
                if (v == 'import') await _importJson();
              },
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _Error(message: _error!, onRetry: _bootstrap)
                  : LayoutBuilder(builder: (ctx, box) {
                      final w = box.maxWidth;
                      final columns = w >= 1100 ? 3 : w >= 700 ? 2 : 1;
                      final gutter = 12.0;
                      final padH = w < 380 ? 10.0 : 16.0;
                      final bmiVal = _bmi(weight, height);
                      final bmiClass = _bmiClass(bmiVal);

                      return ListView(
                        padding: EdgeInsets.fromLTRB(padH, 10, padH, 20),
                        children: [
                          // السعرات والماكروز
                          _Section(
                            title: 'السعرات والماكروز',
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // أهداف يومية
                          _Section(
                            title: 'أهداف يومية',
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
                      );
                    }),
        ),
      ),
    );
  }

  // إجراءات
  Future<void> _openEditBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EditBasicsSheet(
        initial: BasicsData(
            name: displayName,
            gender: gender,
            age: age,
            height: height,
            weight: weight,
            lifestyleScore: lifestyleScore),
        onSubmit: (upd) async {
          displayName =
              upd.name?.trim().isEmpty == true ? displayName : upd.name ?? displayName;
          gender = upd.gender;
          age = upd.age;
          height = upd.height;
          // قفل تغيير الوزن 7 أيام
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
                  email ?? prefs.getString(_Prefs.currentEmail) ?? 'unknown_user';
              await prefs.setInt(
                  '${_Prefs.lastWeightChangeAt}_$currentEmail', _lastWeightChangeAtMs!);
            }
          }
          lifestyleScore = upd.lifestyleScore;
          _recalculate();
          await _persistAll();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _openGoalSelector() async {
    final selected =
        await showDialog<String>(context: context, builder: (ctx) => _GoalDialog(initialSelected: goal));
    if (selected != null) {
      goal = selected;
      goalFatShred = selected == 'تنشيف الدهون';
      _recalculate();
      await _persistAll();
      if (mounted) setState(() {});
    }
  }

  Future<void> _openTargetsBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TargetsSheet(
        waterMl: waterMlTarget,
        steps: stepsTarget,
        sleepHours: sleepHoursTarget,
        onSubmit: (w, s, h) async {
          waterMlTarget = w;
          stepsTarget = s;
          sleepHoursTarget = h;
          await _persistAll();
          if (mounted) setState(() {});
        },
      ),
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
  Future<void> _exportJson() async {
    final prefs = await SharedPreferences.getInstance();
    final currentEmail = email ?? prefs.getString(_Prefs.currentEmail) ?? 'unknown_user';
    final json = await exportUserDataToJson(prefs, currentEmail);
    if (!mounted) return;
    await showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('تصدير JSON'),
              content: SelectableText(json, maxLines: 10),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))
              ],
            ));
  }

  Future<void> _importJson() async {
    final controller = TextEditingController();
    await showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('استيراد JSON'),
              content: TextField(
                  controller: controller,
                  maxLines: 8,
                  decoration:
                      const InputDecoration(hintText: 'ألصق JSON هنا')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final currentEmail =
                          email ?? prefs.getString(_Prefs.currentEmail) ?? 'unknown_user';
                      await importUserDataFromJson(
                          prefs, currentEmail, controller.text);
                      Navigator.pop(c);
                      await _bootstrap();
                    },
                    child: const Text('استيراد')),
              ],
            ));
  }
}

// ====== Widgets ======

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.health_and_safety_rounded, color: cs.primary, size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }
}

// بطاقة السعرات (أرقام فقط + 🔥)
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
        color: cs.secondaryContainer,
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
        Row(children: [
          Text('${total.toStringAsFixed(0)}',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(width: 4),
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('kcal', style: theme.textTheme.labelLarge)),
          
        ])
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
              Row(children: [
                Text(grams.toStringAsFixed(0),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('غ', style: theme.textTheme.labelMedium)),
                const Spacer(),
                _KcalChip(value: kcal),
              ]),
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
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text('${value.toStringAsFixed(0)} كال',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              )),
    );
  }
}


class _GoalPill extends StatelessWidget {
  const _GoalPill({required this.icon, required this.title, required this.value, this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  Color _bg(ColorScheme cs){
    if(title.contains('الماء')) return cs.primaryContainer.withOpacity(.8);
    if(title.contains('الخطوات')) return cs.tertiaryContainer.withOpacity(.8);
    if(title.contains('النوم')) return cs.secondaryContainer.withOpacity(.8);
    return cs.surfaceContainer;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg(cs),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, color: cs.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// شبكة متكيفة
class _AdaptiveGrid extends StatelessWidget {
  const _AdaptiveGrid({required this.children, required this.columns, this.gutter = 12});
  final List<Widget> children;
  final int columns;
  final double gutter;
  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
          children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gutter),
          children[i]
        ]
      ]);
    }
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, math.min(i + columns, children.length));
      rows.add(Row(children: [
        for (int j = 0; j < slice.length; j++) ...[
          if (j > 0) SizedBox(width: gutter),
          Expanded(child: slice[j])
        ]
      ]));
      if (i + columns < children.length) rows.add(SizedBox(height: gutter));
    }
    return Column(children: rows);
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة')),
        ]),
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
    final pct = (value / 35).clamp(0.0, 1.0);
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
  });
  final String name, gender, goal, bmiClass;
  final int age, steps, waterMl;
  final double height, weight, calories, protein, carbs, fat, sleepH, bmi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onPrim = cs.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: const [
            Icon(Icons.badge_rounded),
            SizedBox(width: 8),
            Text('بطاقتي الصحية', style: TextStyle(fontWeight: FontWeight.w800))
          ]),
          const SizedBox(height: 12),
          // بطاقة رئيسية بألوان من الثيم لضمان التوافق مع Light/Dark
          Container(
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.secondaryContainer,
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      name.characters.first.toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: onPrim, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          _ChipWhite(icon: Icons.flag_rounded, label: goal, darkText: onPrim),
                          _ChipWhite(
                              icon: Icons.monitor_heart_rounded,
                              label: 'BMI ${bmi.toStringAsFixed(1)} • $bmiClass',
                              darkText: onPrim),
                        ]),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _ChipWhite(icon: Icons.wc_rounded, label: gender, darkText: onPrim),
                  _ChipWhite(icon: Icons.cake_rounded, label: '$age سنة', darkText: onPrim),
                  _ChipWhite(icon: Icons.height, label: '${height.toStringAsFixed(0)} سم', darkText: onPrim),
                  _ChipWhite(icon: Icons.monitor_weight, label: '${weight.toStringAsFixed(1)} كجم', darkText: onPrim),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [
                    Icon(Icons.local_fire_department_rounded),
                    SizedBox(width: 6),
                    Text('هدف السعرات والماكروز',
                        style: TextStyle(fontWeight: FontWeight.w800))
                  ]),
                  const SizedBox(height: 6),
                  Text('السعرات: ${calories.toStringAsFixed(0)} كال'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Text('بروتين: ${protein.toStringAsFixed(0)} جم')),
                    Expanded(child: Text('كارب: ${carbs.toStringAsFixed(0)} جم')),
                    Expanded(child: Text('دهون: ${fat.toStringAsFixed(0)} جم')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text('الماء: ${waterMl} مل')),
                    Expanded(child: Text('الخطوات: $steps')),
                    Expanded(child: Text('النوم: ${sleepH.toStringAsFixed(1)} س')),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipWhite extends StatelessWidget {
  const _ChipWhite({required this.icon, required this.label, this.darkText});
  final IconData icon;
  final String label;
  final Color? darkText; // لتلوين النص حسب الثيم
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: darkText ?? Colors.white),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: darkText ?? Colors.white)),
      ]),
    );
  }
}

// Sheets & Dialogs
class BasicsData {
  final String? name;
  final String gender;
  final int age;
  final double height;
  final double weight;
  final int lifestyleScore;
  const BasicsData({
    required this.name,
    required this.gender,
    required this.age,
    required this.height,
    required this.weight,
    required this.lifestyleScore,
  });
}

class _EditBasicsSheet extends StatefulWidget {
  const _EditBasicsSheet({required this.initial, required this.onSubmit});
  final BasicsData initial;
  final Future<void> Function(BasicsData) onSubmit;
  @override
  State<_EditBasicsSheet> createState() => _EditBasicsSheetState();
}

class _EditBasicsSheetState extends State<_EditBasicsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.initial.name ?? '');
  late String gender = widget.initial.gender;
  late double height = widget.initial.height;
  late double weight = widget.initial.weight;
  late int age = widget.initial.age;
  late int lifestyleScore = widget.initial.lifestyleScore;

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: view),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: const [
              Icon(Icons.edit_note_rounded),
              SizedBox(width: 8),
              Text('تعديل البيانات الأساسية',
                  style: TextStyle(fontWeight: FontWeight.w800))
            ]),
            const SizedBox(height: 12),
            TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'الاسم (اختياري)',
                    prefixIcon: Icon(Icons.person_outline_rounded))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                value: gender,
                decoration: const InputDecoration(
                    labelText: 'الجنس', prefixIcon: Icon(Icons.wc_rounded)),
                items: const [
                  DropdownMenuItem(value: 'ذكر', child: Text('ذكر')),
                  DropdownMenuItem(value: 'أنثى', child: Text('أنثى'))
                ],
                onChanged: (v) => setState(() => gender = v ?? 'ذكر')),
            const SizedBox(height: 12),
            TextFormField(
                initialValue: age.toString(),
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                decoration: const InputDecoration(
                    labelText: 'العمر (سنة)', prefixIcon: Icon(Icons.cake_rounded)),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 10 || n > 100) return 'أدخل عمرًا بين 10 و100';
                  return null;
                },
                onSaved: (v) => age = int.parse(v!)),
            const SizedBox(height: 12),
            TextFormField(
                initialValue: height.toStringAsFixed(0),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'الطول (سم)', prefixIcon: Icon(Icons.height)),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 100 || n > 250) return 'أدخل طولًا واقعيًا (100 - 250)';
                  return null;
                },
                onSaved: (v) => height = double.parse(v!)),
            const SizedBox(height: 12),
            TextFormField(
                initialValue: weight.toStringAsFixed(1),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الوزن (كجم)', prefixIcon: Icon(Icons.monitor_weight)),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 25 || n > 400) return 'أدخل وزنًا واقعيًا (25 - 400)';
                  return null;
                },
                onSaved: (v) => weight = double.parse(v!)),
            const SizedBox(height: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('نمط الحياة (0 خامل - 100 عالٍ جدًا)',
                  style: Theme.of(context).textTheme.labelLarge),
              Slider(
                  value: lifestyleScore.toDouble(),
                  onChanged: (v) => setState(() => lifestyleScore = v.round()),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: lifestyleScore.toString()),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: () async {
                  if (_formKey.currentState?.validate() != true) return;
                  _formKey.currentState?.save();
                  await widget.onSubmit(BasicsData(
                      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                      gender: gender,
                      age: age,
                      height: height,
                      weight: weight,
                      lifestyleScore: lifestyleScore));
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('حفظ')),
          ]),
        ),
      ),
    );
  }
}


// أوصاف الأهداف لتظهر عند الضغط على علامة الاستفهام
const Map<String, String> kGoalDescriptions = {
  'إنقاص الوزن': 'هدف يركز على خفض الوزن تدريجيًا مع الحفاظ على الكتلة العضلية قدر الإمكان.',
  'تنشيف الدهون': 'هذا الهدف يجعل جسمك مشدودًا أكثر ويقلل نسبة الدهون تحت الجلد مع الحفاظ على العضلات.',
  'بناء العضلات': 'زيادة الكتلة والقوة العضلية مع برنامج غذائي وسعري مناسب للتضخيم النظيف.',
  'زيادة الوزن': 'رفع الوزن بشكل صحي ومتوازن لمن لديهم نحافة أو كتلة منخفضة.',
  'نمط حياة صحي': 'تركيز عام على عادات مفيدة: نوم جيد، حركة يومية، طعام متوازن بدون ضغط على الأرقام.',
  'زيادة النشاط اليومي': 'رفع معدل الحركة والخطوات اليومية لتحسين الحرق والصحة القلبية.',
  'ضبط مستوى السكر في الدم': 'تقليل الارتفاعات الحادة في السكر مع توزيع كارب محسوب وتركيز على بروتين ودهون صحية.',
};
class _GoalDialog extends StatefulWidget {
  const _GoalDialog({this.initialSelected});
  final String? initialSelected;
  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late String selected;
  @override
  void initState() {
    super.initState();
    selected = widget.initialSelected ?? 'نمط حياة صحي';
  }
  @override
  Widget build(BuildContext context) {
    const items = [
      'إنقاص الوزن',
      'تنشيف الدهون',
      'بناء العضلات',
      'زيادة الوزن',
      'نمط حياة صحي',
      'زيادة النشاط اليومي',
      'ضبط مستوى السكر في الدم',
    ];
    return AlertDialog(
      title: const Text('اختر الهدف'),
      content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final v in items)
  InkWell(
    onTap: () => setState(() => selected = v),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<String>(
        value: v,
        groupValue: selected,
        onChanged: (_) => setState(() => selected = v),
      ),
      title: Text(v),
      trailing: IconButton(
        icon: const Icon(Icons.help_outline_rounded),
        tooltip: 'عن هذا الهدف',
        onPressed: () {
          final desc = kGoalDescriptions[v] ?? 'لا يوجد وصف متاح.';
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(v),
              content: Text(desc),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('تحديد'))
      ],
    );
  }
}

class _TargetsSheet extends StatefulWidget {
  const _TargetsSheet(
      {required this.waterMl,
      required this.steps,
      required this.sleepHours,
      required this.onSubmit});
  final int waterMl;
  final int steps;
  final double sleepHours;
  final Future<void> Function(int waterMl, int steps, double sleepH) onSubmit;
  @override
  State<_TargetsSheet> createState() => _TargetsSheetState();
}

class _TargetsSheetState extends State<_TargetsSheet> {
  late int water = widget.waterMl;
  late int steps = widget.steps;
  late double sleepH = widget.sleepHours;
  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: view),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: const [
            Icon(Icons.settings_suggest_rounded),
            SizedBox(width: 8),
            Text('ضبط الأهداف اليومية', style: TextStyle(fontWeight: FontWeight.w800))
          ]),
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
                await widget.onSubmit(water, steps, sleepH);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('حفظ')),
        ]),
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
  static const protein = 'protein';
  static const carbs = 'carbs';
  static const fat = 'fat';
  static const lastWeightChangeAt = 'lastWeightChangeAt';
  static const waterMlTarget = 'waterMlTarget';
  static const stepsTarget = 'stepsTarget';
  static const sleepHoursTarget = 'sleepHoursTarget';
}

// تصدير/استيراد JSON
Future<String> exportUserDataToJson(SharedPreferences prefs, String email) async {
  final m = <String, dynamic>{
    'gender': prefs.getString('gender_$email'),
    'age': prefs.getInt('age_$email'),
    'height': prefs.getDouble('height_$email'),
    'weight': prefs.getDouble('weight_$email'),
    'goal': prefs.getString('goal_$email'),
    'goal_fat_shred': prefs.getBool('goal_fat_shred_$email'),
    'lifestyleScore': prefs.getInt('lifestyleScore_$email'),
    'caloriesNeeded': prefs.getDouble('caloriesNeeded_$email'),
    'protein': prefs.getDouble('protein_$email'),
    'carbs': prefs.getDouble('carbs_$email'),
    'fat': prefs.getDouble('fat_$email'),
  };
  return jsonEncode(m);
}

Future<void> importUserDataFromJson(
    SharedPreferences prefs, String email, String json) async {
  final m = jsonDecode(json) as Map<String, dynamic>;
  if (m['gender'] != null) await prefs.setString('gender_$email', m['gender'] as String);
  if (m['age'] != null) await prefs.setInt('age_$email', (m['age'] as num).toInt());
  if (m['height'] != null) await prefs.setDouble('height_$email', (m['height'] as num).toDouble());
  if (m['weight'] != null) await prefs.setDouble('weight_$email', (m['weight'] as num).toDouble());
  if (m['goal'] != null) await prefs.setString('goal_$email', m['goal'] as String);
  if (m['goal_fat_shred'] != null) {
    final v = m['goal_fat_shred'];
    await prefs.setBool('goal_fat_shred_$email', (v is bool) ? v : v.toString() == 'true');
  }
  if (m['lifestyleScore'] != null) {
    await prefs.setInt('lifestyleScore_$email', (m['lifestyleScore'] as num).toInt());
  }
  if (m['caloriesNeeded'] != null) {
    await prefs.setDouble('caloriesNeeded_$email', (m['caloriesNeeded'] as num).toDouble());
  }
  if (m['protein'] != null) await prefs.setDouble('protein_$email', (m['protein'] as num).toDouble());
  if (m['carbs'] != null) await prefs.setDouble('carbs_$email', (m['carbs'] as num).toDouble());
  if (m['fat'] != null) await prefs.setDouble('fat_$email', (m['fat'] as num).toDouble());
}

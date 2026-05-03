// lib/screens/set_goal_page.dart
import 'dart:async'; // ⬅️ Timer لرسالة "المزامنة بطيئة"
import 'dart:convert'; // ⬅️ json.encode/decode
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ⬅️ Firestore

import '../providers/goal_provider.dart';
import '../data/legacy_user_repository.dart';
import '../services/goal_service.dart';
import '../models/weight_goal.dart';
import '../utils/calorie_calculator.dart';

class SetGoalPage extends StatefulWidget {
  const SetGoalPage({
    super.key,
    this.embedded = false, // وضع مضمّن داخل تبويب
    this.onSaved, // كولباك اختياري بعد الحفظ في الوضع المضمّن
  });

  final bool embedded;
  final VoidCallback? onSaved;

  @override
  State<SetGoalPage> createState() => _SetGoalPageState();
}

class _SetGoalPageState extends State<SetGoalPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _currentCtrl;
  late TextEditingController _targetCtrl;
  DateTime _targetDate = DateTime.now().add(const Duration(days: 90));

  int _age = 25;
  String _activity = 'moderate'; // 'low' | 'moderate' | 'high'
  double _height = 170.0;

  // منع تعديل الوزن الحالي هنا (يتحدث من صفحة بياناتي كل ٧ أيام)
  bool _weightEditable = false;
  DateTime? _nextWeightEditAllowedAt;

  // سجل الأهداف (نحتفظ بآخر 10)
  List<Map<String, dynamic>> _goalHistory = [];

  bool _loading = true;
  bool _saving = false; // ⬅️ لمنع النقر المكرر وإظهار مؤشر

  @override
  void initState() {
    super.initState();
    _currentCtrl = TextEditingController();
    _targetCtrl = TextEditingController();
    _loadInitial();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAddGoalSheet() async {
    final ctrl = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('إضافة هدف', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'مثال: أبي أنحف ٥ كجم خلال هذا الشهر',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final t = ctrl.text.trim();
                    if (t.isEmpty) return;
                    Navigator.pop(ctx, t);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('حفظ'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (value is String && value.trim().isNotEmpty) {
      await _appendFreeNoteHistory(value.trim());
    }
  }

  Future<void> _appendFreeNoteHistory(String note) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    final list = _loadGoalHistory(prefs, email);
    final entry = {
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'note',
      'text': note,
    };
    list.insert(0, entry);
    while (list.length > 10) list.removeLast();
    await prefs.setString('goal_history_$email', json.encode(list));
    setState(() => _goalHistory = list);
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';

    final weight = prefs.getDouble('weight_$email') ?? 70.0;
    final age = prefs.getInt('age_$email') ?? 25;
    final level = prefs.getString('activityLevel_$email') ?? 'moderate';
    final height = prefs.getDouble('height_$email') ?? 170.0;

    // قراءة آخر تاريخ تم فيه تعديل الوزن (من صفحة بياناتي)
    DateTime? lastUpdate;
    final lastStr = prefs.getString('weight_last_updated_$email');
    if (lastStr != null) {
      try {
        lastUpdate = DateTime.parse(lastStr);
      } catch (_) {}
    }
    DateTime? nextAllowed;
    if (lastUpdate != null) {
      nextAllowed = lastUpdate.add(const Duration(days: 7));
    }
    _weightEditable = false; // هذه الصفحة لا تسمح بتعديل الوزن الحالي
    _nextWeightEditAllowedAt = nextAllowed;

    // تاريخ افتراضي للهدف (٣ أشهر) + وزن مستهدف تخميني
    final suggestedTarget = (weight - 5).clamp(30.0, 250.0);

    // تحميل سجل الأهداف
    _goalHistory = _loadGoalHistory(prefs, email);

    _currentCtrl.text = weight.toStringAsFixed(1);
    _targetCtrl.text = suggestedTarget.toStringAsFixed(1);

    setState(() {
      _age = age;
      _activity = _mapActivityLevel(level); // توحيد القيمة
      _height = height;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _loadGoalHistory(SharedPreferences prefs, String email) {
    final raw = prefs.getString('goal_history_$email');
    if (raw == null) return [];
    try {
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _appendGoalHistory(WeightGoal g) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';

    final entry = {
      'createdAt': DateTime.now().toIso8601String(),
      'current': g.currentWeight,
      'target': g.targetWeight,
      'targetDate': g.targetDate.toIso8601String(),
      'weekly': g.weeklyChangeKg,
      'dailyDelta': g.dailyCalorieDelta,
      'difficulty': g.difficulty.name, // نخزّن الإنجليزي ونحوّله عند العرض
    };

    final list = _loadGoalHistory(prefs, email);
    list.insert(0, entry);
    // احتفظ بآخر 10 فقط
    while (list.length > 10) list.removeLast();

    await prefs.setString('goal_history_$email', json.encode(list));
    setState(() => _goalHistory = list);
  }

  String _mapActivityLevel(String v) {
    switch (v) {
      case 'sedentary':
      case 'low':
        return 'low';
      case 'active':
      case 'very_active':
      case 'high':
        return 'high';
      case 'moderate':
      case 'light':
      default:
        return 'moderate';
    }
  }

  double _factorFromActivityKey(String k) {
    switch (k) {
      case 'low':
        return 1.2;
      case 'high':
        return 1.725;
      case 'moderate':
      default:
        return 1.55;
    }
  }

  int _weeksBetween(DateTime from, DateTime to) {
    final days = to.difference(from).inDays;
    return (days / 7).ceil().clamp(1, 520);
  }

  List<FlSpot> _buildSpots(double current, double target, DateTime targetDate) {
    final weeks = _weeksBetween(DateTime.now(), targetDate);
    final dw = (target - current) / weeks;
    return List.generate(weeks + 1, (i) => FlSpot(i.toDouble(), current + dw * i));
  }

  Future<void> _handleSave(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    setState(() => _saving = true);
    FocusScope.of(context).unfocus();

    final goalProv = context.read<GoalProvider>();

    final current = double.tryParse(_currentCtrl.text) ?? 70.0;
    final target = double.tryParse(_targetCtrl.text) ?? (current - 5);

    final built = goalProv.buildGoal(
      currentWeight: current,
      targetWeight: target,
      targetDate: _targetDate,
      age: _age,
      activityLevel: _activity,
    );

    // -------- 1) حاول الحفظ على السحابة (بدون Timeout قاسي) --------
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    bool cloudSaved = false;

    if (uid != null) {
      Timer? slowTimer;
      slowTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المزامنة بطيئة قليلًا… جاري الحفظ على السحابة')),
        );
      });

      try {
        await GoalService.saveGoal(uid, built);
        await const LegacyUserRepository().saveGoalStep(goal: built);
        cloudSaved = true;
      } on FirebaseException catch (e, st) {
        debugPrint('[SetGoalPage] cloud save failed: ${e.code} ${e.message}\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم الحفظ محليًا، وتعذّر حفظ السحابة الآن: ${e.code}')),
          );
        }
      } catch (e, st) {
        debugPrint('[SetGoalPage] cloud save failed: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الحفظ محليًا، وتعذّرت المزامنة الآن')),
          );
        }
      } finally {
        slowTimer?.cancel();
      }
    }

    // -------- 2) احفظ دائمًا محليًا كـ fallback (حتى لو نجح السحابي) --------
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ?? 'unknown_user';
      await prefs.setString('goal_difficulty_$email', built.difficulty.name);
      await prefs.setDouble('goal_weekly_$email', built.weeklyChangeKg);
      await prefs.setDouble('goal_dailyDelta_$email', built.dailyCalorieDelta);
      await prefs.setString('goal_note_$email', built.analysisNote);
      await prefs.setDouble('goal_current_$email', built.currentWeight);
      await prefs.setDouble('goal_target_$email', built.targetWeight);
      await prefs.setString('goal_targetDate_$email', built.targetDate.toIso8601String());
    } catch (e) {
      debugPrint('[SetGoalPage] local fallback save failed: $e');
    }

    // -------- 3) سجل في السجل المحلي + احسب الماكروز دائماً --------
    await _appendGoalHistory(built);
    await _computeAndStoreMacros();

    // -------- 4) حالة الأونبوردنغ تُحدَّث في الجذر داخل users/{uid} عبر LegacyUserRepository --------

    // -------- 5) حدّث الـ Provider وتقدّم للخطوة التالية دائماً --------
    goalProv.setGoal(built);

    if (!mounted) return;

    if (widget.embedded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cloudSaved ? '✅ حُفظ الهدف' : '✅ حُفظ الهدف محليًا')),
      );
      widget.onSaved?.call();
    } else {
      Navigator.pushReplacementNamed(context, '/summary');
    }

    if (mounted) setState(() => _saving = false);
  }

  /// يقرأ (الجنس/الطول/الوزن/العمر/الهدف) من التخزين
  /// يحسب السعرات حسب النشاط (من Lifestyle) ثم يحسب الماكروز ويخزنها.
  Future<void> _computeAndStoreMacros() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';

    final String gender = prefs.getString('gender_$email') ?? 'ذكر';
    final double weight = prefs.getDouble('weight_$email') ?? (double.tryParse(_currentCtrl.text) ?? 70.0);
    final double height = prefs.getDouble('height_$email') ?? _height;
    final int age = prefs.getInt('age_$email') ?? _age;
    final String goal = prefs.getString('goal_$email') ?? 'نمط حياة صحي';

    final double activityFactor = _factorFromActivityKey(_activity);

    final double calculatedCalories = calculateCalories(
      age: age,
      gender: gender,
      weight: weight,
      height: height,
      activityFactor: activityFactor,
      goal: goal,
    );

    final double protein = weight * 2.0;
    final double fat = weight * 0.8;
    final double rawCarbs = (calculatedCalories - (protein * 4 + fat * 9)) / 4.0;
    final double carbs = rawCarbs.isFinite ? (rawCarbs < 0 ? 0.0 : rawCarbs) : 0.0;

    await prefs.setDouble('caloriesNeeded_$email', calculatedCalories);
    await prefs.setDouble('protein_$email', protein);
    await prefs.setDouble('fat_$email', fat);
    await prefs.setDouble('carbs_$email', carbs);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final goalProv = context.watch<GoalProvider>();

    final current = double.tryParse(_currentCtrl.text) ?? 70.0;
    final target = double.tryParse(_targetCtrl.text) ?? (current - 5);

    final tempGoal = goalProv.buildGoal(
      currentWeight: current,
      targetWeight: target,
      targetDate: _targetDate,
      age: _age,
      activityLevel: _activity,
    );

    final spots = _buildSpots(current, target, _targetDate);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final content = SafeArea(
      top: !widget.embedded,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Form(
          key: _formKey,
          child: AnimatedPadding(
            padding: EdgeInsets.only(bottom: bottomInset),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              children: [
                if (!widget.embedded) ...[
                  _SGHeader(title: 'ضع هدفك'),
                  const SizedBox(height: 8),
                ],

                // ---------------- البطاقة: بيانات الإدخال الأساسية ----------------
                _SGCard(
                  title: 'بيانات الهدف',
                  icon: Icons.flag_circle_outlined,
                  child: Column(
                    children: [
                      _SGField(
                        label: 'وزنك الحالي',
                        controller: _currentCtrl,
                        enabled: false,
                        prefixText: 'كجم  ',
                        helper: _nextWeightEditAllowedAt == null
                            ? 'يتم التحديث من صفحة "بياناتي".'
                            : 'يمكن تعديل الوزن من "بياناتي" بعد: ${_formatDate(_nextWeightEditAllowedAt!)}',
                        suffixIcon: Icons.lock,
                      ),
                      const SizedBox(height: 10),
                      _SGField(
                        label: 'الوزن المستهدف',
                        controller: _targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done, // ✅ يغلق الكيبورد بزر تم
                        onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                        prefixText: 'كجم  ',
                        onChanged: (_) => setState(() {}),
                        validator: _numValidator,
                      ),
                      const SizedBox(height: 12),

                      // ✅ صف متكّيف لمنع أي Overflow
                      _InlineAdaptiveRow(
                        left: _SGInfoPill(
                          icon: Icons.event_outlined,
                          text: 'تاريخ الوصول: ${_formatDate(_targetDate)}',
                        ),
                        right: TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime.now().add(const Duration(days: 1)),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                              initialDate: _targetDate,
                            );
                            if (picked != null) setState(() => _targetDate = picked);
                          },
                          icon: const Icon(Icons.edit_calendar),
                          label: const Text('تغيير التاريخ'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ---------------- البطاقة: مسار الوزن (الرسم) ----------------
                _SGCard(
                  title: 'مسار الوزن المتوقع',
                  icon: Icons.show_chart_rounded,
                  child: SizedBox(
                    height: 240,
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: _weeksBetween(DateTime.now(), _targetDate).toDouble(),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, meta) => Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  v.toStringAsFixed(0),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                // عرض كل 4 أسابيع
                                if (value % 4 != 0) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'أسبوع ${value.toInt()}',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary.withOpacity(.25),
                                  Theme.of(context).colorScheme.secondary.withOpacity(.12),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: Theme.of(context).dividerColor.withOpacity(.35),
                            strokeWidth: 0.5,
                          ),
                          getDrawingVerticalLine: (v) => FlLine(
                            color: Theme.of(context).dividerColor.withOpacity(.25),
                            strokeWidth: 0.5,
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(
                            color: Theme.of(context).dividerColor.withOpacity(.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ---------------- البطاقة: تحليل الخطة ----------------
                _SGCard(
                  title: 'تحليل الخطة',
                  icon: Icons.analytics_outlined,
                  child: _AnalysisCard(goal: tempGoal, height: _height),
                ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _openAddGoalSheet,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('إضافة هدف'),
                  ),
                ),

                if (_goalHistory.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _SGCard(
                    title: 'آخر الأهداف',
                    icon: Icons.history_edu_outlined,
                    child: _GoalHistoryList(history: _goalHistory),
                  ),
                ],

                const SizedBox(height: 18),

                // زر الحفظ
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _handleSave(context),
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(widget.embedded ? 'حفظ' : 'حفظ والانتقال'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return content; // لا AppBar في الوضع المضمّن
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ضع هدفك')),
      resizeToAvoidBottomInset: true, // ✅ يدفع المحتوى فوق الكيبورد
      body: content,
    );
  }

  String _formatDate(DateTime d) => d.toLocal().toString().split(' ').first;

  String? _numValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'أدخل قيمة صحيحة';
    final d = double.tryParse(v);
    if (d == null || d <= 0) return 'أدخل رقمًا أكبر من صفر';
    return null;
  }
}

// ==============================
// بطاقة التحليل (بدون تغيير للمنطق)
// ==============================
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.goal, required this.height});
  final WeightGoal goal;
  final double height;

  String get statusText {
    switch (goal.difficulty) {
      case GoalDifficulty.easy:
        return 'سهل';
      case GoalDifficulty.feasible:
        return 'ممكن';
      case GoalDifficulty.hard:
        return 'صعب';
      case GoalDifficulty.unrealistic:
        return 'غير صحي/غير واقعي';
    }
  }

  double _bmi(double w, double hCm) {
    final h = (hCm / 100.0);
    if (h <= 0) return 0;
    return w / (h * h);
  }

  String _bmiClass(double bmi) {
    if (bmi < 18.5) return 'نحافة';
    if (bmi < 25) return 'طبيعي';
    if (bmi < 30) return 'زيادة وزن';
    return 'سمنة';
  }

  _RiskScore _riskFromPace(double weeklyKg, double currentKg) {
    final rate = weeklyKg.abs();
    final bmiNow = _bmi(currentKg, height);
    double low = 0.3, medium = 0.75, high = 1.0;
    if (bmiNow >= 30) {
      low = 0.5;
      medium = 1.0;
      high = 1.25;
    } else if (bmiNow >= 27) {
      low = 0.4;
      medium = 0.9;
      high = 1.1;
    } else if (bmiNow <= 21) {
      low = 0.25;
      medium = 0.6;
      high = 0.9;
    }

    final days = goal.targetDate.difference(DateTime.now()).inDays;
    final totalDelta = (goal.targetWeight - goal.currentWeight).abs();
    if (totalDelta <= 2.1 && days >= 12 && days <= 18) {
      return _RiskScore('منخفض', Colors.green);
    }

    if (rate <= low) return _RiskScore('منخفض', Colors.green);
    if (rate <= medium) return _RiskScore('متوسط', Colors.amber);
    if (rate <= high) return _RiskScore('مرتفع', Colors.orange);
    return _RiskScore('مرتفع جدًا', Colors.red);
  }

  @override
  Widget build(BuildContext context) {
    final sign = goal.dailyCalorieDelta >= 0 ? '+' : '−';
    final absDelta = goal.dailyCalorieDelta.abs().round();

    final weeks = (goal.targetDate.difference(DateTime.now()).inDays / 7).ceil().clamp(1, 520);
    final pctChange = ((goal.targetWeight - goal.currentWeight) / goal.currentWeight) * 100;

    final bmiNow = _bmi(goal.currentWeight, height);
    final bmiTarget = _bmi(goal.targetWeight, height);
    final risk = _riskFromPace(goal.weeklyChangeKg, goal.currentWeight);

    final String riskNote = () {
      switch (risk.label) {
        case 'منخفض':
          return 'معدل أسبوعي واقعي وآمن لمعظم الناس.';
        case 'متوسط':
          return 'معدل سريع لكنه ممكن إذا التغذية والنوم ممتازان.';
        case 'مرتفع':
          return 'معدل عالٍ؛ يُستحسن إطالة المدة لتقليل الإجهاد وفقد العضلة.';
        default:
          return 'المعدل مبالغ فيه؛ قلّل الهدف أو زد المدة.';
      }
    }();

    final chips = <Widget>[
      _ChipInfo(label: 'المدة', value: '$weeks أسبوعًا'),
      _ChipInfo(label: 'التغيّر', value: '${goal.weeklyChangeKg.toStringAsFixed(2)} كجم/أسبوع'),
      _ChipInfo(label: 'النسبة من الوزن', value: '${pctChange.toStringAsFixed(1)}%'),
      _ChipInfo(label: 'BMI الآن', value: '${bmiNow.toStringAsFixed(1)} • ${_bmiClass(bmiNow)}'),
      _ChipInfo(label: 'BMI المستهدف', value: '${bmiTarget.toStringAsFixed(1)} • ${_bmiClass(bmiTarget)}'),
      _ChipInfo(label: 'المخاطر', value: risk.label, color: risk.color),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تقييم الخطة: $statusText', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(riskNote),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _KV('السعرات/يوم', '$sign$absDelta kcal')),
              Expanded(child: _KV('الموعد', goal.targetDate.toLocal().toString().split(' ').first)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('تنبيه: هذه تقديرات تقريبية وليست نصيحة طبية.'),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  final String k, v;
  const _KV(this.k, this.v, {super.key});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 2),
      Text(v, style: Theme.of(context).textTheme.titleMedium),
    ]);
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = (color ?? cs.primary).withOpacity(0.12);
    final border = (color ?? cs.primary).withOpacity(0.35);
    final fg = color ?? cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 14, color: fg),
            const SizedBox(width: 6),
            Text('$label: $value', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _RiskScore {
  final String label;
  final Color color;
  _RiskScore(this.label, this.color);
}

// ==============================
// عناصر تنسيق عام للصفحة (UI Helpers)
// ==============================
class _SGHeader extends StatelessWidget {
  final String title;
  const _SGHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.flag, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _SGCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SGCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SGField extends StatelessWidget {
  const _SGField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.keyboardType,
    this.prefixText,
    this.helper,
    this.suffixIcon,
    this.onChanged,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? prefixText;
  final String? helper;
  final IconData? suffixIcon;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        helperText: helper,
        suffixIcon: suffixIcon == null ? null : Icon(suffixIcon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// صف متكيّف: يحوّل تلقائيًا إلى عمود عند ضيق العرض (يمنع Overflow)
class _InlineAdaptiveRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _InlineAdaptiveRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final isNarrow = c.maxWidth < 360;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: right),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 8),
            right,
          ],
        );
      },
    );
  }
}

class _SGInfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SGInfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          // ✅ يمنع أي Overflow داخل الحبة
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================
// قائمة سجل الأهداف (بعناوين عربية للصعوبة)
// ==============================
class _GoalHistoryList extends StatelessWidget {
  const _GoalHistoryList({required this.history});
  final List<Map<String, dynamic>> history;

  @override
  Widget build(BuildContext context) {
    final items = history.take(5).toList(); // عرض آخر 5
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final e in items) ...[
          _GoalHistoryTile(entry: e),
          const SizedBox(height: 8),
        ],
        if (history.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '… وهناك ${history.length - 5} عناصر أخرى في السجل',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

class _GoalHistoryTile extends StatelessWidget {
  const _GoalHistoryTile({required this.entry});
  final Map<String, dynamic> entry;

  String _fmtDate(String s) {
    try {
      return DateTime.parse(s).toLocal().toString().split(' ').first;
    } catch (_) {
      return s;
    }
  }

  String _difficultyAr(String v) {
    switch (v) {
      case 'easy':
        return 'سهل';
      case 'feasible':
        return 'ممكن';
      case 'hard':
        return 'صعب';
      case 'unrealistic':
        return 'غير صحي/غير واقعي';
      default:
        return v; // احتياط
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = (entry['type'] ?? '').toString();
    final cs = Theme.of(context).colorScheme;

    if (type == 'note') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withOpacity(.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.note_alt_outlined, color: cs.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ملاحظة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text((entry['text'] ?? '').toString()),
                  const SizedBox(height: 6),
                  Text(_fmtDate((entry['createdAt'] ?? '').toString()),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final createdAt = _fmtDate((entry['createdAt'] ?? '').toString());
    final cur = (entry['current'] ?? 0).toString();
    final tar = (entry['target'] ?? 0).toString();
    final date = _fmtDate((entry['targetDate'] ?? '').toString());
    final weekly = (entry['weekly'] ?? 0).toString();
    final diff = _difficultyAr((entry['difficulty'] ?? '').toString());

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تاريخ الحفظ: $createdAt', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipInfo(label: 'الحالي', value: '$cur كجم'),
              _ChipInfo(label: 'المستهدف', value: '$tar كجم'),
              _ChipInfo(label: 'الموعد', value: date),
              _ChipInfo(label: 'التغيّر/أسبوع', value: '$weekly كجم'),
              _ChipInfo(label: 'الصعوبة', value: diff),
            ],
          ),
        ],
      ),
    );
  }
}
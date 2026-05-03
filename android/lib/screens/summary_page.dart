import 'dart:math';
import 'dart:async'; // ⬅️ للـ Timeout
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ⬇️ لإتمام تعليم الأونبوردنغ في السحابة
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/legacy_user_repository.dart';

import '../utils/calorie_calculator.dart';
import 'main_navigation_screen.dart';

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

    // --- السعرات بعد الهدف: نفس الدالة الأصلية لديك ---
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

    // --- الماكروز: نفس منطقك بالضبط ---
    final pPref = prefs.getDouble('protein_$email');
    final fPref = prefs.getDouble('fat_$email');
    final cPref = prefs.getDouble('carbs_$email');

    if (protein > 0 && fat > 0 && carbs > 0) {
      // نستخدم اللي جاء من Firestore/metrics
    } else if (pPref != null && fPref != null && cPref != null) {
      protein = pPref;
      fat = fPref;
      carbs = cPref;
    } else {
      if (goal == 'تنشيف الدهون') {
        protein = weight * 2.2;
        fat = weight * 0.6;
      } else {
        protein = weight * 2.0;
        fat = weight * 0.8;
      }
      carbs = ((adjustedCalories - (protein * 4 + fat * 9)) / 4)
          .clamp(0, double.infinity);
    }

    analysisText = _buildAnalysis();

    if (!mounted) return;
    setState(() => _loading = false);
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
        return '💪 كل تكرار يقوّيك. استمر وسترى الفرق بالأداء والشكل!';
      case 'إنقاص الوزن':
        return '✨ توازن أكل + نشاط ثابت = نتائج تدوم. فخور فيك!';
      case 'زيادة الوزن':
        return '🍽️ وجباتك المتوازنة + تدريب مقاومة = بناء وزن صحي.';
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
    // دخول التطبيق
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
    );

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

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      appBar: AppBar(
        title: const Text('ملخصك الصحي'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تعديل الهدف',
            icon: const Icon(Icons.track_changes),
            onPressed: () => Navigator.pushNamed(context, '/set-goal'),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
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

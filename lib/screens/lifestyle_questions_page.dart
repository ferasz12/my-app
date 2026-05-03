// lib/screens/lifestyle_questions_page.dart — FULL DIAGNOSTICS VERSION
import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/legacy_user_repository.dart';
import 'user_input_page.dart';

class LifestyleQuestionsPage extends StatefulWidget {
  const LifestyleQuestionsPage({super.key});
  @override
  State<LifestyleQuestionsPage> createState() => _LifestyleQuestionsPageState();
}

class _LifestyleQuestionsPageState extends State<LifestyleQuestionsPage> {
  // 1. المتغيرات (نفس متغيراتك الأصلية تماماً)
  int? steps, sitting, workout, activityType, meals, stairs, sleep, water, fatigue, job;
  int? cardioMinutes, strengthDays, intensity, standHours, commute, weekendActivity, sleepQuality;

  bool _saving = false;

  // 2. المنطق (Logic)
  List<int?> get _allFields => [
        steps, sitting, workout, activityType, meals, stairs, sleep, water, fatigue, job,
        cardioMinutes, strengthDays, intensity, standHours, commute, weekendActivity, sleepQuality,
      ];

  int get _answeredCount => _allFields.where((e) => e != null).length;
  int get _totalCount => _allFields.length;
  bool get allAnswered => _answeredCount == _totalCount;

  int calculateScore() => _allFields.fold(0, (sum, v) => sum + (v ?? 0));

  String _levelFromScore(int score) {
    if (score <= 10) return 'sedentary';
    if (score <= 18) return 'light';
    if (score <= 26) return 'moderate';
    if (score <= 30) return 'active';
    return 'very_active';
  }

  double _activityFactor(String level) {
    switch (level) {
      case 'sedentary': return 1.2;
      case 'light': return 1.375;
      case 'moderate': return 1.55;
      case 'active': return 1.725;
      default: return 1.9;
    }
  }

  // 3. نظام التشخيص (Logging)
  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('🧭 [LifestyleDiag] ${DateTime.now().second}:${DateTime.now().millisecond} | $msg');
    }
  }

  Future<void> _showDiagDialog(String title, String body) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, textAlign: TextAlign.right),
        content: SingleChildScrollView(child: Text(body, textAlign: TextAlign.right)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // حماية من NaN في شريط التقدم
    final double progress = (_totalCount > 0) ? (_answeredCount / _totalCount).clamp(0.0, 1.0) : 0.0;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('أسئلة نمط الحياة'),
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
        bottomNavigationBar: _buildBottomBar(progress),
        body: Container(
          decoration: _OnbDecorations.background(context),
          child: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 80, 16, 120),
              children: [
                _HeaderProgressCard(
                  progress: progress,
                  answered: _answeredCount,
                  total: _totalCount,
                ),
                const SizedBox(height: 16),

                _SectionHeader(emoji: '🏃‍♂️', title: 'حركتك اليومية '),
                _QuestionCard(q: 'خطواتك اليومية؟', opt: {0: 'أقل من 3 آلاف', 1: '3 - 7 آلاف', 2: 'أكثر من 7 آلاف'}, val: steps, onCh: (v)=>setState(()=>steps=v)),
                _QuestionCard(q: 'ساعات الجلوس؟', opt: {0: 'أكثر من 8 ساعات', 1: '4 - 8 ساعات', 2: 'أقل من 4 ساعات'}, val: sitting, onCh: (v)=>setState(()=>sitting=v)),
                _QuestionCard(q: 'طبيعة عملك؟', opt: {0: 'مكتبي', 1: 'حركة متوسطة', 2: 'نشاط بدني'}, val: job, onCh: (v)=>setState(()=>job=v)),
                _QuestionCard(q: 'ساعات الوقوف بالعمل؟', opt: {0: '< 2 ساعة', 1: '2 - 5 ساعات', 2: '> 5 ساعات'}, val: standHours, onCh: (v)=>setState(()=>standHours=v)),
                _QuestionCard(q: 'أسلوب التنقل؟', opt: {0: 'سيارة', 1: 'مختلط', 2: 'مشي'}, val: commute, onCh: (v)=>setState(()=>commute=v)),
                _QuestionCard(q: 'نشاط نهاية الأسبوع؟', opt: {0: 'خامل', 1: 'نشاط خفيف', 2: 'نشاط خارجي'}, val: weekendActivity, onCh: (v)=>setState(()=>weekendActivity=v)),

                _SectionHeader(emoji: '🏋️', title: ' تمارينك'),
                _QuestionCard(q: 'مرات التمرين أسبوعياً؟', opt: {0: 'نادراً', 1: '1 - 3 مرات', 2: '4+ مرات'}, val: workout, onCh: (v)=>setState(()=>workout=v)),
                _QuestionCard(q: 'شدة التمرين؟', opt: {0: 'خفيفة', 1: 'متوسطة', 2: 'عالية'}, val: intensity, onCh: (v)=>setState(()=>intensity=v)),
                _QuestionCard(q: 'دقائق الكارديو؟', opt: {0: '< 30 د', 1: '30 - 90 د', 2: '> 90 د'}, val: cardioMinutes, onCh: (v)=>setState(()=>cardioMinutes=v)),
                _QuestionCard(q: 'أيام المقاومة؟', opt: {0: '0 يوم', 1: '1 - 2 يوم', 2: '3+ أيام'}, val: strengthDays, onCh: (v)=>setState(()=>strengthDays=v)),
                _QuestionCard(q: 'نوع النشاط الغالب؟', opt: {0: 'خمول', 1: 'خفيف', 2: 'متوسط/عالٍ'}, val: activityType, onCh: (v)=>setState(()=>activityType=v)),

                _SectionHeader(emoji: '🌙', title: 'عاداتك الصحية '),
                _QuestionCard(q: 'عدد الوجبات؟', opt: {0: '1 أو أقل', 1: '2 - 3', 2: 'أكثر من 3'}, val: meals, onCh: (v)=>setState(()=>meals=v)),
                _QuestionCard(q: 'شرب الماء؟', opt: {0: '< 4 أكواب', 1: '4 - 7 أكواب', 2: '8+ أكواب'}, val: water, onCh: (v)=>setState(()=>water=v)),
                _QuestionCard(q: 'ساعات النوم؟', opt: {0: '< 5 ساعات', 1: '5 - 7 ساعات', 2: '> 7 ساعات'}, val: sleep, onCh: (v)=>setState(()=>sleep=v)),
                _QuestionCard(q: 'جودة النوم؟', opt: {0: 'سيئة', 1: 'متوسطة', 2: 'جيدة'}, val: sleepQuality, onCh: (v)=>setState(()=>sleepQuality=v)),
                _QuestionCard(q: 'مستوى الطاقة؟', opt: {0: 'تعب مستمر', 1: 'طاقة متوسطة', 2: 'نشاط وحيوية'}, val: fatigue, onCh: (v)=>setState(()=>fatigue=v)),
                _QuestionCard(q: 'استخدام الدرج؟', opt: {0: 'نادراً', 1: 'أحياناً', 2: 'دائماً'}, val: stairs, onCh: (v)=>setState(()=>stairs=v)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 4. دالة الحفظ مع التشخيص العميق
  Future<void> _onContinue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_saving) return;

    _log("🚀 بدء عملية الحفظ...");
    setState(() => _saving = true);

    try {
      // (أ) فحص المستخدم والجلسة
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _log("❌ فشل: Auth User is NULL");
        await _showDiagDialog('فشل الهوية', 'لم يتم العثور على مستخدم مسجل. الجلسة منتهية.');
        return;
      }
      _log("✅ المستخدم موجود: ${user.uid}");

      // (ب) تحديث التوكن (Token Refresh) لحل مشكلة Invalid Token
      try {
        _log("⏳ جاري تحديث التوكن...");
        await user.reload();
        await user.getIdToken(true);
        _log("✅ تم تجديد التوكن.");
      } catch (e) {
        _log("❌ فشل تحديث التوكن: $e");
        await _showDiagDialog('خطأ في الجلسة', 'انتهت صلاحية الجلسة. يرجى إعادة تسجيل الدخول.');
        return;
      }

      // (ج) فحص الحسابات (Protection against NaN)
      final score = calculateScore();
      final level = _levelFromScore(score);
      final factor = _activityFactor(level);
      _log("📊 الحسبة: Score=$score, Level=$level");

      // (د) محاولة الكتابة في Firestore مع Timeout
      _log("⏳ محاولة الكتابة في Firestore...");
      await const LegacyUserRepository().saveLifestyleStep(
        answers: {
          'steps': steps, 'sitting': sitting, 'workout': workout, 'activityType': activityType,
          'meals': meals, 'stairs': stairs, 'sleep': sleep, 'water': water, 'fatigue': fatigue,
          'job': job, 'cardioMinutes': cardioMinutes, 'strengthDays': strengthDays,
          'intensity': intensity, 'standHours': standHours, 'commute': commute,
          'weekendActivity': weekendActivity, 'sleepQuality': sleepQuality,
        },
        score: score,
        activityLevel: level,
        activityFactor: factor,
      ).timeout(const Duration(seconds: 15));

      _log("🎉 نجحت عملية الكتابة في السحابة!");

      if (mounted) {
        // ✅ مهم: نستخدم push بدل pushReplacement حتى تقدر ترجع وتعدّل الإجابات.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserInputPage(lifestyleScore: score)),
        );
      }
    } on FirebaseException catch (e) {
      _log("❌ Firebase Error: [${e.code}] ${e.message}");
      await _showDiagDialog('خطأ Firebase', 'كود: ${e.code}\nالرسالة: ${e.message}');
    } on TimeoutException {
      _log("❌ Timeout: السيرفر لم يستجب");
      await _showDiagDialog('انتهى الوقت', 'لم يصل رد من السيرفر. تأكد من جودة الإنترنت أو إعدادات App Check.');
    } catch (e) {
      _log("❌ خطأ غير متوقع: $e");
      await _showDiagDialog('خطأ غير متوقع', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // === عناصر الواجهة المساعدة ===
  Widget _buildBottomBar(double progress) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      allAnswered ? 'جاهز للحفظ' : 'باقي ${_totalCount - _answeredCount} إجابات',
                      style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text('${(progress * 100).round()}%', style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (allAnswered && !_saving) ? _onContinue : null,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_back),
                  label: Text(_saving ? 'جاري الفحص والحفظ…' : 'حفظ ومتابعة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderProgressCard extends StatelessWidget {
  final double progress;
  final int answered;
  final int total;
  const _HeaderProgressCard({required this.progress, required this.answered, required this.total});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.primary.withOpacity(0.18)),
                  ),
                  child: Icon(Icons.monitor_heart_outlined, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(' عشان نحدد نمط حياتك ', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('جاوب بسرعة — نستخدمها  لحساب السعرات.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerHighest.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${(progress * 100).round()}% مكتمل', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$answered / $total', style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String emoji, title;
  const _SectionHeader({required this.emoji, required this.title});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: cs.outlineVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final String q; final Map<int, String> opt; final int? val; final ValueChanged<int> onCh;
  const _QuestionCard({required this.q, required this.opt, required this.val, required this.onCh});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: opt.entries.map((e) {
                final sel = val == e.key;
                return ChoiceChip(
                  label: Text(e.value, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  selected: sel,
                  onSelected: (_) => onCh(e.key),
                  selectedColor: cs.primary.withOpacity(0.18),
                  backgroundColor: cs.surface.withOpacity(0.75),
                  side: BorderSide(
                    color: sel ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.6),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================
// تصميم مشترك (خلفيات + Glass)
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
        color: cs.surface.withOpacity(0.75),
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
          child: child,
        ),
      ),
    );
  }
}
// lib/screens/lifestyle_questions_page.dart — diagnostics build
// ✅ نفس الصفحة لكن مع (Logs) دقيقة جدًا عشان تعرف وين يعلق الحفظ وليه
// ✅ أي Timeout يعني Firestore ما قدر يأكد الكتابة من السيرفر (غالباً اتصال/شبكة/Proxy/VPN/AppCheck)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';

import '../core/diagnostics/firestore_diag.dart';
import '../core/diagnostics/onb_log.dart';
import '../data/legacy_user_repository.dart';

import 'user_input_page.dart';

class LifestyleQuestionsPage extends StatefulWidget {
  const LifestyleQuestionsPage({super.key});

  @override
  State<LifestyleQuestionsPage> createState() => _LifestyleQuestionsPageState();
}

class _LifestyleQuestionsPageState extends State<LifestyleQuestionsPage> {
  // === الأسئلة الأساسية ===
  int? steps, sitting, workout, activityType, meals, stairs, sleep, water, fatigue, job;

  // === أسئلة مضافة (تفيد تقدير السعرات) ===
  int? cardioMinutes, strengthDays, intensity, standHours, commute, weekendActivity, sleepQuality;

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
      case 'sedentary':
        return 1.2;
      case 'light':
        return 1.375;
      case 'moderate':
        return 1.55;
      case 'active':
        return 1.725;
      default:
        return 1.9; // very_active
    }
  }

  bool _saving = false;

  // ===== Verbose diagnostics =====
  void _log(String event, {Map<String, Object?>? ctx}) {
    OnbLog.i('LifestyleQuestionsPage', event, ctx: ctx);
    if (!kDebugMode) return;
    debugPrint('🧭 [LifestyleQuestionsPage] ${DateTime.now().toIso8601String()} | $event${ctx == null ? '' : ' | $ctx'}');
  }

  Future<void> _showDiagDialog(String title, String body) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: SingleChildScrollView(
          child: Text(body, textDirection: TextDirection.rtl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  String _fmtErr(Object e) {
    if (e is FirebaseException) {
      return '[${e.plugin}] code=${e.code} message=${e.message} details=${e.stackTrace ?? ''}';
    }
    return e.toString();
  }


  @override
  Widget build(BuildContext context) {
    final progress = _totalCount == 0 ? 0.0 : _answeredCount / _totalCount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('أسئلة نمط الحياة')),
        resizeToAvoidBottomInset: true,
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: (allAnswered && !_saving) ? _onContinue : null,
              icon: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_saving ? 'جارٍ الحفظ...' : 'إدخال البيانات'),
                  Text('${(_answeredCount / _totalCount * 100).round()}%'),
                ],
              ),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _HeaderProgressCard(
                title: 'لنحدّد نمط حياتك بدقّة ✨',
                subtitle: 'جاوب بسرعة — هذا يساعدنا نحسب السعرات الأنسب لك.',
                progress: progress,
              ),
              const SizedBox(height: 16),

              _SectionHeader(emoji: '🏃‍♂️', title: 'الحركة اليومية'),
              _QuestionCard(
                question: 'كم خطوة تمشي يوميًا تقريبًا؟',
                options: const {0: 'أقل من 3 آلاف', 1: '3 - 7 آلاف', 2: 'أكثر من 7 آلاف'},
                selected: steps,
                onChanged: (v) => setState(() => steps = v),
              ),
              _QuestionCard(
                question: 'كم ساعة تجلس بدون حركة؟',
                options: const {0: 'أكثر من 8 ساعات', 1: '4 - 8 ساعات', 2: 'أقل من 4 ساعات'},
                selected: sitting,
                onChanged: (v) => setState(() => sitting = v),
              ),
              _QuestionCard(
                question: 'هل طبيعة عملك تتطلب حركة؟',
                options: const {0: 'مكتبي بالكامل', 1: 'حركة متوسطة', 2: 'نشاط بدني يومي'},
                selected: job,
                onChanged: (v) => setState(() => job = v),
              ),
              _QuestionCard(
                question: 'كم ساعة توقف/تمشي أثناء العمل؟',
                options: const {0: 'أقل من 2 ساعة', 1: '2 - 5 ساعات', 2: 'أكثر من 5 ساعات'},
                selected: standHours,
                onChanged: (v) => setState(() => standHours = v),
              ),
              _QuestionCard(
                question: 'وش أسلوب تنقّلك اليومي؟',
                options: const {0: 'سيارة', 1: 'مختلط', 2: 'مشي/سيكل'},
                selected: commute,
                onChanged: (v) => setState(() => commute = v),
              ),
              _QuestionCard(
                question: 'نشاطك في نهاية الأسبوع؟',
                options: const {0: 'خامل غالبًا', 1: 'نشاط خفيف', 2: 'نشاط خارجي/رياضة'},
                selected: weekendActivity,
                onChanged: (v) => setState(() => weekendActivity = v),
              ),

              const SizedBox(height: 6),
              _SectionHeader(emoji: '🏋️', title: 'التمارين'),
              _QuestionCard(
                question: 'كم مره تتمرن بالأسبوع؟',
                options: const {0: 'نادراً', 1: '1 - 3 مرات', 2: '4+ مرات'},
                selected: workout,
                onChanged: (v) => setState(() => workout = v),
              ),
              _QuestionCard(
                question: 'شدة التمرين المعتادة؟',
                options: const {0: 'خفيفة', 1: 'متوسطة', 2: 'عالية'},
                selected: intensity,
                onChanged: (v) => setState(() => intensity = v),
              ),
              _QuestionCard(
                question: 'دقائق الكارديو أسبوعيًا؟',
                options: const {0: '< 30 دقيقة', 1: '30 - 90 دقيقة', 2: '> 90 دقيقة'},
                selected: cardioMinutes,
                onChanged: (v) => setState(() => cardioMinutes = v),
              ),
              _QuestionCard(
                question: 'أيام تمارين مقاومة/أوزان أسبوعيًا؟',
                options: const {0: '0 يوم', 1: '1 - 2 يوم', 2: '3+ أيام'},
                selected: strengthDays,
                onChanged: (v) => setState(() => strengthDays = v),
              ),
              _QuestionCard(
                question: 'نوع نشاطك البدني غالبًا؟',
                options: const {0: 'خمول/جلوس', 1: 'نشاط خفيف', 2: 'نشاط متوسط/عالٍ'},
                selected: activityType,
                onChanged: (v) => setState(() => activityType = v),
              ),

              const SizedBox(height: 6),
              _SectionHeader(emoji: '🌙', title: 'العادات اليومية'),
              _QuestionCard(
                question: 'كم وجبة رئيسية يوميًا؟',
                options: const {0: '1 أو أقل', 1: '2 - 3', 2: 'أكثر من 3'},
                selected: meals,
                onChanged: (v) => setState(() => meals = v),
              ),
              _QuestionCard(
                question: 'كم تشرب ماء يوميًا؟',
                options: const {0: '< 4 أكواب', 1: '4 - 7 أكواب', 2: '8+ أكواب'},
                selected: water,
                onChanged: (v) => setState(() => water = v),
              ),
              _QuestionCard(
                question: 'عدد ساعات النوم؟',
                options: const {0: '< 5 ساعات', 1: '5 - 7 ساعات', 2: '> 7 ساعات'},
                selected: sleep,
                onChanged: (v) => setState(() => sleep = v),
              ),
              _QuestionCard(
                question: 'جودة النوم؟',
                options: const {0: 'سيئة', 1: 'متوسطة', 2: 'جيدة'},
                selected: sleepQuality,
                onChanged: (v) => setState(() => sleepQuality = v),
              ),
              _QuestionCard(
                question: 'مستوى طاقتك خلال اليوم؟',
                options: const {0: 'تعب مستمر', 1: 'طاقة متوسطة', 2: 'نشاط وحيوية'},
                selected: fatigue,
                onChanged: (v) => setState(() => fatigue = v),
              ),
              _QuestionCard(
                question: 'هل تستخدم الدرج بدل المصعد؟',
                options: const {0: 'نادراً', 1: 'أحيانًا', 2: 'دائمًا'},
                selected: stairs,
                onChanged: (v) => setState(() => stairs = v),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onContinue() async {
    FocusManager.instance.primaryFocus?.unfocus();

    _log('CONTINUE_PRESSED', ctx: {
      'answered': _answeredCount,
      'total': _totalCount,
      'allAnswered': allAnswered,
      'saving': _saving,
    });

    if (_saving) return;

    if (!allAnswered) {
      _log('BLOCK_NOT_ALL_ANSWERED');
      await _showDiagDialog('ناقص بيانات', 'لازم تجاوب على كل الأسئلة قبل المتابعة.');
      return;
    }

    setState(() => _saving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _log('BLOCK_NO_USER');
      await _showDiagDialog('فشل الحفظ', 'المشكلة: المستخدم غير مسجّل دخولًا.');
      if (mounted) setState(() => _saving = false);
      return;
    }

    try {
      await user.reload();
    } catch (e) {
      _log('USER_RELOAD_FAILED', ctx: {'err': e.toString()});
    }

    _log('USER_STATE', ctx: {
      'uid': user.uid,
      'email': user.email,
      'emailVerified': user.emailVerified,
    });

    if (!user.emailVerified) {
      _log('BLOCK_EMAIL_NOT_VERIFIED');
      await _showDiagDialog('فشل الحفظ', 'المشكلة: لازم تفعيل البريد قبل المتابعة.');
      if (mounted) setState(() => _saving = false);
      return;
    }

    final score = calculateScore();
    final level = _levelFromScore(score);
    final factor = _activityFactor(level);

    final answers = <String, dynamic>{
      'steps': steps,
      'sitting': sitting,
      'workout': workout,
      'activityType': activityType,
      'meals': meals,
      'stairs': stairs,
      'sleep': sleep,
      'water': water,
      'fatigue': fatigue,
      'job': job,
      'cardioMinutes': cardioMinutes,
      'strengthDays': strengthDays,
      'intensity': intensity,
      'standHours': standHours,
      'commute': commute,
      'weekendActivity': weekendActivity,
      'sleepQuality': sleepQuality,
    };

    _log('CALC_RESULT', ctx: {
      'score': score,
      'level': level,
      'factor': factor,
    });

    // تحقق سريع: هل الـ payload قابل للتخزين؟
    final issues = FirestoreDiag.validateEncodable({'answers': answers, 'score': score, 'factor': factor});
    if (issues.isNotEmpty) {
      _log('BLOCK_INVALID_PAYLOAD', ctx: {'issuesCount': issues.length});
      await _showDiagDialog(
        'تعذّر الحفظ (Payload غير صالح)',
        'فيه قيم غير مقبولة في Firestore:\n- ${issues.join('\n- ')}',
      );
      if (mounted) setState(() => _saving = false);
      return;
    }

    // تنبيه غير مزعج إذا طال حفظ السحابة
    final slowTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المزامنة بطيئة قليلًا… جاري الحفظ على السحابة')),
      );
    });

    try {
      _log('SAVE_LIFESTYLE_START');
      await const LegacyUserRepository()
          .saveLifestyleStep(
            answers: answers,
            score: score,
            activityLevel: level,
            activityFactor: factor,
          )
          .timeout(const Duration(seconds: 20));
      _log('SAVE_LIFESTYLE_OK');
    } catch (e, st) {
      _log('SAVE_LIFESTYLE_FAILED', ctx: {'err': e.toString()});
      OnbLog.e('LifestyleQuestionsPage', 'SAVE_LIFESTYLE_EXCEPTION', e, st);

      // ✅ تشخيص دقيق: هل Firestore أصلًا يقدر يكتب على users/{uid}؟
      try {
        final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
        await FirestoreDiag.diagnoseWrite(
          tag: 'lifestyle_next_button',
          ref: ref,
          payload: {
            'diagPing': DateTime.now().toIso8601String(),
            'stage': 'LifestyleQuestionsPage._onContinue',
          },
          confirmField: 'diagLifestyleWriteId',
        );
      } catch (e2) {
        _log('DIAG_FAILED', ctx: {'err': e2.toString()});
      }

      await _showDiagDialog('تعذّر الحفظ', 'خطأ أثناء حفظ البيانات:\n${_fmtErr(e)}');
      if (mounted) setState(() => _saving = false);
      return;
    } finally {
      slowTimer.cancel();
    }

    if (!mounted) return;

    _log('NAVIGATE_TO_USER_INPUT', ctx: {'score': score});
    setState(() => _saving = false);

    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(builder: (_) => UserInputPage(lifestyleScore: score)),
    );
  }

}

//// ===== Widgets =====

class _HeaderProgressCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double progress;
  const _HeaderProgressCard({
    required this.title,
    required this.subtitle,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: cs.surface,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${(progress * 100).round()}% مكتمل',
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  const _SectionHeader({required this.emoji, required this.title});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('اختر إجابة واحدة', style: tt.labelMedium),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final String question;
  final Map<int, String> options;
  final int? selected;
  final ValueChanged<int> onChanged;

  const _QuestionCard({
    required this.question,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 12),
            _FancyChoiceGrid(options: options, selected: selected, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _FancyChoiceGrid extends StatelessWidget {
  final Map<int, String> options;
  final int? selected;
  final ValueChanged<int> onChanged;

  const _FancyChoiceGrid({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (ctx, cons) {
        final isNarrow = cons.maxWidth < 420;
        final colWidth = isNarrow ? cons.maxWidth : (cons.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.entries.map((e) {
            final k = e.key;
            final text = e.value;
            final sel = selected == k;

            return SizedBox(
              width: colWidth,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onChanged(k),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: sel
                          ? LinearGradient(
                              colors: [cs.primaryContainer, cs.surface],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            )
                          : null,
                      color: sel ? null : cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                      boxShadow: [
                        if (sel) BoxShadow(color: cs.primary.withOpacity(0.15), blurRadius: 14, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 28,
                          width: 28,
                          decoration: BoxDecoration(
                            color: sel ? cs.primary : cs.surface,
                            border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            sel ? Icons.check_rounded : Icons.circle_outlined,
                            size: sel ? 18 : 16,
                            color: sel ? cs.onPrimary : cs.outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// lib/screens/goal_progress_onboarding_page.dart
// صفحة تُعرض بعد (ضع هدفك) في الأونبوردنغ
// - ترسم انتقال وزنك من الحالي إلى الهدف (عرض تحفيزي)
// - لا تغيّر أي منطق بيانات/حفظ (فقط قراءة من WeightGoal)

import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/legacy_user_repository.dart';
import '../models/weight_goal.dart';
import '../providers/goal_provider.dart';
import '../services/goal_service.dart';

class GoalProgressOnboardingPage extends StatefulWidget {
  const GoalProgressOnboardingPage({
    super.key,
    this.goal,
  });

  /// تمرير الهدف مباشرة (يفضل من SetGoalPage)
  final WeightGoal? goal;

  @override
  State<GoalProgressOnboardingPage> createState() => _GoalProgressOnboardingPageState();
}

class _GoalProgressOnboardingPageState extends State<GoalProgressOnboardingPage> {
  WeightGoal? _goal;
  bool _loading = true;
  bool _savingStep = false;

  @override
  void initState() {
    super.initState();
    _goal = widget.goal;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ نحاول نجلب الهدف من Provider (لو ما انرسل كـ argument)
    _goal ??= context.read<GoalProvider>().goal;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!_loading) return;

    // إذا الهدف موجود خلاص
    if (_goal != null) {
      setState(() => _loading = false);
      return;
    }

    // ✅ fallback أخير: اقرأ من السحابة
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final g = await GoalService.getGoal(uid);
        if (g != null) {
          _goal = g;
          // حافظ على Provider متزامن (بدون إلزام)
          try {
            context.read<GoalProvider>().setGoal(g);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[GoalProgressOnboardingPage] load goal failed: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  int _daysLeft(DateTime targetDate) {
    final d = targetDate.difference(DateTime.now()).inDays;
    return math.max(1, d);
  }

  String _fmtKg(double v) => v.toStringAsFixed(1);

  String _motivation(WeightGoal g) {
    final delta = (g.targetWeight - g.currentWeight);
    final absDelta = delta.abs();
    final isLoss = g.targetWeight < g.currentWeight;

    if (absDelta < 1.0) {
      return 'هدفك بسيط وواضح — خطوات صغيرة يوميًا وتوصله بسرعة 💚';
    }

    if (g.difficulty == GoalDifficulty.unrealistic) {
      return isLoss
          ? 'هدفك قوي جدًا! تقدر توصله… بس خلّنا نمشي بخطوات صحية ونثبت الاستمرارية.'
          : 'هدفك عالي جدًا! ركّز على جودة الأكل والتمرين وبتشوف فرق تدريجي.';
    }

    return isLoss
        ? 'ممتاز! كل يوم تلتزم فيه = خطوة أقرب للوزن اللي تبيه 🔥'
        : 'ممتاز! التزامك بالتغذية والتمرين بيبني لك وزن صحي بشكل تدريجي 💪';
  }

  Future<void> _goNext() async {
    if (_savingStep) return;
    setState(() => _savingStep = true);

    // ✅ خزّن خطوة الأونبوردنغ الجديدة (حتى لو فشل، لا نوقف المستخدم)
    try {
      await const LegacyUserRepository().updateLegacyUserRoot(
        patch: const {'onboardingDone': false},
        stepAtLeast: 4,
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushNamed(context, '/summary');
    if (mounted) setState(() => _savingStep = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(0.10),
                cs.secondary.withOpacity(0.06),
                cs.surface,
              ],
            ),
          ),
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_goal == null)
                    ? _EmptyGoalState(onBack: () => Navigator.pop(context))
                    : _Content(
                        goal: _goal!,
                        tt: tt,
                        cs: cs,
                        onNext: _goNext,
                        busy: _savingStep,
                        motivation: _motivation(_goal!),
                        daysLeft: _daysLeft(_goal!.targetDate),
                        fmtKg: _fmtKg,
                      ),
          ),
        ),
      ),
    );
  }
}

class _EmptyGoalState extends StatelessWidget {
  final VoidCallback onBack;
  const _EmptyGoalState({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text('ما قدرنا نقرأ هدفك', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'ارجع لصفحة الهدف وحدّد الوزن الحالي والهدف مرة ثانية.',
            style: tt.bodyLarge?.copyWith(height: 1.5),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final WeightGoal goal;
  final TextTheme tt;
  final ColorScheme cs;
  final VoidCallback onNext;
  final bool busy;
  final String motivation;
  final int daysLeft;
  final String Function(double) fmtKg;

  const _Content({
    required this.goal,
    required this.tt,
    required this.cs,
    required this.onNext,
    required this.busy,
    required this.motivation,
    required this.daysLeft,
    required this.fmtKg,
  });

  @override
  Widget build(BuildContext context) {
    final current = goal.currentWeight;
    final target = goal.targetWeight;
    final isLoss = target < current;
    final delta = (target - current);
    final absDelta = delta.abs();

    final weeksLeft = math.max(1, (daysLeft / 7).ceil());
    final weekly = goal.weeklyChangeKg;

    final title = isLoss ? 'رحلة نزول الوزن' : 'رحلة زيادة الوزن';
    final rangeLine = 'من ${fmtKg(current)} إلى ${fmtKg(target)} كجم';
    final subLine = 'خلال $daysLeft يوم (تقريبًا $weeksLeft أسبوع)';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== Header =====
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      rangeLine,
                      style: (tt.bodyLarge ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subLine,
                      style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                        color: cs.onSurface.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ===== Stats =====
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'وزنك الآن',
                  value: '${fmtKg(current)} كجم',
                  icon: Icons.monitor_weight_outlined,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  title: 'الهدف',
                  value: '${fmtKg(target)} كجم',
                  icon: Icons.flag_outlined,
                  cs: cs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatCardWide(
            title: 'الفارق',
            value: '${absDelta.toStringAsFixed(1)} كجم',
            subtitle: 'تقريبًا ${weekly.toStringAsFixed(2)} كجم أسبوعيًا',
            cs: cs,
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isLoss ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                color: cs.primary,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ===== Chart =====
          _ChartCard(
            current: current,
            target: target,
            cs: cs,
          ),

          const SizedBox(height: 12),

          // ===== Motivation =====
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.primary.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                  color: Colors.black.withOpacity(0.06),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    motivation,
                    style: (tt.bodyLarge ?? const TextStyle()).copyWith(
                      height: 1.55,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.86),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ===== CTA =====
          FilledButton(
            onPressed: busy ? null : onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('التالي'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final ColorScheme cs;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (tt.bodySmall ?? const TextStyle()).copyWith(
                    color: cs.onSurface.withOpacity(0.58),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: (tt.titleMedium ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
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

class _StatCardWide extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Widget leading;
  final ColorScheme cs;

  const _StatCardWide({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.leading,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (tt.bodySmall ?? const TextStyle()).copyWith(
                    color: cs.onSurface.withOpacity(0.58),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: (tt.titleMedium ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: (tt.bodySmall ?? const TextStyle()).copyWith(
                    color: cs.onSurface.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
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

class _ChartCard extends StatelessWidget {
  final double current;
  final double target;
  final ColorScheme cs;

  const _ChartCard({
    required this.current,
    required this.target,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final minV = math.min(current, target);
    final maxV = math.max(current, target);
    final pad = math.max(1.5, (maxV - minV) * 0.25);
    final minY = (minV - pad);
    final maxY = (maxV + pad);

    final mid = current + (target - current) * 0.55;

    final spots = <FlSpot>[
      FlSpot(0, current),
      FlSpot(1, mid),
      FlSpot(2, target),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'مسار الهدف',
                style: (tt.titleMedium ?? const TextStyle()).copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                'كجم',
                style: (tt.bodySmall ?? const TextStyle()).copyWith(
                  color: cs.onSurface.withOpacity(0.55),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                minX: 0,
                maxX: 2,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: (maxY - minY) / 4,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: cs.onSurface.withOpacity(0.06),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: (maxY - minY) / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(0),
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.45),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final s = (value == 0)
                            ? 'الآن'
                            : (value == 2)
                                ? 'هدفك'
                                : '';
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            s,
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.60),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    barWidth: 4,
                    gradient: LinearGradient(
                      colors: [cs.primary.withOpacity(0.95), cs.secondary.withOpacity(0.80)],
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          cs.primary.withOpacity(0.18),
                          cs.primary.withOpacity(0.00),
                        ],
                      ),
                    ),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, p, bar, i) {
                        final isEnd = (spot.x == 2);
                        final isStart = (spot.x == 0);
                        final double r = isEnd ? 6.5 : (isStart ? 5.5 : 0.0);
                        return FlDotCirclePainter(
                          radius: r,
                          color: cs.primary,
                          strokeWidth: 3,
                          strokeColor: cs.surface,
                        );
                      },
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((s) {
                        final label = (s.x == 0)
                            ? 'الآن'
                            : (s.x == 2)
                                ? 'الهدف'
                                : 'منتصف الطريق';
                        return LineTooltipItem(
                          '$label\n${s.y.toStringAsFixed(1)} كجم',
                          TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

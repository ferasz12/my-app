// =============================================================
// FILE: lib/screens/regimen_if16_screen.dart
// صفحة الصيام المتقطع — نسخة وازن المختصرة والمرتبة
// - مؤقت واضح بدون زحمة
// - إعداد سريع للمدة ووقت البداية
// - سجل + مراحل + تنبيهات بداية/منتصف/نهاية الصيام من FastingService
// =============================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../fasting/fasting_history_page.dart';
import '../fasting/fasting_ring.dart';
import '../fasting/fasting_service.dart';
import '../fasting/fasting_stage_engine.dart';
import '../regimens/high_protein_guard.dart';
import '../regimens/keto_guard.dart';
import '../regimens/lowcarb_guard.dart';
import '../regimens/lowfat_guard.dart';
import '../regimens/mediterranean_guard.dart';
import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'regimen_screen.dart' show DietBus;

class RegimenIF16Screen extends StatefulWidget {
  const RegimenIF16Screen({super.key});

  @override
  State<RegimenIF16Screen> createState() => _RegimenIF16ScreenState();
}

class _RegimenIF16ScreenState extends State<RegimenIF16Screen> {
  int _hours = 16;
  bool _startNow = true;
  bool _strictMode = true;
  bool _busy = false;
  TimeOfDay? _customStart;

  final _timeFmt = DateFormat('hh:mm a', 'ar');
  final _dateFmt = DateFormat('EEE، d MMM - hh:mm a', 'ar');

  DateTime get _now => DateTime.now();

  DateTime get _plannedStart {
    if (_startNow || _customStart == null) return _now;
    final selected = DateTime(_now.year, _now.month, _now.day, _customStart!.hour, _customStart!.minute);
    return selected.isBefore(_now) ? selected.add(const Duration(days: 1)) : selected;
  }

  DateTime get _plannedEnd => _plannedStart.add(Duration(hours: _hours));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fs = context.read<FastingService>();
      _strictMode = fs.enforce;
      fs.addListener(_onFastingChanged);
      setState(() {});
    });
  }

  @override
  void dispose() {
    try {
      context.read<FastingService>().removeListener(_onFastingChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onFastingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startFasting(FastingService fs) async {
    if (_busy) return;
    final ok = await _confirm(
      icon: Icons.play_circle_fill_rounded,
      title: 'بدء الصيام؟',
      message: 'سيتم تفعيل مؤقت الصيام وتنبيهات وازن. إذا كان الوضع الصارم شغال، سيمنع تسجيل الوجبات أثناء الصيام.',
      okText: 'ابدأ الآن',
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await KetoGuard.endRegimen();
      await LowCarbGuard.setActive(false);
      await LowFatGuard.setActive(false);
      await HighProteinGuard.setActive(false);
      await MediterraneanGuard.setActive(false);
      await DietBus.activateExclusive('if-16-8');
      await fs.startFasting(start: _plannedStart, end: _plannedEnd);
      await fs.setEnforce(_strictMode);
      await DietBus.setActiveById('if-16-8');
      DietBus.invalidate();
      if (!mounted) return;
      _snack('تم بدء الصيام وتنبيهات وازن اشتغلت');
    } catch (e) {
      if (!mounted) return;
      _snack('تعذر بدء الصيام: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopFasting(FastingService fs) async {
    if (_busy) return;
    final ok = await _confirm(
      icon: Icons.stop_circle_rounded,
      title: 'إنهاء الصيام؟',
      message: 'سيتم حفظ الجلسة في السجل وإلغاء تنبيهات الصيام.',
      okText: 'إنهاء',
      danger: true,
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await fs.stopFasting();
      await fs.setEnforce(false);
      await DietBus.setActive(null);
      DietBus.invalidate();
      if (!mounted) return;
      _snack('تم إنهاء الصيام وحفظ الجلسة');
    } catch (e) {
      if (!mounted) return;
      _snack('تعذر إنهاء الصيام: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text, textAlign: TextAlign.right)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FastingService>();
    final active = fs.isActive;
    final startAt = active ? fs.startAt : _plannedStart;
    final endAt = active ? fs.endAt : _plannedEnd;
    final elapsed = active ? fs.elapsed : Duration.zero;
    final total = active ? fs.total : Duration(hours: _hours);
    final remaining = active ? fs.remaining : Duration(hours: _hours);
    final stage = active ? fs.stage : FastingStageEngine.current(Duration.zero);
    final stats = _FastingStats.fromHistory(fs.history);

    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الصيام المتقطع'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'السجل',
              icon: const Icon(Icons.history_rounded),
              onPressed: _openHistory,
            ),
          ],
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _MainFastingCard(
                  active: active,
                  busy: _busy,
                  percent: active ? fs.percent : 0,
                  remaining: _formatDuration(remaining),
                  stateText: active ? stage.title : 'جاهز للبدء',
                  endText: endAt == null ? '--' : 'ينتهي ${_timeFmt.format(endAt.toLocal())}',
                  onPrimary: active ? () => _stopFasting(fs) : () => _startFasting(fs),
                ),
                const SizedBox(height: 12),
                _CompactStats(stats: stats),
                const SizedBox(height: 12),
                _PlanCard(
                  active: active,
                  hours: _hours,
                  startNow: _startNow,
                  strictMode: _strictMode,
                  startText: startAt == null ? '--' : _dateFmt.format(startAt.toLocal()),
                  endText: endAt == null ? '--' : _dateFmt.format(endAt.toLocal()),
                  onHoursChanged: active ? null : (v) => setState(() => _hours = v),
                  onStartNowChanged: active ? null : (v) => setState(() => _startNow = v),
                  onStrictChanged: active
                      ? null
                      : (v) async {
                          setState(() => _strictMode = v);
                          await fs.setEnforce(v);
                        },
                  onPickStart: active ? null : _pickStartTime,
                ),
                const SizedBox(height: 12),
                _MiniStageCard(
                  active: active,
                  elapsed: elapsed,
                  total: total,
                  stage: stage,
                  onTimeline: () => _showTimeline(elapsed: elapsed, total: total),
                ),
                const SizedBox(height: 12),
                _ToolsCard(
                  onHistory: _openHistory,
                  onGuide: _showGuide,
                  onTimeline: () => _showTimeline(elapsed: elapsed, total: total),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final t = await showTimePicker(context: context, initialTime: _customStart ?? TimeOfDay.now());
    if (t == null) return;
    setState(() {
      _startNow = false;
      _customStart = t;
    });
  }

  void _openHistory() {
    final fs = context.read<FastingService>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: fs, child: const FastingHistoryPage()),
      ),
    );
  }

  Future<bool?> _confirm({
    required IconData icon,
    required String title,
    required String message,
    required String okText,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 44),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okText))),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showTimeline({required Duration elapsed, required Duration total}) {
    final stages = FastingStageEngine.timeline(total);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.35,
          initialChildSize: 0.62,
          maxChildSize: 0.9,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 14),
              const Text('مراحل الصيام', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 10),
              ...stages.map((s) {
                final done = elapsed >= s.threshold;
                return ListTile(
                  leading: Icon(done ? Icons.check_circle_rounded : s.icon, color: done ? Colors.green : Theme.of(context).colorScheme.primary),
                  title: Text('${s.threshold.inHours} ساعة — ${s.title}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(s.description),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showGuide() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('نصائح وازن للصيام', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            SizedBox(height: 12),
            _GuideBullet('ابدأ بـ 12 أو 14 ساعة إذا أنت جديد.'),
            _GuideBullet('اشرب ماء كفاية، ولا تستخدم الصيام الجاف.'),
            _GuideBullet('اكسر الصيام بوجبة فيها بروتين وخضار، مو سكريات فقط.'),
            _GuideBullet('إذا حسيت بدوخة قوية أو تعب غير طبيعي، أوقف الصيام.'),
          ]),
        ),
      ),
    );
  }
}

class _MainFastingCard extends StatelessWidget {
  final bool active;
  final bool busy;
  final double percent;
  final String remaining;
  final String stateText;
  final String endText;
  final VoidCallback onPrimary;

  const _MainFastingCard({required this.active, required this.busy, required this.percent, required this.remaining, required this.stateText, required this.endText, required this.onPrimary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: [cs.primary.withOpacity(.94), cs.primary.withOpacity(.70)]),
        boxShadow: [BoxShadow(color: cs.primary.withOpacity(.22), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.timer_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 8),
          Expanded(child: Text(active ? 'صيامك شغال الآن' : 'ابدأ صيامك بهدوء', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.17), borderRadius: BorderRadius.circular(999)),
            child: Text(active ? 'نشط' : 'جاهز', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: 210,
          child: FastingRing(
            percent: percent,
            centerTop: active ? remaining : 'اختر الخطة',
            centerBottom: active ? endText : stateText,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onPrimary,
            icon: Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(active ? 'إنهاء الصيام' : 'بدء الصيام'),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: cs.primary),
          ),
        ),
      ]),
    );
  }
}

class _CompactStats extends StatelessWidget {
  final _FastingStats stats;
  const _CompactStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _StatBox(label: 'الجلسات', value: '${stats.sessions}')),
      const SizedBox(width: 8),
      Expanded(child: _StatBox(label: 'المكتملة', value: '${stats.completed}')),
      const SizedBox(width: 8),
      Expanded(child: _StatBox(label: 'الأطول', value: '${stats.longestHours}س')),
    ]);
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceVariant.withOpacity(.35), borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant.withOpacity(.6))),
      child: Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool active;
  final int hours;
  final bool startNow;
  final bool strictMode;
  final String startText;
  final String endText;
  final ValueChanged<int>? onHoursChanged;
  final ValueChanged<bool>? onStartNowChanged;
  final ValueChanged<bool>? onStrictChanged;
  final VoidCallback? onPickStart;

  const _PlanCard({required this.active, required this.hours, required this.startNow, required this.strictMode, required this.startText, required this.endText, required this.onHoursChanged, required this.onStartNowChanged, required this.onStrictChanged, required this.onPickStart});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'الخطة السريعة',
      icon: Icons.tune_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [12, 14, 16, 18, 20].map((h) => ChoiceChip(label: Text('$h ساعة'), selected: hours == h, onSelected: active ? null : (_) => onHoursChanged?.call(h))).toList()),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: startNow,
          onChanged: active ? null : onStartNowChanged,
          title: const Text('ابدأ الآن'),
          subtitle: Text(startNow ? 'المؤقت يبدأ فورًا' : 'اختر وقت بداية الصيام'),
        ),
        if (!startNow)
          OutlinedButton.icon(onPressed: active ? null : onPickStart, icon: const Icon(Icons.schedule_rounded), label: const Text('اختيار وقت البداية')),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: strictMode,
          onChanged: active ? null : onStrictChanged,
          title: const Text('وضع وازن الصارم'),
          subtitle: const Text('يمنع تسجيل الوجبات أثناء نافذة الصيام'),
        ),
        const Divider(height: 20),
        _PlanLine(icon: Icons.play_circle_outline_rounded, label: 'البداية', value: startText),
        const SizedBox(height: 6),
        _PlanLine(icon: Icons.flag_circle_rounded, label: 'النهاية', value: endText),
      ]),
    );
  }
}

class _MiniStageCard extends StatelessWidget {
  final bool active;
  final Duration elapsed;
  final Duration total;
  final FastingStage stage;
  final VoidCallback onTimeline;
  const _MiniStageCard({required this.active, required this.elapsed, required this.total, required this.stage, required this.onTimeline});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'مرحلتك الآن',
      icon: stage.icon,
      trailing: TextButton(onPressed: onTimeline, child: const Text('المراحل')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(active ? stage.title : 'ابدأ الصيام لعرض المرحلة', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 6),
        Text(active ? stage.description : 'وازن يعرض لك المرحلة الحالية بشكل مختصر بدون زحمة.'),
      ]),
    );
  }
}

class _ToolsCard extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onGuide;
  final VoidCallback onTimeline;
  const _ToolsCard({required this.onHistory, required this.onGuide, required this.onTimeline});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'أدوات سريعة',
      icon: Icons.widgets_rounded,
      child: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: onHistory, icon: const Icon(Icons.history_rounded), label: const Text('السجل'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: onTimeline, icon: const Icon(Icons.timeline_rounded), label: const Text('المراحل'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: onGuide, icon: const Icon(Icons.lightbulb_rounded), label: const Text('نصائح'))),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _Card({required this.title, required this.icon, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: cs.outlineVariant.withOpacity(.65))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _PlanLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _PlanLine({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, color: cs.primary, size: 20),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w800)),
      Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
    ]);
  }
}

class _GuideBullet extends StatelessWidget {
  final String text;
  const _GuideBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

class _FastingStats {
  final int sessions;
  final int completed;
  final int longestHours;

  const _FastingStats({required this.sessions, required this.completed, required this.longestHours});

  factory _FastingStats.fromHistory(List<FastingSession> history) {
    if (history.isEmpty) return const _FastingStats(sessions: 0, completed: 0, longestHours: 0);
    var completed = 0;
    var longest = 0;
    for (final h in history) {
      if (h.percentDone >= .95) completed++;
      final hours = Duration(seconds: h.durationSec).inHours;
      if (hours > longest) longest = hours;
    }
    return _FastingStats(sessions: history.length, completed: completed, longestHours: longest);
  }
}

String _formatDuration(Duration d) {
  final safe = d.isNegative ? Duration.zero : d;
  final h = safe.inHours.toString().padLeft(2, '0');
  final m = (safe.inMinutes % 60).toString().padLeft(2, '0');
  final s = (safe.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

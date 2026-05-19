// =============================================================
// FILE: lib/screens/regimen_if16_screen.dart
// صفحة الصيام المتقطع — واجهة مرتبة وهادئة مع الحفاظ على نفس الميزات
// =============================================================
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../fasting/fasting_history_page.dart';
import '../fasting/fasting_ring.dart';
import '../fasting/fasting_service.dart';
import '../fasting/fasting_stage_engine.dart';
import '../regimens/keto_guard.dart';
import '../regimens/lowcarb_guard.dart';
import '../regimens/lowfat_guard.dart';
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
  TimeOfDay? _customStart;
  bool _busy = false;

  final _timeFmt = DateFormat('hh:mm a', 'ar');
  final _dateFmt = DateFormat('EEEE، d MMM - hh:mm a', 'ar');

  DateTime get _now => DateTime.now();

  DateTime get _plannedStart {
    if (_startNow || _customStart == null) return _now;
    final selected = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _customStart!.hour,
      _customStart!.minute,
    );
    return selected.isBefore(_now) ? selected.add(const Duration(days: 1)) : selected;
  }

  DateTime get _plannedEnd => _plannedStart.add(Duration(hours: _hours));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fs = context.read<FastingService>();
      _syncEnforce(fs);
      fs.addListener(_onFastingChanged);
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
    if (!mounted) return;
    _syncEnforce(context.read<FastingService>());
    setState(() {});
  }

  Future<void> _syncEnforce(FastingService fs) async {
    final shouldEnforce = fs.isActive;
    if (fs.enforce != shouldEnforce) {
      await fs.setEnforce(shouldEnforce);
    }
  }

  Future<void> _startFasting(FastingService fs) async {
    final ok = await _confirmStart();
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await KetoGuard.endRegimen();
      await LowCarbGuard.setActive(false);
      await LowFatGuard.setActive(false);
      await DietBus.activateExclusive('if-16-8');

      await fs.startFasting(start: _plannedStart, end: _plannedEnd);
      await fs.setEnforce(true);

      await DietBus.setActiveById('if-16-8');
      DietBus.invalidate();

      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('تم بدء الصيام، والمؤقت اشتغل الآن');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('تعذر بدء الصيام: $e');
    }
  }

  Future<void> _stopFasting(FastingService fs) async {
    final ok = await _confirmStop();
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await fs.stopFasting();
      await fs.setEnforce(false);
      await DietBus.setActive(null);
      DietBus.invalidate();

      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('تم إنهاء الصيام');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('تعذر إنهاء الصيام: $e');
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text, textAlign: TextAlign.right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FastingService>();
    final active = fs.isActive;
    final total = active ? fs.total : Duration(hours: _hours);
    final remaining = active ? fs.remaining : Duration(hours: _hours);
    final elapsed = active ? fs.elapsed : Duration.zero;
    final startAt = active ? fs.startAt : _plannedStart;
    final endAt = active ? fs.endAt : _plannedEnd;
    final stage = active ? fs.stage : FastingStageEngine.current(Duration.zero);
    final nextStage = active ? FastingStageEngine.nextOrNull(elapsed, total) : null;
    final stats = _FastingStats.fromHistory(fs.history);

    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
        appBar: AppBar(
          title: const Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Text('الصيام المتقطع'),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'سجل الصيام',
              onPressed: _openHistory,
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        ),
        body: Directionality(
          textDirection: ui.TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
              children: [
                _HeroCard(
                  active: active,
                  busy: _busy,
                  hours: _hours,
                  percent: active ? fs.percent : 0,
                  remaining: _formatHms(remaining),
                  startText: startAt == null ? '--' : _timeFmt.format(startAt.toLocal()),
                  endText: endAt == null ? '--' : _timeFmt.format(endAt.toLocal()),
                  stage: stage,
                  nextStage: nextStage,
                  onPrimary: active ? () => _stopFasting(fs) : () => _startFasting(fs),
                ),
                const SizedBox(height: 14),
                if (active) ...[
                  _ActiveLockNotice(endText: endAt == null ? '--' : _timeFmt.format(endAt.toLocal())),
                  const SizedBox(height: 14),
                ],
                _PlanCard(
                  active: active,
                  hours: _hours,
                  startNow: _startNow,
                  customStart: _customStart,
                  plannedEndText: _dateFmt.format(_plannedEnd.toLocal()),
                  onHoursChanged: active || _busy ? null : (h) => setState(() => _hours = h),
                  onStartNowChanged: active || _busy ? null : (v) => setState(() => _startNow = v),
                  onPickStart: active || _busy ? null : _pickStartTime,
                ),
                const SizedBox(height: 14),
                _StageCard(
                  active: active,
                  stage: stage,
                  nextStage: nextStage,
                  elapsed: elapsed,
                  total: total,
                  onTimeline: () => _showTimelineSheet(elapsed: elapsed, total: total, active: active),
                ),
                const SizedBox(height: 14),
                _StatsCard(stats: stats),
                const SizedBox(height: 14),
                _ToolsCard(
                  onHistory: _openHistory,
                  onTimeline: () => _showTimelineSheet(elapsed: elapsed, total: total, active: active),
                  onGuide: _showGuideMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _customStart ?? TimeOfDay.now(),
    );
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
        builder: (_) => ChangeNotifierProvider.value(
          value: fs,
          child: const FastingHistoryPage(),
        ),
      ),
    );
  }

  Future<bool?> _confirmStart() {
    return _confirmSheet(
      icon: Icons.play_circle_fill_rounded,
      title: 'بدء الصيام؟',
      message:
          'سيبدأ الصيام لمدة $_hours ساعة. سيتم قفل الكيتو، لو كارب، وقليل الدهون تلقائيًا حتى تنهي الصيام.',
      okText: 'ابدأ الصيام',
    );
  }

  Future<bool?> _confirmStop() {
    return _confirmSheet(
      icon: Icons.stop_circle_outlined,
      title: 'إنهاء الصيام؟',
      message: 'سيتم حفظ مدة الصيام في السجل، وفتح إمكانية تشغيل نظام آخر بعد الإنهاء.',
      okText: 'إنهاء',
      danger: true,
    );
  }

  Future<bool?> _confirmSheet({
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 18),
              Row(
                children: [
                  _IconBubble(icon: icon, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(message, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: danger ? FilledButton.styleFrom(backgroundColor: color) : null,
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(okText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGuideMenu() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Row(
                children: [
                  _IconBubble(icon: Icons.menu_book_rounded, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'دليل الصيام السريع',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _GuideTile(icon: Icons.local_cafe_rounded, title: 'المسموح أثناء الصيام', onTap: () { Navigator.pop(ctx); _showAllowedGuide(); }),
              _GuideTile(icon: Icons.restaurant_menu_rounded, title: 'طريقة كسر الصيام', onTap: () { Navigator.pop(ctx); _showBreakFastGuide(); }),
              _GuideTile(icon: Icons.warning_amber_rounded, title: 'أخطاء تخرب الالتزام', onTap: () { Navigator.pop(ctx); _showMistakesGuide(); }),
              _GuideTile(icon: Icons.health_and_safety_rounded, title: 'إذا تعبت أثناء الصيام', onTap: () { Navigator.pop(ctx); _showTiredGuide(); }),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimelineSheet({
    required Duration elapsed,
    required Duration total,
    required bool active,
  }) {
    final list = FastingStageEngine.timeline(total <= Duration.zero ? const Duration(hours: 16) : total);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            children: [
              const _SheetHandle(),
              const SizedBox(height: 18),
              Text('مراحل الصيام', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final s in list)
                _TimelineRow(stage: s, reached: active && elapsed >= s.threshold),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllowedGuide() {
    _showInfoSheet(
      icon: Icons.local_cafe_rounded,
      title: 'المسموح أثناء الصيام',
      items: const [
        'الماء مسموح ويفضل توزيعه خلال ساعات الصيام.',
        'القهوة السوداء والشاي بدون سكر غالبًا لا تكسر الصيام.',
        'المشروبات الدايت قد لا تحتوي سعرات، لكنها قد تزيد الشهية عند بعض الناس.',
        'أي شيء فيه سعرات واضحة مثل الحليب، العصير، السكر، أو المكسرات يكسر الصيام.',
      ],
    );
  }

  void _showBreakFastGuide() {
    _showInfoSheet(
      icon: Icons.restaurant_menu_rounded,
      title: 'كسر الصيام بذكاء',
      items: const [
        'ابدأ بماء، ثم وجبة متوازنة بدل الاندفاع لسناك عالي السعرات.',
        'خل أول وجبة فيها بروتين واضح مثل دجاج، تونة، بيض، لحم قليل دهن، أو زبادي يوناني.',
        'أضف كارب مناسب لهدفك مثل رز، بطاطس، شوفان، أو خبز بر بكمية محسوبة.',
        'لا تبدأ بوجبة عالية الدهون جدًا إذا معدتك تتعب بعد الصيام.',
      ],
    );
  }

  void _showMistakesGuide() {
    _showInfoSheet(
      icon: Icons.warning_amber_rounded,
      title: 'أخطاء تخرب الصيام',
      items: const [
        'الأكل القليل جدًا في نافذة الأكل ثم التعويض آخر الليل.',
        'نسيان البروتين والماء ثم الشعور بتعب وجوع شديد.',
        'كسر الصيام بسكريات كثيرة يرفع الشهية ويصعب الالتزام.',
        'تطويل الصيام رغم وجود دوخة أو تعب غير طبيعي.',
      ],
    );
  }

  void _showTiredGuide() {
    _showInfoSheet(
      icon: Icons.health_and_safety_rounded,
      title: 'إذا تعبت أثناء الصيام',
      items: const [
        'اشرب ماء واجلس في مكان هادئ إذا كان التعب بسيطًا.',
        'إذا عندك دوخة قوية، رجفة، أو تعب غير طبيعي، لا تكابر وأنهِ الصيام.',
        'إذا عندك مرض مزمن أو تستخدم أدوية، استشر مختص قبل تطبيق الصيام لفترات طويلة.',
        'وازن يساعدك تنظم الصيام، لكنه لا يغني عن نصيحة الطبيب عند الحالات الصحية.',
      ],
    );
  }

  void _showInfoSheet({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 18),
              Row(
                children: [
                  _IconBubble(icon: icon, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...items.map((e) => _BulletText(e)),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHms(Duration d) {
    final seconds = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.active,
    required this.busy,
    required this.hours,
    required this.percent,
    required this.remaining,
    required this.startText,
    required this.endText,
    required this.stage,
    required this.nextStage,
    required this.onPrimary,
  });

  final bool active;
  final bool busy;
  final int hours;
  final double percent;
  final String remaining;
  final String startText;
  final String endText;
  final FastingStage stage;
  final FastingStage? nextStage;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.98),
            cs.primary.withOpacity(0.82),
            cs.tertiary.withOpacity(0.54),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.20),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(top: -70, start: -45, child: _Glow(size: 185, color: Colors.white.withOpacity(0.10))),
          PositionedDirectional(bottom: -90, end: -40, child: _Glow(size: 210, color: Colors.white.withOpacity(0.10))),
          Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 355;
                final ring = narrow ? 122.0 : 142.0;

                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.start,
                      children: [
                        _WhitePill(
                          icon: active ? Icons.lock_rounded : Icons.radio_button_unchecked_rounded,
                          text: active ? 'الصيام نشط' : 'جاهز للبدء',
                        ),
                        _WhitePill(icon: Icons.schedule_rounded, text: '$hours ساعة'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      active ? 'باقي على نهاية الصيام' : 'ابدأ صيامك بخطة واضحة',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white.withOpacity(0.86),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active ? remaining : _planLabel(hours),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _StageMiniCard(stage: stage, nextStage: nextStage, active: active),
                  ],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (narrow)
                      Column(
                        children: [
                          SizedBox.square(
                            dimension: ring,
                            child: FastingRing(
                              percent: percent,
                              centerTop: active ? remaining : '$hours ساعة',
                              centerBottom: active ? 'المتبقي' : 'الخطة',
                            ),
                          ),
                          const SizedBox(height: 16),
                          summary,
                        ],
                      )
                    else
                      Row(
                        children: [
                          SizedBox.square(
                            dimension: ring,
                            child: FastingRing(
                              percent: percent,
                              centerTop: active ? remaining : '$hours ساعة',
                              centerBottom: active ? 'المتبقي' : 'الخطة',
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(child: summary),
                        ],
                      ),
                    const SizedBox(height: 16),
                    _WindowRow(start: startText, end: endText),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: active ? Colors.white.withOpacity(0.18) : Colors.white,
                          foregroundColor: active ? Colors.white : cs.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: busy ? null : onPrimary,
                        icon: busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(active ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded),
                        label: Text(
                          active ? 'إنهاء الصيام' : 'ابدأ الصيام الآن',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.active,
    required this.hours,
    required this.startNow,
    required this.plannedEndText,
    this.customStart,
    this.onHoursChanged,
    this.onStartNowChanged,
    this.onPickStart,
  });

  final bool active;
  final int hours;
  final bool startNow;
  final TimeOfDay? customStart;
  final String plannedEndText;
  final ValueChanged<int>? onHoursChanged;
  final ValueChanged<bool>? onStartNowChanged;
  final VoidCallback? onPickStart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.tune_rounded,
      title: 'إعداد الصيام',
      subtitle: active ? 'الخطة مقفلة أثناء الصيام.' : 'اختر المدة ووقت البداية.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in const [12, 14, 16, 18, 20])
                _PlanChip(
                  label: _planLabel(h),
                  selected: hours == h,
                  enabled: !active && onHoursChanged != null,
                  onTap: () => onHoursChanged?.call(h),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.play_arrow_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ابدأ من الآن',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Switch.adaptive(
                      value: startNow,
                      onChanged: active || onStartNowChanged == null ? null : onStartNowChanged,
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: startNow
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: active ? null : onPickStart,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: const Icon(Icons.access_time_rounded),
                              label: Text(customStart == null ? 'اختيار وقت البداية' : 'البداية: ${customStart!.format(context)}'),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                _InfoLine(
                  icon: Icons.event_available_rounded,
                  text: 'الانتهاء المتوقع: $plannedEndText',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.active,
    required this.stage,
    required this.nextStage,
    required this.elapsed,
    required this.total,
    required this.onTimeline,
  });

  final bool active;
  final FastingStage stage;
  final FastingStage? nextStage;
  final Duration elapsed;
  final Duration total;
  final VoidCallback onTimeline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final elapsedText = _formatStageTime(elapsed);
    final totalText = _formatStageTime(total);

    return _SectionCard(
      icon: stage.icon,
      title: active ? stage.title : 'مراحل الصيام',
      subtitle: active
          ? (nextStage == null ? 'أنت في آخر مرحلة من الخطة.' : 'المرحلة القادمة: ${nextStage!.title}')
          : 'تظهر المراحل بالتدرج بعد تشغيل الصيام.',
      trailing: TextButton(
        onPressed: onTimeline,
        child: const Text('عرض المراحل'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            active ? stage.description : 'ابدأ الصيام، ووازن يعرض لك المرحلة الحالية وماذا يحدث خلال الخطة.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: active ? (total.inSeconds <= 0 ? 0 : (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0)) : 0,
              backgroundColor: cs.surfaceVariant.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SmallLabel(label: 'المنقضي', value: active ? elapsedText : 'لم يبدأ')),
              const SizedBox(width: 8),
              Expanded(child: _SmallLabel(label: 'الخطة', value: totalText)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final _FastingStats stats;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.insights_rounded,
      title: 'ملخص الصيام',
      subtitle: 'إحصائياتك من السجل.',
      child: Row(
        children: [
          Expanded(child: _StatBox(label: 'الستريك', value: '${stats.streak}', suffix: 'يوم', icon: Icons.local_fire_department_rounded)),
          const SizedBox(width: 10),
          Expanded(child: _StatBox(label: 'الجلسات', value: '${stats.sessions}', suffix: 'جلسة', icon: Icons.check_circle_rounded)),
          const SizedBox(width: 10),
          Expanded(child: _StatBox(label: 'المتوسط', value: stats.avgHours.toStringAsFixed(1), suffix: 'س', icon: Icons.timer_rounded)),
        ],
      ),
    );
  }
}

class _ToolsCard extends StatelessWidget {
  const _ToolsCard({required this.onHistory, required this.onTimeline, required this.onGuide});

  final VoidCallback onHistory;
  final VoidCallback onTimeline;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.grid_view_rounded,
      title: 'الأدوات',
      subtitle: 'كل شيء تحتاجه للصيام في مكان مرتب.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _ToolButton(icon: Icons.timeline_rounded, label: 'المراحل', onTap: onTimeline)),
              const SizedBox(width: 10),
              Expanded(child: _ToolButton(icon: Icons.menu_book_rounded, label: 'الدليل', onTap: onGuide)),
              const SizedBox(width: 10),
              Expanded(child: _ToolButton(icon: Icons.history_rounded, label: 'السجل', onTap: onHistory)),
            ],
          ),
          const SizedBox(height: 12),
          const _InfoLine(
            icon: Icons.notifications_active_rounded,
            text: 'التنبيهات تعمل لبداية الصيام، منتصف المدة، النهاية، وتذكير الوجبة.',
          ),
        ],
      ),
    );
  }
}

class _ActiveLockNotice extends StatelessWidget {
  const _ActiveLockNotice({required this.endText});

  final String endText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          _IconBubble(icon: Icons.lock_rounded, color: cs.primary, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'أثناء الصيام يتم قفل إضافة الوجبات وباقي الأنظمة حتى $endText.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.82)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconBubble(icon: icon, color: cs.primary, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.62)),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primary.withOpacity(0.16) : cs.surface;
    final border = selected ? cs.primary.withOpacity(0.42) : cs.outlineVariant.withOpacity(0.86);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minWidth: 68),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? bg : bg.withOpacity(0.58),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                color: selected ? cs.primary : cs.onSurface.withOpacity(enabled ? 0.88 : 0.45),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 5),
              Icon(Icons.check_rounded, size: 16, color: cs.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.start, required this.end});
  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _GlassTime(icon: Icons.play_arrow_rounded, label: 'البداية', value: start)),
        const SizedBox(width: 8),
        Expanded(child: _GlassTime(icon: Icons.flag_rounded, label: 'النهاية', value: end)),
      ],
    );
  }
}

class _GlassTime extends StatelessWidget {
  const _GlassTime({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 10)),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageMiniCard extends StatelessWidget {
  const _StageMiniCard({required this.stage, required this.nextStage, required this.active});
  final FastingStage stage;
  final FastingStage? nextStage;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(stage.icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? stage.title : 'مراحل الصيام جاهزة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  active
                      ? (nextStage == null ? 'أنت في آخر مرحلة.' : 'القادمة: ${nextStage!.title}')
                      : 'تظهر المرحلة بعد التشغيل.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.suffix, required this.icon});
  final String label;
  final String value;
  final String suffix;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.72)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value $suffix',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.72)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: cs.primary),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: cs.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.28),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurface.withOpacity(0.58))),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.stage, required this.reached});
  final FastingStage stage;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: reached ? cs.primary.withOpacity(0.14) : cs.surfaceVariant.withOpacity(0.45),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(reached ? Icons.check_rounded : stage.icon, color: reached ? cs.primary : cs.onSurface.withOpacity(0.50), size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_formatStageTime(stage.threshold)} • ${stage.title}', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(stage.description, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.color, this.size = 46});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size >= 44 ? 16 : 14),
      ),
      child: Icon(icon, color: color, size: size >= 44 ? 22 : 19),
    );
  }
}

class _GuideTile extends StatelessWidget {
  const _GuideTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.26),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
              Icon(Icons.chevron_left_rounded, color: cs.onSurface.withOpacity(0.40)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }
}

class _FastingStats {
  const _FastingStats({required this.sessions, required this.streak, required this.avgHours});

  final int sessions;
  final int streak;
  final double avgHours;

  static _FastingStats fromHistory(List<FastingSession> history) {
    if (history.isEmpty) return const _FastingStats(sessions: 0, streak: 0, avgHours: 0);

    final completed = history.where((s) => s.durationSec > 0).toList();
    final avg = completed.isEmpty
        ? 0.0
        : completed.map((s) => s.durationSec / 3600.0).reduce((a, b) => a + b) / completed.length;

    final days = completed.map((s) => s.ymd).toSet();
    int streak = 0;
    var d = DateTime.now();
    for (int i = 0; i < 120; i++) {
      final ymd = DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
      if (days.contains(ymd)) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return _FastingStats(sessions: completed.length, streak: streak, avgHours: avg);
  }
}

String _planLabel(int h) {
  switch (h) {
    case 12:
      return '12/12';
    case 14:
      return '14/10';
    case 16:
      return '16/8';
    case 18:
      return '18/6';
    case 20:
      return '20/4';
    default:
      return '$h ساعة';
  }
}

String _formatStageTime(Duration d) {
  if (d.inMinutes <= 0) return 'البداية';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h <= 0) return '$m دقيقة';
  if (m == 0) return '$h ساعة';
  return '$h ساعة و$m دقيقة';
}

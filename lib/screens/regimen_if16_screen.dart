// =============================================================
// FILE: lib/screens/regimen_if16_screen.dart
// صفحة الصيام المتقطع — نسخة ثابتة بدون سكرول + مؤقت فوري + AppBar بنفس اتجاه التطبيق
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
            child: LayoutBuilder(
              builder: (context, c) {
                // توزيع مرن للارتفاعات بدون سكرول، عشان الصفحة تثبت على الجوالات الصغيرة.
                final h = c.maxHeight;
                final verySmall = h < 620;
                final small = h < 700;
                final gap = verySmall ? 6.0 : (small ? 8.0 : 10.0);
                final padTop = verySmall ? 6.0 : 8.0;
                final padBottom = verySmall ? 8.0 : 12.0;

                var heroHeight = (h * (verySmall ? 0.38 : 0.39))
                    .clamp(218.0, small ? 274.0 : 292.0)
                    .toDouble();
                var setupHeight = (h * (_startNow ? 0.255 : 0.292))
                    .clamp(_startNow ? 148.0 : 176.0, _startNow ? 202.0 : 224.0)
                    .toDouble();

                // اضمن أن الجزء السفلي لا يقل عن حد عملي، ولو الشاشة صغيرة قلّص الأعلى بدل overflow.
                final availableForBottom = h - padTop - padBottom - (gap * 2) - heroHeight - setupHeight;
                final minBottom = verySmall ? 104.0 : 132.0;
                if (availableForBottom < minBottom) {
                  final deficit = minBottom - availableForBottom;
                  final cutHero = (deficit * 0.62).clamp(0.0, 36.0).toDouble();
                  final cutSetup = (deficit - cutHero).clamp(0.0, 30.0).toDouble();
                  heroHeight = (heroHeight - cutHero).clamp(208.0, 292.0).toDouble();
                  setupHeight = (setupHeight - cutSetup).clamp(_startNow ? 142.0 : 168.0, 224.0).toDouble();
                }

                return Padding(
                  padding: EdgeInsets.fromLTRB(12, padTop, 12, padBottom),
                  child: Column(
                    children: [
                      SizedBox(
                        height: heroHeight,
                        child: _HeroCard(
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
                      ),
                      SizedBox(height: gap),
                      SizedBox(
                        height: setupHeight,
                        child: _ControlCard(
                          active: active,
                          hours: _hours,
                          startNow: _startNow,
                          customStart: _customStart,
                          plannedEndText: _dateFmt.format(_plannedEnd.toLocal()),
                          onHoursChanged: active || _busy ? null : (h) => setState(() => _hours = h),
                          onStartNowChanged: active || _busy ? null : (v) => setState(() => _startNow = v),
                          onPickStart: active || _busy ? null : _pickStartTime,
                        ),
                      ),
                      SizedBox(height: gap),
                      Expanded(
                        child: _BottomTools(
                          active: active,
                          endText: endAt == null ? '--' : _timeFmt.format(endAt.toLocal()),
                          stats: stats,
                          onHistory: _openHistory,
                          onTimeline: () => _showTimelineSheet(elapsed: elapsed, total: total, active: active),
                          onGuide: _showGuideMenu,
                        ),
                      ),
                    ],
                  ),
                );
              },
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 16),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('دليل الصيام السريع', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 12),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              const _SheetHandle(),
              const SizedBox(height: 14),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...items.map((e) => _BulletText(e)),
              const SizedBox(height: 14),
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

    return LayoutBuilder(
      builder: (context, c) {
        final short = c.maxHeight < 246;
        final veryShort = c.maxHeight < 222;
        final narrow = c.maxWidth < 340;
        final pad = short ? 10.0 : 14.0;
        final gap = short ? 6.0 : 8.0;
        final topH = short ? 30.0 : 34.0;
        final windowH = short ? 36.0 : 40.0;
        final buttonH = short ? 38.0 : 44.0;
        final bodyH = (c.maxHeight - (pad * 2) - topH - windowH - buttonH - (gap * 3))
            .clamp(66.0, 136.0)
            .toDouble();
        final ringSize = bodyH.clamp(76.0, short ? 108.0 : 132.0).toDouble();

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(short ? 22 : 28),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                cs.primary.withOpacity(0.95),
                cs.primary.withOpacity(0.76),
                cs.tertiary.withOpacity(0.58),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              PositionedDirectional(top: -55, start: -38, child: _Glow(size: 160, color: Colors.white.withOpacity(0.10))),
              PositionedDirectional(bottom: -72, end: -44, child: _Glow(size: 190, color: Colors.white.withOpacity(0.10))),
              Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: topH,
                      child: Row(
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                children: [
                                  _WhitePill(
                                    icon: active ? Icons.lock_rounded : Icons.auto_awesome_rounded,
                                    text: active ? 'الصيام نشط' : 'جاهز للبدء',
                                    compact: short || narrow,
                                  ),
                                  SizedBox(width: short ? 6 : 8),
                                  _WhitePill(
                                    icon: Icons.schedule_rounded,
                                    text: '$hours ساعة',
                                    compact: short || narrow,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            active ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                            color: Colors.white,
                            size: short ? 20 : 24,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: bodyH,
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: ringSize,
                            child: FastingRing(
                              percent: percent,
                              centerTop: active ? remaining : '$hours ساعة',
                              centerBottom: active ? 'المتبقي' : 'الخطة',
                            ),
                          ),
                          SizedBox(width: short ? 8 : 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  active ? 'استمر.. أنت داخل نافذة الصيام' : 'ابدأ صيامك من هنا',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: veryShort ? 13 : (short ? 14 : null),
                                  ),
                                ),
                                if (!veryShort) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    active
                                        ? 'منع الوجبات وباقي الأنظمة مفعّل حتى نهاية الصيام.'
                                        : 'المؤقت والتنبيهات وقفل الأنظمة تعمل مباشرة بعد البدء.',
                                    textAlign: TextAlign.right,
                                    maxLines: short ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withOpacity(0.86),
                                      height: 1.15,
                                      fontSize: short ? 10.5 : null,
                                    ),
                                  ),
                                ],
                                SizedBox(height: short ? 5 : 8),
                                Flexible(
                                  child: _StageMiniCard(
                                    stage: stage,
                                    nextStage: nextStage,
                                    active: active,
                                    compact: short,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(height: windowH, child: _WindowRow(start: startText, end: endText, compact: short || narrow)),
                    SizedBox(height: gap),
                    SizedBox(
                      height: buttonH,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: active ? Colors.white.withOpacity(0.18) : Colors.white,
                          foregroundColor: active ? Colors.white : cs.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(short ? 14 : 16)),
                          padding: EdgeInsets.symmetric(horizontal: short ? 10 : 14),
                        ),
                        onPressed: busy ? null : onPrimary,
                        icon: busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(active ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded, size: short ? 18 : 20),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            active ? 'إنهاء الصيام' : 'ابدأ الصيام الآن',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
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
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final short = c.maxHeight < 170;
        final veryShort = c.maxHeight < 154;
        final pad = short ? 9.0 : 12.0;
        final headerH = veryShort ? 34.0 : 40.0;
        final chipH = short ? 30.0 : 34.0;
        final boxPadV = short ? 6.0 : 8.0;

        return _Card(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: headerH,
                child: _CardTitle(
                  icon: Icons.tune_rounded,
                  title: 'إعداد الصيام',
                  subtitle: active ? 'الخطة مقفلة أثناء الصيام.' : 'اختر المدة ووقت البداية.',
                  compact: short,
                ),
              ),
              SizedBox(height: short ? 5 : 8),
              SizedBox(
                height: chipH,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final h in const [12, 14, 16, 18, 20]) ...[
                        _PlanChip(
                          label: _planLabel(h),
                          selected: hours == h,
                          enabled: !active && onHoursChanged != null,
                          compact: short,
                          onTap: () => onHoursChanged?.call(h),
                        ),
                        const SizedBox(width: 7),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: short ? 5 : 8),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: boxPadV),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withOpacity(0.30),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: short ? 32 : 36,
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow_rounded, color: cs.primary, size: short ? 18 : 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ابدأ من الآن',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: short ? 12 : null,
                                ),
                              ),
                            ),
                            Transform.scale(
                              scale: short ? 0.82 : 0.92,
                              child: Switch.adaptive(
                                value: startNow,
                                onChanged: active || onStartNowChanged == null ? null : onStartNowChanged,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!startNow) ...[
                        SizedBox(height: short ? 4 : 6),
                        SizedBox(
                          width: double.infinity,
                          height: short ? 32 : 36,
                          child: OutlinedButton.icon(
                            onPressed: active ? null : onPickStart,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.access_time_rounded, size: 17),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(customStart == null ? 'اختيار وقت البداية' : 'البداية: ${customStart!.format(context)}'),
                            ),
                          ),
                        ),
                      ],
                      if (!veryShort) ...[
                        SizedBox(height: short ? 3 : 5),
                        Row(
                          children: [
                            Icon(Icons.event_available_rounded, color: cs.primary, size: 17),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'الانتهاء المتوقع: $plannedEndText',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: short ? 10.5 : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primary.withOpacity(0.18) : cs.surface;
    final border = selected ? cs.primary.withOpacity(0.34) : cs.outlineVariant.withOpacity(0.85);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: compact ? 30 : 34,
        constraints: BoxConstraints(minWidth: compact ? 58 : 64),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13),
        decoration: BoxDecoration(
          color: enabled ? bg : bg.withOpacity(0.55),
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
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11 : 12,
                color: selected ? cs.primary : cs.onSurface.withOpacity(enabled ? 0.88 : 0.45),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 5),
              Icon(Icons.check_rounded, size: compact ? 14 : 16, color: cs.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomTools extends StatelessWidget {
  const _BottomTools({
    required this.active,
    required this.endText,
    required this.stats,
    required this.onHistory,
    required this.onTimeline,
    required this.onGuide,
  });

  final bool active;
  final String endText;
  final _FastingStats stats;
  final VoidCallback onHistory;
  final VoidCallback onTimeline;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final ultra = c.maxHeight < 126;
        final compact = c.maxHeight < 158;
        final pad = ultra ? 7.0 : 10.0;
        final buttonH = ultra ? 34.0 : 40.0;

        return _Card(
          padding: EdgeInsets.all(pad),
          child: Column(
            children: [
              if (active && !compact) ...[
                _MiniNotice(endText: endText),
                const SizedBox(height: 7),
              ],
              if (ultra)
                SizedBox(
                  height: 31,
                  child: Row(
                    children: [
                      Expanded(child: _StatInline(label: 'ستريك', value: '${stats.streak}ي', icon: Icons.local_fire_department_rounded)),
                      const SizedBox(width: 6),
                      Expanded(child: _StatInline(label: 'جلسات', value: '${stats.sessions}', icon: Icons.check_circle_rounded)),
                      const SizedBox(width: 6),
                      Expanded(child: _StatInline(label: 'متوسط', value: '${stats.avgHours.toStringAsFixed(1)}س', icon: Icons.timer_rounded)),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _StatBox(label: 'الستريك', value: '${stats.streak}', suffix: 'يوم', icon: Icons.local_fire_department_rounded, compact: compact)),
                      const SizedBox(width: 8),
                      Expanded(child: _StatBox(label: 'الجلسات', value: '${stats.sessions}', suffix: 'جلسة', icon: Icons.check_circle_rounded, compact: compact)),
                      const SizedBox(width: 8),
                      Expanded(child: _StatBox(label: 'المتوسط', value: stats.avgHours.toStringAsFixed(1), suffix: 'س', icon: Icons.timer_rounded, compact: compact)),
                    ],
                  ),
                ),
              SizedBox(height: ultra ? 6 : 8),
              SizedBox(
                height: buttonH,
                child: Row(
                  children: [
                    Expanded(child: _ToolButton(icon: Icons.timeline_rounded, label: 'المراحل', onTap: onTimeline, compact: compact)),
                    const SizedBox(width: 8),
                    Expanded(child: _ToolButton(icon: Icons.menu_book_rounded, label: 'الدليل', onTap: onGuide, compact: compact)),
                    const SizedBox(width: 8),
                    Expanded(child: _ToolButton(icon: Icons.history_rounded, label: 'السجل', onTap: onHistory, compact: compact)),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, color: cs.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'التنبيهات: بداية الصيام، منتصف المدة، النهاية، وتذكير وجبة.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatInline extends StatelessWidget {
  const _StatInline({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.30),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: cs.primary, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$label $value', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniNotice extends StatelessWidget {
  const _MiniNotice({required this.endText});
  final String endText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'باقي الأنظمة مقفلة حتى $endText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.compact = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: compact ? 16 : 18, color: cs.primary),
            SizedBox(width: compact ? 4 : 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 12 : 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, required this.subtitle, this.compact = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = compact ? 34.0 : 40.0;
    return Row(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
          ),
          child: Icon(icon, color: cs.primary, size: compact ? 18 : 21),
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 13 : null,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.64)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.suffix, required this.icon, this.compact = false});
  final String label;
  final String value;
  final String suffix;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 5 : 8),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: cs.primary, size: compact ? 16 : 18),
          SizedBox(height: compact ? 2 : 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: compact ? 10 : null)),
          SizedBox(height: compact ? 1 : 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value $suffix',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 12 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.start, required this.end, this.compact = false});
  final String start;
  final String end;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _GlassTime(icon: Icons.play_arrow_rounded, label: 'البداية', value: start, compact: compact)),
        SizedBox(width: compact ? 6 : 8),
        Expanded(child: _GlassTime(icon: Icons.flag_rounded, label: 'النهاية', value: end, compact: compact)),
      ],
    );
  }
}

class _GlassTime extends StatelessWidget {
  const _GlassTime({required this.icon, required this.label, required this.value, this.compact = false});
  final IconData icon;
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: compact ? 15 : 17),
          SizedBox(width: compact ? 5 : 7),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: compact ? 9 : 10)),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: compact ? 10.5 : 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageMiniCard extends StatelessWidget {
  const _StageMiniCard({required this.stage, required this.nextStage, required this.active, this.compact = false});
  final FastingStage stage;
  final FastingStage? nextStage;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 7 : 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(stage.icon, color: Colors.white, size: compact ? 18 : 22),
          SizedBox(width: compact ? 6 : 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? stage.title : 'مراحل الصيام جاهزة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: compact ? 12 : 13),
                ),
                SizedBox(height: compact ? 1 : 2),
                Text(
                  active
                      ? (nextStage == null ? 'أنت في آخر مرحلة.' : 'القادمة: ${nextStage!.title}')
                      : 'تظهر المرحلة بعد التشغيل.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: compact ? 10 : 11),
                ),
              ],
            ),
          ),
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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: reached ? cs.primary.withOpacity(0.14) : cs.surfaceVariant.withOpacity(0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(reached ? Icons.check_rounded : stage.icon, color: reached ? cs.primary : cs.onSurface.withOpacity(0.50), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_formatStageTime(stage.threshold)} • ${stage.title}', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(stage.description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.icon, required this.text, this.compact = false});
  final IconData icon;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: compact ? 13 : 15),
          SizedBox(width: compact ? 4 : 5),
          Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: compact ? 11 : 12)),
        ],
      ),
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
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
      padding: const EdgeInsets.only(bottom: 9),
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
          Expanded(child: Text(text)),
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

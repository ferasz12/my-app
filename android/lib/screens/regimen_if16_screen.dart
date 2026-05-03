// =============================================================
// FILE: lib/screens/regimen_if16_screen.dart
// شاشة الصيام المتقطع 16/8 — س:د:ث + مرحلة حالية (فقط أثناء الصيام)
// + زر يفتح صفحة "سجل الرجيم" منفصلة
// =============================================================
import 'dart:ui' as ui; // لاستخدام ui.TextDirection.rtl
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../fasting/fasting_service.dart';
import 'regimen_screen.dart' show DietBus;
import '../fasting/fasting_ring.dart';
import '../fasting/fasting_stage_engine.dart';
import '../fasting/fasting_history_page.dart';

class RegimenIF16Screen extends StatefulWidget {
  const RegimenIF16Screen({super.key});

  @override
  State<RegimenIF16Screen> createState() => _RegimenIF16ScreenState();
}

class _RegimenIF16ScreenState extends State<RegimenIF16Screen> {
  void _onFsChanged() {
    final fs = context.read<FastingService>();
    final shouldEnforce = fs.isActive;
    if (fs.enforce != shouldEnforce) {
      fs.setEnforce(shouldEnforce);
    
  @override
  void dispose() {
    final fs = context.read<FastingService>();
    try { fs.removeListener(_onFsChanged); } catch (_) {}
    super.dispose();
  }
}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fs = context.read<FastingService>();
      _onFsChanged(); // sync once on first build
      fs.addListener(_onFsChanged);
    });
  }

  bool byDuration = true;
  int hours = 16;
  TimeOfDay? startClock;

  final fmtDateTime = DateFormat('EEEE، d MMM - hh:mm a', 'ar');

  DateTime get _now => DateTime.now();
  DateTime get _startAt => startClock == null
      ? _now
      : DateTime(_now.year, _now.month, _now.day, startClock!.hour, startClock!.minute);
  DateTime get _endAt => _startAt.add(Duration(hours: hours));

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FastingService>();
    final cs = Theme.of(context).colorScheme;

    final remaining = fs.isActive ? fs.remaining : Duration(hours: hours);
    final remStrHms = _formatHms(remaining);
    final endStr = fs.isActive && fs.endAt != null
        ? fmtDateTime.format(fs.endAt!.toLocal())
        : fmtDateTime.format(_endAt.toLocal());

    final currentStage = fs.stage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الصيام المتقطع 16/8'),
        actions: [
          IconButton(
            tooltip: 'سجل الرجيم',
            onPressed: () {
              final fsInst = context.read<FastingService>();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: fsInst,
                    child: const FastingHistoryPage(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // المؤشّر + نصوص
          Card(elevation: 0, color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  FastingRing(
                    percent: fs.isActive ? fs.percent : 0,
                    centerTop: fs.isActive
                        ? 'المتبقي: $remStrHms'
                        : 'المدة المختارة: ${_formatHms(Duration(hours: hours))}',
                    centerBottom: 'ينتهي: $endStr',
                  ),
                  const SizedBox(height: 12),
                  // المرحلة الحالية تظهر فقط أثناء الصيام
                  if (fs.isActive) _StageNowTile(stage: currentStage),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          _InfoBox(
            title: 'كيف تستخدم الصيام 16/8؟',
            icon: Icons.schedule,
            color: cs.primary,
            children: [
              const Text(
                'اختر مدة الصيام (افتراضي 16 ساعة) أو حدّد وقت بداية (مثلاً 8:00 مساءً) وسنحسب لك وقت الانتهاء المتوقّع.',
              ),
              const SizedBox(height: 8),
              _FastingConfigurator(
                byDuration: byDuration,
                hours: hours,
                startClock: startClock,
                onToggleMode: (v) => setState(() => byDuration = v),
                onPickHours: (h) => setState(() => hours = h),
                onPickTime: (t) => setState(() => startClock = t),
              ),
              const SizedBox(height: 8),

              // أزرار التحكم: بدء/إنهاء + منع الأكل أثناء الصيام
              Row(children: [
                if (!fs.isActive)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await DietBus.activateExclusive('if-16-8');
                        await fs.startFasting(start: _startAt, end: _endAt);
                        await fs.setEnforce(true);
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.play_circle_fill),
                      label: const Text('ابدأ الصيام'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final ok = await _confirmStop(context);
                        if (ok == true) {
                          await fs.stopFasting();
                        await fs.setEnforce(false);
                        await DietBus.setActive(null);
                        DietBus.invalidate();
                        if (mounted) setState(() {});
                        }
                      },
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('إنهاء مبكر'),
                    ),
                  ),
              ]),

              const SizedBox(height: 8),
              // زر يفتح صفحة "سجل الرجيم" (لا نعرض السجل هنا)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('سجل الرجيم'),
                  onPressed: () {
                    final fsInst = context.read<FastingService>();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: fsInst,
                          child: const FastingHistoryPage(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          const SizedBox(height: 10),

          const SizedBox(height: 12),
          // مراحل الصيام: لا تظهر إلا إذا الصيام شغال
          if (fs.isActive)
            _InfoBox(
              title: 'مراحل الصيام اليوم',
              icon: Icons.timeline,
              color: Colors.amber,
              children: _buildStages(fs),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildStages(FastingService fs) {
    final total = fs.total;
    final nowElapsed = fs.elapsed;
    return FastingStageEngine.timeline(total).map((s) {
      final active = nowElapsed >= s.threshold;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          active ? Icons.check_circle : Icons.radio_button_unchecked,
          color: active ? Colors.green : null,
        ),
        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(s.description),
        trailing: Text(_formatMmH(s.threshold)),
      );
    }).toList();
  }

  String _formatHms(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  String _formatMmH(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h <= 0) return '${m} دقيقة';
    if (m == 0) return '${h} ساعة';
    return '${h}س ${m}د';
  }

  Future<bool?> _confirmStop(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنهاء الصيام؟'),
          content: const Text('هل أنت متأكد من إنهاء الصيام الحالي؟ ستفقد تقدمك لهذا اليوم.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('تأكيد الإنهاء')),
          ],
        ),
      ),
    );
  }
}

class _StageNowTile extends StatelessWidget {
  final FastingStage stage;
  const _StageNowTile({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('المرحلة الحالية: ${stage.title}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(stage.description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FastingConfigurator extends StatelessWidget {
  final bool byDuration;
  final int hours;
  final TimeOfDay? startClock;
  final ValueChanged<bool> onToggleMode; // true = بالمدة
  final ValueChanged<int> onPickHours;
  final ValueChanged<TimeOfDay> onPickTime;
  const _FastingConfigurator({
    required this.byDuration,
    required this.hours,
    required this.startClock,
    required this.onToggleMode,
    required this.onPickHours,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('بالمدة')),
          ButtonSegment(value: false, label: Text('بالوقت')),
          ],
          selected: {byDuration},
          onSelectionChanged: (s) => onToggleMode(s.first),
        ),
        const SizedBox(height: 8),
        if (byDuration) ...[
          Wrap(spacing: 8, children: [
            for (final h in [12, 14, 16, 18, 20])
              ChoiceChip(
                label: Text('$h ساعة'),
                selected: hours == h,
                onSelected: (_) => onPickHours(h),
              ),
          ]),
        ] else ...[
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(startClock == null
                    ? 'اختر وقت البداية (مثال 8:00 م)'
                    : 'البداية: ${startClock!.format(context)}'),
                onPressed: () async {
                  final now = TimeOfDay.now();
                  final t = await showTimePicker(context: context, initialTime: now);
                  if (t != null) onPickTime(t);
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: hours,
              items: [12, 14, 16, 18, 20]
                  .map((h) => DropdownMenuItem(value: h, child: Text('$h ساعة')))
                  .toList(),
              onChanged: (v) {
                if (v != null) onPickHours(v);
              },
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'نحسب لك وقت الانتهاء تلقائيًا بناءً على وقت البداية والمدة المختارة.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ]
      ],
    );
  }
}


class _InfoBox extends StatelessWidget {
  final String title; final IconData icon; final Color color; final List<Widget> children;
  const _InfoBox({required this.title, required this.icon, required this.color, required this.children});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.10),
                cs.surfaceVariant.withOpacity(0.35),
              ],
            ),
            border: Border.all(color: color.withOpacity(0.20), width: 1),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletBox extends StatelessWidget {
  final String title; final IconData icon; final Color color; final List<String> bullets; final String bullet;
  const _BulletBox({required this.title, required this.icon, required this.color, required this.bullets, this.bullet = '•'});
  @override
  Widget build(BuildContext context) => _InfoBox(
    title: title, icon: icon, color: color,
    children: bullets.map((e) => Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(bullet, style: TextStyle(color: color, fontWeight: FontWeight.bold)), const SizedBox(width: 6), Expanded(child: Text(e)),
      ]),
    )).toList(),
  );
}

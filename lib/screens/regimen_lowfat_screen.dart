
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import '../regimens/lowfat_guard.dart';
import 'regimen_screen.dart' show DietBus;

class RegimenLowFatScreen extends StatefulWidget {
  const RegimenLowFatScreen({super.key});

  @override
  State<RegimenLowFatScreen> createState() => _RegimenLowFatScreenState();
}

class _RegimenLowFatScreenState extends State<RegimenLowFatScreen> {
  bool _active = false;
  double _limit = 60.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await LowFatGuard.isActive();
    final lim = await LowFatGuard.fatLimit();
    if (!mounted) return;
    setState(() { _active = on; _limit = lim; _loading = false; });
  }

  Future<void> _start() async {
    final active = await DietBus.getActive();
    if (active != null && active.id != 'low-fat') {
      await _sheetInfo('لا يمكن تفعيل رجيم قليل الدهون الآن',
          'هناك نظام آخر فعّال حاليًا (${active.title}). لا يمكنك تفعيل نظامين في نفس الوقت.');
      return;
    }
    await LowFatGuard.setActive(true);
      await DietBus.activateExclusive('low-fat');
    await _load();
    await _sheetInfo('تم البدء', 'بدأت رجيم قليل الدهون ✅');
  }

  Future<void> _end() async {
    final ok = await _sheetConfirm('إنهاء رجيم قليل الدهون؟', 'سيتم إيقاف النظام الحالي.');
    if (ok != true) return;
    await LowFatGuard.setActive(false);
    await DietBus.setActive(null);
DietBus.invalidate();

    await _load();
    await _sheetInfo('تم الإنهاء', 'انتهى الرجيم. يمكنك إعادة تشغيله متى شئت.');
  }

  Future<void> _saveLimit(double v) async {
    await LowFatGuard.setFatLimit(v);
    await _load();
    await _sheetInfo('تم ضبط حد الدهون', 'الحد اليومي الجديد: ${v.toStringAsFixed(0)}غ.');
  }

  Future<void> _sheetInfo(String title, String msg) async {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.check_circle, color: cs.primary, size: 48),
            const SizedBox(height: 8),
            Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(msg, style: txt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('تمام')),
          ]),
        ),
      ),
    );
  }

  Future<bool?> _sheetConfirm(String title, String msg) async {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 48),
            const SizedBox(height: 8),
            Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(msg, style: txt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: ()=> Navigator.pop(ctx, false), child: const Text('إلغاء'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: ()=> Navigator.pop(ctx, true), child: const Text('تأكيد'))),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
      appBar: AppBar(title: const Text('رجيم قليل الدهون')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (!_active)
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('ابدأ الرجيم'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _end,
                      style: FilledButton.styleFrom(backgroundColor: cs.error),
                      icon: const Icon(Icons.stop),
                      label: const Text('إنهاء الرجيم'),
                    ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('حد الدهون اليومي (غرام)', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: Slider(
                                min: 30, max: 120, divisions: 18,
                                value: _limit,
                                label: '${_limit.toStringAsFixed(0)}غ',
                                onChanged: (v) => setState(()=> _limit = v),
                                onChangeEnd: _saveLimit,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${_limit.toStringAsFixed(0)}غ'),
                          ]),
                          const SizedBox(height: 8),
                          Text('نقترح 60غ/يوم كبداية، وعدّل حسب هدفك وسعراتك.', style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: const Text('سينبّهك التطبيق إذا كانت الوجبة عالية الدهون (≥ 20غ)، '
                          'وسيطلب تأكيدًا إذا كان إجمالي دهون اليوم سيتجاوز الحد.'),
                    ),
                  ),
                ],
              ),
            ),
    ),
    );
  }
}
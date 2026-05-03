
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import '../regimens/lowcarb_guard.dart';
import 'regimen_screen.dart' show DietBus; // لفحص وجود نظام آخر مفعّل

class RegimenLowCarbScreen extends StatefulWidget {
  const RegimenLowCarbScreen({super.key});

  @override
  State<RegimenLowCarbScreen> createState() => _RegimenLowCarbScreenState();
}

class _RegimenLowCarbScreenState extends State<RegimenLowCarbScreen> {
  bool _active = false;
  double _limit = 100.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await LowCarbGuard.isActive();
    final lim = await LowCarbGuard.carbLimit();
    if (!mounted) return;
    setState(() {
      _active = on;
      _limit = lim;
      _loading = false;
    });
  }

  Future<void> _start() async {
    // منع تفعيل أكثر من رجيم
    final active = await DietBus.getActive();
    if (active != null && active.id != 'low-carb') {
      await _showInfoSheet(
        icon: Icons.block,
        color: Theme.of(context).colorScheme.error,
        title: 'لا يمكن تفعيل لو كارب الآن',
        message: 'هناك نظام آخر فعّال حاليًا (${active.title}). '
            'لا يمكنك تفعيل نظامين في نفس الوقت. أنهِ النظام الحالي أولًا ثم ابدأ لو كارب.',
      );
      return;
    }
    await LowCarbGuard.setActive(true);
      await DietBus.activateExclusive('low-carb');
    await _load();
    await _showInfoSheet(
      icon: Icons.check_circle,
      color: Colors.green,
      title: 'تم البدء',
      message: 'بدأت رجيم لو كارب ✅\nسننبّهك عند الوجبات عالية الكارب، '
          'وسنحذّرك إذا تجاوزت الحد اليومي.',
    );
  }

  Future<void> _end() async {
    final ok = await _showConfirmSheet(
      icon: Icons.stop_circle_outlined,
      color: Theme.of(context).colorScheme.error,
      title: 'إنهاء رجيم لو كارب؟',
      message: 'سيتم إيقاف التقييد الحالي. يمكنك إعادة تشغيله متى شئت.',
      okText: 'إنهاء الرجيم',
    );
    if (ok != true) return;
    await LowCarbGuard.setActive(false);
    await DietBus.setActive(null);
DietBus.invalidate(); // يمسح الكاش ويجبر القراءة الصحيحة

    await _load();
    await _showInfoSheet(
      icon: Icons.history,
      color: Theme.of(context).colorScheme.primary,
      title: 'تم الإنهاء',
      message: 'انتهى الرجيم. يمكنك تعديل الحد اليومي ثم البدء مجددًا.',
    );
  }

  Future<void> _saveLimit(double v) async {
    await LowCarbGuard.setCarbLimit(v);
    await _load();
    await _showInfoSheet(
      icon: Icons.tune,
      color: Theme.of(context).colorScheme.secondary,
      title: 'تم ضبط حد الكارب',
      message: 'الحد اليومي الجديد: ${v.toStringAsFixed(0)}غ.',
      okText: 'حسنًا',
    );
  }

  Future<void> _showInfoSheet({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String okText = 'تمام',
  }) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 12),
              Icon(icon, color: color, size: 52),
              const SizedBox(height: 12),
              Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, style: txt.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: ()=> Navigator.pop(ctx), child: Text(okText)),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showConfirmSheet({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String cancelText = 'إلغاء',
    String okText = 'تأكيد',
  }) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 12),
              Icon(icon, color: color, size: 52),
              const SizedBox(height: 12),
              Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, style: txt.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: ()=> Navigator.pop(ctx, false), child: Text(cancelText))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: ()=> Navigator.pop(ctx, true), child: Text(okText))),
                ],
              ),
            ],
          ),
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
      appBar: AppBar(title: const Text('رجيم لو كارب')),
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
                          const Text('حد الكارب اليومي', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  min: 50, max: 200, divisions: 15,
                                  value: _limit,
                                  label: '${_limit.toStringAsFixed(0)}غ',
                                  onChanged: (v) => setState(()=> _limit = v),
                                  onChangeEnd: _saveLimit,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${_limit.toStringAsFixed(0)}غ'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('ننصح بالبدء بـ 100غ/يوم ثم التعديل حسب نشاطك.', style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: const Text('ملاحظات: سيعرض التطبيق تحذيرًا إذا كانت الوجبة عالية الكارب (≥ 40غ)، '
                          'وسينبّهك عند محاولة تجاوز إجمالي كارب اليوم للحد.'),
                    ),
                  ),
                ],
              ),
            ),
    ),
    );
  }
}
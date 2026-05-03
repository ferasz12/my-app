import 'package:flutter/material.dart';
import 'package:my_app/regimens/keto_guard.dart';
import 'regimen_screen.dart' show DietBus; // لفحص وجود نظام آخر مفعّل

class KetoRegimenScreen extends StatefulWidget {
  const KetoRegimenScreen({super.key});

  @override
  State<KetoRegimenScreen> createState() => _KetoRegimenScreenState();
}

class _KetoRegimenScreenState extends State<KetoRegimenScreen> {
  bool _active = false;
  double _limit = 30.0;
  double _todayScore = 0.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await KetoGuard.isActive();
    final l = await KetoGuard.carbLimit();
    final s = await KetoGuard.computeAndStoreTodayScore();
    if (!mounted) return;
    setState(() {
      _active = a;
      _limit = l;
      _todayScore = s.clamp(0.0, 1.0);
      _loading = false;
    });
  }

  // ===== رسائل فخمة (نفس روح الصيام) =====
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
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42, height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                      style: txt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Text(message, style: txt.bodyMedium),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(cancelText),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(okText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
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
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42, height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                      style: txt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Text(message, style: txt.bodyMedium),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(okText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  // ===== منطق البدء/الإيقاف =====
  Future<void> _start() async {
    // منع تفعيل أكثر من رجيم: افحص DietBus
    final active = await DietBus.getActive();
    if (active != null && active.id != 'keto') {
      await _showInfoSheet(
        icon: Icons.block,
        color: Theme.of(context).colorScheme.error,
        title: 'لا يمكن تفعيل الكيتو الآن',
        message: 'هناك نظام آخر فعّال حاليًا (${active.title}). '
            'لا يمكنك تفعيل نظامين في نفس الوقت. أنهِ النظام الحالي أولًا ثم ابدأ الكيتو.',
      );
      return;
    }

    final ok = await _showConfirmSheet(
      icon: Icons.play_arrow_rounded,
      color: Theme.of(context).colorScheme.primary,
      title: 'بدء رجيم الكيتو؟',
      message: 'سيتم تفعيل مراقبة الكارب اليومي والتنبيهات للوجبات عالية الكارب. '
          'هل ترغب بالبدء الآن؟',
      okText: 'ابدأ الآن',
    );
    if (ok != true) return;

    await KetoGuard.startRegimen();
    await _load();

    await _showInfoSheet(
      icon: Icons.check_circle,
      color: Colors.green,
      title: 'تم البدء',
      message: 'بدأت رجيم الكيتو ✅\nسننبّهك عند محاولة إضافة وجبة عالية الكارب، '
          'وسنحسب لك نسبة الالتزام يوميًا.',
    );
  }

  Future<void> _end() async {
    final ok = await _showConfirmSheet(
      icon: Icons.stop_circle_outlined,
      color: Theme.of(context).colorScheme.error,
      title: 'إنهاء رجيم الكيتو؟',
      message: 'سيتم إنهاء الجلسة الحالية،هل انت متأكد انك تريد انهاء الرجيم؟ ',
      okText: 'إنهاء الرجيم',
    );
    if (ok != true) return;

    await KetoGuard.endRegimen();
    await DietBus.setActive(null);
DietBus.invalidate();

    await _load();

    await _showInfoSheet(
      icon: Icons.history,
      color: Theme.of(context).colorScheme.primary,
      title: 'تم الإنهاء',
      message: 'انتهى الرجيم .',
    );
  }

  Future<void> _saveLimit(double v) async {
    await KetoGuard.setCarbLimit(v);
    await _load();
    await _showInfoSheet(
      icon: Icons.tune,
      color: Theme.of(context).colorScheme.secondary,
      title: 'تم ضبط حد الكارب',
      message: 'الحد اليومي الجديد: ${v.toStringAsFixed(0)}غ.',
      okText: 'حسنًا',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('رجيم الكيتو')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  // زر البدء/الإنهاء برسالة فخمة
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

                  // الحد اليومي للكارب
                  Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('حد الكارب اليومي',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  min: 10, max: 80, divisions: 70,
                                  value: _limit,
                                  label: '${_limit.toStringAsFixed(0)}غ',
                                  onChanged: (v) => setState(()=> _limit = v),
                                  onChangeEnd: _saveLimit,
                                ),
                              ),
                              Wrap(
                                spacing: 6,
                                children: [20, 30, 50].map((e) {
                                  return OutlinedButton(
                                    onPressed: ()=> _saveLimit(e.toDouble()),
                                    child: Text('$eغ'),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'سنحاول إبقاء مجموع الكارب اليوم ≤ ${_limit.toStringAsFixed(0)}غ. '
                            'إذا أضفت وجبة عالية الكارب ستظهر ملاحظة، وإذا تجاوزت حد اليوم قد نمنع الإضافة.',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // مؤشر الالتزام اليوم
                  Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('نسبة الالتزام اليوم',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Center(
                            child: SizedBox(
                              width: 140, height: 140,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: _todayScore.clamp(0.0, 1.0),
                                    strokeWidth: 10,
                                  ),
                                  Text(
                                    '${(_todayScore * 100).round()}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 20),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'تزيد النسبة كلما كان الكارب منخفضًا، وتزداد أكثر عند اختيار عناصر ≤ 5غ كارب.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // المعلومات

                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}


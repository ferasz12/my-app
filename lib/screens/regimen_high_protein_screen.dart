import 'package:flutter/material.dart';

import '../regimens/high_protein_guard.dart';
import '../services/tracker_store.dart';
import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'regimen_screen.dart' show DietBus;

class RegimenHighProteinScreen extends StatefulWidget {
  const RegimenHighProteinScreen({super.key});

  @override
  State<RegimenHighProteinScreen> createState() => _RegimenHighProteinScreenState();
}

class _RegimenHighProteinScreenState extends State<RegimenHighProteinScreen> {
  bool _active = false;
  bool _loading = true;
  bool _notifications = true;
  double _target = HighProteinGuard.defaultTarget;
  double _mealMin = HighProteinGuard.defaultMealMin;
  double _todayProtein = 0;
  int _morningH = 11;
  int _morningM = 30;
  int _eveningH = 20;
  int _eveningM = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await HighProteinGuard.isActive();
    final target = await HighProteinGuard.targetProtein();
    final mealMin = await HighProteinGuard.mealMinProtein();
    final notifications = await HighProteinGuard.notificationsEnabled();
    final times = await HighProteinGuard.reminderTimes();
    final day = await TrackerStore.getDay(DateTime.now());
    if (!mounted) return;
    setState(() {
      _active = active;
      _target = target;
      _mealMin = mealMin;
      _notifications = notifications;
      _morningH = times.morningH;
      _morningM = times.morningM;
      _eveningH = times.eveningH;
      _eveningM = times.eveningM;
      _todayProtein = ((day['protein'] as num?)?.toDouble() ?? 0).clamp(0, 9999).toDouble();
      _loading = false;
    });
  }

  Future<void> _start() async {
    final active = await DietBus.getActive();
    if (active != null && active.id != 'high-protein') {
      await _message(
        icon: Icons.block_rounded,
        title: 'فيه رجيم نشط حاليًا',
        message: 'النظام النشط: ${active.title}. أنهِه أولًا ثم فعّل عالي البروتين.',
        danger: true,
      );
      return;
    }
    await DietBus.activateExclusive('high-protein');
    await HighProteinGuard.setActive(true);
    await _load();
    await _message(
      icon: Icons.check_circle_rounded,
      title: 'تم تفعيل عالي البروتين',
      message: 'وازن الآن يراقب بروتين وجباتك، وينبهك إذا الوجبة قليلة بروتين أو تحتاج تذكير آخر اليوم.',
    );
  }

  Future<void> _stop() async {
    final ok = await _confirm(
      icon: Icons.stop_circle_rounded,
      title: 'إنهاء رجيم عالي البروتين؟',
      message: 'سيتم إيقاف تنبيهات البروتين ومراقبة الوجبات منخفضة البروتين.',
      okText: 'إنهاء',
      danger: true,
    );
    if (ok != true) return;
    await HighProteinGuard.setActive(false);
    await DietBus.setActive(null);
    DietBus.invalidate();
    await _load();
  }

  Future<void> _saveTarget(double value) async {
    await HighProteinGuard.setTargetProtein(value);
    await _load();
  }

  Future<void> _saveMealMin(double value) async {
    await HighProteinGuard.setMealMinProtein(value);
    await _load();
  }

  Future<void> _toggleNotifications(bool value) async {
    await HighProteinGuard.setNotificationsEnabled(value);
    await _load();
    if (value) {
      await _message(
        icon: Icons.notifications_active_rounded,
        title: 'تم تشغيل التذكيرات',
        message: 'راح يذكرك وازن بتوزيع البروتين ومراجعة المتبقي آخر اليوم.',
      );
    }
  }

  Future<void> _pickReminder({required bool morning}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: morning ? _morningH : _eveningH,
        minute: morning ? _morningM : _eveningM,
      ),
    );
    if (t == null) return;
    await HighProteinGuard.setReminderTimes(
      morningHour: morning ? t.hour : _morningH,
      morningMinute: morning ? t.minute : _morningM,
      eveningHour: morning ? _eveningH : t.hour,
      eveningMinute: morning ? _eveningM : t.minute,
    );
    await _load();
  }

  String _fmtTime(int h, int m) {
    final p = TimeOfDay(hour: h, minute: m);
    return p.format(context);
  }

  double get _progress => _target <= 0 ? 0 : (_todayProtein / _target).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remain = (_target - _todayProtein).clamp(0, 9999).toStringAsFixed(0);
    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
        appBar: AppBar(title: const Text('رجيم عالي البروتين'), centerTitle: true),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
                    children: [
                      _HeroCard(
                        icon: Icons.fitness_center_rounded,
                        title: 'هدفك اليومي للبروتين',
                        subtitle: _active ? 'نشط الآن — وازن يراقب وجباتك' : 'اضبط الهدف ثم فعّل النظام',
                        value: '${_todayProtein.toStringAsFixed(0)} / ${_target.toStringAsFixed(0)}غ',
                        progress: _progress,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 12),
                      _StatusButton(active: _active, onStart: _start, onStop: _stop),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'إعدادات البروتين',
                        icon: Icons.tune_rounded,
                        children: [
                          _SliderLine(
                            title: 'هدف البروتين اليومي',
                            value: _target,
                            min: 70,
                            max: 240,
                            divisions: 34,
                            suffix: 'غ',
                            onChanged: (v) => setState(() => _target = v),
                            onChangeEnd: _saveTarget,
                          ),
                          const SizedBox(height: 10),
                          _SliderLine(
                            title: 'الحد الأدنى للوجبة',
                            value: _mealMin,
                            min: 15,
                            max: 50,
                            divisions: 35,
                            suffix: 'غ',
                            onChanged: (v) => setState(() => _mealMin = v),
                            onChangeEnd: _saveMealMin,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'باقي لك تقريبًا $remainغ بروتين. إذا أضفت وجبة أقل من ${_mealMin.toStringAsFixed(0)}غ بروتين، وازن يعطيك تنبيه لطيف.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'التذكيرات',
                        icon: Icons.notifications_active_rounded,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('تذكيرات البروتين'),
                            subtitle: const Text('تذكير توزيع البروتين ومراجعة المتبقي'),
                            value: _notifications,
                            onChanged: _toggleNotifications,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _notifications ? () => _pickReminder(morning: true) : null,
                                  icon: const Icon(Icons.wb_sunny_rounded),
                                  label: Text('الأول ${_fmtTime(_morningH, _morningM)}'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _notifications ? () => _pickReminder(morning: false) : null,
                                  icon: const Icon(Icons.nights_stay_rounded),
                                  label: Text('الأخير ${_fmtTime(_eveningH, _eveningM)}'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'كيف يشتغل داخل وازن؟',
                        icon: Icons.auto_awesome_rounded,
                        children: const [
                          _Bullet('يراقب بروتين اليوم من سجل الأكل الحقيقي.'),
                          _Bullet('ينبهك إذا كانت الوجبة قليلة البروتين بالنسبة لهدفك.'),
                          _Bullet('يساعد مدرب وازن والوصفات على اقتراح وجبات عالية البروتين.'),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<bool?> _confirm({
    required IconData icon,
    required String title,
    required String message,
    String okText = 'تأكيد',
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
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

  Future<void> _message({
    required IconData icon,
    required String title,
    required String message,
    bool danger = false,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 44),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ]),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final double progress;
  final Color color;
  const _HeroCard({required this.icon, required this.title, required this.subtitle, required this.value, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: [color.withOpacity(.95), color.withOpacity(.68)]),
        boxShadow: [BoxShadow(color: color.withOpacity(.22), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Colors.white, size: 34),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
        ]),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.86))),
        const SizedBox(height: 18),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: progress, minHeight: 10, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white)),
        ),
      ]),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final bool active;
  final VoidCallback onStart;
  final VoidCallback onStop;
  const _StatusButton({required this.active, required this.onStart, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return active
        ? FilledButton.icon(
            onPressed: onStop,
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            icon: const Icon(Icons.stop_rounded),
            label: const Text('إنهاء الرجيم'),
          )
        : FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('تفعيل الرجيم'),
          );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: cs.outlineVariant.withOpacity(.65))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: cs.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))]),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }
}

class _SliderLine extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  const _SliderLine({required this.title, required this.value, required this.min, required this.max, required this.divisions, required this.suffix, required this.onChanged, required this.onChangeEnd});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text('${value.toStringAsFixed(0)}$suffix')]),
      Slider(min: min, max: max, divisions: divisions, value: value.clamp(min, max).toDouble(), label: '${value.toStringAsFixed(0)}$suffix', onChanged: onChanged, onChangeEnd: onChangeEnd),
    ]);
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

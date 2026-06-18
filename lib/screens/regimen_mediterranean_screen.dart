import 'package:flutter/material.dart';

import '../regimens/mediterranean_guard.dart';
import '../services/tracker_store.dart';
import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'regimen_screen.dart' show DietBus;

class RegimenMediterraneanScreen extends StatefulWidget {
  const RegimenMediterraneanScreen({super.key});

  @override
  State<RegimenMediterraneanScreen> createState() => _RegimenMediterraneanScreenState();
}

class _RegimenMediterraneanScreenState extends State<RegimenMediterraneanScreen> {
  bool _active = false;
  bool _loading = true;
  bool _notifications = true;
  int _plantGoal = 5;
  int _fishGoal = 2;
  double _fatLimit = 35;
  double _todayCalories = 0;
  double _todayCarbs = 0;
  double _todayFat = 0;
  double _todayProtein = 0;
  int _lunchH = 13;
  int _lunchM = 0;
  int _dinnerH = 20;
  int _dinnerM = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await MediterraneanGuard.isActive();
    final plant = await MediterraneanGuard.plantServingsGoal();
    final fish = await MediterraneanGuard.fishMealsGoal();
    final fatLimit = await MediterraneanGuard.fatNudgeLimit();
    final notifications = await MediterraneanGuard.notificationsEnabled();
    final times = await MediterraneanGuard.reminderTimes();
    final day = await TrackerStore.getDay(DateTime.now());
    if (!mounted) return;
    setState(() {
      _active = active;
      _plantGoal = plant;
      _fishGoal = fish;
      _fatLimit = fatLimit;
      _notifications = notifications;
      _lunchH = times.lunchH;
      _lunchM = times.lunchM;
      _dinnerH = times.dinnerH;
      _dinnerM = times.dinnerM;
      _todayCalories = ((day['calories'] as num?)?.toDouble() ?? 0).clamp(0, 99999).toDouble();
      _todayProtein = ((day['protein'] as num?)?.toDouble() ?? 0).clamp(0, 9999).toDouble();
      _todayCarbs = ((day['carb'] as num?)?.toDouble() ?? 0).clamp(0, 9999).toDouble();
      _todayFat = ((day['fat'] as num?)?.toDouble() ?? 0).clamp(0, 9999).toDouble();
      _loading = false;
    });
  }

  Future<void> _start() async {
    final active = await DietBus.getActive();
    if (active != null && active.id != 'mediterranean') {
      await _message(
        icon: Icons.block_rounded,
        title: 'فيه رجيم نشط حاليًا',
        message: 'النظام النشط: ${active.title}. أنهِه أولًا ثم فعّل البحر المتوسط.',
        danger: true,
      );
      return;
    }
    await DietBus.activateExclusive('mediterranean');
    await MediterraneanGuard.setActive(true);
    await _load();
    await _message(
      icon: Icons.check_circle_rounded,
      title: 'تم تفعيل البحر المتوسط',
      message: 'وازن الآن يذكرك باختيارات أخف، ويعطي تنبيهًا للوجبات العالية بالدهون حتى تتأكد من جودة الدهون وموازنة الطبق.',
    );
  }

  Future<void> _stop() async {
    final ok = await _confirm(
      icon: Icons.stop_circle_rounded,
      title: 'إنهاء رجيم البحر المتوسط؟',
      message: 'سيتم إيقاف التذكيرات والتنبيهات الخاصة بهذا النظام.',
      okText: 'إنهاء',
      danger: true,
    );
    if (ok != true) return;
    await MediterraneanGuard.setActive(false);
    await DietBus.setActive(null);
    DietBus.invalidate();
    await _load();
  }

  Future<void> _toggleNotifications(bool value) async {
    await MediterraneanGuard.setNotificationsEnabled(value);
    await _load();
  }

  Future<void> _savePlant(double value) async {
    await MediterraneanGuard.setPlantServingsGoal(value.round());
    await _load();
  }

  Future<void> _saveFish(double value) async {
    await MediterraneanGuard.setFishMealsGoal(value.round());
    await _load();
  }

  Future<void> _saveFatLimit(double value) async {
    await MediterraneanGuard.setFatNudgeLimit(value);
    await _load();
  }

  Future<void> _pickReminder({required bool lunch}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: lunch ? _lunchH : _dinnerH, minute: lunch ? _lunchM : _dinnerM),
    );
    if (t == null) return;
    await MediterraneanGuard.setReminderTimes(
      lunchHour: lunch ? t.hour : _lunchH,
      lunchMinute: lunch ? t.minute : _lunchM,
      dinnerHour: lunch ? _dinnerH : t.hour,
      dinnerMinute: lunch ? _dinnerM : t.minute,
    );
    await _load();
  }

  String _fmtTime(int h, int m) => TimeOfDay(hour: h, minute: m).format(context);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
        appBar: AppBar(title: const Text('رجيم البحر المتوسط'), centerTitle: true),
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
                        icon: Icons.eco_rounded,
                        title: 'نظام متوازن وواقعي',
                        subtitle: _active ? 'نشط الآن — تذكيرات وتنبيهات ذكية' : 'خضار، بروتين، دهون صحية، ومرونة',
                        color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.teal,
                        chips: [
                          '${_todayCalories.toStringAsFixed(0)} سعرة',
                          '${_todayProtein.toStringAsFixed(0)}غ بروتين',
                          '${_todayCarbs.toStringAsFixed(0)}غ كارب',
                          '${_todayFat.toStringAsFixed(0)}غ دهون',
                        ],
                      ),
                      const SizedBox(height: 12),
                      _StatusButton(active: _active, onStart: _start, onStop: _stop),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'أهداف النظام',
                        icon: Icons.flag_rounded,
                        children: [
                          _SliderLine(
                            title: 'حصص الخضار والفواكه يوميًا',
                            value: _plantGoal.toDouble(),
                            min: 3,
                            max: 8,
                            divisions: 5,
                            suffix: ' حصص',
                            onChanged: (v) => setState(() => _plantGoal = v.round()),
                            onChangeEnd: _savePlant,
                          ),
                          const SizedBox(height: 8),
                          _SliderLine(
                            title: 'وجبات سمك/أسبوع',
                            value: _fishGoal.toDouble(),
                            min: 0,
                            max: 5,
                            divisions: 5,
                            suffix: ' وجبات',
                            onChanged: (v) => setState(() => _fishGoal = v.round()),
                            onChangeEnd: _saveFish,
                          ),
                          const SizedBox(height: 8),
                          _SliderLine(
                            title: 'تنبيه الوجبات عالية الدهون',
                            value: _fatLimit,
                            min: 20,
                            max: 70,
                            divisions: 10,
                            suffix: 'غ',
                            onChanged: (v) => setState(() => _fatLimit = v),
                            onChangeEnd: _saveFatLimit,
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
                            title: const Text('تذكيرات البحر المتوسط'),
                            subtitle: const Text('تذكير وقت الغداء والعشاء باختيار طبق متوازن'),
                            value: _notifications,
                            onChanged: _toggleNotifications,
                          ),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _notifications ? () => _pickReminder(lunch: true) : null,
                                icon: const Icon(Icons.lunch_dining_rounded),
                                label: Text('الغداء ${_fmtTime(_lunchH, _lunchM)}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _notifications ? () => _pickReminder(lunch: false) : null,
                                icon: const Icon(Icons.dinner_dining_rounded),
                                label: Text('العشاء ${_fmtTime(_dinnerH, _dinnerM)}'),
                              ),
                            ),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'كيف يشتغل داخل وازن؟',
                        icon: Icons.auto_awesome_rounded,
                        children: const [
                          _Bullet('يذكرك بوجبات خفيفة ومتوازنة بدل الزحمة والكلام الطويل.'),
                          _Bullet('ينبه عند الوجبات العالية بالدهون لتتأكد من جودة الدهون والكمية.'),
                          _Bullet('يساعد في فلترة الوصفات والمطاعم لاختيارات أقرب للبحر المتوسط.'),
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
  final Color color;
  final List<String> chips;
  const _HeroCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.chips});

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
        Row(children: [Icon(icon, color: Colors.white, size: 34), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)))]),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.86))),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: chips.map((c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white24)),
          child: Text(c, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        )).toList()),
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
        ? FilledButton.icon(onPressed: onStop, style: FilledButton.styleFrom(backgroundColor: cs.error), icon: const Icon(Icons.stop_rounded), label: const Text('إنهاء الرجيم'))
        : FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow_rounded), label: const Text('تفعيل الرجيم'));
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

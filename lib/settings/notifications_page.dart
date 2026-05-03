import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/user_repository.dart';
import '../notifications/app_notifications.dart';
import '../notifications/firestore_broadcast_scheduler.dart';
import '../shared/friendly_errors.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final repo = const UserRepository();

  bool _busy = false;
  bool _loadedLocal = false;
  bool _loadedRemote = false;

  // عام
  bool allEnabled = true; // master
  bool marketingEnabled = true;

  // ماء
  bool waterEnabled = false;
  int waterStartH = 8, waterStartM = 0;
  int waterEndH = 22, waterEndM = 0;
  int waterIntervalMin = 60;

  // وزن
  bool weightEnabled = false;
  int weightH = 8, weightM = 0;

  // سعرات/تسجيل الأكل
  bool caloriesEnabled = false;
  int caloriesH = 21, caloriesM = 0;

  // تمارين
  bool workoutEnabled = false;
  int workoutH = 18, workoutM = 0;
  Set<int> workoutDays = <int>{1, 3, 5}; // Mon..Sun = 1..7

  // نصيحة يومية
  bool tipsEnabled = false;
  int tipsH = 9, tipsM = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalPrefs();
    _loadRemotePrefs();
  }

  // ----------------------------
  // Parsing helpers
  // ----------------------------

  bool _toBool(dynamic v, {bool def = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return def;
  }

  int _toInt(dynamic v, {required int def, int? min, int? max}) {
    int out = def;
    if (v is int) out = v;
    if (v is num) out = v.toInt();
    if (v is String) out = int.tryParse(v.trim()) ?? def;
    if (min != null && out < min) out = min;
    if (max != null && out > max) out = max;
    return out;
  }

  List<int> _toIntList(dynamic v) {
    if (v is List) {
      return v.map((e) => _toInt(e, def: -1)).where((e) => e >= 1 && e <= 7).toSet().toList()..sort();
    }
    return const <int>[];
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  // ----------------------------
  // Load prefs (local first, then remote overwrites)
  // ----------------------------

  Future<void> _loadLocalPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        allEnabled = p.getBool(AppNotifications.kAll) ?? true;

        waterEnabled = p.getBool(AppNotifications.kWaterEnabled) ?? false;
        waterStartH = p.getInt(AppNotifications.kWaterStartH) ?? 8;
        waterStartM = p.getInt(AppNotifications.kWaterStartM) ?? 0;
        waterEndH = p.getInt(AppNotifications.kWaterEndH) ?? 22;
        waterEndM = p.getInt(AppNotifications.kWaterEndM) ?? 0;
        waterIntervalMin = p.getInt(AppNotifications.kWaterInterval) ?? 60;

        workoutEnabled = p.getBool(AppNotifications.kWorkoutEnabled) ?? false;
        workoutH = p.getInt(AppNotifications.kWorkoutH) ?? 18;
        workoutM = p.getInt(AppNotifications.kWorkoutM) ?? 0;
        final csv = p.getString(AppNotifications.kWorkoutDays) ?? '1,3,5';
        workoutDays = csv
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .where((d) => d >= 1 && d <= 7)
            .toSet();

        tipsEnabled = p.getBool(AppNotifications.kTipsEnabled) ?? false;
        tipsH = p.getInt(AppNotifications.kTipsH) ?? 9;
        tipsM = p.getInt(AppNotifications.kTipsM) ?? 0;

        weightEnabled = p.getBool(AppNotifications.kWeightEnabled) ?? false;
        weightH = p.getInt(AppNotifications.kWeightH) ?? 8;
        weightM = p.getInt(AppNotifications.kWeightM) ?? 0;

        caloriesEnabled = p.getBool(AppNotifications.kCaloriesEnabled) ?? false;
        caloriesH = p.getInt(AppNotifications.kCaloriesH) ?? 21;
        caloriesM = p.getInt(AppNotifications.kCaloriesM) ?? 0;

        marketingEnabled = p.getBool(FirestoreBroadcastScheduler.kMarketingEnabledLocal) ?? true;

        _loadedLocal = true;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadRemotePrefs() async {
    try {
      final prefs = await repo.getPrefs() ?? <String, dynamic>{};
      if (!mounted) return;

      final water = _asMap(prefs['water']);
      final workout = _asMap(prefs['workout']);
      final tips = _asMap(prefs['tips']);
      final weight = _asMap(prefs['weight']);
      final calories = _asMap(prefs['calories']);

      setState(() {
        allEnabled = _toBool(prefs['push'], def: allEnabled);
        marketingEnabled = _toBool(prefs['marketing'], def: marketingEnabled);

        if (water != null) {
          waterEnabled = _toBool(water['enabled'], def: waterEnabled);
          waterStartH = _toInt(water['startH'], def: waterStartH, min: 0, max: 23);
          waterStartM = _toInt(water['startM'], def: waterStartM, min: 0, max: 59);
          waterEndH = _toInt(water['endH'], def: waterEndH, min: 0, max: 23);
          waterEndM = _toInt(water['endM'], def: waterEndM, min: 0, max: 59);
          waterIntervalMin = _toInt(water['intervalMin'], def: waterIntervalMin, min: 10, max: 24 * 60);
        }

        if (workout != null) {
          workoutEnabled = _toBool(workout['enabled'], def: workoutEnabled);
          workoutH = _toInt(workout['h'], def: workoutH, min: 0, max: 23);
          workoutM = _toInt(workout['m'], def: workoutM, min: 0, max: 59);
          final days = _toIntList(workout['days']);
          if (days.isNotEmpty) workoutDays = days.toSet();
        }

        if (tips != null) {
          tipsEnabled = _toBool(tips['enabled'], def: tipsEnabled);
          tipsH = _toInt(tips['h'], def: tipsH, min: 0, max: 23);
          tipsM = _toInt(tips['m'], def: tipsM, min: 0, max: 59);
        } else {
          // توافق خلفي
          tipsEnabled = _toBool(prefs['dailyTips'], def: tipsEnabled);
        }

        if (weight != null) {
          weightEnabled = _toBool(weight['enabled'], def: weightEnabled);
          weightH = _toInt(weight['h'], def: weightH, min: 0, max: 23);
          weightM = _toInt(weight['m'], def: weightM, min: 0, max: 59);
        }

        if (calories != null) {
          caloriesEnabled = _toBool(calories['enabled'], def: caloriesEnabled);
          caloriesH = _toInt(calories['h'], def: caloriesH, min: 0, max: 23);
          caloriesM = _toInt(calories['m'], def: caloriesM, min: 0, max: 59);
        }

        _loadedRemote = true;
      });
    } catch (_) {
      // ignore
    }
  }

  // ----------------------------
  // Save + Apply
  // ----------------------------

  Future<void> _saveAndApply() async {
    setState(() => _busy = true);
    try {
      // 1) إذن النظام
      if (allEnabled) {
        final ok = await AppNotifications.instance.requestPermission();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لم يتم منح إذن الإشعارات من النظام')),
          );
        }
      }

      // 2) حفظ محلي
      final p = await SharedPreferences.getInstance();
      await p.setBool(AppNotifications.kAll, allEnabled);

      await p.setBool(AppNotifications.kWaterEnabled, waterEnabled);
      await p.setInt(AppNotifications.kWaterStartH, waterStartH);
      await p.setInt(AppNotifications.kWaterStartM, waterStartM);
      await p.setInt(AppNotifications.kWaterEndH, waterEndH);
      await p.setInt(AppNotifications.kWaterEndM, waterEndM);
      await p.setInt(AppNotifications.kWaterInterval, waterIntervalMin);

      await p.setBool(AppNotifications.kWorkoutEnabled, workoutEnabled);
      await p.setInt(AppNotifications.kWorkoutH, workoutH);
      await p.setInt(AppNotifications.kWorkoutM, workoutM);
      await p.setString(AppNotifications.kWorkoutDays, (workoutDays.toList()..sort()).join(','));

      await p.setBool(AppNotifications.kTipsEnabled, tipsEnabled);
      await p.setInt(AppNotifications.kTipsH, tipsH);
      await p.setInt(AppNotifications.kTipsM, tipsM);

      await p.setBool(AppNotifications.kWeightEnabled, weightEnabled);
      await p.setInt(AppNotifications.kWeightH, weightH);
      await p.setInt(AppNotifications.kWeightM, weightM);

      await p.setBool(AppNotifications.kCaloriesEnabled, caloriesEnabled);
      await p.setInt(AppNotifications.kCaloriesH, caloriesH);
      await p.setInt(AppNotifications.kCaloriesM, caloriesM);

      await p.setBool(FirestoreBroadcastScheduler.kMarketingEnabledLocal, marketingEnabled);

      // 3) تطبيق الجدولة
      await AppNotifications.instance.applySettings(
        allEnabled: allEnabled,
        waterEnabled: waterEnabled,
        waterStartHour: waterStartH,
        waterStartMinute: waterStartM,
        waterEndHour: waterEndH,
        waterEndMinute: waterEndM,
        waterIntervalMinutes: waterIntervalMin,
        workoutEnabled: workoutEnabled,
        workoutHour: workoutH,
        workoutMinute: workoutM,
        workoutWeekdays: workoutDays.toList()..sort(),
        tipsEnabled: tipsEnabled,
        tipsHour: tipsH,
        tipsMinute: tipsM,
        weightEnabled: weightEnabled,
        weightHour: weightH,
        weightMinute: weightM,
        caloriesEnabled: caloriesEnabled,
        caloriesHour: caloriesH,
        caloriesMinute: caloriesM,
      );

      // 4) مزامنة عروض/تسويق من Firestore (تشتغل بعد فتح التطبيق)
      await FirestoreBroadcastScheduler.instance.syncAndSchedule(
        enabled: allEnabled && marketingEnabled,
      );

      // 5) حفظ على Firestore (كمصدر إعدادات على السحابة)
      await repo.setPrefs({
        'push': allEnabled,
        'marketing': marketingEnabled,

        // توافق قديم
        'dailyTips': tipsEnabled,
        'reminders': (waterEnabled || workoutEnabled || weightEnabled || caloriesEnabled),

        'water': {
          'enabled': waterEnabled,
          'startH': waterStartH,
          'startM': waterStartM,
          'endH': waterEndH,
          'endM': waterEndM,
          'intervalMin': waterIntervalMin,
        },
        'workout': {
          'enabled': workoutEnabled,
          'h': workoutH,
          'm': workoutM,
          'days': (workoutDays.toList()..sort()),
        },
        'tips': {
          'enabled': tipsEnabled,
          'h': tipsH,
          'm': tipsM,
        },
        'weight': {
          'enabled': weightEnabled,
          'h': weightH,
          'm': weightM,
        },
        'calories': {
          'enabled': caloriesEnabled,
          'h': caloriesH,
          'm': caloriesM,
        },
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات وتفعيل الجدولة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FriendlyErrors.message(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----------------------------
  // UI helpers
  // ----------------------------

  Future<void> _pickTime({
    required int currentH,
    required int currentM,
    required void Function(int h, int m) onPicked,
  }) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentH, minute: currentM),
    );
    if (t == null) return;
    if (!mounted) return;
    setState(() => onPicked(t.hour, t.minute));
  }

  String _fmt(int h, int m) {
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static const _weekdays = <int, String>{
    1: 'الإثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };

  @override
  Widget build(BuildContext context) {
    final loading = !_loadedLocal && !_loadedRemote;

    return PremiumGate(
      feature: PremiumFeature.notifications,
      child: Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  title: 'عام',
                  children: [
                    SwitchListTile(
                      value: allEnabled,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                allEnabled = v;
                              }),
                      title: const Text('تفعيل الإشعارات'),
                      subtitle: const Text('يعطّل/يمكّن جميع تذكيرات التطبيق'),
                    ),
                    SwitchListTile(
                      value: marketingEnabled,
                      onChanged: (!allEnabled || _busy)
                          ? null
                          : (v) => setState(() {
                                marketingEnabled = v;
                              }),
                      title: const Text('عروض وتنبيهات تسويقية'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _Section(
                  title: 'تذكير الماء',
                  children: [
                    SwitchListTile(
                      value: waterEnabled,
                      onChanged: (!allEnabled || _busy)
                          ? null
                          : (v) => setState(() => waterEnabled = v),
                      title: const Text('تشغيل تذكير الماء 💧'),
                    ),
                    _RowSetting(
                      enabled: allEnabled && waterEnabled && !_busy,
                      label: 'من',
                      value: _fmt(waterStartH, waterStartM),
                      onTap: () => _pickTime(
                        currentH: waterStartH,
                        currentM: waterStartM,
                        onPicked: (h, m) {
                          waterStartH = h;
                          waterStartM = m;
                        },
                      ),
                    ),
                    _RowSetting(
                      enabled: allEnabled && waterEnabled && !_busy,
                      label: 'إلى',
                      value: _fmt(waterEndH, waterEndM),
                      onTap: () => _pickTime(
                        currentH: waterEndH,
                        currentM: waterEndM,
                        onPicked: (h, m) {
                          waterEndH = h;
                          waterEndM = m;
                        },
                      ),
                    ),
                    _RowSetting(
                      enabled: allEnabled && waterEnabled && !_busy,
                      label: 'كل',
                      value: '$waterIntervalMin دقيقة',
                      onTap: () async {
                        final picked = await showModalBottomSheet<int>(
                          context: context,
                          showDragHandle: true,
                          builder: (ctx) {
                            const options = [10, 15, 20, 30, 45, 60, 90, 120];
                            return ListView(
                              children: [
                                const ListTile(title: Text('اختر التكرار')),
                                for (final v in options)
                                  ListTile(
                                    title: Text('$v دقيقة'),
                                    trailing: v == waterIntervalMin ? const Icon(Icons.check) : null,
                                    onTap: () => Navigator.pop(ctx, v),
                                  ),
                              ],
                            );
                          },
                        );
                        if (picked == null || !mounted) return;
                        setState(() => waterIntervalMin = picked);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _Section(
                  title: 'تذكيرات يومية',
                  children: [
                    SwitchListTile(
                      value: weightEnabled,
                      onChanged: (!allEnabled || _busy)
                          ? null
                          : (v) => setState(() => weightEnabled = v),
                      title: const Text('تذكير تسجيل الوزن ⚖️'),
                    ),
                    _RowSetting(
                      enabled: allEnabled && weightEnabled && !_busy,
                      label: 'الوقت',
                      value: _fmt(weightH, weightM),
                      onTap: () => _pickTime(
                        currentH: weightH,
                        currentM: weightM,
                        onPicked: (h, m) {
                          weightH = h;
                          weightM = m;
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: caloriesEnabled,
                      onChanged: (!allEnabled || _busy)
                          ? null
                          : (v) => setState(() => caloriesEnabled = v),
                      title: const Text('تذكير تسجيل الأكل/السعرات 🍽️'),
                    ),
                    _RowSetting(
                      enabled: allEnabled && caloriesEnabled && !_busy,
                      label: 'الوقت',
                      value: _fmt(caloriesH, caloriesM),
                      onTap: () => _pickTime(
                        currentH: caloriesH,
                        currentM: caloriesM,
                        onPicked: (h, m) {
                          caloriesH = h;
                          caloriesM = m;
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _Section(
                  title: 'تمارين ونصائح',
                  children: [
                    SwitchListTile(
                      value: workoutEnabled,
                      onChanged: (!allEnabled || _busy)
                          ? null
                          : (v) => setState(() => workoutEnabled = v),
                      title: const Text('تذكير التمرين 🏋️'),
                    ),
                    _RowSetting(
                      enabled: allEnabled && workoutEnabled && !_busy,
                      label: 'الوقت',
                      value: _fmt(workoutH, workoutM),
                      onTap: () => _pickTime(
                        currentH: workoutH,
                        currentM: workoutM,
                        onPicked: (h, m) {
                          workoutH = h;
                          workoutM = m;
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in _weekdays.entries)
                            FilterChip(
                              label: Text(e.value),
                              selected: workoutDays.contains(e.key),
                              onSelected: (!allEnabled || !workoutEnabled || _busy)
                                  ? null
                                  : (sel) {
                                      setState(() {
                                        if (sel) {
                                          workoutDays.add(e.key);
                                        } else {
                                          workoutDays.remove(e.key);
                                        }
                                      });
                                    },
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: tipsEnabled,
                      onChanged: (!allEnabled || _busy)
                          ? null
                          : (v) => setState(() => tipsEnabled = v),
                      title: const Text('نصيحة صحية يومية ✅'),
                    ),
                    _RowSetting(
                      enabled: allEnabled && tipsEnabled && !_busy,
                      label: 'الوقت',
                      value: _fmt(tipsH, tipsM),
                      onTap: () => _pickTime(
                        currentH: tipsH,
                        currentM: tipsM,
                        onPicked: (h, m) {
                          tipsH = h;
                          tipsM = m;
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                FilledButton.icon(
                  onPressed: _busy ? null : _saveAndApply,
                  icon: const Icon(Icons.save),
                  label: _busy ? const Text('جاري الحفظ...') : const Text('حفظ وتفعيل'),
                ),
              ],
            ),
    ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const Divider(height: 1),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _RowSetting extends StatelessWidget {
  const _RowSetting({
    required this.enabled,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(label),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: enabled ? onTap : null,
    );
  }
}
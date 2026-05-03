// lib/screens/training_schedule_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../schedule/selected_schedule_page.dart';
import '../schedule/workout_data.dart';
import '../schedule/workout_sessions_page.dart';
import '../schedule/schedule_storage.dart';

class TrainingSchedulePage extends StatefulWidget {
  const TrainingSchedulePage({super.key, this.schedule});
  final dynamic schedule;

  @override
  State<TrainingSchedulePage> createState() => _TrainingSchedulePageState();
}

class _TrainingSchedulePageState extends State<TrainingSchedulePage> {
  String userGoal = '';
  String? suggestedPlan;
  String? selectedPlan;

  bool _autoOpenedOnce = false;
  bool _handledIncomingSchedule = false;

  // العداد
  DateTime? _timerStart;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // جداولي (تُعرض في الرئيسية)
  final Map<String, Map<String, dynamic>> _customPlans = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadCustomAndMerge(); // ← مهم: يملأ القائمة مباشرة
    await loadUserGoal();
    await _loadTimer();

    // لو جاي من شاشة الإنشاء ومعطي جدول
    if (widget.schedule != null && !_handledIncomingSchedule) {
      _handledIncomingSchedule = true;
      final norm = ScheduleStorage.normalizePlan(widget.schedule);
      if (norm != null) {
        await ScheduleStorage.saveCustomPlan(norm);
        await _loadCustomAndMerge();
        await _applyIncomingSchedule(norm['name'] as String);
      }
    }
  }

  // -------- دعم شكل days كـ Map أو List
  Map<String, dynamic> _normalizeDays(dynamic daysAny) {
    if (daysAny is Map) return Map<String, dynamic>.from(daysAny);
    if (daysAny is List) {
      final m = <String, dynamic>{};
      for (final e in daysAny) {
        if (e is Map) {
          final title = (e['title'] ?? '').toString();
          final itemsRaw = (e['items'] is List) ? (e['items'] as List) : const [];
          m[title] = itemsRaw.map((it) {
            if (it is Map) {
              return {
                'name': (it['name'] ?? '').toString(),
                'sets': it['sets'] ?? 0,
                'reps': it['reps'] ?? 0,
              };
            }
            return {'name': '', 'sets': 0, 'reps': 0};
          }).toList();
        }
      }
      return m;
    }
    return <String, dynamic>{};
  }

  // -------- تحميل الجداول المخصّصة من التخزين الجديد + القديم ودمجها
  Future<void> _loadCustomAndMerge() async {
    _customPlans.clear();

    // 1) المصدر الجديد (ScheduleStorage)
    final newList = await ScheduleStorage.loadCustomPlans();
    for (final m in newList) {
      final name = (m['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final goal = (m['goal'] ?? '').toString();
      final days = _normalizeDays(m['days']);
      _customPlans[name] = {'goal': goal, 'days': days, 'isCustom': true};
      WorkoutData.workoutPlans[name] = {'goal': goal, 'days': days, 'isCustom': true};
    }

    // 2) المصدر القديم (SharedPreferences: custom_schedules_<email>)
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final legacyRaw = prefs.getString('custom_schedules_$email');
    if (legacyRaw != null) {
      try {
        final legacyList = (jsonDecode(legacyRaw) as List).cast<dynamic>();
        for (final e in legacyList) {
          if (e is! Map) continue;
          final name = (e['name'] ?? '').toString();
          if (name.isEmpty) continue;
          final goal = (e['goal'] ?? '').toString();
          final days = _normalizeDays(e['days']); // يدعم List/Map
          // ما نكتب فوق قيمة موجودة من المصدر الجديد
          _customPlans.putIfAbsent(name, () => {'goal': goal, 'days': days, 'isCustom': true});
          WorkoutData.workoutPlans.putIfAbsent(name, () => {'goal': goal, 'days': days, 'isCustom': true});
        }
      } catch (_) {/* تجاهل */}
    }

    if (mounted) setState(() {});
  }

  // ---------- أدوات البريد ----------
  Future<String> _resolveEmail(SharedPreferences prefs) async {
    final candidates = <String?>[
      prefs.getString('currentEmail'),
      prefs.getString('email'),
      prefs.getString('userEmail'),
      prefs.getString('user_email'),
    ];
    return (candidates.firstWhere(
          (e) => e != null && e.trim().isNotEmpty,
          orElse: () => 'unknown_user',
        )!)
        .trim()
        .toLowerCase();
  }

  String _keyTimerStart(String email) => 'workoutTimerStart_$email';
  String _keySelectedPlan(String email) => 'selectedWorkoutPlan_$email';
  String _keySessionsNew(String email) => 'workoutSessions_$email';
  static const String _keySessionsOld = 'workout_sessions';

  // ---------- بيانات المستخدم ----------
  Future<void> loadUserGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final goal = prefs.getString('goal_$email') ?? 'نمط حياة صحي';
    final savedPlan = prefs.getString(_keySelectedPlan(email));

    setState(() {
      userGoal = goal;
      suggestedPlan = WorkoutData.goalSuggestions[goal];
      selectedPlan = savedPlan;
    });

    _maybeAutoOpenSelected();
  }

  void _maybeAutoOpenSelected() {
    if (!mounted) return;
    if (selectedPlan != null && !_autoOpenedOnce) {
      _autoOpenedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SelectedSchedulePage(planName: selectedPlan!),
          ),
        );
      });
    }
  }

  // تفعيل جدول وصل من الخارج
  Future<void> _applyIncomingSchedule(String planName) async {
    if (!WorkoutData.workoutPlans.containsKey(planName)) {
      await _loadCustomAndMerge();
      if (!WorkoutData.workoutPlans.containsKey(planName)) return;
    }
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    await prefs.setString(_keySelectedPlan(email), planName);
    if (!mounted) return;
    setState(() => selectedPlan = planName);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SelectedSchedulePage(planName: planName)),
      );
    });
  }

  // ---------- العداد ----------
  Future<void> _loadTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final startMs = prefs.getInt(_keyTimerStart(email));
    if (startMs != null) {
      _timerStart = DateTime.fromMillisecondsSinceEpoch(startMs);
      _startTicker();
    } else {
      setState(() {
        _timerStart = null;
        _elapsed = Duration.zero;
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerStart == null || !mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_timerStart!));
    });
    if (_timerStart != null) {
      setState(() => _elapsed = DateTime.now().difference(_timerStart!));
    }
  }

  Future<void> _startTimer() async {
    if (_timerStart != null) return;
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    _timerStart = DateTime.now();
    await prefs.setInt(_keyTimerStart(email), _timerStart!.millisecondsSinceEpoch);
    _startTicker();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('بدأ العداد — تمرين موفّق!')),
    );
  }

  static const _days = [
    'الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'
  ];
  String _dayName(DateTime d) => _days[d.weekday - 1];
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _timeStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _stopTimer() async {
    if (_timerStart == null) return;
    final end = DateTime.now();
    final duration = end.difference(_timerStart!);

    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);

    final keyNew = _keySessionsNew(email);
    final existing = prefs.getString(keyNew);

    List<dynamic> sessions;
    try {
      sessions = existing != null ? (jsonDecode(existing) as List<dynamic>) : <dynamic>[];
    } catch (_) {
      sessions = <dynamic>[];
    }

    final entry = {
      'start': _timerStart!.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'durationSec': duration.inSeconds,
      'plan': selectedPlan ?? 'بدون جدول',
      'day': _dayName(_timerStart!),
      'date': _dateStr(_timerStart!),
      'startTime': _timeStr(_timerStart!),
      'endTime': _timeStr(end),
    };

    sessions.add(entry);
    await prefs.setString(keyNew, jsonEncode(sessions));

    final legacyList = prefs.getStringList(_keySessionsOld) ?? <String>[];
    legacyList.add(jsonEncode(entry));
    await prefs.setStringList(_keySessionsOld, legacyList);

    await prefs.remove(_keyTimerStart(email));
    _ticker?.cancel();
    setState(() {
      _timerStart = null;
      _elapsed = Duration.zero;
    });

    if (!mounted) return;
    final h = duration.inHours, m = duration.inMinutes % 60, s = duration.inSeconds % 60;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.celebration, size: 28),
          const SizedBox(height: 8),
          Text('أحسنت! تم حفظ جلسة التمرين',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('المدة: ${_pad(h)}:${_pad(m)}:${_pad(s)} • الجدول: ${selectedPlan ?? "بدون"}'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history),
                onPressed: () {
                  Navigator.pop(context);
                  _openSessions();
                },
                label: const Text('عرض الجلسات'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تمام'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  String _formatElapsed() {
    final h = _elapsed.inHours, m = _elapsed.inMinutes % 60, s = _elapsed.inSeconds % 60;
    return '${_pad(h)}:${_pad(m)}:${_pad(s)}';
  }
  String _pad(int v) => v.toString().padLeft(2, '0');

  Future<void> confirmSchedule(String planName) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    await prefs.setString(_keySelectedPlan(email), planName);

    if (!mounted) return;
    setState(() => selectedPlan = planName);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SelectedSchedulePage(planName: planName)),
    );
  }

  Future<void> cancelPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    await prefs.remove(_keySelectedPlan(email));
    if (!mounted) return;
    setState(() => selectedPlan = null);
  }

  void _openSessions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutSessionsPage()),
    );
  }

  Future<void> _onRefresh() async {
    await _loadCustomAndMerge();
    await loadUserGoal();
    await _loadTimer();
  }

  Future<void> _createNewSchedule() async {
    final created = await Navigator.pushNamed(context, '/createSchedule');
    if (!mounted) return;
    if (created == true) {
      await _loadCustomAndMerge(); // ← يُظهر الجدول حالًا في الرئيسية
      await loadUserGoal();
    }
  }

  Future<void> _deleteCustomPlan(String name) async {
    // نحذف من الخريطة العامة ومن التخزين الجديد
    WorkoutData.workoutPlans.remove(name);
    await ScheduleStorage.deleteCustomPlan(name);
    // احتمال يكون محفوظًا بالمفتاح القديم كذلك — نحاول نحذفه
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final key = 'custom_schedules_$email';
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        list.removeWhere((e) => e is Map && (e['name'] ?? '') == name);
        await prefs.setString(key, jsonEncode(list));
      } catch (_) {}
    }
    await _loadCustomAndMerge();
  }

  @override
  Widget build(BuildContext context) {
    final plans = WorkoutData.workoutPlans;
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.of(context).size.width;
    final narrow = w < 380;

    final builtInNames = plans.keys
        .where((k) => plans[k]?['isCustom'] != true)
        .toList();

    final customNames = _customPlans.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("جدولي الرياضي"),
        actions: [
          IconButton(
            tooltip: 'إنشاء جدول جديد',
            icon: const Icon(Icons.add),
            onPressed: _createNewSchedule,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _TimerBanner(
                running: _timerStart != null,
                elapsedText: _formatElapsed(),
                planName: selectedPlan,
                onStart: _startTimer,
                onStop: _stopTimer,
                onViewSessions: _openSessions,
                compact: narrow,
              ),
              const SizedBox(height: 10),

              if (selectedPlan == null && suggestedPlan != null)
                _SuggestionCard(
                  userGoal: userGoal,
                  suggestedPlan: suggestedPlan!,
                  onIgnore: () => setState(() => suggestedPlan = null),
                  onUse: () => confirmSchedule(suggestedPlan!),
                  compact: narrow,
                ),

              const SizedBox(height: 12),

              if (selectedPlan != null)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(narrow ? 10 : 14),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: s.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: s.onPrimaryContainer, size: narrow ? 18 : 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "أنت تستخدم حاليًا جدول: $selectedPlan",
                          style: (narrow ? t.bodySmall : t.bodyMedium)
                              ?.copyWith(color: s.onPrimaryContainer),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        onPressed: cancelPlan,
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: const Text("إلغاء"),
                        style: FilledButton.styleFrom(
                          minimumSize: Size(narrow ? 72 : 90, 36),
                          padding: EdgeInsets.symmetric(
                              horizontal: narrow ? 8 : 12, vertical: 8),
                          backgroundColor: s.errorContainer,
                          foregroundColor: s.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),

              Align(
                alignment: Alignment.centerRight,
                child: Text("اختر جدولاً من القائمة:",
                    style: (narrow ? t.titleSmall : t.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 6),

              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  children: [
                    if (customNames.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('جداولي', style: t.titleMedium),
                      ),
                      ...customNames.map((name) {
                        final plan = _customPlans[name]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _PlanTile(
                            planName: name,
                            goalText: (plan['goal'] ?? '').toString(),
                            isSuggested: false,
                            isSelected: selectedPlan == name,
                            compact: narrow,
                            onSelect: () => confirmSchedule(name),
                            // زر حذف للجداول المخصّصة فقط
                            deleteAction: IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteCustomPlan(name),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                    ],

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('قوالب جاهزة', style: t.titleMedium),
                    ),
                    ...builtInNames.map((name) {
                      final plan = plans[name]!;
                      final isSuggested = suggestedPlan == name;
                      final isSelected = selectedPlan == name;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _PlanTile(
                          planName: name,
                          goalText: (plan['goal'] ?? '').toString(),
                          isSuggested: isSuggested,
                          isSelected: isSelected,
                          onSelect: () => confirmSchedule(name),
                          compact: narrow,
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerBanner extends StatelessWidget {
  final bool running;
  final String elapsedText;
  final String? planName;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onViewSessions;
  final bool compact;

  const _TimerBanner({
    required this.running,
    required this.elapsedText,
    required this.planName,
    required this.onStart,
    required this.onStop,
    required this.onViewSessions,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final btnPad = EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14, vertical: compact ? 8 : 10);
    final minBtn = Size(compact ? 0 : 64, 36);

    final titleStyle = (compact ? t.titleSmall : t.titleMedium)?.copyWith(
      fontWeight: FontWeight.w800,
      color: running ? s.onSecondaryContainer : null,
    );
    final subStyle = (compact ? t.bodySmall : t.bodySmall)?.copyWith(
      color: running ? s.onSecondaryContainer.withOpacity(.9) : null,
    );

    final content = Row(
      children: [
        CircleAvatar(
          radius: compact ? 16 : 18,
          backgroundColor: running ? s.secondary : s.primary,
          child: Icon(running ? Icons.timer : Icons.play_arrow_rounded,
              color: s.onPrimary, size: compact ? 18 : 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(running ? 'العدّاد يعمل' : 'ابدأ عدّاد التمرين',
                  style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                running
                    ? 'الوقت: $elapsedText • الجدول: ${planName ?? "بدون"}'
                    : 'شغّل العداد مع بدء التمرين ثم أنهِه عند الانتهاء',
                style: subStyle, maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: onViewSessions,
              icon: const Icon(Icons.history, size: 18),
              label: Text(compact ? 'الجلسات' : 'جلسات التمارين'),
              style: OutlinedButton.styleFrom(
                padding: btnPad,
                minimumSize: minBtn,
                visualDensity: VisualDensity.compact,
              ),
            ),
            running
                ? FilledButton.tonal(
                    onPressed: onStop,
                    style: FilledButton.styleFrom(
                      padding: btnPad,
                      minimumSize: minBtn,
                      backgroundColor: s.errorContainer,
                      foregroundColor: s.onErrorContainer,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('إنهاء'),
                  )
                : FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      padding: btnPad,
                      minimumSize: minBtn,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('ابدأ العداد'),
                  ),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: running ? s.secondaryContainer : s.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.outlineVariant.withOpacity(.3)),
      ),
      child: content,
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final String userGoal;
  final String suggestedPlan;
  final VoidCallback onIgnore;
  final VoidCallback onUse;
  final bool compact;

  const _SuggestionCard({
    required this.userGoal,
    required this.suggestedPlan,
    required this.onIgnore,
    required this.onUse,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: s.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("اقتراح ذكي بناءً على هدفك:",
              style: (compact ? t.titleSmall : t.titleMedium)
                  ?.copyWith(color: s.onSecondaryContainer, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text("🎯 هدفك الحالي: $userGoal",
              style: (compact ? t.bodySmall : t.bodyMedium)
                  ?.copyWith(color: s.onSecondaryContainer)),
          const SizedBox(height: 4),
          Text("📝 نقترح لك جدول: $suggestedPlan",
              style: (compact ? t.bodySmall : t.bodyMedium)
                  ?.copyWith(color: s.onSecondaryContainer)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onIgnore, child: const Text("تجاهل")),
              const SizedBox(width: 6),
              FilledButton(onPressed: onUse, child: const Text("استخدام الجدول")),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final String planName;
  final String goalText;
  final bool isSuggested;
  final bool isSelected;
  final VoidCallback onSelect;
  final bool compact;
  final Widget? deleteAction; // يظهر فقط للمخصّص

  const _PlanTile({
    required this.planName,
    required this.goalText,
    required this.isSuggested,
    required this.isSelected,
    required this.onSelect,
    this.compact = false,
    this.deleteAction,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                planName,
                style: (compact ? t.titleSmall : t.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: s.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check, size: 14, color: s.primary),
                  const SizedBox(width: 4),
                  Text("مُفعّل",
                      style: (compact ? t.labelMedium : t.labelLarge)
                          ?.copyWith(color: s.primary)),
                ]),
              )
            else if (isSuggested)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: s.tertiary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text("مُقترح",
                    style: (compact ? t.labelMedium : t.labelLarge)
                        ?.copyWith(color: s.tertiary)),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            goalText,
            style: (compact ? t.bodySmall : t.bodyMedium)
                ?.copyWith(color: s.onSurfaceVariant),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (deleteAction != null) deleteAction!,
            isSelected
                ? FilledButton.tonalIcon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text("مُفعل"),
                    style: FilledButton.styleFrom(
                      minimumSize: Size(compact ? 72 : 90, 36),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                : FilledButton(
                    onPressed: onSelect,
                    style: FilledButton.styleFrom(
                      minimumSize: Size(compact ? 72 : 90, 36),
                      padding: EdgeInsets.symmetric(
                          horizontal: compact ? 10 : 14, vertical: compact ? 8 : 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text("اختيار"),
                  ),
          ],
        ),
      ),
    );
  }
}

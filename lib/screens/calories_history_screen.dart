// lib/screens/calories_history_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/end_of_day_cloud_backup_service.dart';
import '../services/tracker_store.dart';

/// سجلّ السعرات (تصميم مُصغّر):
/// - بطاقة صغيرة بالعرض: اليوم + التاريخ + السعرات
/// - زر "عرض التفاصيل" يفتح صفحة تعرض الماكروز بنفس ايموجيات الصفحة الرئيسية
class CaloriesHistoryScreen extends StatefulWidget {
  const CaloriesHistoryScreen({super.key});

  @override
  State<CaloriesHistoryScreen> createState() => _CaloriesHistoryScreenState();
}

class _CaloriesHistoryScreenState extends State<CaloriesHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _backgroundRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // helper: yyyy-mm-dd (محلي)
  String _ymd(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _loadHistory({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      // قراءة محلية فقط وسريعة؛ السحابة تتزامن بالخلفية داخل TrackerStore.
      final data = await TrackerStore.getAllDays();

      // ترتيب من الأحدث إلى الأقدم
      data.sort((a, b) {
        final da = DateTime.tryParse((a['date'] ?? '') as String) ?? DateTime(2000);
        final db = DateTime.tryParse((b['date'] ?? '') as String) ?? DateTime(2000);
        return db.compareTo(da);
      });

      // ✅ لا نعرض "اليوم" لأن التثبيت يتم 11:59م
      final String today = _ymd(DateTime.now());
      final filtered = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final m in data) {
        final d = (m['date'] ?? '').toString();
        if (d.isEmpty || d == today) continue;
        if (seen.contains(d)) continue;
        seen.add(d);
        filtered.add(m);
      }

      if (!mounted) return;
      setState(() => _history = filtered);
    } catch (e) {
      debugPrint('Error loading calories history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء تحميل سجلّ السعرات')),
      );
    } finally {
      if (mounted && showLoader) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_backgroundRefreshing) return;
    setState(() => _backgroundRefreshing = true);
    try {
      // تحديث محلي فقط. لا نقرأ Firestore من سجل السعرات حتى تبقى الصفحة سريعة.
      await _loadHistory(showLoader: false);
    } finally {
      if (mounted) setState(() => _backgroundRefreshing = false);
    }
  }

  Future<void> _deleteDay(String date) async {
    try {
      await TrackerStore.clearDay(date);
      await _loadHistory(showLoader: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف يوم $date')));
    } catch (e) {
      debugPrint('Error deleting day $date: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حذف هذا اليوم')));
    }
  }

  String _weekdayAr(int weekday) {
    switch (weekday) {
      case 1:
        return 'الإثنين';
      case 2:
        return 'الثلاثاء';
      case 3:
        return 'الأربعاء';
      case 4:
        return 'الخميس';
      case 5:
        return 'الجمعة';
      case 6:
        return 'السبت';
      case 7:
        return 'الأحد';
      default:
        return '';
    }
  }

  String _fmtDMY(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  Future<void> _openPastDayPicker() async {
    final now = DateTime.now();
    final initial = now.subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3, 1, 1),
      lastDate: initial,
      helpText: 'اختر اليوم الذي تريد تعديله',
      cancelText: 'إلغاء',
      confirmText: 'فتح اليوم',
    );

    if (picked == null || !mounted) return;

    final rawDate = _ymd(picked);
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CaloriesDayDetailsPage(
          dayText: _weekdayAr(picked.weekday),
          dateText: _fmtDMY(picked),
          rawDate: rawDate,
          calories: 0,
          protein: 0,
          carbs: 0,
          fat: 0,
          onDelete: () => _deleteDay(rawDate),
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadHistory(showLoader: false);
    }
  }

  Widget _openPreviousDayButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _openPastDayPicker,
        icon: const Icon(Icons.edit_calendar_rounded),
        label: const Text('إضافة أو تعديل يوم سابق'),
      ),
    );
  }

  Widget _infoNote(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تقدر تفتح أي يوم سابق من السجل، تضيف وجبة ناقصة، ثم تقفل اليوم ليتم حفظ التعديل.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('سجل السعرات')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _infoNote(context),
                      _openPreviousDayButton(context),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          'لا يوجد سجل حتى الآن',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _history.length + 2, // ملاحظة + زر تعديل يوم سابق
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) return _infoNote(context);
                      if (index == 1) return _openPreviousDayButton(context);

                      final item = _history[index - 2];
                      final date = (item['date'] ?? '').toString();

                      final calories = (item['calories'] as num?)?.toDouble() ?? 0.0;
                      final protein = (item['protein'] as num?)?.toDouble() ?? 0.0;
                      final carbs = (item['carb'] as num?)?.toDouble() ?? 0.0;
                      final fat = (item['fat'] as num?)?.toDouble() ?? 0.0;

                      DateTime? dt;
                      try {
                        dt = DateTime.parse(date);
                      } catch (_) {}

                      final day = dt != null ? _weekdayAr(dt.weekday) : 'اليوم';
                      final dateText = dt != null ? _fmtDMY(dt) : date;

                      return _HistoryCompactCard(
                        dayText: day,
                        dateText: dateText,
                        calories: calories,
                        onDetails: () {
                          Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaloriesDayDetailsPage(
                                dayText: day,
                                dateText: dateText,
                                rawDate: date,
                                calories: calories,
                                protein: protein,
                                carbs: carbs,
                                fat: fat,
                                onDelete: () => _deleteDay(date),
                              ),
                            ),
                          ).then((changed) {
                            if (changed == true && context.mounted) {
                              _loadHistory(showLoader: false);
                            }
                          });
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

/// بطاقة صغيرة بالعرض
class _HistoryCompactCard extends StatelessWidget {
  const _HistoryCompactCard({
    required this.dayText,
    required this.dateText,
    required this.calories,
    required this.onDetails,
  });

  final String dayText;
  final String dateText;
  final double calories;
  final VoidCallback onDetails;

  String _fmt0(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // اليوم + التاريخ
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // السعرات + زر التفاصيل
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmt0(calories)} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    foregroundColor: cs.primary,
                  ),
                  child: const Text(
                    'عرض التفاصيل',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// صفحة تفاصيل ماكروز يوم محدد (بنفس ايموجيات الصفحة الرئيسية)
class CaloriesDayDetailsPage extends StatefulWidget {
  const CaloriesDayDetailsPage({
    super.key,
    required this.dayText,
    required this.dateText,
    required this.rawDate,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.onDelete,
  });

  final String dayText;
  final String dateText;
  final String rawDate;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final VoidCallback onDelete;

  @override
  State<CaloriesDayDetailsPage> createState() => _CaloriesDayDetailsPageState();
}

class _CaloriesDayDetailsPageState extends State<CaloriesDayDetailsPage> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;

  double _calories = 0;
  double _protein = 0;
  double _carbs = 0;
  double _fat = 0;

  @override
  void initState() {
    super.initState();
    _calories = widget.calories;
    _protein = widget.protein;
    _carbs = widget.carbs;
    _fat = widget.fat;
    _loadDayDetails();
  }

  String _fmtNum(double v, {int decimals = 0}) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(decimals);
  }

  double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString().replaceAll(',', '.').trim()) ?? 0.0;
  }

  Future<String> _email() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('currentEmail') ??
            FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'unknown_user')
        .trim();
  }

  Future<void> _loadDayDetails() async {
    if (mounted) setState(() => _loading = true);
    try {
      final date = DateTime.tryParse(widget.rawDate);
      final day = date == null
          ? <String, dynamic>{
              'date': widget.rawDate,
              'calories': widget.calories,
              'protein': widget.protein,
              'carb': widget.carbs,
              'fat': widget.fat,
            }
          : await TrackerStore.getDay(date);

      final email = await _email();
      final prefs = await SharedPreferences.getInstance();
      final rawEntries = prefs.getString('intake_entries_${email}_${widget.rawDate}');
      final loadedEntries = <Map<String, dynamic>>[];

      if (rawEntries != null && rawEntries.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawEntries);
          if (decoded is List) {
            for (final raw in decoded) {
              if (raw is! Map) continue;
              final item = Map<String, dynamic>.from(raw);
              loadedEntries.add({
                'name': (item['name'] ?? 'وجبة').toString(),
                'k': _toD(item['k'] ?? item['cal'] ?? item['calories']),
                'p': _toD(item['p'] ?? item['protein']),
                'c': _toD(item['c'] ?? item['carb'] ?? item['carbs']),
                'f': _toD(item['f'] ?? item['fat']),
              });
            }
          }
        } catch (_) {}
      }

      final totalK = _toD(day['calories']);
      final totalP = _toD(day['protein']);
      final totalC = _toD(day['carb'] ?? day['carbs']);
      final totalF = _toD(day['fat']);

      // إذا كان اليوم قديمًا محفوظًا كمجاميع فقط بدون تفاصيل وجبات، نحافظ على المجاميع
      // كعنصر سابق حتى لا تنمسح عند إضافة وجبة جديدة.
      if (loadedEntries.isEmpty && (totalK > 0 || totalP > 0 || totalC > 0 || totalF > 0)) {
        loadedEntries.add({
          'name': 'سجل سابق',
          'k': totalK,
          'p': totalP,
          'c': totalC,
          'f': totalF,
          'legacy': true,
        });
      }

      if (!mounted) return;
      setState(() {
        _entries = loadedEntries;
        _recalculateTotals();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading day details: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحميل تفاصيل هذا اليوم')),
      );
    }
  }

  void _recalculateTotals() {
    double k = 0, p = 0, c = 0, f = 0;
    for (final e in _entries) {
      k += _toD(e['k'] ?? e['cal'] ?? e['calories']);
      p += _toD(e['p'] ?? e['protein']);
      c += _toD(e['c'] ?? e['carb'] ?? e['carbs']);
      f += _toD(e['f'] ?? e['fat']);
    }
    _calories = k;
    _protein = p;
    _carbs = c;
    _fat = f;
  }

  Future<void> _persistDay({bool closeAfter = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final entriesToSave = _entries
          .map((e) => {
                'name': (e['name'] ?? 'وجبة').toString(),
                'k': _toD(e['k'] ?? e['cal'] ?? e['calories']),
                'p': _toD(e['p'] ?? e['protein']),
                'c': _toD(e['c'] ?? e['carb'] ?? e['carbs']),
                'f': _toD(e['f'] ?? e['fat']),
              })
          .toList();

      await TrackerStore.setDayTotals(
        ymd: widget.rawDate,
        cal: _calories,
        protein: _protein,
        carb: _carbs,
        fat: _fat,
        entries: entriesToSave,
      );

      // نرفع اليوم المعدّل للسحابة بالخلفية حتى يظهر بعد تغيير الجهاز/إعادة التثبيت.
      unawaited(
        DailyCloudBackupService.instance
            .backupDay(widget.rawDate, reason: 'manual_history_edit', force: true)
            .catchError((_) {}),
      );

      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(closeAfter ? 'تم حفظ وقفل اليوم' : 'تم حفظ التعديل')),
      );
      if (closeAfter) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving day ${widget.rawDate}: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ التعديل، حاول مرة ثانية')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAddMealDialog() async {
    final nameController = TextEditingController();
    final calController = TextEditingController();
    final proteinController = TextEditingController();
    final carbController = TextEditingController();
    final fatController = TextEditingController();
    bool autoCalc = true;

    double calcKcal() {
      final p = _toD(proteinController.text);
      final c = _toD(carbController.text);
      final f = _toD(fatController.text);
      return (p * 4) + (c * 4) + (f * 9);
    }

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void recompute() {
              if (!autoCalc) return;
              final kcal = calcKcal();
              calController.text = kcal > 0 ? kcal.toStringAsFixed(0) : '';
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'إضافة وجبة إلى ${widget.dateText}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم الوجبة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: autoCalc,
                      onChanged: (v) {
                        setModalState(() {
                          autoCalc = v ?? true;
                          recompute();
                        });
                      },
                      title: const Text('احسب السعرات تلقائيًا من الماكروز'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    TextField(
                      controller: calController,
                      enabled: !autoCalc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'السعرات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: proteinController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'بروتين',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(recompute),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: carbController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'كارب',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(recompute),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fatController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'دهون',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(recompute),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () {
                        final name = nameController.text.trim().isEmpty ? 'وجبة مضافة' : nameController.text.trim();
                        double k = autoCalc ? calcKcal() : _toD(calController.text);
                        final p = _toD(proteinController.text);
                        final c = _toD(carbController.text);
                        final f = _toD(fatController.text);
                        if (k <= 0 && (p > 0 || c > 0 || f > 0)) {
                          k = (p * 4 + c * 4 + f * 9).roundToDouble();
                        }
                        if (k <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('أدخل سعرات أو ماكروز صحيحة')),
                          );
                          return;
                        }
                        setState(() {
                          _entries.add({'name': name, 'k': k, 'p': p, 'c': c, 'f': f});
                          _recalculateTotals();
                        });
                        Navigator.pop(sheetContext, true);
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('إضافة الوجبة'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    calController.dispose();
    proteinController.dispose();
    carbController.dispose();
    fatController.dispose();

    if (added == true) {
      await _persistDay();
    }
  }

  Future<void> _deleteEntry(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final itemName = (_entries[index]['name'] ?? 'الوجبة').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الوجبة؟'),
        content: Text('تأكيد حذف "$itemName" من هذا اليوم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _entries.removeAt(index);
      _recalculateTotals();
    });
    await _persistDay();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget macroLine({
      required String label,
      required String emoji,
      required String value,
      required String unit,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
            Text(
              '$value $unit',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
            ),
          ],
        ),
      );
    }

    Future<bool> handleBack() async {
      Navigator.pop(context, _changed);
      return false;
    }

    return WillPopScope(
      onWillPop: handleBack,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.dayText} • ${widget.dateText}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            IconButton(
              tooltip: 'حذف هذا اليوم',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    return AlertDialog(
                      title: const Text('حذف اليوم؟'),
                      content: Text('تأكيد حذف سجل يوم ${widget.rawDate}؟'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                      ],
                    );
                  },
                );
                if (ok == true) {
                  widget.onDelete();
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.7),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تفاصيل اليوم',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        macroLine(
                          label: 'السعرات',
                          emoji: '🔥',
                          value: _fmtNum(_calories, decimals: 0),
                          unit: 'kcal',
                        ),
                        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                        macroLine(
                          label: 'البروتين',
                          emoji: '🥩',
                          value: _fmtNum(_protein, decimals: 1),
                          unit: 'غ',
                        ),
                        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                        macroLine(
                          label: 'الكارب',
                          emoji: '🍞',
                          value: _fmtNum(_carbs, decimals: 1),
                          unit: 'غ',
                        ),
                        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                        macroLine(
                          label: 'الدهون',
                          emoji: '🥑',
                          value: _fmtNum(_fat, decimals: 1),
                          unit: 'غ',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _showAddMealDialog,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('إضافة وجبة'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _saving ? null : () => _persistDay(closeAfter: true),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.lock_rounded),
                          label: Text(_saving ? 'جارٍ الحفظ...' : 'قفل اليوم'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'وجبات هذا اليوم',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                      ),
                      child: Text(
                        'ما فيه وجبات محفوظة لهذا اليوم. اضغط إضافة وجبة لإدخال أكلك السابق.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    ...List.generate(_entries.length, (index) {
                      final e = _entries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            (e['name'] ?? 'وجبة').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '🔥 ${_fmtNum(_toD(e['k']), decimals: 0)} kcal  •  🥩 ${_fmtNum(_toD(e['p']), decimals: 1)}غ  •  🍞 ${_fmtNum(_toD(e['c']), decimals: 1)}غ  •  🥑 ${_fmtNum(_toD(e['f']), decimals: 1)}غ',
                          ),
                          trailing: IconButton(
                            tooltip: 'حذف الوجبة',
                            onPressed: _saving ? null : () => _deleteEntry(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

// lib/screens/calories_history_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/meal_analysis/meal_analysis.dart';
import '../models/meal.dart';
import '../services/barcode_service.dart' show FoodMacro;
import '../services/tracker_store.dart';
import '../shared/session_manager.dart';
import 'barcode_scanner_page.dart';
import 'food_camera_screen.dart';
import 'ready_foods_flow.dart';
import 'restaurants_page.dart';

/// سجلّ السعرات:
/// - يقرأ محليًا فقط حتى يبقى سريع.
/// - يسمح بفتح يوم سابق وإضافة وجبة له بنفس طرق الإضافة الموجودة في التطبيق.
/// - يدعم قفل اليوم بعد الانتهاء من التعديل.
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

  String _ymd(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _loadHistory({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      final data = await TrackerStore.getAllDays();
      data.sort((a, b) {
        final da = DateTime.tryParse((a['date'] ?? '') as String) ?? DateTime(2000);
        final db = DateTime.tryParse((b['date'] ?? '') as String) ?? DateTime(2000);
        return db.compareTo(da);
      });

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
              'تقدر تفتح أي يوم سابق، تضيف وجبة بالطريقة المناسبة، ثم تقفل اليوم بعد الانتهاء.',
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
                      const SizedBox(height: 8),
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
                    itemCount: _history.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) return _infoNote(context);

                      final item = _history[index - 1];
                      final date = (item['date'] ?? '').toString();

                      final calories = _toD(item['calories']);
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
                        onDetails: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaloriesDayDetailsPage(
                                dayText: day,
                                dateText: dateText,
                                rawDate: date,
                                onDelete: () => _deleteDay(date),
                              ),
                            ),
                          );
                          if (mounted) unawaited(_loadHistory(showLoader: false));
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

// Avoid importing dart:async just for unawaited in this file.
void unawaited(Future<void> future) {}

double _toD(dynamic v) {
  if (v is num) return v.toDouble();
  if (v == null) return 0.0;
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
}

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
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dayText, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
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
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmt0(calories)} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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
                  child: const Text('عرض التفاصيل', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CaloriesDayDetailsPage extends StatefulWidget {
  const CaloriesDayDetailsPage({
    super.key,
    required this.dayText,
    required this.dateText,
    required this.rawDate,
    required this.onDelete,
  });

  final String dayText;
  final String dateText;
  final String rawDate;
  final VoidCallback onDelete;

  @override
  State<CaloriesDayDetailsPage> createState() => _CaloriesDayDetailsPageState();
}

class _CaloriesDayDetailsPageState extends State<CaloriesDayDetailsPage> {
  bool _loading = true;
  bool _busy = false;
  bool _locked = false;
  double _calories = 0;
  double _protein = 0;
  double _carbs = 0;
  double _fat = 0;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  String get _date => TrackerStore.normalizeYmd(widget.rawDate);

  Future<void> _loadDay() async {
    setState(() => _loading = true);
    try {
      final parsed = DateTime.tryParse(_date) ?? DateTime.now();
      final day = await TrackerStore.getDay(parsed);
      final entries = await TrackerStore.getDayEntries(_date);
      final locked = await TrackerStore.isDayLocked(_date);
      if (!mounted) return;
      setState(() {
        _calories = _toD(day['calories']);
        _protein = _toD(day['protein']);
        _carbs = _toD(day['carb'] ?? day['carbs']);
        _fat = _toD(day['fat']);
        _entries = entries;
        _locked = locked;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtNum(double v, {int decimals = 0}) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(decimals);
  }

  Future<bool> _addEntry({
    required String name,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required String source,
  }) async {
    if (_locked) {
      _showSnack('اليوم مقفل. افتح التعديل أولًا إذا تبغى تضيف وجبة.');
      return false;
    }

    var k = calories;
    final p = protein;
    final c = carbs;
    final f = fat;
    if (k <= 0 && (p > 0 || c > 0 || f > 0)) {
      k = (p * 4 + c * 4 + f * 9).roundToDouble();
    }
    if (k <= 0 && p <= 0 && c <= 0 && f <= 0) {
      _showSnack('ما وصلت بيانات غذائية صالحة.');
      return false;
    }

    setState(() => _busy = true);
    try {
      final updated = await TrackerStore.addEntryToDay(
        ymd: _date,
        name: name,
        cal: k,
        protein: p,
        carb: c,
        fat: f,
        source: source,
      );
      if (!mounted) return false;
      setState(() {
        _calories = _toD(updated['calories']);
        _protein = _toD(updated['protein']);
        _carbs = _toD(updated['carb'] ?? updated['carbs']);
        _fat = _toD(updated['fat']);
        _entries = (updated['entries'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            _entries;
      });
      _showSnack('تمت إضافة "$name" إلى يوم ${widget.dateText}', actionLabel: 'قفل اليوم', onAction: _lockDay);
      return true;
    } catch (e) {
      _showSnack('تعذّر حفظ الوجبة: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }

  Future<void> _lockDay() async {
    await TrackerStore.setDayLocked(_date, true);
    if (!mounted) return;
    setState(() => _locked = true);
    _showSnack('تم قفل يوم ${widget.dateText} وحفظه في سجل السعرات.');
  }

  Future<void> _unlockDay() async {
    await TrackerStore.setDayLocked(_date, false);
    if (!mounted) return;
    setState(() => _locked = false);
    _showSnack('تم فتح اليوم للتعديل.');
  }

  Map<String, dynamic>? _foodAiToEntry(dynamic result) {
    if (result == null || result is! Map) return null;
    final map = Map<String, dynamic>.from(result);
    final food = (map['food'] is Map)
        ? Map<String, dynamic>.from(map['food'] as Map)
        : (map['result'] is Map)
            ? Map<String, dynamic>.from(map['result'] as Map)
            : (map['data'] is Map)
                ? Map<String, dynamic>.from(map['data'] as Map)
                : map;

    String name = (food['label'] ?? food['name_ar'] ?? food['name'] ?? food['food_name'] ?? 'وجبة').toString().trim();
    if (name.isEmpty) name = 'وجبة';

    final serving = food['serving'] ?? food['portion_desc_ar'] ?? food['portion_desc'] ?? food['estimated_weight_g'] ?? food['portion_grams'];
    if (serving != null && '$serving'.trim().isNotEmpty) {
      final s = serving.toString().trim();
      if (!name.contains(s)) name = '$name ($s)';
    }

    double cal = _toD(food['calories'] ?? food['cal'] ?? food['kcal'] ?? food['calories_kcal']);
    double p = _toD(food['protein'] ?? food['protein_g'] ?? food['p']);
    double c = _toD(food['carbs'] ?? food['carb'] ?? food['carbs_g'] ?? food['c']);
    double f = _toD(food['fat'] ?? food['fat_g'] ?? food['f']);

    final totalMacros = food['total_macros'];
    if (totalMacros is Map) {
      cal = cal > 0 ? cal : _toD(totalMacros['calories_kcal'] ?? totalMacros['calories'] ?? totalMacros['kcal']);
      p = p > 0 ? p : _toD(totalMacros['protein_g'] ?? totalMacros['protein']);
      c = c > 0 ? c : _toD(totalMacros['carbs_g'] ?? totalMacros['carbs'] ?? totalMacros['carb']);
      f = f > 0 ? f : _toD(totalMacros['fat_g'] ?? totalMacros['fat']);
    }

    final rawItems = food['items'] ?? food['ingredients_breakdown'] ?? food['components'] ?? food['detected_items'];
    if (cal <= 0 && p <= 0 && c <= 0 && f <= 0 && rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final it = Map<String, dynamic>.from(raw);
        cal += _toD(it['cal'] ?? it['calories'] ?? it['calories_kcal'] ?? it['kcal']);
        p += _toD(it['protein'] ?? it['protein_g'] ?? it['p']);
        c += _toD(it['carb'] ?? it['carbs'] ?? it['carbs_g'] ?? it['c']);
        f += _toD(it['fat'] ?? it['fat_g'] ?? it['f']);
      }
    }

    if (cal <= 0 && (p > 0 || c > 0 || f > 0)) cal = (p * 4 + c * 4 + f * 9).roundToDouble();
    return {'name': name, 'cal': cal, 'protein': p, 'carb': c, 'fat': f};
  }

  Future<void> _openAddOptions() async {
    if (_locked) {
      _showSnack('اليوم مقفل. افتح التعديل أولًا إذا تبغى تضيف وجبة.');
      return;
    }

    final parentContext = context;
    final cs = Theme.of(parentContext).colorScheme;

    await showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(color: cs.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.add, size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إضافة وجبة ليوم ${widget.dateText}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 128,
                  ),
                  children: [
                    _AddOptionCard(
                      icon: Icons.create_rounded,
                      color: cs.primary,
                      title: 'إدخال يدوي',
                      subtitle: 'السعرات والماكروز',
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _showManualEntryForm();
                      },
                    ),
                    _AddOptionCard(
                      icon: Icons.fastfood_rounded,
                      color: cs.secondary,
                      title: 'من قائمة جاهزة',
                      subtitle: 'عناصر أو وجبة محفوظة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await showReadyListPicker(
                          parentContext,
                          onAddItemsToToday: (selected) async {
                            for (final e in selected) {
                              await _addEntry(
                                name: '${e.item.name} (${e.qtyLabel})',
                                calories: e.kcal,
                                protein: e.p,
                                carbs: e.c,
                                fat: e.f,
                                source: 'ready_foods',
                              );
                            }
                          },
                          onSaveMealTemplate: _saveMealTemplate,
                        );
                      },
                    ),
                    _AddOptionCard(
                      icon: Icons.notes_rounded,
                      color: cs.secondary,
                      title: 'التحليل بالنص',
                      subtitle: 'حلّل وصف الوجبة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        final payload = await AnalyzeMeal.launch(parentContext);
                        if (!mounted || payload == null) return;
                        await _addEntry(
                          name: (payload['name'] ?? payload['name_ar'] ?? payload['item'] ?? 'وجبة').toString(),
                          calories: _toD(payload['calories_kcal'] ?? payload['calories'] ?? payload['kcal']),
                          protein: _toD(payload['protein_g'] ?? payload['protein'] ?? payload['p']),
                          carbs: _toD(payload['carbs_g'] ?? payload['carbs'] ?? payload['c']),
                          fat: _toD(payload['fat_g'] ?? payload['fat'] ?? payload['f']),
                          source: 'ai_text',
                        );
                      },
                    ),
                    _AddOptionCard(
                      icon: Icons.camera_alt_rounded,
                      color: cs.tertiary,
                      title: 'تصوير الطعام',
                      subtitle: 'تحليل الصورة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        final result = await Navigator.of(parentContext).push(
                          MaterialPageRoute(builder: (_) => const FoodCameraScreen()),
                        );
                        final item = _foodAiToEntry(result);
                        if (!mounted || item == null) return;
                        await _addEntry(
                          name: item['name'].toString(),
                          calories: _toD(item['cal']),
                          protein: _toD(item['protein']),
                          carbs: _toD(item['carb']),
                          fat: _toD(item['fat']),
                          source: 'ai_photo',
                        );
                      },
                    ),
                    _AddOptionCard(
                      icon: Icons.restaurant_menu_rounded,
                      color: cs.primary,
                      title: 'إضافة من مطعم',
                      subtitle: 'مطاعم ومقاهي',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        final Meal? picked = await Navigator.of(parentContext).push<Meal?>(
                          MaterialPageRoute(builder: (_) => const RestaurantsPage(pickMealMode: true)),
                        );
                        if (!mounted || picked == null) return;
                        await _addEntry(
                          name: '${picked.name} — ${picked.restaurant}',
                          calories: picked.calories.toDouble(),
                          protein: picked.protein,
                          carbs: picked.carbs,
                          fat: picked.fat,
                          source: 'restaurant',
                        );
                      },
                    ),
                    _AddOptionCard(
                      icon: Icons.qr_code_scanner_rounded,
                      color: cs.error,
                      title: 'مسح باركود',
                      subtitle: 'جلب القيم تلقائيًا',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        final result = await Navigator.of(parentContext).push(
                          MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
                        );
                        if (!mounted || result == null) return;
                        if (result is FoodMacro) {
                          await _addEntry(
                            name: result.name,
                            calories: result.caloriesKcal,
                            protein: result.proteinG,
                            carbs: result.carbsG,
                            fat: result.fatG,
                            source: 'barcode',
                          );
                          return;
                        }
                        if (result is Map && result['nutriments'] != null) {
                          final n = result['nutriments'] as Map;
                          await _addEntry(
                            name: (result['product_name'] ?? 'منتج من الباركود').toString(),
                            calories: _toD(n['energy-kcal_100g']),
                            protein: _toD(n['proteins_100g']),
                            carbs: _toD(n['carbohydrates_100g']),
                            fat: _toD(n['fat_100g']),
                            source: 'barcode',
                          );
                          return;
                        }
                        _showManualEntryForm(barcode: result is Map ? (result['barcode'] ?? '').toString() : null);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveMealTemplate(String mealName, String? notes, List<SelectedFood> selected) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();
    final k = 'meal_templates_$storageKey';
    final legacyRaw = prefs.getString('meal_templates');
    if (legacyRaw != null && prefs.getString(k) == null) {
      await prefs.setString(k, legacyRaw);
      await prefs.remove('meal_templates');
    }
    final raw = prefs.getString(k);
    final List<Map<String, dynamic>> templates = raw != null
        ? List<Map<String, dynamic>>.from(json.decode(raw) as List)
        : <Map<String, dynamic>>[];
    templates.add({
      'name': mealName,
      'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      'items': selected
          .map((e) => {
                'id': e.item.id,
                'name': e.item.name,
                'qty': e.qty,
                'unit': e.item.unit,
                'per100g': e.item.isPer100g,
                'kcalBase': e.item.kcalPer100g,
                'pBase': e.item.proteinPer100g,
                'cBase': e.item.carbsPer100g,
                'fBase': e.item.fatPer100g,
                if (e.item.isPer100g) 'grams': e.qty,
                if (e.item.isPer100g) 'kcal100': e.item.kcalPer100g,
                if (e.item.isPer100g) 'p100': e.item.proteinPer100g,
                if (e.item.isPer100g) 'c100': e.item.carbsPer100g,
                if (e.item.isPer100g) 'f100': e.item.fatPer100g,
              })
          .toList(),
    });
    await prefs.setString(k, json.encode(templates));
  }

  void _showManualEntryForm({String? barcode}) {
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void recomputeIfNeeded() {
            if (autoCalc) {
              final kcal = calcKcal();
              calController.text = kcal > 0 ? kcal.toStringAsFixed(0) : '';
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('إضافة يدوية ليوم ${widget.dateText}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  if ((barcode ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('الباركود: $barcode', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: nameController, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'اسم الوجبة')),
                  const SizedBox(height: 8),
                  TextField(controller: calController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعرات kcal')),
                  const SizedBox(height: 8),
                  TextField(controller: proteinController, keyboardType: TextInputType.number, onChanged: (_) => setModalState(recomputeIfNeeded), decoration: const InputDecoration(labelText: 'البروتين غ')),
                  const SizedBox(height: 8),
                  TextField(controller: carbController, keyboardType: TextInputType.number, onChanged: (_) => setModalState(recomputeIfNeeded), decoration: const InputDecoration(labelText: 'الكارب غ')),
                  const SizedBox(height: 8),
                  TextField(controller: fatController, keyboardType: TextInputType.number, onChanged: (_) => setModalState(recomputeIfNeeded), decoration: const InputDecoration(labelText: 'الدهون غ')),
                  SwitchListTile.adaptive(
                    value: autoCalc,
                    onChanged: (v) => setModalState(() {
                      autoCalc = v;
                      recomputeIfNeeded();
                    }),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('احسب السعرات من الماكروز تلقائيًا'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('إضافة الوجبة'),
                    onPressed: () async {
                      final name = nameController.text.trim().isEmpty ? 'وجبة مخصصة' : nameController.text.trim();
                      final added = await _addEntry(
                        name: name,
                        calories: autoCalc ? calcKcal() : _toD(calController.text),
                        protein: _toD(proteinController.text),
                        carbs: _toD(carbController.text),
                        fat: _toD(fatController.text),
                        source: 'manual',
                      );
                      if (!mounted || !added) return;
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      nameController.dispose();
      calController.dispose();
      proteinController.dispose();
      carbController.dispose();
      fatController.dispose();
    });
  }

  Widget _macroLine({
    required String label,
    required String emoji,
    required String value,
    required String unit,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text(emoji, style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          Text(
            '$value $unit',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.primary),
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
      appBar: AppBar(
        title: Text('${widget.dayText} • ${widget.dateText}'),
        actions: [
          IconButton(
            tooltip: 'حذف هذا اليوم',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف اليوم؟'),
                  content: Text('تأكيد حذف سجل يوم ${widget.rawDate}؟'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                  ],
                ),
              );
              if (ok == true) {
                widget.onDelete();
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      floatingActionButton: _locked
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _openAddOptions,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة وجبة'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text('تفاصيل اليوم', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          ),
                          if (_locked)
                            Chip(
                              avatar: Icon(Icons.lock_rounded, size: 16, color: cs.primary),
                              label: const Text('مقفل'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _macroLine(label: 'السعرات', emoji: '🔥', value: _fmtNum(_calories), unit: 'kcal'),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                      _macroLine(label: 'البروتين', emoji: '🥩', value: _fmtNum(_protein, decimals: 1), unit: 'غ'),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                      _macroLine(label: 'الكارب', emoji: '🍞', value: _fmtNum(_carbs, decimals: 1), unit: 'غ'),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
                      _macroLine(label: 'الدهون', emoji: '🥑', value: _fmtNum(_fat, decimals: 1), unit: 'غ'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : (_locked ? _unlockDay : _lockDay),
                        icon: Icon(_locked ? Icons.lock_open_rounded : Icons.lock_rounded),
                        label: Text(_locked ? 'فتح التعديل' : 'قفل اليوم'),
                      ),
                    ),
                    if (!_locked) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : _openAddOptions,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('إضافة وجبة'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text('وجبات هذا اليوم', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
                    ),
                    child: Text('لا توجد تفاصيل وجبات محفوظة لهذا اليوم، لكن تقدر تضيف وجبة الآن.', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  )
                else
                  ..._entries.map((e) {
                    final name = (e['name'] ?? 'وجبة').toString();
                    final k = _toD(e['k'] ?? e['cal'] ?? e['calories']);
                    final p = _toD(e['p'] ?? e['protein']);
                    final c = _toD(e['c'] ?? e['carb'] ?? e['carbs']);
                    final f = _toD(e['f'] ?? e['fat']);
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: cs.outlineVariant.withOpacity(.45)),
                      ),
                      child: ListTile(
                        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('🥩 ${_fmtNum(p, decimals: 1)}غ   🍞 ${_fmtNum(c, decimals: 1)}غ   🥑 ${_fmtNum(f, decimals: 1)}غ'),
                        trailing: Text('${_fmtNum(k)} kcal', style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary)),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _AddOptionCard extends StatelessWidget {
  const _AddOptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(.12),
              child: Icon(icon, color: color, size: 19),
            ),
            const Spacer(),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

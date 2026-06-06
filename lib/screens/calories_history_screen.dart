// lib/screens/calories_history_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/meal_analysis/meal_analysis.dart';
import '../models/meal.dart';
import '../services/barcode_service.dart' show FoodMacro;
import '../services/tracker_store.dart';
import '../shared/friendly_errors.dart';
import '../shared/premium_access.dart';
import '../shared/premium_feature.dart';
import '../shared/session_manager.dart';
import 'barcode_scanner_page.dart';
import 'food_ai_screen.dart';
import 'food_camera_screen.dart';
import 'ready_foods_flow.dart';
import 'restaurants_page.dart';

/// سجلّ السعرات:
/// - يعرض الأيام السابقة.
/// - يمكن فتح يوم سابق، إضافة وجبات له بجميع طرق الإضافة، ثم قفل اليوم.
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

  Future<void> _openDay(String rawDate) async {
    final dt = DateTime.tryParse(rawDate);
    if (dt == null) return;
    final day = _weekdayAr(dt.weekday);
    final dateText = _fmtDMY(dt);
    final data = await TrackerStore.getDay(dt);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaloriesDayDetailsPage(
          dayText: day,
          dateText: dateText,
          rawDate: rawDate,
          calories: (data['calories'] as num?)?.toDouble() ?? 0.0,
          protein: (data['protein'] as num?)?.toDouble() ?? 0.0,
          carbs: (data['carb'] as num?)?.toDouble() ?? 0.0,
          fat: (data['fat'] as num?)?.toDouble() ?? 0.0,
          onDelete: () => _deleteDay(rawDate),
          onChanged: () => _loadHistory(showLoader: false),
        ),
      ),
    );
    await _loadHistory(showLoader: false);
  }

  Future<void> _pickPreviousDay() async {
    final now = DateTime.now();
    final yesterday = DateUtils.dateOnly(now.subtract(const Duration(days: 1)));
    final picked = await showDatePicker(
      context: context,
      initialDate: yesterday,
      firstDate: DateTime(2020),
      lastDate: yesterday,
      helpText: 'اختر اليوم السابق',
      cancelText: 'إلغاء',
      confirmText: 'فتح اليوم',
    );
    if (picked == null) return;
    await _openDay(_ymd(picked));
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
              'تقدر الآن ترجع لأي يوم سابق، تضيف وجبة بكل الطرق، ثم تقفل اليوم بعد الحفظ.',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _openPreviousDayCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _pickPreviousDay,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [cs.primary.withOpacity(0.12), cs.secondary.withOpacity(0.10)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primary.withOpacity(0.14),
              child: Icon(Icons.calendar_month_rounded, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إضافة أو تعديل يوم سابق',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'اختر التاريخ ثم أضف أكلك واحفظ اليوم',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل السعرات'),
        actions: [
          IconButton(
            tooltip: 'اختيار يوم سابق',
            onPressed: _pickPreviousDay,
            icon: const Icon(Icons.edit_calendar_rounded),
          ),
        ],
      ),
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
                      _openPreviousDayCard(context),
                      const SizedBox(height: 16),
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
                    itemCount: _history.length + 2,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) return _infoNote(context);
                      if (index == 1) return _openPreviousDayCard(context);

                      final item = _history[index - 2];
                      final date = (item['date'] ?? '').toString();
                      final calories = (item['calories'] as num?)?.toDouble() ?? 0.0;

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
                        onDetails: () => _openDay(date),
                      );
                    },
                  ),
      ),
    );
  }
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
                  Text(
                    dayText,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
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
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.onDelete,
    this.onChanged,
  });

  final String dayText;
  final String dateText;
  final String rawDate;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final VoidCallback onDelete;
  final Future<void> Function()? onChanged;

  @override
  State<CaloriesDayDetailsPage> createState() => _CaloriesDayDetailsPageState();
}

class _CaloriesDayDetailsPageState extends State<CaloriesDayDetailsPage> {
  bool _loading = true;
  bool _adding = false;
  double _calories = 0;
  double _protein = 0;
  double _carbs = 0;
  double _fat = 0;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _calories = widget.calories;
    _protein = widget.protein;
    _carbs = widget.carbs;
    _fat = widget.fat;
    _loadDay();
  }

  double _toD(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString().replaceAll(',', '.')) ?? 0.0;
  }

  Future<void> _loadDay() async {
    setState(() => _loading = true);
    try {
      final dt = DateTime.tryParse(widget.rawDate) ?? DateTime.now();
      final day = await TrackerStore.getDay(dt);
      final entries = await TrackerStore.getDayEntries(widget.rawDate);
      if (!mounted) return;
      setState(() {
        _calories = _toD(day['calories']);
        _protein = _toD(day['protein']);
        _carbs = _toD(day['carb'] ?? day['carbs']);
        _fat = _toD(day['fat']);
        _entries = entries;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل تفاصيل اليوم: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtNum(double v, {int decimals = 0}) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(decimals);
  }

  String _fmtQty(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    final iv = v.roundToDouble();
    if ((v - iv).abs() < 0.00001) return iv.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  Future<void> _appendItems(List<Map<String, dynamic>> items, {String? successName}) async {
    if (items.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      await TrackerStore.appendEntriesToDay(ymd: widget.rawDate, entries: items);
      await _loadDay();
      await widget.onChanged?.call();
      HapticFeedback.selectionClick();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successName == null ? 'تمت إضافة الوجبة إلى هذا اليوم' : 'تمت إضافة "$successName" إلى هذا اليوم')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذرت الإضافة: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeEntry(int index) async {
    try {
      await TrackerStore.removeEntryFromDay(ymd: widget.rawDate, index: index);
      await _loadDay();
      await widget.onChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الوجبة من اليوم')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الوجبة: $e')));
    }
  }

  Map<String, dynamic> _normalizeAiResult(dynamic result) {
    if (result is! Map) return <String, dynamic>{};
    final map = Map<String, dynamic>.from(result);
    final Map<String, dynamic> food = (map['food'] is Map)
        ? Map<String, dynamic>.from(map['food'] as Map)
        : (map['result'] is Map)
            ? Map<String, dynamic>.from(map['result'] as Map)
            : (map['data'] is Map)
                ? Map<String, dynamic>.from(map['data'] as Map)
                : map;

    String name = (food['label'] ?? food['name_ar'] ?? food['name'] ?? food['food_name'] ?? 'وجبة من الصورة').toString().trim();
    if (name.isEmpty) name = 'وجبة من الصورة';

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

    if (cal <= 0 && p <= 0 && c <= 0 && f <= 0) {
      final rawItems = food['items'] ?? food['ingredients_breakdown'] ?? food['components'] ?? food['detected_items'];
      if (rawItems is List) {
        for (final raw in rawItems) {
          if (raw is! Map) continue;
          final it = Map<String, dynamic>.from(raw);
          cal += _toD(it['cal'] ?? it['calories'] ?? it['calories_kcal'] ?? it['kcal']);
          p += _toD(it['protein'] ?? it['protein_g'] ?? it['p']);
          c += _toD(it['carb'] ?? it['carbs'] ?? it['carbs_g'] ?? it['c']);
          f += _toD(it['fat'] ?? it['fat_g'] ?? it['f']);
        }
      }
    }

    if (cal <= 0 && (p > 0 || c > 0 || f > 0)) {
      cal = (p * 4 + c * 4 + f * 9).roundToDouble();
    }

    if (cal <= 0 && p <= 0 && c <= 0 && f <= 0) return <String, dynamic>{};

    return <String, dynamic>{
      'name': name,
      'cal': cal,
      'protein': p,
      'carb': c,
      'fat': f,
      'source': 'history_ai_image',
    };
  }

  Future<void> _handleFoodAiResult(dynamic result) async {
    if (result == null) return;
    final item = _normalizeAiResult(result);
    if (item.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ما وصلت بيانات سعرات صالحة من التحليل. جرّب مرة ثانية أو أضفها يدويًا.')),
      );
      return;
    }
    await _appendItems([item], successName: item['name']?.toString());
  }

  Future<void> _handleAddByCamera() async {
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FoodCameraScreen()),
      );
      if (!mounted) return;
      await _handleFoodAiResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح الكاميرا: $e')));
    }
  }

  Future<void> _handleAddByGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (pickedFile == null || !mounted) return;
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FoodAiScreen(imageFile: pickedFile)),
      );
      if (!mounted) return;
      await _handleFoodAiResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر اختيار الصورة: $e')));
    }
  }

  Future<void> _handleAddByBarcode() async {
    try {
      final dynamic result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
      );
      if (result == null) return;

      if (result is FoodMacro) {
        await _appendItems([
          {
            'name': result.name,
            'cal': result.caloriesKcal,
            'protein': result.proteinG,
            'carb': result.carbsG,
            'fat': result.fatG,
            'source': 'history_barcode',
          }
        ], successName: result.name);
        return;
      }

      if (result is Map && result['nutriments'] != null) {
        final n = result['nutriments'] as Map;
        final name = (result['product_name'] ?? 'منتج من الباركود').toString();
        await _appendItems([
          {
            'name': name,
            'cal': _toD(n['energy-kcal_100g']),
            'protein': _toD(n['proteins_100g']),
            'carb': _toD(n['carbohydrates_100g']),
            'fat': _toD(n['fat_100g']),
            'source': 'history_barcode',
          }
        ], successName: name);
        return;
      }

      if (result is Map && result['barcode'] != null) {
        _showManualEntryForm(barcode: (result['barcode'] ?? '').toString());
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تفسير نتيجة الباركود')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر مسح الباركود: $e')));
    }
  }

  Future<void> _handleAddByText() async {
    try {
      final allowed = await PremiumAccess.ensureSubscribed(
        context,
        feature: PremiumFeature.aiText,
      );
      if (!allowed) return;

      final payload = await AnalyzeMeal.launch(context);
      if (!mounted || payload == null) return;

      final item = <String, dynamic>{
        'name': (payload['name'] ?? payload['name_ar'] ?? payload['item'] ?? 'وجبة').toString(),
        'cal': _toD(payload['calories_kcal'] ?? payload['calories'] ?? payload['kcal']),
        'protein': _toD(payload['protein_g'] ?? payload['protein'] ?? payload['p']),
        'carb': _toD(payload['carbs_g'] ?? payload['carbs'] ?? payload['c']),
        'fat': _toD(payload['fat_g'] ?? payload['fat'] ?? payload['f']),
        'source': 'history_text',
      };
      if (_toD(item['cal']) <= 0 && (_toD(item['protein']) > 0 || _toD(item['carb']) > 0 || _toD(item['fat']) > 0)) {
        item['cal'] = (_toD(item['protein']) * 4 + _toD(item['carb']) * 4 + _toD(item['fat']) * 9).roundToDouble();
      }
      await _appendItems([item], successName: item['name']?.toString());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحليل الوجبة بالنص: ${FriendlyErrors.message(e)}')),
      );
    }
  }

  Future<void> _handleReadyFoods() async {
    await showReadyListPicker(
      context,
      onAddItemsToToday: (selected) async {
        final items = selected.map<Map<String, dynamic>>((e) {
          final qty = e.qty;
          final factor = e.item.isPer100g ? (qty / 100.0) : qty;
          final qtyLabel = e.item.isPer100g ? '${qty.toStringAsFixed(0)}غ' : '${_fmtQty(qty)} ${e.item.unit}';
          return {
            'name': '${e.item.name} ($qtyLabel)',
            'cal': e.item.kcalPer100g * factor,
            'protein': e.item.proteinPer100g * factor,
            'carb': e.item.carbsPer100g * factor,
            'fat': e.item.fatPer100g * factor,
            'source': 'history_ready_foods',
          };
        }).toList();
        await _appendItems(items, successName: items.length == 1 ? items.first['name']?.toString() : null);
      },
      onSaveMealTemplate: (mealName, notes, selected) async {
        final prefs = await SharedPreferences.getInstance();
        final storageKey = await SessionManager.currentStorageKey();
        final k = 'meal_templates_$storageKey';
        final legacyRaw = prefs.getString('meal_templates');
        if (legacyRaw != null && prefs.getString(k) == null) {
          await prefs.setString(k, legacyRaw);
          await prefs.remove('meal_templates');
        }
        final raw = prefs.getString(k);
        final templates = raw != null ? List<Map<String, dynamic>>.from(json.decode(raw)) : <Map<String, dynamic>>[];
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
      },
    );
  }

  Future<void> _handleRestaurant() async {
    try {
      final Meal? picked = await Navigator.of(context).push<Meal?>(
        MaterialPageRoute(builder: (_) => const RestaurantsPage(pickMealMode: true)),
      );
      if (picked == null) return;
      await _appendItems([
        {
          'name': '${picked.name} — ${picked.restaurant}',
          'cal': picked.calories.toDouble(),
          'protein': picked.protein,
          'carb': picked.carbs,
          'fat': picked.fat,
          'source': 'history_restaurant',
        }
      ], successName: picked.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إضافة الوجبة من المطعم: $e')));
    }
  }

  void _showManualEntryForm({String? barcode}) {
    final rootContext = context;
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
      return (p * 4 + c * 4 + f * 9).roundToDouble();
    }

    void recomputeIfNeeded() {
      if (!autoCalc) return;
      final k = calcKcal();
      calController.text = k <= 0 ? '' : k.toStringAsFixed(0);
    }

    showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      barcode == null || barcode.trim().isEmpty ? 'إدخال وجبة ليوم ${widget.dateText}' : 'إدخال منتج الباركود يدويًا',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'اسم الوجبة', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: autoCalc,
                          onChanged: (v) {
                            setModalState(() {
                              autoCalc = v ?? true;
                              recomputeIfNeeded();
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('احسب السعرات تلقائيًا من الماكروز')),
                      ],
                    ),
                    TextField(
                      controller: calController,
                      enabled: !autoCalc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'السعرات', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: proteinController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'بروتين', border: OutlineInputBorder()),
                            onChanged: (_) => setModalState(recomputeIfNeeded),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: carbController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'كارب', border: OutlineInputBorder()),
                            onChanged: (_) => setModalState(recomputeIfNeeded),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fatController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'دهون', border: OutlineInputBorder()),
                            onChanged: (_) => setModalState(recomputeIfNeeded),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        final name = nameController.text.trim().isEmpty ? 'وجبة مخصصة' : nameController.text.trim();
                        double cal = autoCalc ? calcKcal() : _toD(calController.text);
                        final p = _toD(proteinController.text);
                        final c = _toD(carbController.text);
                        final f = _toD(fatController.text);
                        if (cal <= 0 && (p > 0 || c > 0 || f > 0)) cal = (p * 4 + c * 4 + f * 9).roundToDouble();
                        if (cal <= 0) {
                          ScaffoldMessenger.of(rootContext).showSnackBar(const SnackBar(content: Text('يرجى إدخال بيانات صحيحة')));
                          return;
                        }
                        Navigator.of(ctx).pop();
                        await _appendItems([
                          {
                            'name': name,
                            'cal': cal,
                            'protein': p,
                            'carb': c,
                            'fat': f,
                            'barcode': barcode,
                            'source': 'history_manual',
                          }
                        ], successName: name);
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('حفظ في هذا اليوم'),
                    ),
                  ],
                ),
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

  void _showAddOptions() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(color: cs.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(7),
                      child: Icon(Icons.add_rounded, color: cs.primary),
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
                const SizedBox(height: 14),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 118,
                  ),
                  children: [
                    _HistoryAddOptionCard(
                      icon: Icons.create_rounded,
                      color: cs.primary,
                      title: 'إدخال يدوي',
                      subtitle: 'سعرات وماكروز',
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _showManualEntryForm();
                      },
                    ),
                    _HistoryAddOptionCard(
                      icon: Icons.fastfood_rounded,
                      color: cs.secondary,
                      title: 'قائمة جاهزة',
                      subtitle: 'أصناف محفوظة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _handleReadyFoods();
                      },
                    ),
                    _HistoryAddOptionCard(
                      icon: Icons.notes_rounded,
                      color: cs.secondary,
                      title: 'تحليل بالنص',
                      subtitle: 'اكتب وصف الوجبة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _handleAddByText();
                      },
                    ),
                    _HistoryAddOptionCard(
                      icon: Icons.camera_alt_rounded,
                      color: cs.tertiary,
                      title: 'تصوير الطعام',
                      subtitle: 'تحليل صورة مباشرة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _handleAddByCamera();
                      },
                    ),
                    _HistoryAddOptionCard(
                      icon: Icons.photo_library_rounded,
                      color: cs.tertiary,
                      title: 'من المعرض',
                      subtitle: 'اختر صورة وجبة',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _handleAddByGallery();
                      },
                    ),
                    _HistoryAddOptionCard(
                      icon: Icons.restaurant_menu_rounded,
                      color: cs.primary,
                      title: 'من مطعم',
                      subtitle: 'وجبات المطاعم',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _handleRestaurant();
                      },
                    ),
                    _HistoryAddOptionCard(
                      icon: Icons.qr_code_scanner_rounded,
                      color: cs.error,
                      title: 'باركود',
                      subtitle: 'مسح منتج',
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _handleAddByBarcode();
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

  Future<void> _confirmDeleteDay() async {
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
      if (mounted) Navigator.pop(context);
    }
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
            onPressed: _confirmDeleteDay,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _adding ? null : _showAddOptions,
                  icon: _adding
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_rounded),
                  label: const Text('إضافة وجبة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.lock_rounded),
                  label: const Text('قفل اليوم'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDay,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
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
                        Text('تفاصيل اليوم', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                  const SizedBox(height: 14),
                  Text('وجبات هذا اليوم', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                        'ما فيه وجبات مفصلة لهذا اليوم. اضغط “إضافة وجبة” لإضافة أكلك.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    ...List.generate(_entries.length, (i) {
                      final e = _entries[i];
                      final name = (e['name'] ?? 'وجبة').toString();
                      final k = _toD(e['k'] ?? e['cal']);
                      final p = _toD(e['p'] ?? e['protein']);
                      final c = _toD(e['c'] ?? e['carb'] ?? e['carbs']);
                      final f = _toD(e['f'] ?? e['fat']);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 5),
                                  Text(
                                    '🔥 ${_fmtNum(k)}  •  🥩 ${_fmtNum(p, decimals: 1)}غ  •  🍞 ${_fmtNum(c, decimals: 1)}غ  •  🥑 ${_fmtNum(f, decimals: 1)}غ',
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'حذف الوجبة',
                              onPressed: () => _removeEntry(i),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _HistoryAddOptionCard extends StatelessWidget {
  const _HistoryAddOptionCard({
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

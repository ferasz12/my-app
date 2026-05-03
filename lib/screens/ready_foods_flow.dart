import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/session_manager.dart';


const String _kReadyFoodsPrefsKey = 'ready_foods_items';

Future<String> _readyFoodsPrefsKey() async {
  final storageKey = await SessionManager.currentStorageKey();
  return '${_kReadyFoodsPrefsKey}_$storageKey';
}

Map<String, dynamic> _foodItemToPrefs(FoodItem item) => <String, dynamic>{
      'id': item.id,
      'name': item.name,
      'category': item.category,
      'unit': item.unit,
      'isPer100g': item.isPer100g,
      'kcalPer100g': item.kcalPer100g,
      'proteinPer100g': item.proteinPer100g,
      'carbsPer100g': item.carbsPer100g,
      'fatPer100g': item.fatPer100g,
    };

Future<List<FoodItem>> _loadReadyFoodsFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _readyFoodsPrefsKey();

    // Migration: المفتاح القديم كان عام لكل الحسابات. ننقله مرة واحدة لمفتاح المستخدم الحالي.
    final legacyRaw = prefs.getString(_kReadyFoodsPrefsKey);
    if (legacyRaw != null && prefs.getString(scopedKey) == null) {
      await prefs.setString(scopedKey, legacyRaw);
      await prefs.remove(_kReadyFoodsPrefsKey);
    }

    final raw = prefs.getString(scopedKey);
    if (raw == null || raw.trim().isEmpty) return <FoodItem>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <FoodItem>[];

    final out = <FoodItem>[];
    for (final e in decoded) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] ?? '').toString().trim();
        final name = (m['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

        final kcal = d(m['kcalPer100g'] ?? m['kcal100'] ?? m['kcalBase'] ?? m['kcal']);
        final p = d(m['proteinPer100g'] ?? m['p100'] ?? m['pBase'] ?? m['protein']);
        final c = d(m['carbsPer100g'] ?? m['c100'] ?? m['cBase'] ?? m['carb']);
        final f = d(m['fatPer100g'] ?? m['f100'] ?? m['fBase'] ?? m['fat']);

        out.add(FoodItem(
          id: id.isEmpty ? 'custom-${out.length + 1}' : id,
          name: name,
          category: (m['category'] ?? 'عناصري').toString(),
          unit: (m['unit'] ?? m['serving_unit'] ?? 'جرام').toString(),
          isPer100g: (m['isPer100g'] is bool)
              ? (m['isPer100g'] as bool)
              : ((m['per100g'] is bool) ? (m['per100g'] as bool) : null),
          kcalPer100g: kcal,
          proteinPer100g: p,
          carbsPer100g: c,
          fatPer100g: f,
        ));
      }
    }
    return out;
  } catch (_) {
    return <FoodItem>[];
  }
}

List<FoodItem> _defaultReadyFoods() => <FoodItem>[
      FoodItem(
        id: 'demo-1',
        name: 'صدر دجاج',
        category: 'Protein',
        kcalPer100g: 165,
        proteinPer100g: 31,
        carbsPer100g: 0,
        fatPer100g: 3.6,
      ),
      FoodItem(
        id: 'demo-2',
        name: 'أرز أبيض مطبوخ',
        category: 'Carbs',
        kcalPer100g: 130,
        proteinPer100g: 2.4,
        carbsPer100g: 28.2,
        fatPer100g: 0.3,
      ),
      FoodItem(
        id: 'demo-3',
        name: 'بيض كامل',
        category: 'Protein',
        kcalPer100g: 143,
        proteinPer100g: 13,
        carbsPer100g: 0.7,
        fatPer100g: 9.5,
      ),
      FoodItem(
        id: 'demo-4',
        name: 'تفاح',
        category: 'Fruits',
        kcalPer100g: 52,
        proteinPer100g: 0.3,
        carbsPer100g: 14,
        fatPer100g: 0.2,
      ),
    ];

List<FoodItem> _mergeReadyFoods(List<FoodItem> base, List<FoodItem> custom) {
  final byId = <String, FoodItem>{};
  final usedNames = <String>{};

  String norm(FoodItem f) => '${f.name.trim().toLowerCase()}|${f.unit.trim().toLowerCase()}';

  for (final f in base) {
    byId[f.id] = f;
    usedNames.add(norm(f));
  }
  for (final f in custom) {
    final n = norm(f);
    if (byId.containsKey(f.id) || usedNames.contains(n)) continue;
    byId[f.id] = f;
    usedNames.add(n);
  }
  return byId.values.toList();
}

/// نموذج عنصر غذائي موحّد:
/// - إذا كانت unit = "قرام" => القيم (kcal/Protein/Carbs/Fat) محسوبة لكل 100 قرام.
/// - إذا كانت unit != "جرام" => القيم محسوبة لكل 1 وحدة (حبة/علبة/شريحة/كوب...).
class FoodItem {
  final String id;
  final String name;
  final String category;

  /// اسم الوحدة (مثال: قرام / حبة / علبة / شريحة / كوب / ملعقة ...).
  final String unit;

  /// true => القيم لكل 100 قرام والكمية تُدخل بالقرام.
  /// false => القيم لكل 1 وحدة والكمية تُدخل بعدد الوحدات.
  final bool isPer100g;

  // NOTE: نُبقي أسماء الحقول كما هي لتقليل كسر المنطق القديم.
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  FoodItem({
    required this.id,
    required this.name,
    required this.category,
    this.unit = 'قرام',
    bool? isPer100g,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  }) : isPer100g = isPer100g ?? _inferIsPer100g(unit);

  static bool _inferIsPer100g(String u) {
    final t = u.trim();
    return t == 'قرام' || t == 'جرام' || t == 'غ' || t == 'غرام' || t == 'g' || t == 'gram';
  }

  String get baseLabel => isPer100g ? '100 قرام' : unit;

  static String _fmtNumber(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    final iv = v.roundToDouble();
    if ((v - iv).abs() < 0.00001) return iv.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  String formatQty(double qty) {
    return isPer100g ? '${qty.toStringAsFixed(0)} قرام' : '${_fmtNumber(qty)} $unit';
  }

  double kcalForQty(double qty) => isPer100g ? (kcalPer100g * qty / 100.0) : (kcalPer100g * qty);
  double pForQty(double qty) => isPer100g ? (proteinPer100g * qty / 100.0) : (proteinPer100g * qty);
  double cForQty(double qty) => isPer100g ? (carbsPer100g * qty / 100.0) : (carbsPer100g * qty);
  double fForQty(double qty) => isPer100g ? (fatPer100g * qty / 100.0) : (fatPer100g * qty);
}

class SelectedFood {
  final FoodItem item;

  /// كمية مختارة:
  /// - بالقرام إذا item.isPer100g = true
  /// - بعدد الوحدات إذا item.isPer100g = false
  final double qty;

  const SelectedFood(this.item, this.qty);

  String get qtyLabel => item.formatQty(qty);

  double get kcal => item.kcalForQty(qty);
  double get p => item.pForQty(qty);
  double get c => item.cForQty(qty);
  double get f => item.fForQty(qty);
}

enum ReadyPickerMode { composeMeal, quickPick }

/// شاشة "القائمة الجاهزة" بشكل مرتّب:
/// - بحث + تصنيفات
/// - تكوين وجبة (اختيار متعدد + كميات)
/// - اختيار سريع (إضافة عنصر بسرعة)
/// - تبويب "وجباتي" (قوالب محفوظة)
Future<void> showReadyListPicker(
  BuildContext context, {
  required Future<void> Function(List<SelectedFood> items) onAddItemsToToday,
  required Future<void> Function(
    String mealName,
    String? notes,
    List<SelectedFood> items,
  ) onSaveMealTemplate,
  List<FoodItem>? foods,
}) async {
  final customFoods = await _loadReadyFoodsFromPrefs();
  final baseFoods = (foods == null || foods.isEmpty) ? _defaultReadyFoods() : foods;
  final list = _mergeReadyFoods(baseFoods, customFoods);



  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReadyFoodsHubPage(
        foods: list,
        onAddItemsToToday: onAddItemsToToday,
        onSaveMealTemplate: onSaveMealTemplate,
      ),
    ),
  );
}

class ReadyFoodsHubPage extends StatefulWidget {
  const ReadyFoodsHubPage({
    super.key,
    required this.foods,
    required this.onAddItemsToToday,
    required this.onSaveMealTemplate,
  });

  final List<FoodItem> foods;
  final Future<void> Function(List<SelectedFood> items) onAddItemsToToday;
  final Future<void> Function(String mealName, String? notes, List<SelectedFood> items)
      onSaveMealTemplate;

  @override
  State<ReadyFoodsHubPage> createState() => _ReadyFoodsHubPageState();
}

class _ReadyFoodsHubPageState extends State<ReadyFoodsHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  ReadyPickerMode _mode = ReadyPickerMode.composeMeal;

  late List<FoodItem> _foods;

  final TextEditingController _search = TextEditingController();
  String _category = 'الكل';

  // سلة تكوين الوجبة
  final Map<String, double> _qty = {};
  final Set<String> _selected = {};

  // وجباتي (قوالب)
  bool _loadingTemplates = true;
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _foods = List<FoodItem>.of(widget.foods);
    _loadTemplates();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loadingTemplates = true);
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();
    final k = 'meal_templates_$storageKey';

    // ✅ Migration: key القديم كان بدون suffix
    final legacyRaw = prefs.getString('meal_templates');
    if (legacyRaw != null && prefs.getString(k) == null) {
      await prefs.setString(k, legacyRaw);
      await prefs.remove('meal_templates');
    }

    final raw = prefs.getString(k);
    final list = raw == null
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(json.decode(raw));
    if (!mounted) return;
    setState(() {
      _templates = list;
      _loadingTemplates = false;
    });
  }

  // بحث عربي أفضل: إزالة تشكيل + توحيد بعض الأحرف
  String _norm(String s) {
    return s
        .replaceAll(RegExp(r'[\u064B-\u0652]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .trim()
        .toLowerCase();
  }

  List<String> get _categories {
    final set = <String>{'الكل'};
    for (final f in _foods) {
      final c = f.category.trim().isEmpty ? 'Other' : f.category.trim();
      set.add(c);
    }
    final list = set.toList();
    list.sort((a, b) {
      if (a == 'الكل') return -1;
      if (b == 'الكل') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  List<FoodItem> get _filteredFoods {
    final q = _norm(_search.text);
    return _foods
        .where((f) {
          final byCat = (_category == 'الكل') ? true : f.category == _category;
          final bySearch = q.isEmpty ? true : _norm(f.name).contains(q);
          return byCat && bySearch;
        })
        .toList()
      ..sort((a, b) {
        final c = a.category.compareTo(b.category);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
  }

  void _toggleSelect(FoodItem item) {
    setState(() {
      if (_selected.contains(item.id)) {
        _selected.remove(item.id);
      } else {
        _selected.add(item.id);
        _qty.putIfAbsent(item.id, () => item.isPer100g ? 100 : 1);
      }
    });
  }

  double _kcalFor(FoodItem i, double q) =>
      i.isPer100g ? (i.kcalPer100g * q / 100.0) : (i.kcalPer100g * q);
  double _pFor(FoodItem i, double q) =>
      i.isPer100g ? (i.proteinPer100g * q / 100.0) : (i.proteinPer100g * q);
  double _cFor(FoodItem i, double q) =>
      i.isPer100g ? (i.carbsPer100g * q / 100.0) : (i.carbsPer100g * q);
  double _fFor(FoodItem i, double q) =>
      i.isPer100g ? (i.fatPer100g * q / 100.0) : (i.fatPer100g * q);

  List<SelectedFood> get _basketItems {
    return _selected.map((id) {
      final item = _foods.firstWhere((e) => e.id == id);
      final qRaw = (_qty[id] ?? (item.isPer100g ? 100 : 1));
      final q = item.isPer100g
          ? qRaw.clamp(1, 5000).toDouble()
          : qRaw.clamp(0.25, 1000).toDouble();
      return SelectedFood(item, q);
    }).toList();
  }

  Map<String, double> get _basketTotals {
    double kcal = 0, p = 0, c = 0, f = 0;
    for (final s in _basketItems) {
      kcal += _kcalFor(s.item, s.qty);
      p += _pFor(s.item, s.qty);
      c += _cFor(s.item, s.qty);
      f += _fFor(s.item, s.qty);
    }
    return {'kcal': kcal, 'p': p, 'c': c, 'f': f};
  }

  Future<double?> _pickQtySheet({required FoodItem item, required double initial}) async {
    double value = initial;

    final isGram = item.isPer100g;
    final suffix = isGram ? 'قرام' : item.unit;
    final step = isGram ? 25.0 : 1.0;
    final min = isGram ? 1.0 : 0.25;
    final max = isGram ? 5000.0 : 1000.0;

    return showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final controller = TextEditingController(
          text: isGram ? value.toStringAsFixed(0) : FoodItem._fmtNumber(value),
        );

        void apply(double v) {
          value = v.clamp(min, max);
          controller.text = isGram ? value.toStringAsFixed(0) : FoodItem._fmtNumber(value);
        }

        final presets = isGram
            ? <double>[50, 100, 150, 200, 300]
            : <double>[1, 2, 3, 4, 5, 10];

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'حدد الكمية',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  isGram ? 'بالقرام' : 'بالوحدات (${item.unit})',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => apply(value - step),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            suffixText: suffix,
                          ),
                          onChanged: (t) {
                            final n = double.tryParse(t.replaceAll(',', '.'));
                            if (n != null) value = n;
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => apply(value + step),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: presets.map((x) {
                    final label = isGram ? '${x.toStringAsFixed(0)} قرام' : '${FoodItem._fmtNumber(x)} ${item.unit}';
                    return ActionChip(
                      label: Text(label),
                      onPressed: () => apply(x),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, value.clamp(min, max)),
                        child: const Text('تأكيد'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveCustomFoods() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _readyFoodsPrefsKey();
    final custom = _foods
        .where((f) => f.id.startsWith('custom-'))
        .map(_foodItemToPrefs)
        .toList();
    await prefs.setString(key, jsonEncode(custom));
  }

  Future<void> _openCustomFoodSheet() async {
    final created = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => const _CustomFoodSheet(),
    );

    if (!mounted || created == null) return;

    setState(() {
      _foods.add(created);
      _search.clear();
      _category = created.category;
      _selected.add(created.id);
      _qty[created.id] = created.isPer100g ? 100 : 1;
      _mode = ReadyPickerMode.composeMeal;
      _tabs.animateTo(0);
    });
    await _saveCustomFoods();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ ${created.name} ويمكنك استخدامه في وجباتك.')),
    );
  }
Future<void> _quickAdd(FoodItem item) async {
    final q = await _pickQtySheet(item: item, initial: item.isPer100g ? 100 : 1);
    if (q == null) return;
    await widget.onAddItemsToToday([SelectedFood(item, q)]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت إضافة ${item.name} (${item.formatQty(q)})')),
    );
  }

  Future<void> _addBasketToToday() async {
    if (_selected.isEmpty) return;
    await widget.onAddItemsToToday(_basketItems);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تمت إضافة العناصر لليوم')));
  }

  Future<void> _saveMealFlow() async {
    if (_selected.isEmpty) return;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => const _SaveMealTemplateDialog(),
    );

    if (!mounted || result == null) return;

    final rawName = (result['name'] ?? '').trim();
    final mealName = rawName.isEmpty ? 'وجبة بدون اسم' : rawName;
    final notesRaw = (result['notes'] ?? '').trim();
    final notes = notesRaw.isEmpty ? null : notesRaw;

    await widget.onSaveMealTemplate(mealName, notes, _basketItems);
    await _loadTemplates();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تم حفظ "$mealName"')));
  }

  void _openBasketDetails() {
    final items = _basketItems;
    final totals = _basketTotals;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Text(
                'مكونات الوجبة',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _TotalsRow(totals: totals),
              const SizedBox(height: 12),
              ...items.map((s) {
                return ListTile(
                  title: Text(s.item.name),
                  subtitle: Text(
                    '${s.qtyLabel} • ${_kcalFor(s.item, s.qty).toStringAsFixed(0)} kcal',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() => _selected.remove(s.item.id));
                      Navigator.pop(ctx);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _searchBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث عن عنصر…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: _openCustomFoodSheet,
            icon: const Icon(Icons.add),
            tooltip: 'إضافة عنصر خاص',
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _categories[i];
          final selected = _category == c;
          return ChoiceChip(
            label: Text(c),
            selected: selected,
            onSelected: (_) => setState(() => _category = c),
          );
        },
      ),
    );
  }

  Widget _modeSwitcher() {
    // نستخدم ChoiceChips بدل SegmentedButton لزيادة التوافق
    final cs = Theme.of(context).colorScheme;
    final isCompose = _mode == ReadyPickerMode.composeMeal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _mode = ReadyPickerMode.composeMeal),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isCompose ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant,
                        size: 18,
                        color: isCompose ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'تكوين وجبة',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isCompose ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _mode = ReadyPickerMode.quickPick),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !isCompose ? cs.secondaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flash_on,
                        size: 18,
                        color: !isCompose ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'اختيار سريع',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: !isCompose ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsTab() {
    final foods = _filteredFoods;
    final compose = _mode == ReadyPickerMode.composeMeal;

    if (_foods.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 42),
              const SizedBox(height: 10),
              const Text('لا توجد عناصر في القائمة الجاهزة حالياً'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openCustomFoodSheet,
                icon: const Icon(Icons.add),
                label: const Text('إضافة عنصر خاص'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _searchBar(),
        _categoryChips(),
        const SizedBox(height: 8),
        _modeSwitcher(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: foods.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final item = foods[i];
              final isSelected = _selected.contains(item.id);
              final qty = (_qty[item.id] ?? (item.isPer100g ? 100 : 1)).toDouble();

              return _FoodRowCard(
                item: item,
                selected: isSelected,
                compose: compose,
                qty: qty,
                onTap: () {
                  if (compose) {
                    _toggleSelect(item);
                  } else {
                    _quickAdd(item);
                  }
                },
                onMinus: compose
                    ? () {
                        setState(() {
                          final step = item.isPer100g ? 25.0 : 1.0;
                          final min = item.isPer100g ? 1.0 : 0.25;
                          final max = item.isPer100g ? 5000.0 : 1000.0;
                          _qty[item.id] = (qty - step).clamp(min, max).toDouble();
                        });
                      }
                    : null,
                onPlus: compose
                    ? () {
                        setState(() {
                          final step = item.isPer100g ? 25.0 : 1.0;
                          final min = item.isPer100g ? 1.0 : 0.25;
                          final max = item.isPer100g ? 5000.0 : 1000.0;
                          _qty[item.id] = (qty + step).clamp(min, max).toDouble();
                        });
                      }
                    : null,
                onEditQty: compose
                    ? () async {
                        final q = await _pickQtySheet(item: item, initial: qty);
                        if (q == null) return;
                        setState(() => _qty[item.id] = q);
                      }
                    : null,
              );
            },
          ),
        ),

        if (compose && _selected.isNotEmpty)
          _BottomSummaryBar(
            totals: _basketTotals,
            count: _selected.length,
            onDetails: _openBasketDetails,
            onAdd: _addBasketToToday,
            onSave: _saveMealFlow,
          ),
      ],
    );
  }

  Future<void> _deleteTemplateAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await SessionManager.currentStorageKey();
    final k = 'meal_templates_$storageKey';

    setState(() => _templates.removeAt(index));
    await prefs.setString(k, json.encode(_templates));
  }

  Widget _templatesTab() {
    if (_loadingTemplates) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_templates.isEmpty) {
      return const Center(child: Text('لا توجد وجبات محفوظة بعد'));
    }

    return RefreshIndicator(
      onRefresh: _loadTemplates,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _templates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final t = _templates[i];
          final name = (t['name'] ?? 'وجبة').toString();
          final notes = (t['notes'] as String?)?.trim();
          final items = (t['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

          double kcal = 0, p = 0, c = 0, f = 0;
          for (final it in items) {
            double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

            final unit = (it['unit'] ?? 'جرام').toString();
            final per100g = (it['per100g'] is bool)
                ? (it['per100g'] as bool)
                : ((it['isPer100g'] is bool)
                    ? (it['isPer100g'] as bool)
                    : FoodItem._inferIsPer100g(unit));

            final qty = d(it['qty']) != 0
                ? d(it['qty'])
                : (d(it['grams']) != 0 ? d(it['grams']) : 100);

            final kcalBase = d(it['kcalBase']) != 0
                ? d(it['kcalBase'])
                : (d(it['kBase']) != 0
                    ? d(it['kBase'])
                    : (d(it['kcal100']) != 0
                        ? d(it['kcal100'])
                        : d(it['kcal'])));
            final pBase = d(it['pBase']) != 0
                ? d(it['pBase'])
                : (d(it['p100']) != 0 ? d(it['p100']) : d(it['protein']));
            final cBase = d(it['cBase']) != 0
                ? d(it['cBase'])
                : (d(it['c100']) != 0 ? d(it['c100']) : d(it['carb']));
            final fBase = d(it['fBase']) != 0
                ? d(it['fBase'])
                : (d(it['f100']) != 0 ? d(it['f100']) : d(it['fat']));

            final factor = per100g ? (qty / 100.0) : qty;
            kcal += kcalBase * factor;
            p += pBase * factor;
            c += cBase * factor;
            f += fBase * factor;
          }

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _deleteTemplateAt(i),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'حذف',
                      ),
                    ],
                  ),
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(notes, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 10),
                  _TotalsRow(totals: {'kcal': kcal, 'p': p, 'c': c, 'f': f}),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      // نحولها إلى SelectedFood ليتعامل معها Home بنفس طريقة العناصر
                      final selected = items.map((it) {
                        double d(dynamic v) =>
                            (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

                        final id = (it['id'] ?? '').toString();
                        final nm = (it['name'] ?? '').toString();

                        final unit = (it['unit'] ?? 'جرام').toString();
                        final per100g = (it['per100g'] is bool)
                            ? (it['per100g'] as bool)
                            : ((it['isPer100g'] is bool)
                                ? (it['isPer100g'] as bool)
                                : FoodItem._inferIsPer100g(unit));

                        final qty = d(it['qty']) != 0
                            ? d(it['qty'])
                            : (d(it['grams']) != 0 ? d(it['grams']) : 100);

                        final kcalBase = d(it['kcalBase']) != 0
                            ? d(it['kcalBase'])
                            : (d(it['kBase']) != 0
                                ? d(it['kBase'])
                                : (d(it['kcal100']) != 0
                                    ? d(it['kcal100'])
                                    : d(it['kcal'])));
                        final pBase = d(it['pBase']) != 0
                            ? d(it['pBase'])
                            : (d(it['p100']) != 0 ? d(it['p100']) : d(it['protein']));
                        final cBase = d(it['cBase']) != 0
                            ? d(it['cBase'])
                            : (d(it['c100']) != 0 ? d(it['c100']) : d(it['carb']));
                        final fBase = d(it['fBase']) != 0
                            ? d(it['fBase'])
                            : (d(it['f100']) != 0 ? d(it['f100']) : d(it['fat']));

                        final food = FoodItem(
                          id: id.isEmpty ? 'saved-$i-${nm.hashCode}' : id,
                          name: nm,
                          category: 'Saved',
                          unit: unit,
                          isPer100g: per100g,
                          kcalPer100g: kcalBase,
                          proteinPer100g: pBase,
                          carbsPer100g: cBase,
                          fatPer100g: fBase,
                        );
                        return SelectedFood(food, qty.toDouble());
                      }).toList();

                      await widget.onAddItemsToToday(selected);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تمت إضافة "$name" لليوم')),
                      );
                    },
                    icon: const Icon(Icons.add_task),
                    label: const Text('إضافة لليوم'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  

  

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('القائمة الجاهزة'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'إضافة عنصر خاص',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: _openCustomFoodSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'العناصر'),
            Tab(text: 'وجباتي'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _itemsTab(),
          _templatesTab(),
        ],
      ),
    );
  }
}

class _CustomFoodSheet extends StatefulWidget {
  const _CustomFoodSheet();

  @override
  State<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends State<_CustomFoodSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController(text: 'عناصري');
  final _unitCtrl = TextEditingController(text: 'شريحة');
  final _kcalCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  bool _isPer100g = false;
  bool _autoCalories = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  double _toDouble(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0.0;
  }

  void _balanceCalories({bool rebuild = false}) {
    if (!_autoCalories) return;
    final p = _toDouble(_proteinCtrl.text);
    final c = _toDouble(_carbsCtrl.text);
    final f = _toDouble(_fatCtrl.text);
    final kcal = (p * 4) + (c * 4) + (f * 9);
    final newText = kcal.round().toString();
    if (_kcalCtrl.text != newText) {
      _kcalCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    if (rebuild && mounted) setState(() {});
  }

  void _save() {
    _balanceCalories();
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final category = _categoryCtrl.text.trim().isEmpty
        ? 'عناصري'
        : _categoryCtrl.text.trim();
    final unit = _isPer100g ? 'قرام' : _unitCtrl.text.trim();
    final kcal = _toDouble(_kcalCtrl.text);
    final p = _toDouble(_proteinCtrl.text);
    final c = _toDouble(_carbsCtrl.text);
    final f = _toDouble(_fatCtrl.text);

    if (kcal <= 0 && p <= 0 && c <= 0 && f <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل قيمة واحدة على الأقل من السعرات أو الماكروز.')),
      );
      return;
    }

    Navigator.pop(
      context,
      FoodItem(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        category: category,
        unit: unit,
        isPer100g: _isPer100g,
        kcalPer100g: kcal,
        proteinPer100g: p,
        carbsPer100g: c,
        fatPer100g: f,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unitLabel = _unitCtrl.text.trim().isEmpty ? 'وحدة' : _unitCtrl.text.trim();
    final baseLabel = _isPer100g ? 'لكل 100 قرام' : 'لكل 1 $unitLabel';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.add_circle_rounded, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إضافة عنصر غذائي خاص',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'احفظ عناصر مثل شريحة جبن، علبة تونة، صوص… واستخدمها لاحقًا في تكوين وجباتك.',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم العنصر',
                  hintText: 'مثال: شريحة جبن قليل الدسم',
                  prefixIcon: Icon(Icons.restaurant_menu_rounded),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب اسم العنصر' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _categoryCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'التصنيف',
                        hintText: 'عناصري',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _unitCtrl,
                      enabled: !_isPer100g,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'الوحدة',
                        hintText: 'شريحة / حبة / علبة',
                        prefixIcon: Icon(Icons.straighten_rounded),
                      ),
                      validator: (v) {
                        if (_isPer100g) return null;
                        return (v ?? '').trim().isEmpty ? 'اكتب الوحدة' : null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'طريقة حساب القيم',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          selected: !_isPer100g,
                          label: const Text('لكل وحدة'),
                          onSelected: (_) => setState(() => _isPer100g = false),
                        ),
                        ChoiceChip(
                          selected: _isPer100g,
                          label: const Text('لكل 100 قرام'),
                          onSelected: (_) => setState(() {
                            _isPer100g = true;
                            _unitCtrl.text = 'قرام';
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'القيم التالية تُحفظ $baseLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _autoCalories,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('احسب السعرات من الماكروز تلقائيًا'),
                subtitle: const Text('البروتين والكارب × 4، الدهون × 9'),
                onChanged: (v) {
                  setState(() => _autoCalories = v);
                  _balanceCalories();
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _kcalCtrl,
                enabled: !_autoCalories,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'السعرات kcal ($baseLabel)',
                  prefixIcon: const Icon(Icons.local_fire_department_rounded),
                ),
                validator: (v) {
                  final n = _toDouble(v ?? '');
                  if (n < 0 || n > 5000) return 'أدخل سعرات صحيحة';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _proteinCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'بروتين (قرام)'),
                      onChanged: (_) => _balanceCalories(rebuild: true),
                      validator: (v) => _toDouble(v ?? '') < 0 ? 'قيمة غير صحيحة' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _carbsCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'كارب (قرام)'),
                      onChanged: (_) => _balanceCalories(rebuild: true),
                      validator: (v) => _toDouble(v ?? '') < 0 ? 'قيمة غير صحيحة' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _fatCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'دهون (قرام)'),
                onChanged: (_) => _balanceCalories(rebuild: true),
                validator: (v) => _toDouble(v ?? '') < 0 ? 'قيمة غير صحيحة' : null,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded),
                label: const Text('حفظ العنصر'),
                onPressed: _save,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveMealTemplateDialog extends StatefulWidget {
  const _SaveMealTemplateDialog();

  @override
  State<_SaveMealTemplateDialog> createState() => _SaveMealTemplateDialogState();
}

class _SaveMealTemplateDialogState extends State<_SaveMealTemplateDialog> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حفظ كوجبة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الوجبة'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, <String, String?>{
            'name': _nameCtrl.text,
            'notes': _notesCtrl.text,
          }),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _FoodRowCard extends StatelessWidget {
  const _FoodRowCard({
    required this.item,
    required this.selected,
    required this.compose,
    required this.qty,
    required this.onTap,
    this.onMinus,
    this.onPlus,
    this.onEditQty,
  });

  final FoodItem item;
  final bool selected;
  final bool compose;
  final double qty;
  final VoidCallback onTap;

  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onEditQty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget miniChip(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    }

    Widget macroText(String text) {
      return Text(
        text,
        style: tt.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.local_dining, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (compose)
                        Checkbox(
                          value: selected,
                          onChanged: (_) => onTap(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.category,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      miniChip('${item.kcalPer100g.toStringAsFixed(0)} kcal/${item.baseLabel}'),
                      macroText('بروتين ${item.proteinPer100g.toStringAsFixed(0)} قرام'),
                      macroText('كارب ${item.carbsPer100g.toStringAsFixed(0)} قرام'),
                      macroText('دهون ${item.fatPer100g.toStringAsFixed(0)} قرام'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (compose)
                    Row(
                      children: [
                        IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline)),
                        TextButton(
                          onPressed: onEditQty,
                          child: Text(item.formatQty(qty)),
                        ),
                        IconButton(onPressed: onPlus, icon: const Icon(Icons.add_circle_outline)),
                        const Spacer(),
                        Text(
                          'كمية العنصر',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    )
                  else
                    Text(
                      'اضغط للإضافة',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.totals});
  final Map<String, double> totals;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MiniChip(text: '${(totals['kcal'] ?? 0).toStringAsFixed(0)} kcal'),
        _PlainMacroText(text: 'بروتين ${(totals['p'] ?? 0).toStringAsFixed(0)} قرام'),
        _PlainMacroText(text: 'كارب ${(totals['c'] ?? 0).toStringAsFixed(0)} قرام'),
        _PlainMacroText(text: 'دهون ${(totals['f'] ?? 0).toStringAsFixed(0)} قرام'),
      ],
    );
  }
}


class _PlainMacroText extends StatelessWidget {
  const _PlainMacroText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BottomSummaryBar extends StatelessWidget {
  const _BottomSummaryBar({
    required this.totals,
    required this.count,
    required this.onDetails,
    required this.onAdd,
    required this.onSave,
  });

  final Map<String, double> totals;
  final int count;
  final VoidCallback onDetails;
  final VoidCallback onAdd;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, -6),
              color: Colors.black.withOpacity(.06),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'مختار: $count عنصر',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('تفاصيل'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _TotalsRow(totals: totals),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_task),
                    label: const Text('إضافة لليوم'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ كوجبة'),
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
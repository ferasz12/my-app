import 'package:flutter/material.dart';
import '../foods/food_submission_form_screen.dart';

/// نموذج عنصر غذائي موحّد (لكل 100غ)
class FoodItem {
  final String id;
  final String name;
  final String category;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  const FoodItem({
    required this.id,
    required this.name,
    required this.category,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });
}

class SelectedFood {
  final FoodItem item;
  final double grams;
  const SelectedFood(this.item, this.grams);
}

enum MealComposerMode { composeMeal, quickPick }

Future<void> showReadyListPicker(
  BuildContext context, {
  required void Function(List<SelectedFood> items) onAddItemsToToday,
  required void Function(String mealName, List<SelectedFood> items)
      onSaveMealTemplate,
  List<FoodItem>? foods, // ← تمرير أطعمتك هنا
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  final choice = await showModalBottomSheet<MealComposerMode>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 12),
            Text('القائمة الجاهزة',
                style: Theme.of(sheetCtx).textTheme.titleLarge),
            const SizedBox(height: 12),

            // زر إضافة عنصر من المستخدم
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FoodSubmissionFormScreen(),
                  ));
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة عنصر'),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.restaurant, color: cs.onPrimaryContainer),
              ),
              title: const Text('تكوين وجبة'),
              subtitle: const Text('اختر عدة عناصر وحدد الكميات واحفظها كوجبة'),
              onTap: () =>
                  Navigator.pop(sheetCtx, MealComposerMode.composeMeal),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.secondaryContainer,
                child: Icon(Icons.playlist_add, color: cs.onSecondaryContainer),
              ),
              title: const Text('اختيار عناصر بسرعة'),
              subtitle: const Text('اختر عنصرًا وحدد كميته لينضاف مباشرة'),
              onTap: () => Navigator.pop(sheetCtx, MealComposerMode.quickPick),
            ),
          ],
        ),
      );
    },
  );

  if (choice != null) {
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => MealComposerPage(
          mode: choice,
          onAddItemsToToday: onAddItemsToToday,
          onSaveMealTemplate: onSaveMealTemplate,
          initialFoods: foods, // ← هنا تمرير الأطعمة
        ),
      ),
    );
  }
}

class MealComposerPage extends StatefulWidget {
  const MealComposerPage({
    super.key,
    required this.mode,
    required this.onAddItemsToToday,
    required this.onSaveMealTemplate,
    this.initialFoods,
  });

  final MealComposerMode mode;
  final void Function(List<SelectedFood> items) onAddItemsToToday;
  final void Function(String mealName, List<SelectedFood> items)
      onSaveMealTemplate;
  final List<FoodItem>? initialFoods;

  @override
  State<MealComposerPage> createState() => _MealComposerPageState();
}

class _MealComposerPageState extends State<MealComposerPage> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _mealName = TextEditingController();
  String? _selectedCategory;
  final Map<String, double> _gramsMap = {};
  final Set<String> _selectedIds = {};

  // لو ما تم تمرير أطعمة، نوفر ثلاث عناصر افتراضية
  late final List<FoodItem> _all = widget.initialFoods ??
      const [
        FoodItem(
            id: 'demo-1',
            name: 'صدر دجاج',
            category: 'Protein',
            kcalPer100g: 165,
            proteinPer100g: 31,
            carbsPer100g: 0,
            fatPer100g: 3.6),
        FoodItem(
            id: 'demo-2',
            name: 'أرز مطبوخ',
            category: 'Carbs',
            kcalPer100g: 130,
            proteinPer100g: 2.4,
            carbsPer100g: 28,
            fatPer100g: 0.3),
        FoodItem(
            id: 'demo-3',
            name: 'تفاح',
            category: 'Fruits',
            kcalPer100g: 52,
            proteinPer100g: 0.3,
            carbsPer100g: 14,
            fatPer100g: 0.2),
      ];

  List<String> get _categories {
    final s = {'All', ..._all.map((e) => e.category)};
    return s.toList();
  }

  List<FoodItem> get _filtered {
    final q = _search.text.trim();
    final cat = _selectedCategory;
    return _all.where((f) {
      final byCat = (cat == null || cat == 'All') ? true : f.category == cat;
      final bySearch = q.isEmpty ? true : f.name.contains(q);
      return byCat && bySearch;
    }).toList();
  }

  void _toggleSelect(FoodItem item) {
    if (widget.mode == MealComposerMode.quickPick) return;
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
      } else {
        _selectedIds.add(item.id);
      }
      _gramsMap.putIfAbsent(item.id, () => 100);
    });
  }

  void _updateGrams(FoodItem item, double grams) {
    setState(() {
      _gramsMap[item.id] = grams;
      if (widget.mode == MealComposerMode.quickPick) {
        widget.onAddItemsToToday([SelectedFood(item, grams)]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('أُضيف ${item.name} (${grams.toStringAsFixed(0)}غ)')),
        );
      }
    });
  }

  double _kcalFor(FoodItem item, double grams) =>
      item.kcalPer100g * grams / 100.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isCompose = widget.mode == MealComposerMode.composeMeal;

    return Scaffold(
      appBar: AppBar(
        title: Text(isCompose ? 'تكوين وجبة' : 'اختيار عناصر بسرعة'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'ابحث عن عنصر غذائي…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final c = _categories[i];
                final selected = (_selectedCategory ?? 'All') == c;
                return FilterChip(
                  label: Text(c == 'All' ? 'الكل' : c),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedCategory = c),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = _filtered[i];
                final grams = _gramsMap[item.id] ?? 100.0;
                final kcal = _kcalFor(item, grams);

                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.local_dining,
                              color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: Text(item.name,
                                          style: tt.titleMedium)),
                                  if (isCompose)
                                    Checkbox(
                                      value: _selectedIds.contains(item.id),
                                      onChanged: (_) => _toggleSelect(item),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item.category} • ${kcal.toStringAsFixed(0)} kcal',
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('الكمية (غ):', style: tt.bodyMedium),
                                  Expanded(
                                    child: Slider(
                                      value: grams,
                                      min: 20,
                                      max: 400,
                                      divisions: 19,
                                      label: grams.toStringAsFixed(0),
                                      onChanged: (v) => _updateGrams(item, v),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          isDense: true, hintText: 'غ'),
                                      controller: TextEditingController(
                                          text: grams.toStringAsFixed(0)),
                                      onSubmitted: (txt) {
                                        final g = double.tryParse(txt);
                                        if (g != null && g > 0) {
                                          _updateGrams(item, g);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (isCompose)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _mealName,
                      decoration: const InputDecoration(
                        labelText: 'اسم الوجبة (اختياري للحفظ كوجبة جاهزة)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () {
                                    final items = _selectedIds.map((id) {
                                      final item =
                                          _all.firstWhere((e) => e.id == id);
                                      final grams = _gramsMap[id] ?? 100.0;
                                      return SelectedFood(item, grams);
                                    }).toList();
                                    widget.onAddItemsToToday(items);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('تمت إضافة العناصر لليوم')),
                                    );
                                  },
                            icon: const Icon(Icons.add_task),
                            label: const Text('إضافة لليوم'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () {
                                    final name = _mealName.text.trim().isEmpty
                                        ? 'وجبة بدون اسم'
                                        : _mealName.text.trim();
                                    final items = _selectedIds.map((id) {
                                      final item =
                                          _all.firstWhere((e) => e.id == id);
                                      final grams = _gramsMap[id] ?? 100.0;
                                      return SelectedFood(item, grams);
                                    }).toList();
                                    widget.onSaveMealTemplate(name, items);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'تم حفظ "$name" كوجبة جاهزة')),
                                    );
                                  },
                            icon: const Icon(Icons.save),
                            label: const Text('حفظ كوجبة'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

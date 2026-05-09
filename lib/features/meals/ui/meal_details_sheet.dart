// lib/features/meals/ui/meal_details_sheet.dart
// Compact premium meal details bottom sheet.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

double _toD(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int _clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);
String _fmt0(num v) => v.toStringAsFixed(0);
String _fmt1(num v) => v.toStringAsFixed(1);
String _fmtSmart(num v, {int decimals = 1}) {
  if (v.isNaN || v.isInfinite) return '0';
  if (decimals <= 0) return v.round().toString();
  final r = double.parse(v.toStringAsFixed(decimals));
  return (r % 1 == 0) ? r.toStringAsFixed(0) : r.toStringAsFixed(decimals);
}

String _itemName(Map<String, dynamic> item) {
  final raw = item['name'] ?? item['item'] ?? item['label'] ?? item['title'];
  final s = (raw ?? 'عنصر').toString().trim();
  return s.isEmpty ? 'عنصر' : s;
}

double _itemCalories(Map<String, dynamic> item) =>
    _toD(item['calories'] ?? item['cal'] ?? item['kcal']);

double _itemProtein(Map<String, dynamic> item) =>
    _toD(item['protein'] ?? item['pro'] ?? item['protein_g']);

double _itemCarb(Map<String, dynamic> item) =>
    _toD(item['carb'] ?? item['carbs'] ?? item['carb_g'] ?? item['carbs_g']);

double _itemFat(Map<String, dynamic> item) =>
    _toD(item['fat'] ?? item['fat_g'] ?? item['fats']);

double _itemGrams(Map<String, dynamic> item) =>
    _toD(item['grams'] ?? item['g'] ?? item['weight'] ?? item['serving_size_g']);

Future<void> showMealDetailsSheet(
  BuildContext context, {
  required String mealName,
  required double calories,
  required double protein,
  required double carb,
  required double fat,
  required List<Map<String, dynamic>> items,
  required double userWeightKg,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _MealDetailsSheetBody(
      mealName: mealName,
      calories: calories,
      protein: protein,
      carb: carb,
      fat: fat,
      items: items,
      userWeightKg: userWeightKg,
    ),
  );
}

class _MealDetailsSheetBody extends StatelessWidget {
  final String mealName;
  final double calories;
  final double protein;
  final double carb;
  final double fat;
  final List<Map<String, dynamic>> items;
  final double userWeightKg;

  const _MealDetailsSheetBody({
    required this.mealName,
    required this.calories,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.items,
    required this.userWeightKg,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pKcalRaw = math.max(0.0, protein * 4.0);
    final cKcalRaw = math.max(0.0, carb * 4.0);
    final fKcalRaw = math.max(0.0, fat * 9.0);
    final macroKcalRaw = pKcalRaw + cKcalRaw + fKcalRaw;

    final mealKcal = calories > 0 ? calories : macroKcalRaw;
    final mealKcalRounded = math.max(0, mealKcal.round());

    int pKcalDisp = math.max(0, pKcalRaw.round());
    int cKcalDisp = math.max(0, cKcalRaw.round());
    int fKcalDisp = math.max(0, fKcalRaw.round());

    final macroSumRounded = pKcalDisp + cKcalDisp + fKcalDisp;
    int adjust = mealKcalRounded - macroSumRounded;
    if (macroSumRounded > 0 && adjust != 0) {
      final macros = <Map<String, dynamic>>[
        {'k': 'p', 'v': pKcalDisp},
        {'k': 'c', 'v': cKcalDisp},
        {'k': 'f', 'v': fKcalDisp},
      ]..sort((a, b) => (b['v'] as int).compareTo(a['v'] as int));
      for (final m in macros) {
        if (adjust == 0) break;
        int v = m['v'] as int;
        if (adjust > 0) {
          v += adjust;
          adjust = 0;
        } else {
          final take = math.min(v, -adjust);
          v -= take;
          adjust += take;
        }
        m['v'] = v;
      }
      for (final m in macros) {
        final key = m['k'] as String;
        final v = m['v'] as int;
        if (key == 'p') pKcalDisp = v;
        if (key == 'c') cKcalDisp = v;
        if (key == 'f') fKcalDisp = v;
      }
    }

    final pKcal = pKcalDisp.toDouble();
    final cKcal = cKcalDisp.toDouble();
    final fKcal = fKcalDisp.toDouble();
    final macroKcal = pKcal + cKcal + fKcal;
    final safeTotal = mealKcalRounded <= 0 ? 1.0 : mealKcalRounded.toDouble();

    final pPct = macroKcal <= 0 ? 0.0 : (pKcal / macroKcal) * 100.0;
    final cPct = macroKcal <= 0 ? 0.0 : (cKcal / macroKcal) * 100.0;
    final fPct = macroKcal <= 0 ? 0.0 : (fKcal / macroKcal) * 100.0;

    final wRatio = (userWeightKg / 70.0).clamp(0.6, 1.6);
    final kcalPerStep = 0.04 * wRatio;
    final estSteps = _clampInt((safeTotal / kcalPerStep).ceil(), 0, 200000);
    final distanceKm = (estSteps * 0.75) / 1000.0;
    final minutesWalk = estSteps / 100.0;

    final totalGrams = items.fold<double>(0.0, (sum, e) => sum + _itemGrams(e));
    final hasItemDetails = items.isNotEmpty;

    final top = List<Map<String, dynamic>>.from(items);
    top.sort((a, b) => _itemCalories(b).compareTo(_itemCalories(a)));
    final top2 = top.take(2).toList();

    final tips = <String>[];
    if (protein <= 10 && safeTotal >= 300) {
      tips.add('البروتين منخفض مقارنة بالسعرات.');
    }
    if (fPct >= 45) {
      tips.add('الدهون مرتفعة نسبيًا.');
    }
    if (cPct >= 55) {
      tips.add('الكارب مرتفع نسبيًا.');
    }
    if (tips.isEmpty) {
      tips.add('توزيع الماكروز جيد ومتوازن نسبيًا.');
    }

    return SafeArea(
      top: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.86,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'إغلاق',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: cs.onSurface.withOpacity(.85)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            mealName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _HeaderChip(icon: Icons.local_fire_department_rounded, label: '${_fmt0(safeTotal)} kcal'),
                              _HeaderChip(icon: Icons.restaurant_menu_rounded, label: hasItemDetails ? '${items.length} عناصر' : 'وجبة واحدة'),
                              if (totalGrams > 0) _HeaderChip(icon: Icons.scale_rounded, label: '${_fmt0(totalGrams)} غ'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        _SectionCard(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle('ملخص الماكروز'),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _CompactCircleMacroStat(
                                      label: 'السعرات',
                                      value: _fmt0(safeTotal),
                                      unit: 'kcal',
                                      emoji: '🔥',
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _CompactCircleMacroStat(
                                      label: 'البروتين',
                                      value: _fmtSmart(protein),
                                      unit: 'غ',
                                      emoji: '🥩',
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _CompactCircleMacroStat(
                                      label: 'الكارب',
                                      value: _fmtSmart(carb),
                                      unit: 'غ',
                                      emoji: '🍞',
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _CompactCircleMacroStat(
                                      label: 'الدهون',
                                      value: _fmtSmart(fat),
                                      unit: 'غ',
                                      emoji: '🥑',
                                      color: Colors.teal,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SectionCard(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle('التوزيع والتفاصيل السريعة'),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: SizedBox(
                                      height: 148,
                                      child: _MacroPie(
                                        proteinKcal: pKcal,
                                        carbKcal: cKcal,
                                        fatKcal: fKcal,
                                        totalKcal: safeTotal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      children: [
                                        _MacroLegendTile(label: 'بروتين', emoji: '🥩', percent: pPct, kcal: pKcal, color: cs.primary),
                                        const SizedBox(height: 6),
                                        _MacroLegendTile(label: 'كارب', emoji: '🍞', percent: cPct, kcal: cKcal, color: Colors.orange),
                                        const SizedBox(height: 6),
                                        _MacroLegendTile(label: 'دهون', emoji: '🥑', percent: fPct, kcal: fKcal, color: Colors.teal),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (hasItemDetails) ...[
                                const SizedBox(height: 10),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                const _SectionTitle('تفاصيل عناصر الوجبة'),
                                const SizedBox(height: 8),
                                ...items.take(3).map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 7),
                                    child: _CompactIngredientRow(
                                      name: _itemName(item),
                                      calories: _itemCalories(item),
                                      protein: _itemProtein(item),
                                      carb: _itemCarb(item),
                                      fat: _itemFat(item),
                                      grams: _itemGrams(item),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 10),
                                _InfoBanner(
                                  text: 'لا توجد تفاصيل مفصلة لهذه الوجبة حاليًا.',
                                  icon: Icons.info_outline_rounded,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SectionCard(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _SectionTitle('الحرق التقديري'),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: cs.primary.withOpacity(.12),
                                          ),
                                          child: Icon(Icons.directions_walk_rounded, color: cs.primary),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${estSteps.toString()} خطوة', style: const TextStyle(fontSize: 14.2, fontWeight: FontWeight.w900)),
                                              const SizedBox(height: 2),
                                              Text('≈ ${_fmt1(distanceKm)} كم • ${_fmt0(minutesWalk)} د', style: TextStyle(fontSize: 11.2, color: cs.onSurface.withOpacity(.72))),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SectionCard(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _SectionTitle('ملاحظات مفيدة'),
                                    const SizedBox(height: 8),
                                    ...tips.take(2).map(
                                      (t) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.lightbulb_outline_rounded, size: 16, color: cs.primary),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(t, style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (top2.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SectionCard(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionTitle('أعلى العناصر في السعرات'),
                                const SizedBox(height: 8),
                                ...top2.map(
                                  (it) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _itemName(it),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.8),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceVariant.withOpacity(.22),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text('${_fmt0(_itemCalories(it))} kcal', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SectionCard({required this.child, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: cs.surfaceVariant.withOpacity(.18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.18)),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14.2, fontWeight: FontWeight.w900),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11.7, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _CompactCircleMacroStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String emoji;
  final Color color;

  const _CompactCircleMacroStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.emoji,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(.10),
          border: Border.all(color: color.withOpacity(.22)),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  Text(unit, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MacroLegendTile extends StatelessWidget {
  final String label;
  final String emoji;
  final double percent;
  final double kcal;
  final Color color;

  const _MacroLegendTile({
    required this.label,
    required this.emoji,
    required this.percent,
    required this.kcal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.86),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w800))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_fmt0(percent)}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
              Text('${_fmt0(kcal)} kcal', style: TextStyle(fontSize: 10.5, color: cs.onSurface.withOpacity(.7))),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactIngredientRow extends StatelessWidget {
  final String name;
  final double calories;
  final double protein;
  final double carb;
  final double fat;
  final double grams;

  const _CompactIngredientRow({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.grams,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w900)),
              ),
              if (grams > 0)
                Text('${_fmt0(grams)} غ', style: TextStyle(fontSize: 11.2, fontWeight: FontWeight.w800, color: cs.primary)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _TinyPill('🔥', '${_fmt0(calories)} kcal'),
              _TinyPill('🥩', '${_fmtSmart(protein)}غ'),
              _TinyPill('🍞', '${_fmtSmart(carb)}غ'),
              _TinyPill('🥑', '${_fmtSmart(fat)}غ'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  final String emoji;
  final String text;
  const _TinyPill(this.emoji, this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 10.8, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  const _InfoBanner({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _MacroPie extends StatelessWidget {
  final double proteinKcal;
  final double carbKcal;
  final double fatKcal;
  final double totalKcal;

  const _MacroPie({
    required this.proteinKcal,
    required this.carbKcal,
    required this.fatKcal,
    required this.totalKcal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = <PieChartSectionData>[
      PieChartSectionData(value: proteinKcal <= 0 ? 0.01 : proteinKcal, color: cs.primary, title: '', radius: 30),
      PieChartSectionData(value: carbKcal <= 0 ? 0.01 : carbKcal, color: Colors.orange, title: '', radius: 30),
      PieChartSectionData(value: fatKcal <= 0 ? 0.01 : fatKcal, color: Colors.teal, title: '', radius: 30),
    ];

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sections: sections,
            sectionsSpace: 3,
            centerSpaceRadius: 22,
            startDegreeOffset: -90,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fmt0(totalKcal), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            Text('kcal', style: TextStyle(fontSize: 9.5, color: cs.onSurface.withOpacity(.65))),
          ],
        ),
      ],
    );
  }
}

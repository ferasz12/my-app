// lib/features/meals/ui/meal_details_sheet.dart
// Premium fixed meal details sheet using Wazen PDF tracking colors and original macro emojis.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

const Color _wazenSheetBg = Color(0xFFF7FAF9);
const Color _wazenCardBg = Colors.white;
const Color _wazenBorder = Color(0xFFE5ECEA);
const Color _wazenText = Color(0xFF111827);
const Color _wazenMuted = Color(0xFF6B7280);

// نفس هوية ألوان تتبع PDF في وازن:
// بروتين = أزرق/إنديجو، كارب = برتقالي، دهون = رمادي، السعرات = أخضر/تيل.
const Color _pdfProteinColor = Color(0xFF3F51B5);
const Color _pdfCarbColor = Color(0xFFFF5722);
const Color _pdfFatColor = Color(0xFF616161);
const Color _pdfCaloriesColor = Color(0xFF00897B);
const Color _pdfEmptyColor = Color(0xFFE5E7EB);

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
    enableDrag: false,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(.28),
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
    final safeTotal = mealKcalRounded <= 0 ? 0.0 : mealKcalRounded.toDouble();
    final calcTotal = safeTotal <= 0 ? 1.0 : safeTotal;

    final pPct = macroKcal <= 0 ? 0.0 : (pKcal / macroKcal) * 100.0;
    final cPct = macroKcal <= 0 ? 0.0 : (cKcal / macroKcal) * 100.0;
    final fPct = macroKcal <= 0 ? 0.0 : (fKcal / macroKcal) * 100.0;

    final wRatio = (userWeightKg / 70.0).clamp(0.6, 1.6);
    final kcalPerStep = 0.04 * wRatio;
    final estSteps = _clampInt((calcTotal / kcalPerStep).ceil(), 0, 200000);
    final distanceKm = (estSteps * 0.75) / 1000.0;
    final minutesWalk = estSteps / 100.0;

    final totalGrams = items.fold<double>(0.0, (sum, e) => sum + _itemGrams(e));
    final hasItemDetails = items.isNotEmpty;

    final top = List<Map<String, dynamic>>.from(items);
    top.sort((a, b) => _itemCalories(b).compareTo(_itemCalories(a)));
    final top2 = top.take(2).toList();

    final tips = <String>[];
    if (protein <= 10 && calcTotal >= 300) {
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
          heightFactor: 0.88,
          child: Container(
            decoration: const BoxDecoration(
              color: _wazenSheetBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 28,
                  offset: Offset(0, -8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                children: [
                  const _FixedHandle(),
                  const SizedBox(height: 10),
                  _Header(
                    mealName: mealName,
                    calories: safeTotal,
                    itemsCount: items.length,
                    totalGrams: totalGrams,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionTitle('ملخص الماكروز'),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _MacroMetricCard(
                                        label: 'السعرات',
                                        value: _fmt0(safeTotal),
                                        unit: 'kcal',
                                        emoji: '🔥',
                                        color: _pdfCaloriesColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _MacroMetricCard(
                                        label: 'البروتين',
                                        value: _fmtSmart(protein),
                                        unit: 'غ',
                                        emoji: '🥩',
                                        color: _pdfProteinColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _MacroMetricCard(
                                        label: 'الكارب',
                                        value: _fmtSmart(carb),
                                        unit: 'غ',
                                        emoji: '🍞',
                                        color: _pdfCarbColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _MacroMetricCard(
                                        label: 'الدهون',
                                        value: _fmtSmart(fat),
                                        unit: 'غ',
                                        emoji: '🥑',
                                        color: _pdfFatColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionTitle('التوزيع والتفاصيل السريعة'),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 355;
                                    if (compact) {
                                      return Column(
                                        children: [
                                          SizedBox(
                                            height: 158,
                                            child: _MacroPie(
                                              proteinKcal: pKcal,
                                              carbKcal: cKcal,
                                              fatKcal: fKcal,
                                              totalKcal: safeTotal,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          _MacroLegendTile(
                                            label: 'بروتين',
                                            percent: pPct,
                                            kcal: pKcal,
                                            color: _pdfProteinColor,
                                          ),
                                          const SizedBox(height: 7),
                                          _MacroLegendTile(
                                            label: 'كارب',
                                            percent: cPct,
                                            kcal: cKcal,
                                            color: _pdfCarbColor,
                                          ),
                                          const SizedBox(height: 7),
                                          _MacroLegendTile(
                                            label: 'دهون',
                                            percent: fPct,
                                            kcal: fKcal,
                                            color: _pdfFatColor,
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: SizedBox(
                                            height: 158,
                                            child: _MacroPie(
                                              proteinKcal: pKcal,
                                              carbKcal: cKcal,
                                              fatKcal: fKcal,
                                              totalKcal: safeTotal,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 5,
                                          child: Column(
                                            children: [
                                              _MacroLegendTile(
                                                label: 'بروتين',
                                                percent: pPct,
                                                kcal: pKcal,
                                                color: _pdfProteinColor,
                                              ),
                                              const SizedBox(height: 7),
                                              _MacroLegendTile(
                                                label: 'كارب',
                                                percent: cPct,
                                                kcal: cKcal,
                                                color: _pdfCarbColor,
                                              ),
                                              const SizedBox(height: 7),
                                              _MacroLegendTile(
                                                label: 'دهون',
                                                percent: fPct,
                                                kcal: fKcal,
                                                color: _pdfFatColor,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _QuickInfoBox(
                                        icon: Icons.directions_walk_rounded,
                                        label: 'الحرق بالمشي',
                                        value: '${estSteps.toString()} خطوة',
                                        sub: '≈ ${_fmt1(distanceKm)} كم • ${_fmt0(minutesWalk)} د',
                                        color: _pdfCaloriesColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _QuickInfoBox(
                                        icon: Icons.insights_rounded,
                                        label: 'ملاحظة',
                                        value: tips.first,
                                        sub: 'تقدير حسب الماكروز',
                                        color: _pdfProteinColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionTitle('تفاصيل عناصر الوجبة'),
                                const SizedBox(height: 10),
                                if (hasItemDetails)
                                  ...items.take(5).map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: _CompactIngredientRow(
                                            name: _itemName(item),
                                            calories: _itemCalories(item),
                                            protein: _itemProtein(item),
                                            carb: _itemCarb(item),
                                            fat: _itemFat(item),
                                            grams: _itemGrams(item),
                                          ),
                                        ),
                                      )
                                else
                                  const _InfoBanner(
                                    text: 'لا توجد تفاصيل مفصلة لهذه الوجبة حاليًا.',
                                    icon: Icons.info_outline_rounded,
                                  ),
                              ],
                            ),
                          ),
                          if (top2.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _SectionTitle('أعلى العناصر في السعرات'),
                                  const SizedBox(height: 10),
                                  ...top2.map(
                                    (it) => Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _itemName(it),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12.8,
                                                color: _wazenText,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _pdfCaloriesColor.withOpacity(.09),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(color: _pdfCaloriesColor.withOpacity(.14)),
                                            ),
                                            child: Text(
                                              '${_fmt0(_itemCalories(it))} kcal',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w900,
                                                color: _pdfCaloriesColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FixedHandle extends StatelessWidget {
  const _FixedHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF111827).withOpacity(.38),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String mealName;
  final double calories;
  final int itemsCount;
  final double totalGrams;

  const _Header({
    required this.mealName,
    required this.calories,
    required this.itemsCount,
    required this.totalGrams,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'إغلاق',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: _wazenText),
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _wazenText,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _HeaderChip(icon: Icons.local_fire_department_rounded, label: '${_fmt0(calories)} kcal'),
                  _HeaderChip(icon: Icons.restaurant_menu_rounded, label: itemsCount > 0 ? '$itemsCount عناصر' : 'وجبة واحدة'),
                  if (totalGrams > 0) _HeaderChip(icon: Icons.scale_rounded, label: '${_fmt0(totalGrams)} غ'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SectionCard({required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: _wazenCardBg,
        border: Border.all(color: _wazenBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
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
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: _pdfCaloriesColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: _wazenText,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _wazenCardBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _wazenBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _pdfCaloriesColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.7,
              fontWeight: FontWeight.w800,
              color: _wazenText,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String emoji;
  final Color color;

  const _MacroMetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.emoji,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.20)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 17, height: 1),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.2,
              fontWeight: FontWeight.w800,
              color: _wazenText,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _wazenText,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: _wazenMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroLegendTile extends StatelessWidget {
  final String label;
  final double percent;
  final double kcal;
  final Color color;

  const _MacroLegendTile({
    required this.label,
    required this.percent,
    required this.kcal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.7,
                fontWeight: FontWeight.w900,
                color: _wazenText,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_fmt0(percent)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                '${_fmt0(kcal)} kcal',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: _wazenMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickInfoBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _QuickInfoBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(.065),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _wazenMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w900,
              color: _wazenText,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.6,
              fontWeight: FontWeight.w700,
              color: _wazenMuted,
            ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: _wazenSheetBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _wazenBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: _wazenText,
                  ),
                ),
              ),
              if (grams > 0)
                Text(
                  '${_fmt0(grams)} غ',
                  style: const TextStyle(
                    fontSize: 11.3,
                    fontWeight: FontWeight.w900,
                    color: _pdfCaloriesColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _TinyPill('🔥', '${_fmt0(calories)} kcal', _pdfCaloriesColor),
              _TinyPill('🥩', '${_fmtSmart(protein)}غ', _pdfProteinColor),
              _TinyPill('🍞', '${_fmtSmart(carb)}غ', _pdfCarbColor),
              _TinyPill('🥑', '${_fmtSmart(fat)}غ', _pdfFatColor),
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
  final Color color;
  const _TinyPill(this.emoji, this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 12.5, height: 1),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10.8,
              fontWeight: FontWeight.w900,
              color: _wazenText,
            ),
          ),
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
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _pdfCaloriesColor.withOpacity(.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pdfCaloriesColor.withOpacity(.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _pdfCaloriesColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
                color: _wazenText,
              ),
            ),
          ),
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
    final hasValues = (proteinKcal + carbKcal + fatKcal) > 0;
    final sections = hasValues
        ? <PieChartSectionData>[
            PieChartSectionData(
              value: proteinKcal <= 0 ? 0.01 : proteinKcal,
              color: _pdfProteinColor,
              title: '',
              radius: 36,
            ),
            PieChartSectionData(
              value: carbKcal <= 0 ? 0.01 : carbKcal,
              color: _pdfCarbColor,
              title: '',
              radius: 36,
            ),
            PieChartSectionData(
              value: fatKcal <= 0 ? 0.01 : fatKcal,
              color: _pdfFatColor,
              title: '',
              radius: 36,
            ),
          ]
        : <PieChartSectionData>[
            PieChartSectionData(
              value: 1,
              color: _pdfEmptyColor,
              title: '',
              radius: 36,
            ),
          ];

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sections: sections,
            sectionsSpace: hasValues ? 3 : 0,
            centerSpaceRadius: 28,
            startDegreeOffset: -90,
          ),
        ),
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: _wazenCardBg,
            shape: BoxShape.circle,
            border: Border.all(color: _wazenBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _fmt0(totalKcal),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _wazenText,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'kcal',
                style: TextStyle(
                  fontSize: 9.5,
                  color: _wazenMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

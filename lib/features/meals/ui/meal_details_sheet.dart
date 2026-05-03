// lib/features/meals/ui/meal_details_sheet.dart
// Bottom sheet: pie chart for macro distribution + burn estimate + extra insights.

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

/// Show meal details in a modern bottom sheet.
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return _MealDetailsSheetBody(
        mealName: mealName,
        calories: calories,
        protein: protein,
        carb: carb,
        fat: fat,
        items: items,
        userWeightKg: userWeightKg,
      );
    },
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
    final cs = Theme.of(context).colorScheme;    // Macro calories (kcal): P=4, C=4, F=9 — keep numbers consistent everywhere
    final pKcalRaw = math.max(0.0, protein * 4.0);
    final cKcalRaw = math.max(0.0, carb * 4.0);
    final fKcalRaw = math.max(0.0, fat * 9.0);
    final macroKcalRaw = pKcalRaw + cKcalRaw + fKcalRaw;

    // Canonical total kcal for the meal (this is the number shown everywhere)
    final mealKcal = (calories > 0 ? calories : macroKcalRaw);
    final mealKcalRounded = math.max(0, mealKcal.round());

    // For display (chart/legend/chips), adjust macro-kcal so their sum == mealKcalRounded
    int pKcalDisp = math.max(0, pKcalRaw.round());
    int cKcalDisp = math.max(0, cKcalRaw.round());
    int fKcalDisp = math.max(0, fKcalRaw.round());

    final macroSumRounded = pKcalDisp + cKcalDisp + fKcalDisp;
    int adjust = mealKcalRounded - macroSumRounded;

    if (macroSumRounded > 0 && adjust != 0) {
      // Apply the diff to the largest macro first (keeps values stable).
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

    // Burn estimate (steps)
    // Average ~0.04 kcal/step for 70kg. Scale roughly with weight (bounded).
    final wRatio = (userWeightKg / 70.0).clamp(0.6, 1.6);
    final kcalPerStep = 0.04 * wRatio;
    final estSteps = _clampInt((safeTotal / kcalPerStep).ceil(), 0, 200000);

    // Extra: distance and time (rough)
    final distanceKm = (estSteps * 0.75) / 1000.0; // 0.75m average step
    final minutesWalk = estSteps / 100.0; // ~100 steps/min moderate

    // Top items by calories (if available)
    final top = List<Map<String, dynamic>>.from(items);
    top.sort((a, b) => _toD(b['cal']).compareTo(_toD(a['cal'])));
    final top3 = top.take(3).toList();

    // Tips heuristics
    final pPct = macroKcal <= 0 ? 0.0 : (pKcal / macroKcal) * 100.0;
    final cPct = macroKcal <= 0 ? 0.0 : (cKcal / macroKcal) * 100.0;
    final fPct = macroKcal <= 0 ? 0.0 : (fKcal / macroKcal) * 100.0;

    final tips = <String>[];
    if (protein <= 10 && safeTotal >= 300) {
      tips.add('البروتين منخفض مقارنة بالسعرات؛ جرّب إضافة مصدر بروتين (دجاج/تونة/زبادي يوناني).');
    }
    if (fPct >= 45) {
      tips.add('الدهون مرتفعة؛ انتبه للزيوت/الصوص/المقليات—تقليلها يخفّض السعرات بسرعة.');
    }
    if (cPct >= 55) {
      tips.add('الكارب مرتفع؛ لو هدفك تنشيف/كيتو راقب الكارب وبدّل جزء منه بخضار/بروتين.');
    }
    if (tips.isEmpty) {
      tips.add('توزيع الماكروز متوازن نسبيًا—استمر 👍');
    }
    final rawDiff = (mealKcal - macroKcalRaw).abs();
    final showDiffNote = macroKcalRaw > 0 && rawDiff >= 35;

    return SafeArea(
      top: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mealName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: cs.onSurface.withOpacity(.8)),
                  ),
                ],
              ),

              // Summary (same emoji style as Home)
              Card(
                elevation: 0,
                color: cs.surfaceVariant.withOpacity(.22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    children: [
                      _MacroEmojiLine(
                        label: 'السعرات',
                        emoji: '🔥',
                        value: _fmt0(safeTotal),
                        unit: 'kcal',
                      ),
                      Divider(height: 10, color: cs.outlineVariant.withOpacity(0.35)),
                      _MacroEmojiLine(
                        label: 'البروتين',
                        emoji: '🥩',
                        value: _fmtSmart(protein, decimals: 1),
                        unit: 'غ',
                      ),
                      Divider(height: 10, color: cs.outlineVariant.withOpacity(0.35)),
                      _MacroEmojiLine(
                        label: 'الكارب',
                        emoji: '🍞',
                        value: _fmtSmart(carb, decimals: 1),
                        unit: 'غ',
                      ),
                      Divider(height: 10, color: cs.outlineVariant.withOpacity(0.35)),
                      _MacroEmojiLine(
                        label: 'الدهون',
                        emoji: '🥑',
                        value: _fmtSmart(fat, decimals: 1),
                        unit: 'غ',
                      ),
                      if (showDiffNote) ...[
                        const SizedBox(height: 8),
                        Text(
                          'ملاحظة: قد يختلف مجموع سعرات الماكروز (4/4/9) ≈ ${_fmt0(macroKcalRaw)} عن السعرات الكلية (${_fmt0(safeTotal)}) حسب المصدر/التحليل.',
                          style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.7)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text('توزيع الماكروز (بالسعرات)', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withOpacity(.85))),
              const SizedBox(height: 8),

              // Pie + legend
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: cs.surfaceVariant.withOpacity(.18),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 340;

                      final chart = SizedBox(
                        width: 96,
                        height: 96,
                        child: _MacroPie(
                          proteinKcal: pKcal,
                          carbKcal: cKcal,
                          fatKcal: fKcal,
                          totalKcal: safeTotal,
                        ),
                      );

                      final legend = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendRow(
                            emoji: '🥩',
                            label: 'بروتين',
                            kcal: pKcal,
                            pct: pPct,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 6),
                          _LegendRow(
                            emoji: '🍞',
                            label: 'كارب',
                            kcal: cKcal,
                            pct: cPct,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 6),
                          _LegendRow(
                            emoji: '🥑',
                            label: 'دهون',
                            kcal: fKcal,
                            pct: fPct,
                            color: Colors.blue,
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          children: [
                            Center(child: chart),
                            const SizedBox(height: 10),
                            legend,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          chart,
                          const SizedBox(width: 12),
                          Expanded(child: legend),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 14),
              Text('كم تحتاج تمشي لحرق هذه الوجبة؟', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withOpacity(.85))),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: cs.surfaceVariant.withOpacity(.18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.directions_walk_rounded, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${estSteps.toString()} خطوة تقريبًا',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '≈ ${_fmt1(distanceKm)} كم • ≈ ${_fmt0(minutesWalk)} دقيقة مشي (تقديري)',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.75)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'الحساب تقديري (يعتمد على وزنك وسرعة المشي).',
                        style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.65)),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              Text('معلومات مفيدة', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withOpacity(.85))),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: cs.surfaceVariant.withOpacity(.18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MiniStatChip(emoji: '🔥', title: 'سعرات الوجبة', value: '${_fmt0(safeTotal)} kcal'),
                          _MiniStatChip(emoji: '🥩', title: 'سعرات البروتين', value: '${_fmt0(pKcal)} kcal'),
                          _MiniStatChip(emoji: '🍞', title: 'سعرات الكارب', value: '${_fmt0(cKcal)} kcal'),
                          _MiniStatChip(emoji: '🥑', title: 'سعرات الدهون', value: '${_fmt0(fKcal)} kcal'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...tips.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded, size: 18, color: cs.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (top3.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('أكثر عناصر رفعت السعرات', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withOpacity(.85))),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: cs.surfaceVariant.withOpacity(.18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Column(
                      children: top3.map((it) {
                        final name = (it['name'] ?? 'عنصر').toString();
                        final cal = _toD(it['cal']);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 10),
                              Text('${_fmt0(cal)} kcal', style: TextStyle(color: cs.onSurface.withOpacity(.75))),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String title;
  final String value;
  final String suffix;
  final IconData icon;

  const _Kpi({
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.75), fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 1.5),
              child: Text(suffix, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.65))),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact macro line that matches the emoji style used in the Home page.
class _MacroEmojiLine extends StatelessWidget {
  final String label;
  final String emoji;
  final String value;
  final String unit;

  const _MacroEmojiLine({
    required this.label,
    required this.emoji,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
}

class _MiniStatChip extends StatelessWidget {
  final String emoji;
  final String title;
  final String value;

  const _MiniStatChip({
    required this.emoji,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.7), fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String emoji;
  final String label;
  final double kcal;
  final double pct;
  final Color color;

  const _LegendRow({
    required this.emoji,
    required this.label,
    required this.kcal,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withOpacity(.85)),
          ),
        ),
        Text('${_fmt0(kcal)} kcal', style: TextStyle(color: cs.onSurface.withOpacity(.75), fontSize: 12.5)),
        const SizedBox(width: 8),
        Text('${_fmt0(pct)}%', style: TextStyle(color: cs.onSurface.withOpacity(.65), fontSize: 12)),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String left;
  final String right;
  const _InfoLine(this.left, this.right);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(left, style: TextStyle(color: cs.onSurface.withOpacity(.75), fontSize: 12.5))),
          Text(right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
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
    final total = proteinKcal + carbKcal + fatKcal;
    final safeTotal = total <= 0 ? 1.0 : total;

    final sections = <PieChartSectionData>[];

    // Use theme-friendly colors.
    final pColor = cs.primary;
    final cColor = Colors.orange;
    final fColor = Colors.blue;

    // Smaller donut for tighter layouts.
    sections.add(
      PieChartSectionData(
        value: proteinKcal <= 0 ? 0.01 : proteinKcal,
        color: pColor,
        title: '',
        radius: 28,
      ),
    );
    sections.add(
      PieChartSectionData(
        value: carbKcal <= 0 ? 0.01 : carbKcal,
        color: cColor,
        title: '',
        radius: 28,
      ),
    );
    sections.add(
      PieChartSectionData(
        value: fatKcal <= 0 ? 0.01 : fatKcal,
        color: fColor,
        title: '',
        radius: 28,
      ),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sections: sections,
            sectionsSpace: 2,
            centerSpaceRadius: 18,
            startDegreeOffset: -90,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fmt0(totalKcal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            Text('kcal', style: TextStyle(fontSize: 9.5, color: cs.onSurface.withOpacity(.65))),
          ],
        ),
      ],
    );
  }
}

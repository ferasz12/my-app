// lib/screens/food_ai_screen.dart

// NOTE: هذه الصفحة تستقبل الآن الصورة من food_camera_screen عبر الـ constructor
//       (XFile imageFile) وتبدأ التحليل مباشرة في initState بدون فتح الكاميرا هنا.

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/openai_food_service.dart';
import '../shared/friendly_errors.dart';

// اسم الوجبة بالعربية (إن توفر) أو تحويل أسماء شائعة
String _displayNameArabic(Map<String, dynamic>? f) {
  if (f == null) return '';
  final Object? ar =
      f['name_ar'] ?? f['ar_name'] ?? f['arabic_name'] ?? f['display_ar'];
  if (ar is String && ar.trim().isNotEmpty) return ar.trim();
  final String name =
      (f['name'] ?? f['label'] ?? f['title'] ?? '').toString().trim();
  if (name.isEmpty) return '';
  // إذا الاسم عربي أصلاً
  final arabic = RegExp(r'[\u0600-\u06FF]');
  if (arabic.hasMatch(name)) return name;
  final l = name.toLowerCase();
  if (l.contains('masoub') || l.contains('maasoub') || l.contains('masoob'))
    return 'معصوب';
  if (l == 'tea') return 'شاي';
  if (l == 'coffee') return 'قهوة';
  if (l.contains('tea') && l.contains('coffee')) return 'شاي أو قهوة';
  if (l.contains('chicken') && l.contains('rice')) return 'رز مع دجاج';
  if (l.contains('chicken')) return 'دجاج';
  if (l.contains('rice')) return 'رز';
  if (l.contains('toast') || l.contains('bread')) return 'خبز/توست';
  if (l.contains('egg')) return 'بيض';
  return name;
}

double _numFromAny(dynamic v) =>
    (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

Map<String, dynamic> _itemNutritionCompat(Map<String, dynamic> item) {
  final Map<String, dynamic> est = (item['est'] is Map)
      ? Map<String, dynamic>.from(item['est'] as Map)
      : const {};
  final Map<String, dynamic> macros = (item['macros'] is Map)
      ? Map<String, dynamic>.from(item['macros'] as Map)
      : const {};

  double kcal = _numFromAny(
    item['calories_kcal'] ??
        item['kcal'] ??
        item['calories'] ??
        est['kcal'] ??
        macros['energy_kcal'] ??
        macros['calories'],
  );

  double p = _numFromAny(
    item['protein_g'] ??
        item['protein'] ??
        est['protein_g'] ??
        macros['protein_g'],
  );
  double c = _numFromAny(
    item['carbs_g'] ??
        item['carbs'] ??
        item['carb'] ??
        est['carbs_g'] ??
        macros['carbs_g'],
  );
  double f = _numFromAny(
    item['fat_g'] ?? item['fat'] ?? est['fat_g'] ?? macros['fat_g'],
  );

  if (kcal <= 0 && (p > 0 || c > 0 || f > 0)) {
    kcal = (p * 4.0) + (c * 4.0) + (f * 9.0);
  }

  return <String, dynamic>{
    'kcal': kcal,
    'protein_g': p,
    'carbs_g': c,
    'fat_g': f,
  };
}


String _latinDigits(String input) {
  return input
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9')
      .replaceAll('٫', '.')
      .replaceAll(',', '.')
      .replaceAll('،', '.');
}

String _photoItemName(Map<String, dynamic> item) {
  return (item['name_ar'] ??
          item['nameAr'] ??
          item['name'] ??
          item['label'] ??
          item['name_en'] ??
          item['food_name'] ??
          '')
      .toString()
      .trim();
}

double _photoItemGrams(Map<String, dynamic> item) {
  final direct = _numFromAny(item['grams'] ??
      item['estimated_weight_g'] ??
      item['quantity_g'] ??
      item['portion_grams'] ??
      item['serving_size_g'] ??
      item['weight_g'] ??
      item['weight']);
  if (direct > 0) return direct;

  final text = [
    _photoItemName(item),
    item['quantity_label'],
    item['portion_desc_ar'],
    item['serving'],
    item['desc'],
  ].where((e) => e != null).join(' ');
  final m = RegExp(
    r'([0-9٠-٩]+(?:[\.,٫][0-9٠-٩]+)?)\s*(?:g|جم|غ|جرام|غرام)',
    caseSensitive: false,
  ).firstMatch(text);
  if (m != null) {
    return double.tryParse(_latinDigits(m.group(1) ?? '')) ?? 0;
  }
  return 0;
}

int _photoTextCount(String text) {
  final t = text.toLowerCase();
  if (RegExp(r'\b2\b|٢|اثنين|إثنين|حبتين|بيضتين|شريحتين|قطعتين')
      .hasMatch(t)) {
    return 2;
  }
  if (RegExp(r'\b3\b|٣|ثلاث|ثلاثة|ثلاث حبات|ثلاث شرائح').hasMatch(t)) {
    return 3;
  }
  if (RegExp(r'\b4\b|٤|اربع|أربع').hasMatch(t)) return 4;
  return 1;
}

double _estimatePhotoItemGrams(Map<String, dynamic> item) {
  final known = _photoItemGrams(item);
  if (known > 0) return known;

  final name = _photoItemName(item).toLowerCase();
  final all = '$name ${item['quantity_label'] ?? ''} ${item['serving'] ?? ''}';
  final count = _photoTextCount(all);

  if (name.contains('بيض')) return 50.0 * count;
  if (name.contains('تونة') || name.contains('تونه') || name.contains('tuna')) {
    return 95.0;
  }
  if (name.contains('جبن') || name.contains('cheese') || name.contains('فيلاد') || name.contains('فلاف')) {
    return 30.0 * count;
  }
  if (name.contains('توست')) return 28.0 * count;
  if (name.contains('خبز') || name.contains('bread') || name.contains('صامولي')) {
    return 60.0 * count;
  }
  if (name.contains('رز') || name.contains('rice')) return 150.0;
  if (name.contains('دجاج') || name.contains('chicken')) return 120.0;
  if (name.contains('لحم') || name.contains('beef') || name.contains('meat')) return 100.0;
  if (name.contains('بطاط') || name.contains('fries') || name.contains('potato')) {
    return 90.0;
  }
  if (name.contains('خيار') || name.contains('cucumber')) return 30.0;
  if (name.contains('طماطم') || name.contains('tomato')) return 40.0;
  if (name.contains('فلفل')) return 20.0;
  if (name.contains('صلصة') || name.contains('مايونيز') || name.contains('زبد') || name.contains('sauce')) {
    return 15.0;
  }
  if (name.contains('ساندويتش') || name.contains('sandwich')) return 180.0;
  return 35.0;
}

Map<String, dynamic> _normalizePhotoItemForUi(Map<String, dynamic> item) {
  final out = Map<String, dynamic>.from(item);
  final name = _photoItemName(out);
  if (name.isNotEmpty) {
    out['name_ar'] = name;
    out['name'] = name;
  }

  final grams = _estimatePhotoItemGrams(out);
  if (grams > 0) {
    final rounded = double.parse(grams.toStringAsFixed(0));
    out['grams'] = rounded;
    out['estimated_weight_g'] = rounded;
    out['portion_grams'] = rounded;
  }

  final nutr = _itemNutritionCompat(out);
  final kcal = _numFromAny(nutr['kcal']);
  final p = _numFromAny(nutr['protein_g']);
  final c = _numFromAny(nutr['carbs_g']);
  final f = _numFromAny(nutr['fat_g']);
  out['calories_kcal'] = double.parse(kcal.toStringAsFixed(0));
  out['protein_g'] = double.parse(p.toStringAsFixed(1));
  out['carbs_g'] = double.parse(c.toStringAsFixed(1));
  out['fat_g'] = double.parse(f.toStringAsFixed(1));
  out['calories'] = out['calories_kcal'];
  out['protein'] = out['protein_g'];
  out['carbs'] = out['carbs_g'];
  out['fat'] = out['fat_g'];

  final conf = _numFromAny(out['ingredient_confidence'] ?? out['confidence']);
  if (conf <= 0 || (conf - 0.72).abs() < 0.001 || (conf - 72).abs() < 0.01) {
    out['confidence'] = _smartPhotoItemConfidence(out);
  }
  return out;
}

double _smartPhotoItemConfidence(Map<String, dynamic> item) {
  final grams = _photoItemGrams(item);
  final nutr = _itemNutritionCompat(item);
  final hasName = _photoItemName(item).isNotEmpty;
  final hasMacros = _numFromAny(nutr['kcal']) > 0 ||
      _numFromAny(nutr['protein_g']) > 0 ||
      _numFromAny(nutr['carbs_g']) > 0 ||
      _numFromAny(nutr['fat_g']) > 0;
  var score = 0.54;
  if (hasName) score += 0.10;
  if (grams > 0) score += 0.12;
  if (hasMacros) score += 0.10;
  final src = (item['source'] ?? '').toString().toLowerCase();
  if (src.contains('visual') || src.contains('gemini')) score += 0.04;
  return score.clamp(0.55, 0.91).toDouble();
}

int _smartPhotoConfidencePct(Map<String, dynamic> food) {
  final raw = _numFromAny(food['confidence'] ?? food['conf']);
  final rawPct = raw > 1 ? raw : raw * 100.0;
  final isFixedFallback = (rawPct - 72.0).abs() < 0.6;
  if (rawPct > 0 && !isFixedFallback) return rawPct.clamp(1, 99).round();

  final rawItems = food['items'];
  final items = rawItems is List
      ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  final kcal = _numFromAny(food['calories'] ?? food['kcal']);
  final grams = _numFromAny(food['portion_grams']);
  final hasName = _displayNameArabic(food).trim().isNotEmpty ||
      (food['label'] ?? '').toString().trim().isNotEmpty;

  var score = 58.0;
  if (hasName) score += 6;
  if (kcal > 0) score += 8;
  if (grams > 0) score += 8;
  if (items.isNotEmpty) score += 5;
  if (items.any((e) => _photoItemGrams(e) > 0)) score += 5;
  if (items.length >= 2) score += 3;
  return score.clamp(60, 91).round();
}

enum _ErrorKind {
  none,
  noInternet,
  notRecognized,
  service,
  busy,
  dailyLimit,
  authRequired,
  appCheck,
  unknown
}

class FoodAiScreen extends StatefulWidget {
  final XFile imageFile;
  final String? mealNote;

  const FoodAiScreen({
    super.key,
    required this.imageFile,
    this.mealNote,
  });

  @override
  State<FoodAiScreen> createState() => _FoodAiScreenState();
}

class _FoodAiScreenState extends State<FoodAiScreen> {
  bool _loading = true;
  bool _awaitingClarifier = true;
  String? _error;
  _ErrorKind _errorKind = _ErrorKind.none;

  String? _warning;

  Map<String, dynamic>? _food;

  // نسخة الأساس (قبل تعديل وزن الحصّة) — نستخدمها للـ scaling بدون أخطاء تراكمية
  Map<String, dynamic>? _foodBase;

  // تعديل وزن الحصّة (Scaling)
  double _basePortionG = 0;
  double _baseKcal = 0, _baseP = 0, _baseC = 0, _baseF = 0;
  double _portionG = 0;
  bool _portionBaseAssumed = false;

  // الصورة الحالية (قادمة من food_camera_screen أو من المعرض)
  late XFile _currentImage;

  // الأهداف
  double _tK = 0, _tP = 0, _tC = 0, _tF = 0;
  // مجاميع اليوم
  double _sK = 0, _sP = 0, _sC = 0, _sF = 0;
  // نوع الهدف
  String _goalType = 'maintain';
  // الملاحظة
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageFile;
    _noteCtrl.text = (widget.mealNote ?? '').trim();

    // ✅ خطوة واحدة إضافية فقط: توضيح اختياري قبل التحليل لرفع الدقة
    _loading = false;
    _awaitingClarifier = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openInitialClarifierSheet();
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  // إضافة الوجبة: نرجع الخريطة للشاشة السابقة

  // فتح ورقة سفلية لإضافة توضيح (لا نغيّر المنطق؛ مجرد واجهة)
  void _openClarifierSheet() {
    final controller = _noteCtrl;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: _NoteEditor(
              controller: controller,
              onReanalyze: () {
                Navigator.pop(ctx);
                _reanalyzeWithNote();
              }),
        );
      },
    );
  }

  void _handleAddMeal() {
    if (_food == null) return;
    Navigator.of(context).pop(_food);
  }

  double _toD(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  // ✅ ورقة سفلية تُفتح مباشرة بعد التقاط الصورة (خطوة واحدة إضافية فقط)
  Future<void> _openInitialClarifierSheet() async {
    final controller = _noteCtrl;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.tips_and_updates, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'توضيح اختياري لرفع دقة التحليل',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.file(
                    File(_currentImage.path),
                    fit: BoxFit.cover,
                    cacheWidth: 900,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  hintText:
                      'مثال: ساندويتش تونة على بر توست، مايونيز خفيف، كولا دايت 330مل',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 10),
              Text(
                'إذا كان في تفاصيل مهمة (بدون سكر/دايت، مشوي، كمية تقريبية...) اكتبها هنا.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _startAnalysis();
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text(
                  'تحليل',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: const Text('لاحقًا'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startAnalysis() {
    if (!mounted) return;
    setState(() {
      _awaitingClarifier = false;
      _loading = true;
      _error = null;
      _errorKind = _ErrorKind.none;
      _warning = null;
      _food = null;
      _foodBase = null;
      _basePortionG = 0;
      _portionG = 0;
      _portionBaseAssumed = false;
      _baseKcal = 0;
      _baseP = 0;
      _baseC = 0;
      _baseF = 0;
    });

    // نعطي Flutter فرصة يرسم شاشة المسح أولًا، بعدها نبدأ قراءة/ضغط الصورة والشبكة.
    // هذا يمنع إحساس التعليق مباشرة بعد الضغط على زر تحليل.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      unawaited(_run());
    });
  }

  void _startAnalysisFromClarifier() => _startAnalysis();

  // ====== Portion scaling (تعديل وزن الحصّة بدون إعادة استدعاء الذكاء الاصطناعي) ======
  static const double _minPortionG = 20;
  static const double _maxPortionG = 600;
  static const double _portionStepG = 5;

  double _snapPortion(double g) => (g / _portionStepG).round() * _portionStepG;

  double _sumKnownItemsWeightG(Map<String, dynamic> food) {
    final rawItems = food['items'] ??
        food['ingredients_breakdown'] ??
        food['components'] ??
        food['detected_items'];
    if (rawItems is! List) return 0.0;

    double total = 0.0;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      double g = _toD(
        item['grams'] ??
            item['estimated_weight_g'] ??
            item['quantity_g'] ??
            item['portion_grams'] ??
            item['serving_size_g'] ??
            item['weight_g'] ??
            item['weight'],
      );
      if (g <= 0) {
        final q = (item['quantity_label'] ?? item['portion_desc_ar'] ?? item['serving'] ?? '').toString();
        final m = RegExp(r'([0-9٠-٩]+(?:[\.,٫][0-9٠-٩]+)?)\s*(?:g|جم|غ|جرام|غرام)', caseSensitive: false).firstMatch(q);
        if (m != null) {
          final txt = (m.group(1) ?? '')
              .replaceAll('٠', '0')
              .replaceAll('١', '1')
              .replaceAll('٢', '2')
              .replaceAll('٣', '3')
              .replaceAll('٤', '4')
              .replaceAll('٥', '5')
              .replaceAll('٦', '6')
              .replaceAll('٧', '7')
              .replaceAll('٨', '8')
              .replaceAll('٩', '9')
              .replaceAll('،', '.')
              .replaceAll('٫', '.')
              .replaceAll(',', '.');
          g = double.tryParse(txt) ?? 0.0;
        }
      }
      if (g > 0 && g <= 1200) total += g;
    }

    return total > 0 ? total.clamp(_minPortionG, _maxPortionG).toDouble() : 0.0;
  }

  ({double grams, bool assumed}) _deriveBasePortion(Map<String, dynamic> food) {
    double g = _toD(
      food['portion_grams'] ??
          food['serving_size_g'] ??
          food['serving_g'] ??
          food['portion_g'] ??
          food['servingWeight'] ??
          food['weight'],
    );

    // ✅ مهم: لا نفترض وزن افتراضي إذا لم يرسل الـ AI وزن واضح
    // نعرض الوزن فقط إذا كان موجود من الخدمة أو من توضيح المستخدم.
    String _latinizeDigits(String input) {
      return input
          .replaceAll('٠', '0')
          .replaceAll('١', '1')
          .replaceAll('٢', '2')
          .replaceAll('٣', '3')
          .replaceAll('٤', '4')
          .replaceAll('٥', '5')
          .replaceAll('٦', '6')
          .replaceAll('٧', '7')
          .replaceAll('٨', '8')
          .replaceAll('٩', '9');
    }

    // من نص الحصّة (إن وجد)
    if (g <= 0) {
      final s = (food['portion_desc_ar'] ??
              food['serving'] ??
              food['serving_text'] ??
              '')
          .toString();
      final ms = RegExp(r'([0-9٠-٩]+(?:\.[0-9٠-٩]+)?)\s*(?:g|جم|غ)\b',
              caseSensitive: false)
          .firstMatch(s);
      if (ms != null)
        g = double.tryParse(_latinizeDigits(ms.group(1) ?? '')) ?? 0;
    }

    // من الملاحظة (إن كتب المستخدم كمية)
    if (g <= 0) {
      final note =
          (_noteCtrl.text.isNotEmpty ? _noteCtrl.text : (food['note'] ?? ''))
              .toString();
      final mn = RegExp(r'([0-9٠-٩]+(?:\.[0-9٠-٩]+)?)\s*(?:g|جم|غ)\b',
              caseSensitive: false)
          .firstMatch(note);
      if (mn != null)
        g = double.tryParse(_latinizeDigits(mn.group(1) ?? '')) ?? 0;
    }

    // إذا لم يرسل الـ AI وزنًا عامًا، اجمع أوزان المكونات المتوفرة.
    if (g <= 0) {
      g = _sumKnownItemsWeightG(food);
    }

    // لا يوجد وزن واضح حتى بعد جمع العناصر → نخليه غير محدد (0).
    if (g <= 0) {
      return (grams: 0, assumed: false);
    }

    g = g.clamp(_minPortionG, _maxPortionG).toDouble();
    g = _snapPortion(g);
    return (grams: g, assumed: false);
  }

  Map<String, dynamic> _scaleFoodMapFromBase(
    Map<String, dynamic> baseFood, {
    required double grams,
    required double baseGrams,
    required double baseKcal,
    required double baseProtein,
    required double baseCarbs,
    required double baseFat,
  }) {
    final out = Map<String, dynamic>.from(baseFood);

    final double g =
        _snapPortion(grams.clamp(_minPortionG, _maxPortionG).toDouble());
    final double bg = baseGrams > 0 ? baseGrams : g;
    final double factor = bg > 0 ? (g / bg) : 1.0;

    // قيم مقربة وجاهزة للعرض والتخزين
    out['calories'] = double.parse((baseKcal * factor).toStringAsFixed(0));
    out['protein'] = double.parse((baseProtein * factor).toStringAsFixed(1));
    out['carbs'] = double.parse((baseCarbs * factor).toStringAsFixed(1));
    out['fat'] = double.parse((baseFat * factor).toStringAsFixed(1));

    out['portion_grams'] = g;
    final bool unknown = (baseGrams <= 0) || (grams <= 0);
    out['serving'] = unknown ? '—' : '${g.toStringAsFixed(0)} جم';
    out['portion_desc_ar'] = out['serving'];
    out['_portion_scaled'] = true;
    out['_portion_base_g'] = bg;

    if (baseFood['items'] is List) {
      final rawItems = (baseFood['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      out['items'] = rawItems.map((item) {
        final scaledItem = Map<String, dynamic>.from(item);
        final itemGrams = _toD(
          scaledItem['estimated_weight_g'] ??
              scaledItem['grams'] ??
              scaledItem['quantity_g'] ??
              scaledItem['portion_grams'] ??
              scaledItem['weight_g'] ??
              scaledItem['weight'],
        );
        if (itemGrams > 0) {
          final nextG = double.parse((itemGrams * factor).toStringAsFixed(0));
          scaledItem['grams'] = nextG;
          scaledItem['estimated_weight_g'] = nextG;
          scaledItem['portion_grams'] = nextG;
        }

        final est = (scaledItem['est'] is Map)
            ? Map<String, dynamic>.from(scaledItem['est'] as Map)
            : <String, dynamic>{};
        final nutr = _itemNutritionCompat(scaledItem);
        final nextK =
            double.parse((_toD(nutr['kcal']) * factor).toStringAsFixed(0));
        final nextP =
            double.parse((_toD(nutr['protein_g']) * factor).toStringAsFixed(1));
        final nextC =
            double.parse((_toD(nutr['carbs_g']) * factor).toStringAsFixed(1));
        final nextF =
            double.parse((_toD(nutr['fat_g']) * factor).toStringAsFixed(1));

        scaledItem['calories_kcal'] = nextK;
        scaledItem['protein_g'] = nextP;
        scaledItem['carbs_g'] = nextC;
        scaledItem['fat_g'] = nextF;
        scaledItem['protein'] = nextP;
        scaledItem['carbs'] = nextC;
        scaledItem['fat'] = nextF;
        if (est.isNotEmpty) {
          est['kcal'] = nextK;
          est['protein_g'] = nextP;
          est['carbs_g'] = nextC;
          est['fat_g'] = nextF;
          scaledItem['est'] = est;
        }
        return scaledItem;
      }).toList();
    }

    // حدّث الملاءمة حسب السعرات الجديدة
    _ensureSuitabilityFields(out, force: true);

    return out;
  }


  List<Map<String, dynamic>> _extractEditablePhotoItems(
      Map<String, dynamic> food) {
    final raw = food['items'] ??
        food['ingredients_breakdown'] ??
        food['components'] ??
        food['detected_items'];
    final List<Map<String, dynamic>> items = [];

    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final normalized = _normalizePhotoItemForUi(Map<String, dynamic>.from(e));
          if (_photoItemName(normalized).isNotEmpty ||
              _photoItemGrams(normalized) > 0) {
            items.add(normalized);
          }
        } else {
          final name = e.toString().trim();
          if (name.isNotEmpty) {
            items.add(_normalizePhotoItemForUi(<String, dynamic>{'name_ar': name}));
          }
        }
      }
    }

    if (items.isEmpty) {
      final ing = food['ingredients'] ?? food['ingredients_ar'] ?? food['contents'];
      if (ing is List) {
        for (final e in ing) {
          final name = e.toString().trim();
          if (name.isNotEmpty) {
            items.add(_normalizePhotoItemForUi(<String, dynamic>{'name_ar': name}));
          }
        }
      }
    }
    return items;
  }

  Map<String, dynamic> _recalculatePhotoTotals(
    Map<String, dynamic> food,
    List<Map<String, dynamic>> items,
  ) {
    final out = Map<String, dynamic>.from(food);
    final normalized = items
        .map((e) => _normalizePhotoItemForUi(Map<String, dynamic>.from(e)))
        .toList();

    double grams = 0, kcal = 0, p = 0, c = 0, f = 0;
    for (final item in normalized) {
      grams += _photoItemGrams(item);
      final nutr = _itemNutritionCompat(item);
      kcal += _toD(nutr['kcal']);
      p += _toD(nutr['protein_g']);
      c += _toD(nutr['carbs_g']);
      f += _toD(nutr['fat_g']);
    }

    if (normalized.isNotEmpty) {
      out['items'] = normalized;
      out['ingredients'] = normalized
          .map((e) => _photoItemName(e))
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    if (grams > 0) {
      final g = double.parse(grams.toStringAsFixed(0));
      out['portion_grams'] = g;
      out['serving'] = '${g.toStringAsFixed(0)} جم إجمالي الوجبة';
      out['portion_desc_ar'] = out['serving'];
    }
    if (kcal > 0 || p > 0 || c > 0 || f > 0) {
      out['calories'] = double.parse(kcal.toStringAsFixed(0));
      out['protein'] = double.parse(p.toStringAsFixed(1));
      out['carbs'] = double.parse(c.toStringAsFixed(1));
      out['fat'] = double.parse(f.toStringAsFixed(1));
      out['total_macros'] = <String, dynamic>{
        'calories_kcal': out['calories'],
        'protein_g': out['protein'],
        'carbs_g': out['carbs'],
        'fat_g': out['fat'],
      };
    }
    out['confidence'] = _smartPhotoConfidencePct(out) / 100.0;
    return out;
  }

  Map<String, dynamic> _preparePhotoResultForUi(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    final items = _extractEditablePhotoItems(out);
    final prepared = _recalculatePhotoTotals(out, items);
    _ensureSuitabilityFields(prepared, force: true);
    return prepared;
  }

  void _replaceFoodAfterItemEdit(List<Map<String, dynamic>> items) {
    if (_food == null) return;
    final updated = _recalculatePhotoTotals(
      Map<String, dynamic>.from(_food!),
      items,
    );
    _ensureSuitabilityFields(updated, force: true);

    final baseKcal = _toD(updated['calories'] ?? updated['kcal']);
    final baseP = _toD(updated['protein'] ?? updated['p']);
    final baseC = _toD(updated['carbs'] ?? updated['c']);
    final baseF = _toD(updated['fat'] ?? updated['f']);
    final portionInfo = _deriveBasePortion(updated);

    setState(() {
      _food = updated;
      _foodBase = Map<String, dynamic>.from(updated);
      _basePortionG = portionInfo.grams;
      _portionG = portionInfo.grams;
      _portionBaseAssumed = portionInfo.assumed;
      _baseKcal = baseKcal;
      _baseP = baseP;
      _baseC = baseC;
      _baseF = baseF;
    });
  }

  void _setPortionGrams(double grams) {
    if (_foodBase == null) return;

    // نلتزم بالـ step/clamp
    final double g =
        _snapPortion(grams.clamp(_minPortionG, _maxPortionG).toDouble());

    // ✅ إذا لم يكن لدينا أساس وزن واضح من AI/الملاحظة، لا نغيّر الماكروز
    // فقط نخزّن وزن الحصة للعرض والحفظ.
    if (_basePortionG <= 0) {
      if (!mounted) return;
      setState(() {
        _portionG = g;
        final m = Map<String, dynamic>.from(_food ?? _foodBase!);
        m['portion_grams'] = g;
        _food = m;
      });
      return;
    }

    final scaled = _scaleFoodMapFromBase(
      _foodBase!,
      grams: g,
      baseGrams: _basePortionG,
      baseKcal: _baseKcal,
      baseProtein: _baseP,
      baseCarbs: _baseC,
      baseFat: _baseF,
    );

    if (!mounted) return;
    setState(() {
      _portionG = _toD(scaled['portion_grams']);
      _food = scaled;
    });
  }

  Future<void> _editPortionGrams() async {
    // اجبار النوع على double لتفادي ترويج (int) إلى num داخل العامل الثلاثي
    final double current =
        _portionG > 0 ? _portionG : (_basePortionG > 0 ? _basePortionG : 0.0);
    final asked = await _askPortionGrams(defaultValue: current);
    if (asked == null) return;
    _setPortionGrams(asked);
  }

  Future<double?> _askPortionGrams({double defaultValue = 150}) async {
    final ctrl = TextEditingController(
        text: (defaultValue > 0) ? defaultValue.toStringAsFixed(0) : '');
    double? result;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('كم وزن الحصّة تقريبًا؟'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'مثال: 150',
            suffixText: 'جم',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim()) ?? 0;
              result = (v > 0) ? v : null;
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
    return result;
  }

  Future<void> _saveAsReadyFood() async {
    if (_food == null) return;

    final food = _food!;
    final name = (food['name_ar'] ?? food['label'] ?? food['name'] ?? 'طعام')
        .toString()
        .trim();
    if (name.isEmpty) return;

    double grams = _toD(food['portion_grams']);
    if (grams <= 0) {
      // محاولة من serving
      final serving =
          (food['portion_desc_ar'] ?? food['serving'] ?? '').toString();
      final m = RegExp(r'(\d+(?:\.\d+)?)\s*(?:g|جم|غ)').firstMatch(serving);
      if (m != null) grams = double.tryParse(m.group(1) ?? '') ?? 0;
    }
    if (grams <= 0) {
      final asked = await _askPortionGrams(defaultValue: 150);
      if (asked == null) return;
      grams = asked;
    }

    final kcal = _toD(food['calories']);
    final p = _toD(food['protein']);
    final c = _toD(food['carbs']);
    final f = _toD(food['fat']);

    if (kcal <= 0 && p <= 0 && c <= 0 && f <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حفظ طعام بدون قيم غذائية.')),
      );
      return;
    }

    final kcal100 = kcal * 100.0 / grams;
    final p100 = p * 100.0 / grams;
    final c100 = c * 100.0 / grams;
    final f100 = f * 100.0 / grams;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ready_foods_items');
    final List<dynamic> list =
        raw != null ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];

    // إزالة تكرار نفس الاسم
    list.removeWhere(
        (e) => e is Map && (e['name'] ?? '').toString().trim() == name);

    final dynamic ingRaw = food['ingredients'] ??
        food['ingredients_ar'] ??
        food['contents'] ??
        food['components'] ??
        food['ingredients_en'];
    final List<String> ingredients = <String>[];
    if (ingRaw is List) {
      for (final e in ingRaw) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) ingredients.add(s);
      }
    } else if (ingRaw is String) {
      ingredients.addAll(ingRaw
          .split(RegExp(r'[,،;؛\n\-\u2013\u2014\|]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty));
    }

    final item = <String, dynamic>{
      'id': 'ai_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'kcal100': double.parse(kcal100.toStringAsFixed(2)),
      'p100': double.parse(p100.toStringAsFixed(2)),
      'c100': double.parse(c100.toStringAsFixed(2)),
      'f100': double.parse(f100.toStringAsFixed(2)),
      'source': (food['source'] ?? 'ai').toString(),
      if (ingredients.isNotEmpty) 'ingredients': ingredients,
    };

    list.insert(0, item);
    await prefs.setString('ready_foods_items', jsonEncode(list));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الطعام ضمن "القائمة الجاهزة" ✅')),
    );
  }

  Future<Map<String, dynamic>> _pickFdcSuggestionIfNeeded(
      Map<String, dynamic> map) async {
    // مسار تحليل الصورة أصبح Gemini-only، لذلك نتجاهل أي اقتراحات قديمة مرتبطة بـ USDA.
    return map;
  }

  Future<void> _run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final email =
          prefs.getString('currentEmail') ?? user?.email ?? 'unknown_user';
      // 1) الأهداف
      final tgtK = prefs.getDouble('caloriesNeeded_$email');
      final tgtP = prefs.getDouble('protein_$email');
      final tgtC = prefs.getDouble('carbs_$email');
      final tgtF = prefs.getDouble('fat_$email');
      if (tgtK != null && tgtP != null && tgtC != null && tgtF != null) {
        _tK = tgtK;
        _tP = tgtP;
        _tC = tgtC;
        _tF = tgtF;
      } else {
        await _tryFetchTargetsFromFirestore();
      }

      // 2) نوع الهدف
      _goalType = prefs.getString('goalType_$email') ??
          (await _tryFetchGoalTypeFromFirestore()) ??
          'maintain';

      // 3) مجاميع اليوم
      final ymd = DateTime.now().toIso8601String().split('T').first;
      final totalsKey = 'kcal_daytotals_${email}_$ymd';
      final rawTotals = prefs.getString(totalsKey);
      if (rawTotals != null && rawTotals.trim().isNotEmpty) {
        try {
          final Map<String, dynamic> m = jsonDecode(rawTotals);
          _sK = _toD(m['k']);
          _sP = _toD(m['p']);
          _sC = _toD(m['c']);
          _sF = _toD(m['f']);
        } catch (_) {}
      }

      // 4) التحليل
      final profile = DietProfile(
        dailyCalories: _tK.round(),
        proteinTarget: _tP.round(),
        carbsTarget: _tC.round(),
        fatTarget: _tF.round(),
        goal: _goalType,
        dietType: 'متوازن',
      );

      final today = TodayTotals(
        consumedKcal: _sK,
        consumedProtein: _sP,
        consumedCarbs: _sC,
        consumedFat: _sF,
      );

      // ⚠️ لا نرسل null أبدًا — سلسلة فاضية بدلًا عنه
      final String clarifier = _noteCtrl.text.trim().isNotEmpty
          ? _noteCtrl.text.trim()
          : (widget.mealNote ?? '').trim();

      var map = await OpenAIFoodService.analyzeFromXFile(
        _currentImage,
        profile: profile,
        today: today,
        detail: VisionDetail.low,
        maxImageEdge: 1024,
        clarifier: clarifier, // دائمًا String
      );

      if (map == null) {
        throw Exception(
            'تعذر الوصول إلى خدمة تحليل الصور. تأكد من الشبكة وأن Cloud Function analyzeFood منشورة وتعمل.');
      }

      // جهّز نتيجة الصورة للواجهة: أوزان المكونات، وزن الوجبة، ثقة غير ثابتة، وتعديل العناصر.
      map = _preparePhotoResultForUi(Map<String, dynamic>.from(map));

      // ✅ مهم: قد يرجّع السيرفر اقتراحات USDA بدون أرقام نهائية (calories=0)
      // لذلك نعرض اختيار الاقتراح أولاً *قبل* التحقق من السعرات.
      _ensureSuitabilityFields(map);
      map = await _pickFdcSuggestionIfNeeded(map);
      _ensureSuitabilityFields(map);

      final kcal = _toD(map['calories']);
      final mp = _toD(map['protein'] ?? map['p']);
      final mc = _toD(map['carbs'] ?? map['c']);
      final mf = _toD(map['fat'] ?? map['f']);
      final name = _extractMealName(Map<String, dynamic>.from(map));
      final ingredients = _extractIngredients(Map<String, dynamic>.from(map));

      // إذا كانت النتيجة عامة جدًا (وجبة/0) اعتبرها عدم تعرّف
      if ((name.trim().isEmpty || name.trim() == 'وجبة') &&
          kcal <= 0 &&
          mp <= 0 &&
          mc <= 0 &&
          mf <= 0 &&
          ingredients.isEmpty) {
        if (!mounted) return;
        setState(() {
          _errorKind = _ErrorKind.notRecognized;
          _error = _friendlyErrorMessage('', _ErrorKind.notRecognized);
          _food = null;
          _foodBase = null;
          _basePortionG = 0;
          _portionG = 0;
          _portionBaseAssumed = false;
          _baseKcal = 0;
          _baseP = 0;
          _baseC = 0;
          _baseF = 0;
          _warning = null;
          _loading = false;
        });
        return;
      }

      String? warning;
      if (kcal <= 0 && !_isAllowedZeroCase(map)) {
        warning =
            'تم التعرف على الوجبة لكن تعذّر تقدير السعرات/الماكروز تلقائيًا. جرّب صورة أوضح أو أضف توضيح ثم أعد التحليل.';
      }

// نثبت وجود note كسلسلة
      final currentNote = clarifier;
      if (currentNote.isNotEmpty) {
        map['note'] = currentNote;
      }

      // ⚠️ map من analyzeFromXFile نوعه nullable في الدارت.
      // حتى بعد التحقق من null، الترويج (promotion) لا يستمر داخل Closure مثل setState.
      // لذلك نثبت نسخة غير قابلة للـ null هنا ونستخدمها داخل setState.
      final Map<String, dynamic> mapFinal = Map<String, dynamic>.from(map);

      if (!mounted) return;
      setState(() {
        // ثبت نسخة الأساس ثم طبّق وزن الحصّة (افتراضيًا نفس وزن الحصّة الأساسي)
        final baseMap = Map<String, dynamic>.from(mapFinal);

        final baseKcal = _toD(baseMap['calories'] ?? baseMap['kcal']);
        final baseP = _toD(baseMap['protein'] ?? baseMap['p']);
        final baseC = _toD(baseMap['carbs'] ?? baseMap['c']);
        final baseF = _toD(baseMap['fat'] ?? baseMap['f']);

        final portionInfo = _deriveBasePortion(baseMap);
        final baseG = portionInfo.grams;
        final assumed = portionInfo.assumed;

        _foodBase = baseMap;
        _basePortionG = baseG;
        _portionG = baseG;
        _portionBaseAssumed = assumed;

        _baseKcal = baseKcal;
        _baseP = baseP;
        _baseC = baseC;
        _baseF = baseF;

        if (baseG > 0) {
          _food = _scaleFoodMapFromBase(
            baseMap,
            grams: baseG,
            baseGrams: baseG,
            baseKcal: baseKcal,
            baseProtein: baseP,
            baseCarbs: baseC,
            baseFat: baseF,
          );
        } else {
          // لا يوجد تقدير وزن واضح من AI/الملاحظة → لا نعرض وزن افتراضي

          final tmp = Map<String, dynamic>.from(baseMap);

          tmp.remove('portion_grams');

          tmp.remove('portion_g');

          tmp.remove('serving_g');

          tmp.remove('serving_size_g');

          _food = tmp;
        }
        _warning = warning;
        _error = null;
        _errorKind = _ErrorKind.none;
        _loading = false;
      });
    } catch (e) {
      // ✅ إذا تجاوز المستخدم الحد اليومي للتصوير، نعرض رسالة ونرجع للخلف
      if (e is DailyLimitExceeded) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FriendlyErrors.message(e))),
          );
          Navigator.of(context).maybePop();
        }
        return;
      }
      _setError(e);
    }
  }

  // إعادة التحليل بدون زيادة العدّاد
  Future<void> _reanalyzeWithNote() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _errorKind = _ErrorKind.none;
      _warning = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    try {
      final profile = DietProfile(
        dailyCalories: _tK.round(),
        proteinTarget: _tP.round(),
        carbsTarget: _tC.round(),
        fatTarget: _tF.round(),
        goal: _goalType,
        dietType: 'متوازن',
      );
      final today = TodayTotals(
        consumedKcal: _sK,
        consumedProtein: _sP,
        consumedCarbs: _sC,
        consumedFat: _sF,
      );

      final String clarifier = _noteCtrl.text.trim(); // دائمًا String

      var map = await OpenAIFoodService.analyzeFromXFile(
        _currentImage,
        profile: profile,
        today: today,
        detail: VisionDetail.low,
        maxImageEdge: 1024,
        countUsage: false, // إعادة التحليل لنفس الصورة بدون زيادة عدّاد اليوم
        clarifier: clarifier,
      );
      if (map == null)
        throw Exception(
            'تعذر الوصول إلى خدمة تحليل الصور. تأكد من الشبكة وأن Cloud Function analyzeFood منشورة وتعمل.');
      String? warning;
      if (_toD(map['calories']) <= 0) {
        warning =
            'تم التعرف على الوجبة لكن تعذّر تقدير السعرات/الماكروز تلقائيًا. جرّب صورة أوضح أو اكتب كمية تقريبية في الملاحظة ثم أعد التحليل.';
      }

      if (clarifier.isNotEmpty) map['note'] = clarifier;

      map = _preparePhotoResultForUi(Map<String, dynamic>.from(map));

      _ensureSuitabilityFields(map);

      // تثبيت نسخة غير nullable لاستخدامها داخل setState
      final Map<String, dynamic> mapFinal = Map<String, dynamic>.from(map);

      if (!mounted) return;
      setState(() {
        final baseMap = Map<String, dynamic>.from(mapFinal);

        final baseKcal = _toD(baseMap['calories'] ?? baseMap['kcal']);
        final baseP = _toD(baseMap['protein'] ?? baseMap['p']);
        final baseC = _toD(baseMap['carbs'] ?? baseMap['c']);
        final baseF = _toD(baseMap['fat'] ?? baseMap['f']);

        final portionInfo = _deriveBasePortion(baseMap);
        final baseG = portionInfo.grams;
        final assumed = portionInfo.assumed;

        _foodBase = baseMap;
        _basePortionG = baseG;
        _portionG = baseG;
        _portionBaseAssumed = assumed;

        _baseKcal = baseKcal;
        _baseP = baseP;
        _baseC = baseC;
        _baseF = baseF;

        if (baseG > 0) {
          _food = _scaleFoodMapFromBase(
            baseMap,
            grams: baseG,
            baseGrams: baseG,
            baseKcal: baseKcal,
            baseProtein: baseP,
            baseCarbs: baseC,
            baseFat: baseF,
          );
        } else {
          // لا يوجد تقدير وزن واضح من AI/الملاحظة → لا نعرض وزن افتراضي

          final tmp = Map<String, dynamic>.from(baseMap);

          tmp.remove('portion_grams');

          tmp.remove('portion_g');

          tmp.remove('serving_g');

          tmp.remove('serving_size_g');

          _food = tmp;
        }
        _warning = warning;
        _error = null;
        _errorKind = _ErrorKind.none;
        _loading = false;
      });
    } catch (e) {
      // إذا كان لدينا نتيجة سابقة، لا نعرض شاشة خطأ كاملة — نعرض تنبيه أعلى الصفحة
      if (_food != null) {
        final raw = e.toString();
        final kind = _inferErrorKind(raw);
        if (!mounted) return;
        setState(() {
          _errorKind = _ErrorKind.none;
          _error = null;
          _warning = _friendlyErrorMessage(raw, kind);
          _loading = false;
        });
      } else {
        _setError(e);
      }
    }
  }

  // اختيار صورة جديدة من المعرض وإعادة التحليل
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _currentImage = picked;
      _loading = false;
      _awaitingClarifier = true;
      _error = null;
      _errorKind = _ErrorKind.none;
      _food = null;
      _foodBase = null;
      _basePortionG = 0;
      _portionG = 0;
      _portionBaseAssumed = false;
      _baseKcal = 0;
      _baseP = 0;
      _baseC = 0;
      _baseF = 0;
      _warning = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openInitialClarifierSheet();
    });
  }

  // حساب suitability/reason (نحدّثها أيضًا عند تعديل وزن الحصّة)
  void _ensureSuitabilityFields(Map<String, dynamic> map,
      {bool force = false}) {
    // إذا لم تكن أهداف المستخدم محمّلة/معروفة، لا نُصدر حكم (حتى لا تظهر "غير مناسب").
    if (_tK <= 0 || _goalType.trim().isEmpty) return;

    var verdict = '${map['suitability'] ?? ''}'.toString().trim();
    var reason = '${map['reason'] ?? ''}'.toString().trim();

    // إذا كانت موجودة ولا نريد إعادة الحساب
    if (!force && verdict.isNotEmpty && reason.isNotEmpty) return;

    final addK = _toD(map['calories']);
    final afterK = _sK + addK;

    if (_goalType.toLowerCase().contains('loss') ||
        _goalType.contains('خفض') ||
        _goalType.contains('تنحيف')) {
      if (afterK <= _tK) {
        verdict = 'good';
        reason = 'الوجبة ضمن هدف السعرات لخفض الوزن.';
      } else if (afterK <= _tK * 1.10) {
        verdict = 'ok';
        reason = 'تجاوز طفيف عن الهدف اليومي لخفض الوزن.';
      } else {
        verdict = 'bad';
        reason = 'تتجاوز هدف السعرات لخفض الوزن بشكل واضح.';
      }
    } else if (_goalType.toLowerCase().contains('gain') ||
        _goalType.contains('زيادة') ||
        _goalType.contains('عضل') ||
        _goalType.contains('bulk')) {
      if (afterK >= _tK * 0.90) {
        verdict = 'good';
        reason = 'يدعم هدف زيادة الوزن/العضل.';
      } else if (afterK >= _tK * 0.75) {
        verdict = 'ok';
        reason = 'قد تكون السعرات أقل من المطلوب قليلاً.';
      } else {
        verdict = 'bad';
        reason = 'السعرات أقل بكثير من هدف الزيادة.';
      }
    } else {
      final diff = (afterK - _tK).abs();
      if (diff <= _tK * 0.10) {
        verdict = 'good';
        reason = 'قريب جداً من هدف الثبات اليومي.';
      } else if (diff <= _tK * 0.15) {
        verdict = 'ok';
        reason = 'ابتعاد بسيط عن هدف الثبات.';
      } else {
        verdict = 'bad';
        reason = 'بعيد عن هدف الثبات اليومي.';
      }
    }

    map['suitability'] = verdict;
    map['reason'] = reason;
  }

  Future<void> _tryFetchTargetsFromFirestore() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      if (data == null) return;
      final metrics = data['metrics'];
      if (metrics is Map) {
        final k = metrics['caloriesNeeded'] ?? metrics['kcal'];
        final p = metrics['protein'];
        final c = metrics['carbs'];
        final f = metrics['fat'];
        if (k is num && p is num && c is num && f is num) {
          _tK = k.toDouble();
          _tP = p.toDouble();
          _tC = c.toDouble();
          _tF = f.toDouble();
        }
      }
    } catch (_) {}
  }

  Future<String?> _tryFetchGoalTypeFromFirestore() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      if (data == null) return null;

      for (final key in [
        'goalType',
        'goal',
        'dietGoal',
        'planGoal',
        'regimen',
        'plan'
      ]) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v;
        if (v is Map && v['type'] is String) return v['type'] as String;
      }
      if (data['metrics'] is Map && data['metrics']['goalType'] is String) {
        return data['metrics']['goalType'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _goalArabic(String g) {
    final s = g.toLowerCase();
    if (s.contains('loss') ||
        s.contains('خفض') ||
        s.contains('تنحيف') ||
        s.contains('نقص')) return 'خسارة وزن';
    if (s.contains('gain') ||
        s.contains('زيادة') ||
        s.contains('عضل') ||
        s.contains('bulk')) return 'زيادة وزن/عضل';
    return 'ثبات الوزن';
  }

  String _fmt(dynamic v) => (v is num)
      ? v.toStringAsFixed(0)
      : (double.tryParse('$v')?.toStringAsFixed(0) ?? '0');

  _ErrorKind _inferErrorKind(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('no route to host') ||
        s.contains('connection timed out') ||
        s.contains('timed out') ||
        s.contains('connection refused') ||
        s.contains('not connected') ||
        s.contains('errno')) {
      return _ErrorKind.noInternet;
    }

    if (s.contains('quota_exceeded') ||
        s.contains('تم تجاوز الحد اليومي') ||
        s.contains('daily limit') ||
        s.contains('dailylimitexceeded')) {
      return _ErrorKind.dailyLimit;
    }

    if (s.contains('service_busy') ||
        s.contains('resource exhausted') ||
        s.contains('too many requests') ||
        s.contains('gemini api 429') ||
        s.contains('retry-after') ||
        s.contains('retryafter') ||
        s.contains('unavailable') ||
        s.contains('503') ||
        s.contains('تحت ضغط')) {
      return _ErrorKind.busy;
    }
    if (s.contains('unauthorized') ||
        s.contains('401') ||
        s.contains('يلزم تسجيل الدخول') ||
        s.contains('تسجيل الدخول')) {
      return _ErrorKind.authRequired;
    }
    if (s.contains('app check') ||
        s.contains('appcheck') ||
        s.contains('تعذّر التحقق من أمان التطبيق') ||
        s.contains('أمان التطبيق') ||
        s.contains('403')) {
      return _ErrorKind.appCheck;
    }

    if (s.contains('food_proxy_url') ||
        s.contains('proxy') ||
        s.contains('api key') ||
        s.contains('apikey')) {
      return _ErrorKind.service;
    }
    return _ErrorKind.unknown;
  }

  String _friendlyErrorMessage(String raw, _ErrorKind kind) {
    switch (kind) {
      case _ErrorKind.noInternet:
        return 'لا يوجد اتصال بالإنترنت. تأكد من الشبكة ثم حاول مرة أخرى.';
      case _ErrorKind.service:
        return 'تعذّر الوصول لخدمة التحليل. تأكد من اتصالك ومن إعدادات السيرفر ثم أعد المحاولة.';
      case _ErrorKind.busy:
        return 'خدمة تحليل الطعام تحت ضغط حالياً. انتظر قليلًا ثم أعد المحاولة.';
      case _ErrorKind.dailyLimit:
        return 'تم تجاوز الحد اليومي لميزة تصوير الطعام. جرّب بكرة.';
      case _ErrorKind.authRequired:
        return 'يلزم تسجيل الدخول لاستخدام ميزة تحليل الطعام. سجّل دخولك ثم حاول مرة أخرى.';
      case _ErrorKind.appCheck:
        return 'تعذّر التحقق من أمان التطبيق (App Check). حدّث التطبيق أو أعد تشغيله ثم حاول مرة أخرى.';
      case _ErrorKind.notRecognized:
        return 'لم يتم التعرف على الوجبة. جرّب صورة أوضح أو أضف توضيح (مثال: 200 جم دجاج مع نصف كوب رز) ثم أعد التحليل.';
      default:
        return 'حدث خطأ أثناء التحليل. حاول مرة أخرى.';
    }
  }

  void _setError(Object e, {_ErrorKind? forceKind}) {
    final raw = e.toString();
    final kind = forceKind ?? _inferErrorKind(raw);
    if (!mounted) return;
    setState(() {
      _errorKind = kind;
      _error = _friendlyErrorMessage(raw, kind);
      _loading = false;
    });
  }

  String _extractMealName(Map<String, dynamic> food) {
    final String nameAr =
        (food['name_ar'] ?? food['ar_name'] ?? '').toString().trim();
    if (nameAr.isNotEmpty) return nameAr;
    final alt = _displayNameArabic(food).trim();
    if (alt.isNotEmpty) return alt;
    final String name = (food['name'] ?? food['label'] ?? food['title'] ?? '')
        .toString()
        .trim();
    return name.isNotEmpty ? name : 'وجبة';
  }

  String _extractDescription(Map<String, dynamic> food) {
    final candidates = [
      'wazin_analysis',
      'description_ar',
      'description',
      'desc_ar',
      'desc',
      'details_ar',
      'details',
      'about_ar',
      'about',
      'summary_ar',
      'summary',
    ];
    for (final k in candidates) {
      final v = food[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final note = (food['note'] ?? '').toString().trim();
    if (note.isNotEmpty) return note;
    return '';
  }

  String _extractServing(Map<String, dynamic> food) {
    String serving = (food['portion_desc_ar'] ??
            food['serving'] ??
            food['serving_text'] ??
            '')
        .toString()
        .trim();
    if (serving.isEmpty) {
      final pg = _toD(food['portion_grams']);
      if (pg > 0) serving = '${pg.toStringAsFixed(0)} جم';
    }
    if (serving.isEmpty) {
      final sw = _toD(food['servingWeight']);
      final w = _toD(food['weight']);
      final grams = sw > 0 ? sw : (w > 0 ? w : 0);
      if (grams > 0) serving = '${grams.toStringAsFixed(0)} جم';
    }
    if (serving.isEmpty || serving == '—') {
      final totalItemsG = _sumKnownItemsWeightG(food);
      if (totalItemsG > 0) serving = '${totalItemsG.toStringAsFixed(0)} جم إجمالي الوجبة';
    }
    return serving;
  }

  List<String> _extractIngredients(Map<String, dynamic> food) {
    final dynamic ingRaw = food['ingredients'] ??
        food['ingredients_ar'] ??
        food['contents'] ??
        food['components'] ??
        food['ingredients_en'];
    final List<String> ingredients = <String>[];
    if (ingRaw is List) {
      for (final e in ingRaw) {
        if (e is Map) {
          final s = (e['name'] ?? e['name_ar'] ?? e['ingredient_name'] ?? '')
              .toString()
              .trim();
          if (s.isNotEmpty) ingredients.add(s);
        } else {
          final s = (e ?? '').toString().trim();
          if (s.isNotEmpty) ingredients.add(s);
        }
      }
    } else if (ingRaw is String) {
      final parts = ingRaw
          .split(RegExp(r'[,،;؛\n\-\u2013\u2014\|]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      ingredients.addAll(parts);
    }
    return ingredients;
  }

  void _openImagePreview() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: _FoodImageWithBox(
              filePath: _currentImage.path,
              bbox: null,
              height: 420,
            ),
          ),
        );
      },
    );
  }

  bool _isAllowedZeroCase(Map<String, dynamic> food) {
    final String name =
        ('${food['name_ar'] ?? food['name'] ?? food['label'] ?? ''}')
            .toString()
            .toLowerCase();
    final String note = ('${food['note'] ?? ''}').toString().toLowerCase();
    final String all = '$name $note';

    final bool dietSignal = all.contains('دايت') ||
        all.contains('diet') ||
        all.contains('زيرو') ||
        all.contains('zero') ||
        all.contains('sugar free') ||
        all.contains('sugar-free') ||
        all.contains('بدون سكر');
    final bool sodaSignal = all.contains('كولا') ||
        all.contains('cola') ||
        all.contains('coke') ||
        all.contains('بيبسي') ||
        all.contains('pepsi') ||
        all.contains('صودا') ||
        all.contains('soda');
    final bool isDietSoda = dietSignal && sodaSignal;

    final bool isTeaOrCoffee = all.contains('شاي') ||
        all.contains('tea') ||
        all.contains('قهوة') ||
        all.contains('coffee') ||
        all.contains('espresso') ||
        all.contains('americano');
    final bool noSugar = all.contains('بدون سكر') ||
        all.contains('no sugar') ||
        all.contains('unsweetened') ||
        all.contains('sugar free') ||
        all.contains('sugar-free');

    return isDietSoda || (isTeaOrCoffee && noSugar);
  }

  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget content;
    if (_loading) {
      content = _AnalyzingView(imagePath: _currentImage.path);
    } else if (_awaitingClarifier) {
      content = _AwaitingClarifierView(
        imagePath: _currentImage.path,
        onAddNote: _openInitialClarifierSheet,
        onAnalyze: _startAnalysisFromClarifier,
        onClose: () => Navigator.pop(context),
      );
    } else if (_error != null) {
      final String title = _errorKind == _ErrorKind.noInternet
          ? 'لا يوجد اتصال بالإنترنت'
          : (_errorKind == _ErrorKind.service
              ? 'خدمة التحليل غير متاحة'
              : 'حدثت مشكلة');
      content = _ErrorView(
        kind: _errorKind,
        title: title,
        message: _error!,
        onRetry: _run,
        onPickImage: _pickFromGallery,
        onClarify: _openClarifierSheet,
        onReanalyze: _reanalyzeWithNote,
        onClose: () => Navigator.pop(context),
      );
    } else if (_food == null) {
      content = _ErrorView(
        kind: _ErrorKind.notRecognized,
        title: 'لم يتم التعرف على الوجبة',
        message: _friendlyErrorMessage('', _ErrorKind.notRecognized),
        onPickImage: _pickFromGallery,
        onClarify: _openClarifierSheet,
        onReanalyze: _reanalyzeWithNote,
        onClose: () => Navigator.pop(context),
      );
    } else {
      final food = Map<String, dynamic>.from(_food!);

      final String name = _extractMealName(food);
      final String desc = _extractDescription(food);
      final bool hasWazinAnalysis =
          (food['wazin_analysis'] ?? '').toString().trim().isNotEmpty;
      final String serving = _extractServing(food);
      final List<String> ingredients = _extractIngredients(food);
      food['ingredients'] = ingredients;

      final double kcal = _toD(food['calories'] ?? food['kcal']);
      final double p = _toD(food['protein'] ?? food['p']);
      final double c = _toD(food['carbs'] ?? food['c']);
      final double f = _toD(food['fat'] ?? food['f']);

      final int confPct = _smartPhotoConfidencePct(food);

      final bool needClarification = (food['need_clarification'] == true) ||
          (food['needClarification'] == true);
      final List<String> clarificationQuestions =
          (food['clarification_questions'] is List)
              ? List<String>.from((food['clarification_questions'] as List)
                  .map((e) => e.toString()))
              : ((food['questions'] is List)
                  ? List<String>.from(
                      (food['questions'] as List).map((e) => e.toString()))
                  : const <String>[]);

      final bool macrosMissing = (kcal <= 0 && p <= 0 && c <= 0 && f <= 0) &&
          !needClarification &&
          !_isAllowedZeroCase(food);

      content = Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _MealHeaderCard(
              name: name,
              imagePath: _currentImage.path,
              confidencePct: confPct,
              servingText: serving,
              onTapImage: _openImagePreview,
            ),
            if (needClarification) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'نحتاج توضيح',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'الصورة أو الكمية غير واضحة كفاية. جاوب باختصار في خانة التوضيح (اختياري) ثم أعد التحليل.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.4),
                    ),
                    if (clarificationQuestions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...clarificationQuestions.map((q) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(
                                    child: Text(q,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium)),
                              ],
                            ),
                          )),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openClarifierSheet,
                            icon: const Icon(Icons.edit_note),
                            label: const Text('أضف توضيح'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _reanalyzeWithNote,
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('إعادة التحليل'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_warning != null) ...[
              const SizedBox(height: 12),
              _WarningBanner(message: _warning!),
            ],
            const SizedBox(height: 12),
            _SectionCard(
              title: 'الماكروز',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!needClarification) ...[
                    _MacroGrid(
                      kcal: kcal,
                      protein: p,
                      carbs: c,
                      fat: f,
                    ),
                    if (!macrosMissing && _foodBase != null) ...[
                      const SizedBox(height: 12),
                      _PortionAdjuster(
                        grams: (_portionG > 0
                            ? _portionG
                            : _toD(food['portion_grams'])),
                        onChanged: _setPortionGrams,
                        onEdit: _editPortionGrams,
                        assumedBase: _portionBaseAssumed,
                      ),
                    ],
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'ما راح نعرض الماكروز الآن لأن الوجبة تحتاج توضيح. أضف اسم الطلب/الحجم/الكمية ثم أعد التحليل.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                      ),
                    ),
                  ],
                  if (macrosMissing && !needClarification) ...[
                    const SizedBox(height: 10),
                    Text(
                      'ما قدرنا نحسب الماكروز بدقة من الصورة الحالية. جرّب إضافة توضيح (مثال: 200 جم) ثم أعد التحليل.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openClarifierSheet,
                            icon: const Icon(Icons.edit_note),
                            label: const Text('أضف توضيح'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _reanalyzeWithNote,
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('إعادة التحليل'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'المكونات',
              child: _MealBreakdown(
                food: food,
                cs: cs,
                onItemsChanged: _replaceFoodAfterItemEdit,
              ),
            ),
            if (desc.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: hasWazinAnalysis ? 'تحليل وازن' : 'وصف الوجبة',
                child: hasWazinAnalysis
                    ? _WazenInsightCard(text: desc.trim(), cs: cs)
                    : Text(
                        desc.trim(),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.45),
                      ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: needClarification ? null : _handleAddMeal,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('إضافة الوجبة'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bool canSave = !_loading &&
        _error == null &&
        _food != null &&
        !((_food?['need_clarification'] == true) ||
            (_food?['needClarification'] == true));

    return PremiumGate(
      feature: PremiumFeature.aiPhoto,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          centerTitle: true,
          title: const Text('نتيجة تحليل الوجبة'),
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'أضف توضيح',
              icon: const Icon(Icons.edit_note),
              onPressed: _openClarifierSheet,
            ),
            IconButton(
              tooltip: 'إعادة التحليل',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reanalyzeWithNote,
            ),
            IconButton(
              tooltip: 'اختيار صورة من المعرض',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _pickFromGallery,
            ),
            if (canSave)
              IconButton(
                tooltip: 'حفظ كطعام جاهز',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: _saveAsReadyFood,
              ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(.12),
                cs.surface,
              ],
            ),
          ),
          child: SafeArea(child: content),
        ),
      ),
    );
  }
}

// ====== Widgets ======

// ====== New Wazen-style widgets for result layout ======

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? footer;

  const _SectionCard({
    required this.title,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _HeaderInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeaderInfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MealHeaderCard extends StatelessWidget {
  final String name;
  final String imagePath;
  final int confidencePct;
  final String servingText;
  final VoidCallback? onTapImage;

  const _MealHeaderCard({
    required this.name,
    required this.imagePath,
    required this.confidencePct,
    required this.servingText,
    this.onTapImage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final conf = (confidencePct.clamp(0, 100)).toDouble() / 100.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.primary.withOpacity(.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTapImage,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 92,
                height: 92,
                color: cs.surfaceContainerHighest.withOpacity(.35),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isEmpty ? 'وجبة' : name.trim(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderInfoChip(
                      icon: Icons.verified_outlined,
                      text: 'الثقة: ${confidencePct.clamp(0, 100)}%',
                    ),
                    _HeaderInfoChip(
                      icon: Icons.restaurant_outlined,
                      text: servingText.trim().isNotEmpty
                          ? 'الحصّة: ${servingText.trim()}'
                          : 'الحصّة: لم يتم تقدير وزن الحصّة',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: conf.clamp(0.0, 1.0),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withOpacity(.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.tertiary.withOpacity(.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.tertiary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroGrid extends StatelessWidget {
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  const _MacroGrid({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final tileW = (w - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: tileW,
              child: _MacroTile(
                emoji: '🔥',
                label: 'السعرات',
                value: kcal > 0 ? '${kcal.toStringAsFixed(0)}' : '--',
                unit: 'kcal',
              ),
            ),
            SizedBox(
              width: tileW,
              child: _MacroTile(
                emoji: '🥩',
                label: 'البروتين',
                value: protein > 0 ? protein.toStringAsFixed(1) : '--',
                unit: 'جم',
              ),
            ),
            SizedBox(
              width: tileW,
              child: _MacroTile(
                emoji: '🍞',
                label: 'الكارب',
                value: carbs > 0 ? carbs.toStringAsFixed(1) : '--',
                unit: 'جم',
              ),
            ),
            SizedBox(
              width: tileW,
              child: _MacroTile(
                emoji: '🥑',
                label: 'الدهون',
                value: fat > 0 ? fat.toStringAsFixed(1) : '--',
                unit: 'جم',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PortionAdjuster extends StatelessWidget {
  final double grams;
  final ValueChanged<double> onChanged;
  final VoidCallback onEdit;
  final bool assumedBase;

  const _PortionAdjuster({
    required this.grams,
    required this.onChanged,
    required this.onEdit,
    required this.assumedBase,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool unknown = grams <= 0;
    final double g = unknown
        ? _FoodAiScreenState._minPortionG
        : grams
            .clamp(_FoodAiScreenState._minPortionG,
                _FoodAiScreenState._maxPortionG)
            .toDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'وزن الحصّة',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Text(
                unknown ? '—' : '${g.toStringAsFixed(0)} جم',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'إدخال رقم',
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 18),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          if (!unknown)
            Slider(
              value: g,
              min: _FoodAiScreenState._minPortionG,
              max: _FoodAiScreenState._maxPortionG,
              divisions: ((_FoodAiScreenState._maxPortionG -
                          _FoodAiScreenState._minPortionG) /
                      _FoodAiScreenState._portionStepG)
                  .round(),
              onChanged: onChanged,
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'لم يتم تقدير وزن الحصّة. يمكنك إدخال الوزن يدويًا (اختياري).',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String unit;

  const _MacroTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.45)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      unit,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  const _TagChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(.18)),
      ),
      child: Text(
        t,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ======= Result Card (Arabic UI) =======
class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> food;
  final String goalType;
  const _ResultCard({required this.food, required this.goalType});

  double _toD(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  Color _baseColor(String verdict) {
    switch (verdict) {
      case 'good':
        return const Color(0xFF10B981); // teal/green
      case 'bad':
        return const Color(0xFFEF4444); // red
      default:
        return const Color(0xFFF59E0B); // amber
    }
  }

  String _chipText(String verdict) {
    // صياغة ألطف + بدون حكم إذا لم تتوفر أهداف المستخدم
    switch (verdict) {
      case 'good':
        return 'مناسب لهدفك';
      case 'ok':
        return 'قريب من هدفك';
      case 'bad':
        return 'قد يتجاوز هدفك';
      default:
        return 'نتيجة التحليل';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final String verdict = (food['suitability'] ?? '').toString().trim();
    final Color base = verdict.isEmpty ? cs.primary : _baseColor(verdict);

    final double confRaw = _toD(food['confidence'] ?? food['conf'] ?? 0.0);
    final double conf01 = (confRaw > 1.0) ? (confRaw / 100.0) : confRaw;
    final int confPct = (conf01.clamp(0.0, 1.0) * 100).round();

    final String nameAr = (food['name_ar'] ?? '').toString().trim();
    final String name = nameAr.isNotEmpty
        ? nameAr
        : (_displayNameArabic(food).isNotEmpty
            ? _displayNameArabic(food)
            : (food['name'] ?? food['label'] ?? '').toString());

    final double kcal = _toD(food['calories'] ?? food['kcal']);
    final double p = _toD(food['protein'] ?? food['p']);
    final double c = _toD(food['carbs'] ?? food['c']);
    final double f = _toD(food['fat'] ?? food['f']);
    String serving = (food['portion_desc_ar'] ??
            food['serving'] ??
            food['serving_text'] ??
            '')
        .toString()
        .trim();

// دعم صريح لكمية/وصف الحصّة من خدمة التحليل
    if (serving.isEmpty) {
      final pg = _toD(food['portion_grams']);
      if (pg > 0) serving = '${pg.toStringAsFixed(0)} جم';
    }

// Fallback قديم
    if (serving.isEmpty) {
      final sw = _toD(food['servingWeight']);
      final w = _toD(food['weight']);
      final grams = sw > 0 ? sw : (w > 0 ? w : 0);
      if (grams > 0) serving = '${grams.toStringAsFixed(0)} جم';
    }

// ✅ مكوّنات متوقعة (إن توفرت من خدمة التحليل)
    final dynamic ingRaw = food['ingredients'] ??
        food['ingredients_ar'] ??
        food['contents'] ??
        food['components'] ??
        food['ingredients_en'];
    final List<String> ingredients = <String>[];
    if (ingRaw is List) {
      for (final e in ingRaw) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) ingredients.add(s);
      }
    } else if (ingRaw is String) {
      final parts = ingRaw
          .split(RegExp(r'[,،;؛\n\-\u2013\u2014\|]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      ingredients.addAll(parts);
    }

    final String reason = (food['reason'] ?? '').toString().trim();
    final List<String> reasons = reason.isEmpty
        ? const <String>[]
        : reason
            .replaceAll('•', '\n')
            .replaceAll(' - ', '\n')
            .split(RegExp(r'[\n؛]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final List<Map<String, dynamic>> items = (food['items'] is List)
        ? (food['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: base.withOpacity(.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: base.withOpacity(.35)),
                  boxShadow: [
                    BoxShadow(
                        color: base.withOpacity(.08),
                        blurRadius: 2,
                        offset: const Offset(0, 1))
                  ],
                ),
                child: Text(_chipText(verdict),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text('ثقة: $confPct%'),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: conf01.clamp(0.0, 1.0)),
          const SizedBox(height: 16),
          Text('تم التعرف على: $name',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _EmojiRow(
              emoji: '🔥',
              label: 'السعرات',
              value: '${kcal.toStringAsFixed(0)} سعرة'),
          _EmojiRow(
              emoji: '🍗',
              label: 'بروتين',
              value: '${p.toStringAsFixed(1)} جم'),
          _EmojiRow(
              emoji: '🍞', label: 'كارب', value: '${c.toStringAsFixed(1)} جم'),
          _EmojiRow(
              emoji: '🧈', label: 'دهون', value: '${f.toStringAsFixed(1)} جم'),
          if (serving.isNotEmpty)
            _EmojiRow(emoji: '🥄', label: 'الحصّة', value: serving),
          if (ingredients.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('المكوّنات المتوقعة:',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ingredients
                  .take(12)
                  .map((x) => Chip(label: Text(x)))
                  .toList(),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('تفاصيل الطبق:',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            _AiItemsList(items: items),
          ],
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('الأسباب:',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...reasons.map((r) => Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: 6, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(r)),
                    ],
                  ),
                )),
          ]
        ],
      ),
    );
  }
}

class _AiItemsList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _AiItemsList({required this.items});

  double _toD(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _AiItemRow(item: items[i]),
          if (i != items.length - 1) const Divider(height: 16),
        ],
      ],
    );
  }
}

class _AiItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AiItemRow({required this.item});

  double _toD(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final String name = (item['name_ar'] ?? item['name'] ?? item['label'] ?? '')
        .toString()
        .trim();
    final double grams = _toD(
      item['grams'] ??
          item['estimated_weight_g'] ??
          item['quantity_g'] ??
          item['portion_grams'] ??
          item['weight_g'] ??
          item['weight'],
    );
    final nutr = _itemNutritionCompat(item);
    final double kcal = _toD(nutr['kcal']);
    final double p = _toD(nutr['protein_g']);
    final double c = _toD(nutr['carbs_g']);
    final double f = _toD(nutr['fat_g']);

    final double confRaw = _toD(item['confidence']);
    final double conf01 = (confRaw > 1.0) ? (confRaw / 100.0) : confRaw;
    final int confPct = (conf01.clamp(0.0, 1.0) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? 'عنصر' : name,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            if (grams > 0)
              _MiniChip(
                  label: 'الكمية', value: '${grams.toStringAsFixed(0)} جم'),
            if (kcal > 0)
              _MiniChip(
                  label: 'السعرات', value: '${kcal.toStringAsFixed(0)} كال'),
            _MiniChip(label: 'بروتين', value: '${p.toStringAsFixed(1)}g'),
            _MiniChip(label: 'كارب', value: '${c.toStringAsFixed(1)}g'),
            _MiniChip(label: 'دهون', value: '${f.toStringAsFixed(1)}g'),
            _MiniChip(label: 'ثقة', value: '$confPct%'),
          ],
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final String value;
  const _MiniChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child:
          Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _EmojiRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;

  const _EmojiRow(
      {required this.emoji, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodImageWithBox extends StatelessWidget {
  final String filePath;
  final Map<String, dynamic>? bbox; // لم نعد نستخدمها (إبقاء للتوافق)
  final double height;

  const _FoodImageWithBox({
    required this.filePath,
    this.bbox,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(filePath),
                fit: BoxFit.contain,
                cacheWidth: 1200,
                filterQuality: FilterQuality.low,
              ),
              // تظليل لطيف لإحساس "فخم" بدون التأثير على الصورة
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        cs.surface.withOpacity(.35),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _AwaitingClarifierView extends StatelessWidget {
  final String imagePath;
  final VoidCallback onAddNote;
  final VoidCallback onAnalyze;
  final VoidCallback onClose;

  const _AwaitingClarifierView({
    required this.imagePath,
    required this.onAddNote,
    required this.onAnalyze,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(.94),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: cs.primary.withOpacity(.14)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.06),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: _FoodImageWithBox(
                            filePath: imagePath,
                            bbox: null,
                            height: 332,
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.42),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: Colors.white.withOpacity(.14)),
                            ),
                            child: const Text(
                              'جاهز للتحليل',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'قبل التحليل',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'إذا تبغى ترفع دقة التحليل أكثر، أضف ملاحظة قصيرة مثل الكمية أو نوع المكونات. وإذا ما تحتاج، اضغط تحليل مباشرة.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _PrepHintChip(label: 'مثال: 200 جم'),
                        _PrepHintChip(label: 'مثال: بدون سكر'),
                        _PrepHintChip(label: 'مثال: خبز بر'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onAddNote,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              side: BorderSide(
                                  color: cs.primary.withOpacity(.25)),
                            ),
                            child: const Text(
                              'أضف توضيح',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: onAnalyze,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'تحليل',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onClose,
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrepHintChip extends StatelessWidget {
  final String label;
  const _PrepHintChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _UsageBanner extends StatelessWidget {
  final int used;
  final int limit;
  const _UsageBanner({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final left = (limit - used).clamp(0, limit);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.camera_alt, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'المتبقي اليوم: $left / $limit مرات',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


class _AnalyzingView extends StatefulWidget {
  final String imagePath;
  const _AnalyzingView({required this.imagePath});

  @override
  State<_AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<_AnalyzingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<String> _scanSteps = [
    'نراجع الصورة والتفاصيل',
    'نحدد الوجبة والمكونات',
    'نقدّر الكميات والقرامات',
    'نحسب السعرات والماكروز',
    'نجهز النتيجة النهائية',
  ];

  @override
  void initState() {
    super.initState();
    // تشغيل واحد فقط: الخطوات تظهر بالتسلسل مرة واحدة ولا تعيد نفسها.
    // لو التحليل أخذ وقت أطول، تبقى آخر خطوة ظاهرة بدون استهلاك أنيميشن مستمر.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 14500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _activeStep(double progress) {
    final idx = (progress * _scanSteps.length).floor();
    return idx.clamp(0, _scanSteps.length - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(.96),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cs.primary.withOpacity(.16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.07),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 285,
                    width: double.infinity,
                    child: _AnalyzingImageStage(
                      imagePath: widget.imagePath,
                      controller: _controller,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'انتظر شوي عشان نحسب لك الماكروز',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = _controller.value.clamp(0.0, 1.0);
                    final activeIndex = _activeStep(progress);
                    return Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: Text(
                            _scanSteps[activeIndex],
                            key: ValueKey<int>(activeIndex),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.45,
                                  fontWeight: FontWeight.w800,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _AnalyzeMiniStatusCard(
                                title: 'الصورة',
                                subtitle: activeIndex >= 0 ? 'جاري' : 'انتظار',
                                active: activeIndex >= 0,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: _AnalyzeMiniStatusCard(
                                title: 'المكونات',
                                subtitle: activeIndex >= 2 ? 'تم البدء' : 'انتظار',
                                active: activeIndex >= 2,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: _AnalyzeMiniStatusCard(
                                title: 'القرامات',
                                subtitle: activeIndex >= 3 ? 'تقدير' : 'انتظار',
                                active: activeIndex >= 3,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: _AnalyzeMiniStatusCard(
                                title: 'الماكروز',
                                subtitle: activeIndex >= 4 ? 'حساب' : 'انتظار',
                                active: activeIndex >= 4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (0.10 + (progress * 0.88)).clamp(0.0, 0.98),
                            minHeight: 8,
                            backgroundColor: cs.surfaceVariant.withOpacity(.45),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyzingImageStage extends StatelessWidget {
  final String imagePath;
  final Animation<double> controller;

  const _AnalyzingImageStage({
    required this.imagePath,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        // الصورة ثابتة داخل RepaintBoundary حتى لا يعاد رسمها مع كل فريم.
        RepaintBoundary(
          child: Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            cacheWidth: 900,
            errorBuilder: (_, __, ___) => Container(
              color: cs.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(.10),
                Colors.black.withOpacity(.25),
              ],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final progress = controller.value.clamp(0.0, 1.0);
            return _MacroPulseOverlay(progress: progress);
          },
        ),
        Positioned(
          right: 14,
          left: 14,
          bottom: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.42),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(.16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'انتظر شوي عشان نحسب لك الماكروز',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MacroPulseOverlay extends StatelessWidget {
  final double progress;
  const _MacroPulseOverlay({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pulse = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final softScale = 0.92 + (pulse * 0.16);
    final softOpacity = 0.18 + (pulse * 0.24);

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.82,
                colors: [
                  cs.primary.withOpacity(softOpacity),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Transform.scale(
            scale: softScale,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(.34),
                  width: 1.6,
                ),
                color: cs.primary.withOpacity(.12),
              ),
              child: Center(
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(.32),
                    border: Border.all(color: Colors.white.withOpacity(.18)),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyzeMiniStatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;

  const _AnalyzeMiniStatusCard({
    required this.title,
    required this.subtitle,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withOpacity(.10)
            : cs.surfaceVariant.withOpacity(.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? cs.primary.withOpacity(.18)
              : cs.outlineVariant.withOpacity(.18),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: active ? cs.primary : cs.outlineVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.2,
              height: 1.2,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCorner extends StatelessWidget {
  final bool top;
  final bool right;
  const _ScanCorner({required this.top, required this.right});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _ScanCornerPainter(
          top: top,
          right: right,
          color: Theme.of(context).colorScheme.primary.withOpacity(.95),
        ),
      ),
    );
  }
}

class _ScanCornerPainter extends CustomPainter {
  final bool top;
  final bool right;
  final Color color;
  _ScanCornerPainter({required this.top, required this.right, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final x0 = right ? size.width : 0.0;
    final x1 = right ? size.width - 12 : 12.0;
    final y0 = top ? 0.0 : size.height;
    final y1 = top ? 12.0 : size.height - 12;
    path.moveTo(x0, y1);
    path.lineTo(x0, y0);
    path.lineTo(x1, y0);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _ScanCornerPainter oldDelegate) {
    return oldDelegate.top != top ||
        oldDelegate.right != right ||
        oldDelegate.color != color;
  }
}

class _ErrorView extends StatelessWidget {
  final _ErrorKind kind;
  final String title;
  final String message;

  final VoidCallback? onRetry;
  final VoidCallback? onPickImage;
  final VoidCallback? onClarify;
  final VoidCallback? onReanalyze;
  final VoidCallback onClose;

  const _ErrorView({
    required this.kind,
    required this.title,
    required this.message,
    required this.onClose,
    this.onRetry,
    this.onPickImage,
    this.onClarify,
    this.onReanalyze,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    IconData icon;
    Color accent;
    switch (kind) {
      case _ErrorKind.noInternet:
        icon = Icons.wifi_off_rounded;
        accent = cs.tertiary;
        break;
      case _ErrorKind.notRecognized:
        icon = Icons.search_off_rounded;
        accent = cs.primary;
        break;
      case _ErrorKind.service:
        icon = Icons.cloud_off_rounded;
        accent = cs.secondary;
        break;
      default:
        icon = Icons.error_outline;
        accent = cs.error;
    }

    final List<Widget> actions = [];

    if (onRetry != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
      actions.add(const SizedBox(height: 10));
    }

    // حلول شائعة
    if (onPickImage != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('اختيار صورة أخرى'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
      actions.add(const SizedBox(height: 10));
    }

    if (onClarify != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onClarify,
            icon: const Icon(Icons.edit_note),
            label: const Text('أضف توضيح'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
      actions.add(const SizedBox(height: 10));
    }

    if (onReanalyze != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onReanalyze,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('إعادة التحليل'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
      actions.add(const SizedBox(height: 10));
    }

    actions.add(
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onClose,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: cs.surfaceVariant,
            foregroundColor: cs.onSurfaceVariant,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('إغلاق'),
        ),
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withOpacity(.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: accent),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.35),
              ),
              const SizedBox(height: 16),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditor extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onReanalyze;
  const _NoteEditor({required this.controller, required this.onReanalyze});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2, color: cs.primary),
              const SizedBox(width: 8),
              const Text('ملاحظة على الوجبة (اختياري)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              hintText:
                  'مثال: ساندويتش تونة على بر توست، مايونيز خفيف، كولا دايت 330مل',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 6),
          Text(
            'كتابة وصف قصير للأكل (مثلاً: يوجد فيه بيضتين + خبز) تساعدنا على التحليل بشكل أدق 👌',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onReanalyze,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث التحليل'),
            ),
          ),
        ],
      ),
    );
  }
}

/// تفصيل مكونات الوجبة (Breakdown) — يعتمد على items الراجعة من السيرفر.
/// لا يؤثر على منطق الحفظ/الإضافة (مجرد UI).

class _MealBreakdown extends StatelessWidget {
  final Map<String, dynamic> food;
  final ColorScheme cs;
  final ValueChanged<List<Map<String, dynamic>>> onItemsChanged;

  const _MealBreakdown({
    required this.food,
    required this.cs,
    required this.onItemsChanged,
  });

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _fmt(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  }

  List<Map<String, dynamic>> _itemsFromFood() {
    final raw = food['items'] ??
        food['ingredients_breakdown'] ??
        food['components'] ??
        food['detected_items'];
    final List<Map<String, dynamic>> items = [];
    if (raw is List) {
      for (final x in raw) {
        if (x is Map) {
          items.add(_normalizePhotoItemForUi(Map<String, dynamic>.from(x)));
        } else {
          final name = x.toString().trim();
          if (name.isNotEmpty) {
            items.add(_normalizePhotoItemForUi(<String, dynamic>{'name_ar': name}));
          }
        }
      }
    }
    if (items.isEmpty) {
      final ing = food['ingredients'];
      if (ing is List) {
        for (final x in ing) {
          final name = x.toString().trim();
          if (name.isNotEmpty) {
            items.add(_normalizePhotoItemForUi(<String, dynamic>{'name_ar': name}));
          }
        }
      }
    }
    return items;
  }

  Future<void> _editItem(
    BuildContext context,
    int index,
    List<Map<String, dynamic>> items,
  ) async {
    final current = Map<String, dynamic>.from(items[index]);
    final nutr = _itemNutritionCompat(current);
    final nameCtrl = TextEditingController(text: _photoItemName(current));
    final gramsCtrl = TextEditingController(
        text: _photoItemGrams(current) > 0
            ? _photoItemGrams(current).toStringAsFixed(0)
            : '');
    final kcalCtrl = TextEditingController(
        text: _toD(nutr['kcal']) > 0 ? _toD(nutr['kcal']).toStringAsFixed(0) : '');
    final pCtrl = TextEditingController(
        text: _toD(nutr['protein_g']) > 0 ? _toD(nutr['protein_g']).toStringAsFixed(1) : '');
    final cCtrl = TextEditingController(
        text: _toD(nutr['carbs_g']) > 0 ? _toD(nutr['carbs_g']).toStringAsFixed(1) : '');
    final fCtrl = TextEditingController(
        text: _toD(nutr['fat_g']) > 0 ? _toD(nutr['fat_g']).toStringAsFixed(1) : '');

    double parse(TextEditingController c) =>
        double.tryParse(_latinDigits(c.text.trim())) ?? 0.0;

    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المكوّن'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المكوّن'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: gramsCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الكمية', suffixText: 'جم'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: kcalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'السعرات', suffixText: 'kcal'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'البروتين', suffixText: 'جم'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الكارب', suffixText: 'جم'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الدهون', suffixText: 'جم'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final updated = Map<String, dynamic>.from(current);
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                updated['name_ar'] = name;
                updated['name'] = name;
              }
              final grams = parse(gramsCtrl);
              if (grams > 0) {
                updated['grams'] = grams;
                updated['estimated_weight_g'] = grams;
                updated['portion_grams'] = grams;
              }
              updated['calories_kcal'] = parse(kcalCtrl);
              updated['calories'] = updated['calories_kcal'];
              updated['protein_g'] = parse(pCtrl);
              updated['protein'] = updated['protein_g'];
              updated['carbs_g'] = parse(cCtrl);
              updated['carbs'] = updated['carbs_g'];
              updated['fat_g'] = parse(fCtrl);
              updated['fat'] = updated['fat_g'];
              updated['confidence'] = _smartPhotoItemConfidence(updated);
              Navigator.pop(ctx, updated);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    gramsCtrl.dispose();
    kcalCtrl.dispose();
    pCtrl.dispose();
    cCtrl.dispose();
    fCtrl.dispose();

    if (saved == null) return;
    final next = items.map((e) => Map<String, dynamic>.from(e)).toList();
    next[index] = saved;
    onItemsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFromFood();

    if (items.isNotEmpty) {
      return Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _BreakItemRow(
              item: items[i],
              cs: cs,
              fmt: _fmt,
              toD: _toD,
              onEdit: () => _editItem(context, i, items),
            ),
            if (i != items.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Text(
      'لا توجد تفاصيل للمكونات.',
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: cs.onSurface.withOpacity(.8)),
    );
  }
}

class _BreakItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final ColorScheme cs;
  final String Function(num) fmt;
  final double Function(dynamic) toD;
  final VoidCallback onEdit;

  const _BreakItemRow({
    required this.item,
    required this.cs,
    required this.fmt,
    required this.toD,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizePhotoItemForUi(item);
    final name = _photoItemName(normalized);
    final grams = _photoItemGrams(normalized);
    final nutr = _itemNutritionCompat(normalized);
    final kcal = toD(nutr['kcal']);
    final p = toD(nutr['protein_g']);
    final c = toD(nutr['carbs_g']);
    final f = toD(nutr['fat_g']);
    final src = (normalized['source'] ?? '').toString().toLowerCase();
    final ic = _smartPhotoItemConfidence(normalized);

    String? tag;
    Color? tagColor;
    if (src.contains('visual') || src.contains('gemini') || src.isEmpty) {
      tag = 'تقدير بصري';
      tagColor = cs.primary;
    } else {
      tag = 'تقديري';
      tagColor = cs.secondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? 'مكوّن' : name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('تعديل'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              if (grams > 0)
                Text(
                  '${grams.toStringAsFixed(0)}غ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor!.withOpacity(.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tagColor.withOpacity(.18)),
                ),
                child: Text(
                  tag!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tagColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text('🔥 ${fmt(kcal)} kcal'),
              Text('🥩 ${fmt(p)}غ'),
              Text('🍞 ${fmt(c)}غ'),
              Text('🥑 ${fmt(f)}غ'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ثقة تقديرية: ${(ic * 100).clamp(0, 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _WazenInsightCard extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _WazenInsightCard({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            cs.primary.withOpacity(.12),
            cs.secondary.withOpacity(.08),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: cs.primary.withOpacity(.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.favorite_rounded, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نصيحة وازن',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======= Meal Details UI =======

class FoodDetailsSection extends StatelessWidget {
  final Map<String, dynamic> food;
  final VoidCallback onAdd;

  const FoodDetailsSection(
      {super.key, required this.food, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final name = (food['name'] ?? food['label'] ?? '').toString();
    final kcal = (food['kcal'] ?? food['cal'] ?? food['calories'] ?? 0);
    final serving = (food['serving'] ?? food['size'] ?? '').toString();
    final macros =
        (food['macros'] ?? const {'p': 0.0, 'c': 0.0, 'f': 0.0}) as Map;
    final double p = _toD(macros['p'] ?? food['protein']);
    final double c = _toD(macros['c'] ?? food['carbs'] ?? food['carb']);
    final double f = _toD(macros['f'] ?? food['fat']);
    final double conf = _clamp01(_toD(food['confidence'] ?? food['conf']));

    // محاولة استخراج مكونات الوجبة (إن توفرت من الـ AI)
    final rawIngredients = food['ingredients'] ??
        food['components'] ??
        food['items'] ??
        food['parts'];
    final List<String> ingredients = <String>[];
    if (rawIngredients is List) {
      for (final item in rawIngredients) {
        if (item is String) {
          final t = item.trim();
          if (t.isNotEmpty) ingredients.add(t);
        } else if (item is Map && item['name'] is String) {
          final t = (item['name'] as String).trim();
          if (t.isNotEmpty) ingredients.add(t);
        }
      }
    } else if (rawIngredients is String) {
      for (final part in rawIngredients.split(RegExp('[,،]'))) {
        final t = part.trim();
        if (t.isNotEmpty) ingredients.add(t);
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'معلومات الوجبة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name.isEmpty ? 'وجبة غير معروفة' : name,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _InfoRow(label: 'السعرات', value: '${_fmt(kcal)} كالوري'),
                if (serving.isNotEmpty)
                  _InfoRow(label: 'الحجم', value: serving),
                const SizedBox(height: 10),
                _ConfidenceBar(confidence: conf),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'الماكروز',
            child: Column(
              children: [
                _MacroRow(label: 'بروتين', grams: p, color: Colors.teal),
                const Divider(height: 12),
                _MacroRow(label: 'كربوهيدرات', grams: c, color: Colors.indigo),
                const Divider(height: 12),
                _MacroRow(label: 'دهون', grams: f, color: Colors.orange),
                const SizedBox(height: 8),
                _MacroKcalNote(p: p, c: c, f: f),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (ingredients.isNotEmpty)
            _SectionCard(
              title: 'مكونات الوجبة (تقديريًا)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final ing in ingredients)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ' + ing),
                    ),
                ],
              ),
            ),
          if (ingredients.isNotEmpty) const SizedBox(height: 12),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('إضافة الوجبة'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          )
        ],
      ),
    );
  }

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _clamp01(double x) => x.isNaN
      ? 0
      : x < 0
          ? 0
          : (x > 1 ? 1 : x);
  static String _fmt(num n) =>
      n is int || n == n.roundToDouble() ? n.toString() : n.toStringAsFixed(1);
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Expanded(
              child:
                  Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;
  const _MacroRow(
      {required this.label, required this.grams, required this.color});

  @override
  Widget build(BuildContext context) {
    final kcal = _macroToKcal(label, grams);
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Text('${FoodDetailsSection._fmt(grams)} جم',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 10),
        Text('${FoodDetailsSection._fmt(kcal)} سعرة',
            style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }

  num _macroToKcal(String label, double grams) {
    switch (label) {
      case 'دهون':
        return grams * 9;
      default:
        return grams * 4;
    }
  }
}

class _MacroKcalNote extends StatelessWidget {
  final double p, c, f;
  const _MacroKcalNote({required this.p, required this.c, required this.f});

  @override
  Widget build(BuildContext context) {
    final total = p * 4 + c * 4 + f * 9;
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
          'إجمالي طاقة الماكروز التقريبية: ${FoodDetailsSection._fmt(total)} سعرة',
          style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double confidence; // 0..1
  const _ConfidenceBar({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final percent = (confidence * 100).round();
    final Color color = confidence >= 0.8
        ? Colors.green
        : confidence >= 0.6
            ? Colors.orange
            : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('الثقة بالتعرّف',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(.4)),
              ),
              child: Text('$percent%',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: confidence,
            minHeight: 10,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// === مختصر الماكروز ===
class _MacrosSummary extends StatelessWidget {
  final double calories, protein, carbs, fat;
  const _MacrosSummary({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  String _fmt(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget line(String label, double value, {Color? color, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 18, color: color ?? cs.primary),
            if (icon != null) const SizedBox(width: 6),
            Expanded(child: Text(label)),
            Text(_fmt(value),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Column(
      children: [
        line('السعرات (kcal)', calories,
            color: cs.primary, icon: Icons.local_fire_department),
        line('بروتين (غ)', protein, icon: Icons.egg),
        line('كربوهيدرات (غ)', carbs, icon: Icons.bubble_chart),
        line('دهون (غ)', fat, icon: Icons.water_drop),
      ],
    );
  }
}

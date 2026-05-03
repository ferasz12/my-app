// lib/screens/food_ai_screen.dart

// NOTE: هذه الصفحة تستقبل الآن الصورة من food_camera_screen عبر الـ constructor
//       (XFile imageFile) وتبدأ التحليل مباشرة في initState بدون فتح الكاميرا هنا.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/openai_food_service.dart';

// اسم الوجبة بالعربية (إن توفر) أو تحويل أسماء شائعة
String _displayNameArabic(Map<String, dynamic>? f) {
  if (f == null) return '';
  final Object? ar = f['name_ar'] ?? f['ar_name'] ?? f['arabic_name'] ?? f['display_ar'];
  if (ar is String && ar.trim().isNotEmpty) return ar.trim();
  final String name = (f['name'] ?? f['label'] ?? f['title'] ?? '').toString().trim();
  if (name.isEmpty) return '';
  // إذا الاسم عربي أصلاً
  final arabic = RegExp(r'[\u0600-\u06FF]');
  if (arabic.hasMatch(name)) return name;
  final l = name.toLowerCase();
  if (l.contains('masoub') || l.contains('maasoub') || l.contains('masoob')) return 'معصوب';
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
  String? _error;

  Map<String, dynamic>? _food;

  // الصورة الحالية (قادمة من food_camera_screen أو من المعرض)
  late XFile _currentImage;

  // الأهداف
  double _tK = 0, _tP = 0, _tC = 0, _tF = 0;
  // مجاميع اليوم
  double _sK = 0, _sP = 0, _sC = 0, _sF = 0;
  // نوع الهدف
  String _goalType = 'maintain';

  // حد الاستخدام اليومي
  static const int _dailyLimit = 3;
  int _usageCount = 0;
  bool _blocked = false;

  // الملاحظة
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageFile;
    _noteCtrl.text = (widget.mealNote ?? '').trim();
    _run();
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
            left: 16, right: 16, top: 16,
          ),
          child: _NoteEditor(controller: controller, onReanalyze: () { Navigator.pop(ctx); _reanalyzeWithNote(); }),
        );
      },
    );
  }

void _handleAddMeal() {
    if (_food == null) return;
    Navigator.of(context).pop(_food);
  }

  Future<void> _run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final email = prefs.getString('currentEmail') ?? user?.email ?? 'unknown_user';

      // 0) حد الاستخدام اليومي
      final ymd = DateTime.now().toIso8601String().split('T').first;
      final usageKey = 'food_ai_usage_${email}_$ymd';
      _usageCount = prefs.getInt(usageKey) ?? 0;
      if (_usageCount >= _dailyLimit) {
        setState(() {
          _blocked = true;
          _loading = false;
        });
        return;
      }
      _usageCount += 1;
      await prefs.setInt(usageKey, _usageCount);

      // 1) الأهداف
      final k = prefs.getDouble('caloriesNeeded_$email');
      final p = prefs.getDouble('protein_$email');
      final c = prefs.getDouble('carbs_$email');
      final f = prefs.getDouble('fat_$email');
      if (k != null && p != null && c != null && f != null) {
        _tK = k; _tP = p; _tC = c; _tF = f;
      } else {
        await _tryFetchTargetsFromFirestore();
      }

      // 2) نوع الهدف
      _goalType = prefs.getString('goalType_$email') ??
          (await _tryFetchGoalTypeFromFirestore()) ??
          'maintain';

      // 3) مجاميع اليوم
      final totalsKey = 'kcal_daytotals_${email}_$ymd';
      final rawTotals = prefs.getString(totalsKey);
      if (rawTotals != null && rawTotals.trim().isNotEmpty) {
        try {
          final Map<String, dynamic> m = jsonDecode(rawTotals);
          _sK = _toD(m['k']); _sP = _toD(m['p']); _sC = _toD(m['c']); _sF = _toD(m['f']);
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

      final map = await OpenAIFoodService.analyzeFromXFile(
        _currentImage,
        profile: profile,
        today: today,
        detail: VisionDetail.high,
        maxImageEdge: 1536,
        clarifier: clarifier, // دائمًا String
      );

      if (map == null) {
        throw Exception('لا يوجد اتصال بالخدمة: تأكد من FOOD_PROXY_URL أو الشبكة');
      }
      final kcal = _toD(map['calories']);
      if (kcal <= 0) {
        throw Exception('تم التحليل لكن بدون سعرات (جرّب صورة أوضح/أقرب)');
      }

      // نثبت وجود note كسلسلة
      final currentNote = clarifier;
      if (currentNote.isNotEmpty) {
        map['note'] = currentNote;
      }

      _ensureSuitabilityFields(map);

      setState(() {
        _food = map;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // إعادة التحليل بدون زيادة العدّاد
  Future<void> _reanalyzeWithNote() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
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

      final map = await OpenAIFoodService.analyzeFromXFile(
        _currentImage,
        profile: profile,
        today: today,
        detail: VisionDetail.high,
        maxImageEdge: 1536,
        clarifier: clarifier,
      );
      if (map == null) throw Exception('لا يوجد اتصال بالخدمة');
      if (_toD(map['calories']) <= 0) throw Exception('تحليل غير كافٍ، جرّب صورة أوضح');

      if (clarifier.isNotEmpty) map['note'] = clarifier;

      _ensureSuitabilityFields(map);

      setState(() {
        _food = map;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // اختيار صورة جديدة من المعرض وإعادة التحليل
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _currentImage = picked;
      _loading = true;
      _error = null;
      _food = null;
    });
    await _run();
  }

  // حساب suitability/reason إذا مفقودة
  void _ensureSuitabilityFields(Map<String, dynamic> map) {
    var verdict = '${map['suitability'] ?? ''}';
    var reason  = '${map['reason'] ?? ''}';

    final addK = _toD(map['calories']);
    final afterK = _sK + addK;

    if (verdict.isEmpty || reason.isEmpty) {
      if (_goalType.toLowerCase().contains('loss') || _goalType.contains('خفض') || _goalType.contains('تنحيف')) {
        if (afterK <= _tK) { verdict = 'good'; reason = 'الوجبة ضمن هدف السعرات لخفض الوزن.'; }
        else if (afterK <= _tK * 1.10) { verdict = 'ok'; reason = 'تجاوز طفيف عن الهدف اليومي لخفض الوزن.'; }
        else { verdict = 'bad'; reason = 'تتجاوز هدف السعرات لخفض الوزن بشكل واضح.'; }
      } else if (_goalType.toLowerCase().contains('gain') || _goalType.contains('زيادة') || _goalType.contains('bulk')) {
        if (afterK >= _tK * 0.90) { verdict = 'good'; reason = 'يدعم هدف زيادة الوزن/العضل.'; }
        else if (afterK >= _tK * 0.75) { verdict = 'ok'; reason = 'قد تكون السعرات أقل من المطلوب قليلاً.'; }
        else { verdict = 'bad'; reason = 'السعرات أقل بكثير من هدف الزيادة.'; }
      } else {
        final diff = (afterK - _tK).abs();
        if (diff <= _tK * 0.10) { verdict = 'good'; reason = 'قريب جداً من هدف الثبات اليومي.'; }
        else if (diff <= _tK * 0.15) { verdict = 'ok'; reason = 'ابتعاد بسيط عن هدف الثبات.'; }
        else { verdict = 'bad'; reason = 'بعيد عن هدف الثبات اليومي.'; }
      }
      map['suitability'] = verdict;
      map['reason'] = reason;
    }
  }

  double _toD(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  Future<void> _tryFetchTargetsFromFirestore() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      if (data == null) return;
      final metrics = data['metrics'];
      if (metrics is Map) {
        final k = metrics['caloriesNeeded'] ?? metrics['kcal'];
        final p = metrics['protein'];
        final c = metrics['carbs'];
        final f = metrics['fat'];
        if (k is num && p is num && c is num && f is num) {
          _tK = k.toDouble(); _tP = p.toDouble(); _tC = c.toDouble(); _tF = f.toDouble();
        }
      }
    } catch (_) {}
  }

  Future<String?> _tryFetchGoalTypeFromFirestore() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      final doc = await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data();
      if (data == null) return null;

      for (final key in ['goalType','goal','dietGoal','planGoal','regimen','plan']) {
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
    if (s.contains('loss') || s.contains('خفض') || s.contains('تنحيف') || s.contains('نقص')) return 'خسارة وزن';
    if (s.contains('gain') || s.contains('زيادة') || s.contains('عضل') || s.contains('bulk')) return 'زيادة وزن/عضل';
    return 'ثبات الوزن';
  }

  String _fmt(dynamic v) =>
      (v is num) ? v.toStringAsFixed(0) : (double.tryParse('$v')?.toStringAsFixed(0) ?? '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليل الطعام بالذكاء الاصطناعي'),
        actions: [
          IconButton(
            tooltip: 'اختيار صورة من المعرض',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _pickFromGallery,
          ),
        ],
      ),
      body: _loading
          ? const _AnalyzingView()
          : _blocked
              ? _LimitView(
                  used: _usageCount,
                  limit: _dailyLimit,
                  onClose: () => Navigator.pop(context),
                )
              : _error != null
                  ? _ErrorView(
                      message: _error!,
                      onClose: () => Navigator.pop(context),
                    )
                  : _food == null
                      ? _ErrorView(
                          message: 'لم يتم التعرف على الطعام.',
                          onClose: () => Navigator.pop(context),
                        )
                      : Directionality(
                          textDirection: TextDirection.rtl,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            
children: [
                              // صورة + صندوق التحديد
                              _FoodImageWithBox(
                                filePath: _currentImage.path,
                                bbox: null,
                                height: 260,
                              ),
                              const SizedBox(height: 8),
                              // تلميح مبسط
                              const Text(
                                'تأكد أن الصورة تُظهر وجبتك كاملة بوضوح. يمكنك إضافة وصف اختياري أدناه ثم إعادة التحليل.',
                                textAlign: TextAlign.center,
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _pickFromGallery,
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: const Text('اختيار صورة من المعرض'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // أزرار التوضيح السريعة
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _openClarifierSheet,
                                      icon: const Icon(Icons.edit_note),
                                      label: const Text('أضف توضيح'),
                                    ),
                                  ),
                                  
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'مثال: 100 غرام دجاج مشوي، نصف كوب رز، شريحة توست… (يزيد دقة الحساب)',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              // زر التحليل
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _reanalyzeWithNote,
                                  icon: const Icon(Icons.analytics_outlined),
                                  label: const Text('تحليل الصورة'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // بطاقة النتيجة
                              _ResultCard(
                                food: _food!,
                                goalType: _goalType,
                              ),
                              const SizedBox(height: 16),
                              // زر إضافة الوجبة
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _handleAddMeal,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('إضافة للوجبة'),
                                ),
                              ),
                            ],

                          ),
                        ),
    );
  }
}

// ====== Widgets ======

// ======= Result Card (Arabic UI) =======
class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> food;
  final String goalType;
  const _ResultCard({required this.food, required this.goalType});

  double _toD(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  Color _baseColor(String verdict) {
    switch (verdict) {
      case 'good': return const Color(0xFF10B981); // teal/green
      case 'bad' : return const Color(0xFFEF4444); // red
      default    : return const Color(0xFFF59E0B); // amber
    }
  }

  String _chipText(String verdict) {
    switch (verdict) {
      case 'bad': return 'غير مناسب لنظامك وهدفك';
      default   : return 'مناسب لنظامك وهدفك';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String verdict = (food['suitability'] ?? '').toString();
    final Color base = _baseColor(verdict);
    final double conf = _toD(food['confidence'] ?? food['conf'] ?? 0.0);
    final String name = _displayNameArabic(food).isNotEmpty
        ? _displayNameArabic(food)
        : (food['name'] ?? '').toString();

    final double kcal = _toD(food['calories'] ?? food['kcal']);
    final double p = _toD(food['protein'] ?? food['p']);
    final double c = _toD(food['carbs']   ?? food['c']);
    final double f = _toD(food['fat']     ?? food['f']);
    String serving = (food['serving'] ?? food['serving_text'] ?? '').toString();
    if (serving.isEmpty) {
      final sw = _toD(food['servingWeight']);
      final w  = _toD(food['weight']);
      final grams = sw > 0 ? sw : (w > 0 ? w : 0);
      if (grams > 0) serving = '${grams.toStringAsFixed(0)} g';
    }

    final String reason = (food['reason'] ?? '').toString().trim();
    final List<String> reasons = reason.isEmpty
        ? const []
        : reason.replaceAll('•', '\n').replaceAll(' - ', '\n').split(RegExp(r'[\n؛]')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();

    return Container(
      decoration: BoxDecoration(
        color: base.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: base.withOpacity(.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: base.withOpacity(.35)),
                  boxShadow: [BoxShadow(color: base.withOpacity(.08), blurRadius: 2, offset: const Offset(0,1))],
                ),
                child: Text(_chipText(verdict), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text('ثقة: ${conf.toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 16),
          Text('تم التعرف على: $name',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _EmojiRow(emoji: '🔥', label: 'السعرات', value: '${kcal.toStringAsFixed(0)}'),
          _EmojiRow(emoji: '🍗', label: 'بروتين',  value: '${p.toStringAsFixed(1)} g'),
          _EmojiRow(emoji: '🍞', label: 'كارب',     value: '${c.toStringAsFixed(1)} g'),
          _EmojiRow(emoji: '🧈', label: 'دهون',     value: '${f.toStringAsFixed(1)} g'),
          if (serving.isNotEmpty) _EmojiRow(emoji: '🥄', label: 'الحصّة', value: serving),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('الأسباب:', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...reasons.map((r)=>Padding(
              padding: const EdgeInsetsDirectional.only(start: 6, bottom: 4),
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

class _EmojiRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  const _EmojiRow({required this.emoji, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
class _FoodImageWithBox extends StatelessWidget {
  final String filePath;
  final Map<String, dynamic>? bbox; // {x,y,w,h} ∈ [0..1]
  final double height;
  const _FoodImageWithBox({required this.filePath, required this.bbox, this.height = 220});

  @override
  Widget build(BuildContext context) {
    double x = 0.3, y = 0.3, w = 0.4, h = 0.4;
    double _d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

    if (bbox != null) {
      final bx = _d(bbox!['x']);
      final by = _d(bbox!['y']);
      final bw = _d(bbox!['w']);
      final bh = _d(bbox!['h']);
      if (bx >= 0 && by >= 0 && bw > 0 && bh > 0 && bx <= 1 && by <= 1 && (bx + bw) <= 1.001 && (by + bh) <= 1.001) {
        x = bx.clamp(0.0, 1.0);
        y = by.clamp(0.0, 1.0);
        w = bw.clamp(0.0, 1.0 - x);
        h = bh.clamp(0.0, 1.0 - y);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(filePath), fit: BoxFit.contain),
            LayoutBuilder(
              builder: (ctx, c) {
                final wPx = c.maxWidth;
                final hPx = height;
                return Stack(
                  children: [
                    Positioned(
                      left: x * wPx,
                      top: y * hPx,
                      width: (w * wPx),
                      height: (h * hPx),
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.amber, width: 3),
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.amber.withOpacity(0.10),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
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
              'المتبقي اليوم: $used / $limit مرات',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(height: 8),
              Text(
                'نحلل الآن وجبتك، انتظر شوي…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'انتظر لحظات قليلة حتى ننتهي من قراءة الصورة وحساب الماكروز.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitView extends StatelessWidget {
  final int used;
  final int limit;
  final VoidCallback onClose;
  const _LimitView({required this.used, required this.limit, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 40, color: Colors.orange),
              const SizedBox(height: 12),
              Text('وصلت حد تصوير الطعام اليومي.', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('استخدمت: $used/$limit محاولات. جرّب لاحقًا.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onClose, child: const Text('رجوع')),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String suitability; // good | ok | bad
  final VoidCallback onAdd;
  const _AddButton({required this.suitability, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (suitability) {
      case 'good': bg = Colors.green; break;
      case 'ok'  : bg = Colors.orange; break;
      default    : bg = Colors.grey; break;
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
      ),
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('إضافة للوجبات'),
    );
  }
}

class _GoalAndRemainderCard extends StatelessWidget {
  final String goalLabel;
  final double tK, tP, tC, tF; // targets
  final double sK, sP, sC, sF; // so far
  final double addK, addP, addC, addF; // meal

  const _GoalAndRemainderCard({
    required this.goalLabel,
    required this.tK, required this.tP, required this.tC, required this.tF,
    required this.sK, required this.sP, required this.sC, required this.sF,
    required this.addK, required this.addP, required this.addC, required this.addF,
  });

  String _fmt(dynamic v) =>
      (v is num) ? v.toStringAsFixed(0) : (double.tryParse('$v')?.toStringAsFixed(0) ?? '0');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final afterK = sK + addK;
    final afterP = sP + addP;
    final afterC = sC + addC;
    final afterF = sF + addF;

    Widget row(String title, String a, String b, {IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text('$a  →  $b'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.secondary.withOpacity(.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.flag, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'هدفك: $goalLabel',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          row('السعرات (اليوم)', '${_fmt(sK)}/${_fmt(tK)}', '${_fmt(afterK)}/${_fmt(tK)}', icon: Icons.local_fire_department),
          row('البروتين (غ)', '${_fmt(sP)}/${_fmt(tP)}', '${_fmt(afterP)}/${_fmt(tP)}', icon: Icons.egg),
          row('الكارب (غ)', '${_fmt(sC)}/${_fmt(tC)}', '${_fmt(afterC)}/${_fmt(tC)}', icon: Icons.bubble_chart),
          row('الدهون (غ)', '${_fmt(sF)}/${_fmt(tF)}', '${_fmt(afterF)}/${_fmt(tF)}', icon: Icons.water_drop),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final String verdict; // good | ok | bad
  final String reason;
  const _VerdictCard({required this.verdict, required this.reason});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (verdict) {
      case 'good': icon = Icons.check_circle; color = const Color(0xFF16A34A); break;
      case 'bad' : icon = Icons.block;        color = const Color(0xFFEF4444);   break;
      default    : icon = Icons.info;         color = const Color(0xFFF59E0B);
    }

    // نحول نتيجة suitability إلى تقييم من ١٠
    int score;
    String label;
    switch (verdict) {
      case 'good':
        score = 9;
        label = 'وجبة صحية ومناسبة لهدفك.';
        break;
      case 'bad':
        score = 3;
        label = 'وجبة غير مناسبة لهدفك الحالي.';
        break;
      default:
        score = 6;
        label = 'وجبة متوسطة يمكن تناولها باعتدال.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تقييم صحة هذه الوجبة: $score/10',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (reason.trim().isNotEmpty)
                  Text(
                    reason,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _ErrorView({required this.message, required this.onClose});
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onClose, child: const Text('إغلاق')),
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
              const Text('ملاحظة على الوجبة (اختياري)', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              hintText: 'مثال: الأكل يوجد فيه بيضتين + خبز أسمر',
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

// ======= Meal Details UI =======

class FoodDetailsSection extends StatelessWidget {
  final Map<String, dynamic> food;
  final VoidCallback onAdd;

  const FoodDetailsSection({super.key, required this.food, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final name = (food['name'] ?? food['label'] ?? '').toString();
    final kcal = (food['kcal'] ?? food['cal'] ?? food['calories'] ?? 0);
    final serving = (food['serving'] ?? food['size'] ?? '').toString();
    final macros = (food['macros'] ?? const {'p': 0.0, 'c': 0.0, 'f': 0.0}) as Map;
    final double p = _toD(macros['p'] ?? food['protein']);
    final double c = _toD(macros['c'] ?? food['carbs'] ?? food['carb']);
    final double f = _toD(macros['f'] ?? food['fat']);
    final double conf = _clamp01(_toD(food['confidence'] ?? food['conf']));

    // محاولة استخراج مكونات الوجبة (إن توفرت من الـ AI)
    final rawIngredients = food['ingredients'] ?? food['components'] ?? food['items'] ?? food['parts'];
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _InfoRow(label: 'السعرات', value: '${_fmt(kcal)} كالوري'),
                if (serving.isNotEmpty) _InfoRow(label: 'الحجم', value: serving),
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
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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

  static double _clamp01(double x) => x.isNaN ? 0 : x < 0 ? 0 : (x > 1 ? 1 : x);
  static String _fmt(num n) => n is int || n == n.roundToDouble() ? n.toString() : n.toStringAsFixed(1);
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
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
          Text('$label: ', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;
  const _MacroRow({required this.label, required this.grams, required this.color});

  @override
  Widget build(BuildContext context) {
    final kcal = _macroToKcal(label, grams);
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Text('${FoodDetailsSection._fmt(grams)} جم',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 10),
        Text('${FoodDetailsSection._fmt(kcal)} kcal', style: Theme.of(context).textTheme.labelMedium),
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
      child: Text('إجمالي طاقة الماكروز التقريبية: ${FoodDetailsSection._fmt(total)} kcal',
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
            Text('الثقة بالتعرّف', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(.4)),
              ),
              child: Text('$percent%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
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
        line('السعرات (kcal)', calories, color: cs.primary, icon: Icons.local_fire_department),
        line('بروتين (غ)', protein, icon: Icons.egg),
        line('كربوهيدرات (غ)', carbs, icon: Icons.bubble_chart),
        line('دهون (غ)', fat, icon: Icons.water_drop),
      ],
    );
  }
}
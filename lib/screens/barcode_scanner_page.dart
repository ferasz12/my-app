// lib/screens/barcode_scanner_page.dart
//
// صفحة الباركود — تصميم أفخم + منطق مرن:
// - MobileScanner مع عناصر تحكم (فلاش/كاميرا)
// - إطار توجيهي لالتقاط المنتج
// - لوحة سفلية أنيقة لإظهار نتيجة البحث (اسم/علامة/سعرات/ماكروز)
// - إيقاف القراءة مؤقتًا بعد الالتقاط ثم زر "إعادة المسح"
// - عند نجاح جلب بيانات المنتج: Navigator.pop(context, FoodMacro) (بعد اختيار الكمية)
// - عند الفشل: Navigator.pop(context, {'barcode': code}) للانتقال للإدخال اليدوي
//
// وضع خاص (raw): يرجّع الباركود كنص مباشرة (مفيد للكوبونات/أكواد التفعيل).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/barcode_service.dart'; // يوفر BarcodeService و FoodMacro

enum BarcodeScannerMode { food, raw }

class BarcodeScannerPage extends StatefulWidget {
  final BarcodeScannerMode mode;
  const BarcodeScannerPage({super.key, this.mode = BarcodeScannerMode.food});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with SingleTickerProviderStateMixin {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [BarcodeFormat.all],
  );

  bool _isBusy = false; // قراءة/تحميل
  bool _paused = false; // إيقاف السكينر بعد الالتقاط
  bool _torchOn = false; // حالة الفلاش (محلية)
  String? _lastCode; // آخر كود تم التقاطه
  FoodMacro? _macro; // نتيجة المنتج
  String? _error; // رسالة خطأ لطيفة

  // الكمية المختارة
  final TextEditingController _qtyCtrl = TextEditingController();
  double _qty = 100;
  String _unit = 'g'; // g | ml | serving

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(String rawCode) async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _paused = true;
      _lastCode = rawCode;
      _error = null;
      _macro = null;
    });

    // وضع "raw": نرجّع الكود مباشرة (بدون أي بحث غذائي)
    if (widget.mode == BarcodeScannerMode.raw) {
      if (mounted) {
        Navigator.pop(context, rawCode);
      }
      return;
    }

    try {
      final service = BarcodeService(FirebaseFirestore.instance);
      final result = await service.lookup(rawCode);

      if (!mounted) return;

      if (result == null) {
        // لا توجد بيانات — نسمح بالانتقال للإدخال اليدوي
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('لم نجد بيانات كافية'),
            content: Text('الباركود: $rawCode\nتقدر تضيفه يدويًا إن رغبت.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('متابعة'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context, {'barcode': rawCode});
        return;
      }

      setState(() {
        _macro = result;
        _initQtyForMacro(result);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _onDetect(BarcodeCapture cap) {
    if (_paused) return;
    final code = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (code == null) return;

    // Debounce بسيط حتى لا تتكرر القراءة أكثر من مرة
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _handleBarcode(code);
    });
  }

  Future<void> _resume() async {
    setState(() {
      _paused = false;
      _macro = null;
      _error = null;
      _lastCode = null;
      _qty = 100;
      _unit = 'g';
      _qtyCtrl.text = '';
    });
  }

  String _formatQty(double v) {
    final r = v.roundToDouble();
    if ((v - r).abs() < 0.0001) return r.toInt().toString();
    return v.toStringAsFixed(1);
  }

  String _unitLabel(String u) {
    switch (u) {
      case 'ml':
        return 'مل';
      case 'serving':
        return 'حصة';
      default:
        return 'غ';
    }
  }

  void _initQtyForMacro(FoodMacro base) {
    final per = (base.nutritionPer).toLowerCase().trim();
    final hasG = (base.servingSizeG ?? 0) > 0;
    final hasMl = (base.servingSizeMl ?? 0) > 0;

    double qty = 100;
    String unit = 'g';

    if (per == 'serving') {
      if (hasMl) {
        qty = base.servingSizeMl!;
        unit = 'ml';
      } else if (hasG) {
        qty = base.servingSizeG!;
        unit = 'g';
      } else {
        qty = 1;
        unit = 'serving';
      }
    } else if (per == '100ml') {
      // غالبًا مشروب
      if (hasMl) {
        qty = base.servingSizeMl!;
      } else {
        qty = 100;
      }
      unit = 'ml';
    } else {
      // 100g (الافتراضي)
      if (hasG) {
        qty = base.servingSizeG!;
        unit = 'g';
      } else if (hasMl) {
        qty = base.servingSizeMl!;
        unit = 'ml';
      } else {
        qty = 100;
        unit = 'g';
      }
    }

    _qty = qty;
    _unit = unit;
    _qtyCtrl.text = _formatQty(qty);
  }

  List<String> _availableUnits(FoodMacro base) {
    final per = base.nutritionPer.toLowerCase().trim();
    final hasServingSize = (base.servingSizeG ?? 0) > 0 || (base.servingSizeMl ?? 0) > 0;

    if (per == 'serving' && !hasServingSize) {
      return ['serving'];
    }

    final out = <String>['g', 'ml'];
    if (per == 'serving' || hasServingSize) out.add('serving');
    return out;
  }

  double _scaleRatio(FoodMacro base) {
    final per = base.nutritionPer.toLowerCase().trim();
    final sg = base.servingSizeG ?? 0;
    final sm = base.servingSizeMl ?? 0;

    if (per == 'serving') {
      if (_unit == 'serving') return _qty;
      if (_unit == 'g' && sg > 0) return _qty / sg;
      if (_unit == 'ml' && sm > 0) return _qty / sm;
      // لا نقدر نحسبها بدون حجم الحصة: اعتبرها عدد حصص
      return _qty;
    }

    // per 100g/100ml
    if (_unit == 'serving') {
      final size = sm > 0 ? sm : sg;
      if (size > 0) return (_qty * size) / 100.0;
      return _qty;
    }

    return _qty / 100.0;
  }

  String _baseLabel(FoodMacro base) {
    final per = base.nutritionPer.toLowerCase().trim();
    if (per == 'serving') return 'لكل حصة';
    if (per == '100ml') return 'لكل 100 مل';
    return 'لكل 100 غ';
  }

  void _adjustQty(double delta) {
    final next = (_qty + delta);
    final safe = next < 0 ? 0.0 : next;
    setState(() {
      _qty = safe;
      _qtyCtrl.text = _formatQty(safe);
    });
  }

  double _stepSize() {
    if (_unit == 'serving') return 0.5;
    if (_qty < 100) return 10;
    if (_qty < 1000) return 50;
    return 100;
  }

  void _addAndClose() {
    final base = _macro;
    if (base == null) return;

    final ratio = _scaleRatio(base);
    final qtyLabel = '${_formatQty(_qty)} ${_unitLabel(_unit)}';

    final scaled = FoodMacro(
      name: '${base.name} ($qtyLabel)',
      brand: base.brand,
      servingSizeG: base.servingSizeG,
      servingSizeMl: base.servingSizeMl,
      nutritionPer: 'custom',
      caloriesKcal: base.caloriesKcal * ratio,
      proteinG: base.proteinG * ratio,
      carbsG: base.carbsG * ratio,
      fatG: base.fatG * ratio,
      source: base.source,
    );

    Navigator.pop(context, scaled);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // الكاميرا
          Positioned.fill(
            child: MobileScanner(
              controller: controller,
              onDetect: _onDetect,
            ),
          ),

          // تدرّج علوي جميل
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(.7), Colors.transparent],
                ),
              ),
            ),
          ),

          // إطار التوجيه (Rounded Rect)
          Center(
            child: AspectRatio(
              aspectRatio: 1.4, // مناسب لباركود المنتجات
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(.9), width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 24),
                  ],
                ),
              ),
            ),
          ),

          // شريط علوي للتحكم
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () async {
                      try {
                        await controller.toggleTorch();
                        setState(() => _torchOn = !_torchOn);
                      } catch (_) {
                        // ignore
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                    onPressed: () => controller.switchCamera(),
                  ),
                ],
              ),
            ),
          ),

          // لوحة سفلية للنتيجة/التعليمات
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.25),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: _buildBottomContent(context, cs, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: cs.onSecondaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: t.bodyLarge)),
        Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildQtyPicker(FoodMacro base) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final units = _availableUnits(base);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الكمية', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: () => _adjustQty(-_stepSize()),
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) {
                  final raw = v.replaceAll(',', '.').trim();
                  final parsed = double.tryParse(raw);
                  if (parsed == null) return;
                  setState(() => _qty = parsed < 0 ? 0.0 : parsed);
                },
              ),
            ),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _unit,
              items: units
                  .map((u) => DropdownMenuItem<String>(
                        value: u,
                        child: Text(_unitLabel(u)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _unit = v);
              },
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => _adjustQty(_stepSize()),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('القيم الأساسية ${_baseLabel(base)}', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildBottomContent(BuildContext context, ColorScheme cs, TextTheme t) {
    if (_isBusy) {
      return Row(
        children: [
          const SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 12),
          Text('جاري القراءة… قرّب الباركود داخل الإطار', style: t.bodyLarge),
        ],
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('حدث خطأ', style: t.titleLarge?.copyWith(color: cs.error, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_error!, style: t.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _resume,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المسح'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  if (_lastCode != null) Navigator.pop(context, {'barcode': _lastCode});
                },
                child: const Text('إدخال يدوي'),
              ),
            ],
          ),
        ],
      );
    }

    if (_macro == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('وجّه الباركود داخل الإطار', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('نوقف الكاميرا تلقائيًا بعد القراءة لعرض المنتج. تقدر تشغّل الفلاش من الأعلى.', style: t.bodyMedium),
          if (_lastCode != null) ...[
            const SizedBox(height: 10),
            Text('آخر كود: $_lastCode', style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _resume,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('استمرار المسح'),
            ),
          ],
        ],
      );
    }

    // بطاقة المنتج
    final m = _macro!;
    final ratio = _scaleRatio(m);
    final cal = m.caloriesKcal * ratio;
    final carbs = m.carbsG * ratio;
    final protein = m.proteinG * ratio;
    final fat = m.fatG * ratio;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_2_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (m.brand != null) Text(m.brand!, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    if (_lastCode != null) Text('الباركود: $_lastCode', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // اختيار الكمية
          _buildQtyPicker(m),
          const SizedBox(height: 12),

          _statRow(Icons.local_fire_department_rounded, 'السعرات', '${cal.toStringAsFixed(0)} kcal'),
          const SizedBox(height: 8),
          _statRow(Icons.breakfast_dining_rounded, 'الكربوهيدرات', '${carbs.toStringAsFixed(1)} غ'),
          const SizedBox(height: 8),
          _statRow(Icons.lunch_dining_rounded, 'البروتين', '${protein.toStringAsFixed(1)} غ'),
          const SizedBox(height: 8),
          _statRow(Icons.egg_rounded, 'الدهون', '${fat.toStringAsFixed(1)} غ'),

          if (m.servingSizeMl != null) ...[
            const SizedBox(height: 8),
            _statRow(Icons.local_drink_rounded, 'حجم الحصة', '${m.servingSizeMl!.toStringAsFixed(0)} مل'),
          ] else if (m.servingSizeG != null) ...[
            const SizedBox(height: 8),
            _statRow(Icons.scale_rounded, 'حجم الحصة', '${m.servingSizeG!.toStringAsFixed(0)} غ'),
          ],

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resume,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المسح'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addAndClose,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة للوجبة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

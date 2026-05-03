// lib/screens/meal_editor_page.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/restaurants_firestore_repository.dart';
import '../models/meal.dart';

class MealEditorPage extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;
  final Meal? existing;

  const MealEditorPage({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.existing,
  });

  @override
  State<MealEditorPage> createState() => _MealEditorPageState();
}

class _MealEditorPageState extends State<MealEditorPage> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _category = TextEditingController();
  final _serving = TextEditingController();

  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  final _repo = RestaurantsFirestoreRepository();

  late final String _mealId;
  String? _imageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _mealId = ex?.id ?? _repo.newMealId(widget.restaurantId);

    _name.text = ex?.name ?? '';
    _desc.text = ex?.description ?? '';
    _category.text = ex?.category ?? '';
    _serving.text = ex?.serving ?? '';

    _calories.text = (ex?.calories ?? 0).toString();
    _protein.text = (ex?.protein ?? 0).toString();
    _carbs.text = (ex?.carbs ?? 0).toString();
    _fat.text = (ex?.fat ?? 0).toString();

    _imageUrl = ex?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _category.dispose();
    _serving.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  String get _title => widget.existing == null ? 'إضافة وجبة' : 'تعديل الوجبة';

  Future<void> _pickImage() async {
    try {
      final url = await _repo.pickAndUploadImage(
        storagePath: 'restaurants/${widget.restaurantId}/meals/$_mealId.jpg',
      );
      if (!mounted) return;
      if (url == null) return;
      setState(() => _imageUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر رفع الصورة: $e')),
      );
    }
  }

  int? _parseInt(String v) => int.tryParse(v.trim());
  double? _parseDouble(String v) => double.tryParse(v.trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final calories = _parseInt(_calories.text) ?? 0;
    final protein = _parseDouble(_protein.text) ?? 0.0;
    final carbs = _parseDouble(_carbs.text) ?? 0.0;
    final fat = _parseDouble(_fat.text) ?? 0.0;

    setState(() => _saving = true);
    try {
      await _repo.upsertMeal(
        restaurantId: widget.restaurantId,
        mealId: _mealId,
        restaurantName: widget.restaurantName,
        name: _name.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        category: _category.text.trim(),
        serving: _serving.text.trim(),
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        imageUrl: _imageUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.10),
                    cs.surface,
                    cs.secondary.withOpacity(0.06),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ImageBox(imageUrl: _imageUrl, onPick: _pickImage),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'اسم الوجبة',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'اكتب اسم الوجبة' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _desc,
                      decoration: const InputDecoration(
                        labelText: 'وصف/ملاحظات (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _category,
                            decoration: const InputDecoration(
                              labelText: 'التصنيف (اختياري)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _serving,
                            decoration: const InputDecoration(
                              labelText: 'الحصة (اختياري)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MacrosGrid(
                      calories: _calories,
                      protein: _protein,
                      carbs: _carbs,
                      fat: _fat,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ID: $_mealId',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 12),
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
}

class _ImageBox extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onPick;

  const _ImageBox({required this.imageUrl, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
              child: imageUrl == null
                  ? const Center(child: Icon(Icons.fastfood, size: 44))
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Icon(Icons.broken_image, size: 44)),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.photo_library),
          label: const Text('اختيار/تغيير صورة الوجبة'),
        ),
      ],
    );
  }
}

class _MacrosGrid extends StatelessWidget {
  final TextEditingController calories;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  const _MacrosGrid({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  String? _reqNum(String? v) {
    if ((v ?? '').trim().isEmpty) return 'مطلوب';
    if (double.tryParse(v!.trim()) == null) return 'رقم';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('القيم الغذائية (لكل وجبة)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: calories,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'السعرات',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return 'مطلوب';
                  if (int.tryParse(v!.trim()) == null) return 'رقم صحيح';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: protein,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'البروتين (غ)',
                  border: OutlineInputBorder(),
                ),
                validator: _reqNum,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: carbs,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الكارب (غ)',
                  border: OutlineInputBorder(),
                ),
                validator: _reqNum,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: fat,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الدهون (غ)',
                  border: OutlineInputBorder(),
                ),
                validator: _reqNum,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

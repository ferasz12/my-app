
// =====================
// lib/screens/food_capture_page.dart
// نسخة خفيفة بدون camera — تستخدم image_picker للكاميرا/المعرض
// وتعيد نتيجة FoodAiScreen إلى الصفحة السابقة (Home) كناتج Navigator.pop(map).
// =====================

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'food_ai_screen.dart';

class FoodCapturePage extends StatefulWidget {
  const FoodCapturePage({super.key});

  @override
  State<FoodCapturePage> createState() => _FoodCapturePageState();
}

class _FoodCapturePageState extends State<FoodCapturePage> {
  final _noteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    try {
      setState(() => _busy = true);
      final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (file == null) return;
      if (!mounted) return;
      final map = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FoodAiScreen(imageFile: file, mealNote: _noteCtrl.text.trim()),
        ),
      );
      if (!mounted) return;
      // ارجع بالنتيجة إلى الصفحة التي استدعتنا (Home)
      Navigator.of(context).pop(map);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    try {
      setState(() => _busy = true);
      final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (file == null) return;
      if (!mounted) return;
      final map = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FoodAiScreen(imageFile: file, mealNote: _noteCtrl.text.trim()),
        ),
      );
      if (!mounted) return;
      // ارجع بالنتيجة إلى الصفحة التي استدعتنا (Home)
      Navigator.of(context).pop(map);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تصوير الطعام')),
        body: Column(
          children: [
            // مساحة عرض أنيقة بدل المعاينة الحية (لا نستخدم camera)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      Center(
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.amber, width: 3),
                            color: Colors.amber.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            'التقط صورة للطعام أو اختر من المعرض ثم حلّلها',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (_busy)
                        const ColoredBox(
                          color: Color(0x66000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // ملاحظات أسفل المعاينة
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات على الوجبة (مثال: 100 جم رز/بدون سكر)',
                  prefixIcon: Icon(Icons.edit_note_outlined),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('من المعرض'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('التقاط وتحليل'),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

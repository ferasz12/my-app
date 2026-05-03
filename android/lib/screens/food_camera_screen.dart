// lib/screens/food_camera_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';

import 'food_ai_screen.dart'; // يجب أن يستقبل imageFile: Object?
import 'dart:typed_data';

// Ensures any supported image value is treated as XFile
XFile _ensureXFile(Object fileLike) {
  if (fileLike is XFile) return fileLike;
  if (fileLike is File) return XFile(fileLike.path);
  if (fileLike is String) return XFile(fileLike); // assume path
  if (fileLike is Uint8List) {
    return XFile.fromData(
      fileLike,
      name: 'meal.jpg',
      mimeType: 'image/jpeg',
    );
  }
  throw ArgumentError('Unsupported image type: ${fileLike.runtimeType}');
}


/// صفحة كاميرا مخصّصة مع معاينة حيّة + إطار مربّع + زر معرض
/// - عند الالتقاط/الاختيار: تذهب مباشرة لصفحة التحليل، ثم ترجع النتيجة للهوم.
class FoodCameraScreen extends StatefulWidget {
  const FoodCameraScreen({super.key});

  @override
  State<FoodCameraScreen> createState() => _FoodCameraScreenState();
}

class _FoodCameraScreenState extends State<FoodCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  CameraDescription? _camera;
  bool _isBusy = false;
  bool _cameraInitFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      _camera = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _controller = CameraController(
        _camera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _initFuture = _controller!.initialize();
      await _initFuture;
      if (mounted) setState(() => _cameraInitFailed = false);
    } catch (e) {
      // فشل التهيئة: سنستخدم التقاط من image_picker كخطة بديلة
      _cameraInitFailed = true;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _goToAnalysis(Object fileLike) async {
    if (!mounted) return;
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FoodAiScreen(imageFile: _ensureXFile(fileLike))),
    );
    if (!mounted) return;
    Navigator.pop(context, res); // ارجع للهوم ومع النتيجة
  }

  Future<void> _takePhoto() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (_controller != null && !_cameraInitFailed) {
        await _initFuture;
        final shot = await _controller!.takePicture(); // XFile
        await _goToAnalysis(shot);
      } else {
        // fallback: استخدم كاميرا النظام عبر image_picker
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
        if (x != null) await _goToAnalysis(x);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر الالتقاط: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (x != null) await _goToAnalysis(x);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر اختيار الصورة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('صوِّر الطعام'),
          centerTitle: false,
        ),
        body: Stack(
          children: [
            // المعاينة أو خلفية داكنة إذا فشلت الكاميرا
            Positioned.fill(
              child: _cameraInitFailed || _controller == null
                  ? Container(color: Colors.black)
                  : FutureBuilder(
                      future: _initFuture,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return Center(child: CameraPreview(_controller!));
                      },
                    ),
            ),
            // طبقة الإطار المربع الإرشادي
            const _SquareOverlay(),
            // زر المعرض أعلى يمين
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('اختيار من المعرض'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.15),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
            // زر الالتقاط أسفل الوسط
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: _isBusy ? null : _takePhoto,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // رسالة فشل التهيئة (إن حدثت)
            if (_cameraInitFailed)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('تعذّرت تهيئة الكاميرا، سيتم استخدام كاميرا النظام.', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// طبقة شفافة مع نافذة مربعة في الوسط + تلميح
class _SquareOverlay extends StatelessWidget {
  const _SquareOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final size = (w * 0.8).clamp(220.0, h * 0.6); // حجم الإطار
      final left = (w - size) / 2;
      final top = (h - size) / 2;

      return Stack(
        children: [
          // تعتيم بسيط
          Positioned.fill(child: Container(color: Colors.black26)),
          // إطار أبيض رقيق حول المربع
          Positioned(
            left: left,
            top: top,
            width: size,
            height: size,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          // تلميح
          Positioned(
            bottom: h * 0.15,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                'ضع الطعام داخل الإطار',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    });
  }
}

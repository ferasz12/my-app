// lib/screens/food_camera_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'food_ai_screen.dart';

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

/// ✅ صفحة مدفوعة: تحليل الصور
class FoodCameraScreen extends StatelessWidget {
  const FoodCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PremiumGate(
      feature: PremiumFeature.aiPhoto,
      child: _FoodCameraInner(),
    );
  }
}

/// صفحة كاميرا مخصّصة مع معاينة حيّة + إطار مربّع + زر معرض
///
/// ملاحظة مهمة:
/// كان فيه خلل يظهر بعد أول استخدام لأن CameraController كان ينتهي/يتصرف
/// وقت تغيّر حالة التطبيق أو عند الانتقال للتحليل بدون تصفيره وإغلاقه بشكل آمن.
/// لذلك صارت التهيئة والإغلاق هنا صريحة ومحمية من تداخل العمليات.
class _FoodCameraInner extends StatefulWidget {
  const _FoodCameraInner({super.key});

  @override
  State<_FoodCameraInner> createState() => _FoodCameraInnerState();
}

class _FoodCameraInnerState extends State<_FoodCameraInner>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  CameraDescription? _camera;

  bool _isBusy = false;
  bool _cameraInitFailed = false;
  bool _isDisposingCamera = false;

  int _cameraInitToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera(force: true);
  }

  Future<void> _disposeCamera() async {
    final oldController = _controller;

    // صفّر المراجع أولًا حتى لا يستخدم الـ UI أو lifecycle كنترولر تم التخلص منه.
    _controller = null;
    _initFuture = null;

    if (oldController == null) return;

    _isDisposingCamera = true;
    try {
      await oldController.dispose();
    } catch (e) {
      debugPrint('[FoodCamera] dispose skipped: $e');
    } finally {
      _isDisposingCamera = false;
    }
  }

  Future<void> _initCamera({bool force = false}) async {
    final token = ++_cameraInitToken;

    if (!mounted || _isDisposingCamera) return;

    try {
      if (!force && _controller?.value.isInitialized == true) return;

      setState(() {
        _cameraInitFailed = false;
      });

      // لو فيه كنترولر قديم، اقفله قبل إنشاء واحد جديد.
      await _disposeCamera();
      if (!mounted || token != _cameraInitToken) return;

      final cams = await availableCameras();
      if (cams.isEmpty) {
        throw CameraException('no_camera', 'No cameras found on this device.');
      }

      _camera = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final controller = CameraController(
        _camera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      final initFuture = controller.initialize();

      if (!mounted || token != _cameraInitToken) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initFuture = initFuture;
      });

      await initFuture;

      if (!mounted || token != _cameraInitToken) {
        await controller.dispose();
        return;
      }

      if (mounted) {
        setState(() {
          _cameraInitFailed = false;
        });
      }
    } catch (e) {
      debugPrint('[FoodCamera] init failed: $e');
      await _disposeCamera();
      if (!mounted || token != _cameraInitToken) return;
      setState(() {
        _cameraInitFailed = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // لا تعتمد على قيمة isInitialized القديمة؛ أحيانًا يكون الكنترولر disposed
    // ولكن المراجع ما زالت موجودة، وهذا كان يمنع فتح الكاميرا مرة ثانية.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _disposeCamera();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _initCamera(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraInitToken++;
    final oldController = _controller;
    _controller = null;
    _initFuture = null;
    try {
      oldController?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _goToAnalysis(Object fileLike) async {
    if (!mounted) return;

    // مهم جدًا: حرر الكاميرا قبل فتح شاشة التحليل حتى لا يبقى مورد الكاميرا محجوزًا.
    await _disposeCamera();
    if (!mounted) return;

    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoodAiScreen(imageFile: _ensureXFile(fileLike)),
      ),
    );

    if (!mounted) return;

    // ارجع للهوم ومع النتيجة. لو المستخدم رجع بدون نتيجة نرجع null أيضًا.
    Navigator.of(context).pop(res);
  }

  Future<void> _takePhoto() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      final controller = _controller;
      final initFuture = _initFuture;

      if (!_cameraInitFailed && controller != null && initFuture != null) {
        await initFuture;

        if (!mounted) return;

        if (controller.value.isInitialized && !controller.value.isTakingPicture) {
          final shot = await controller.takePicture();
          await _goToAnalysis(shot);
          return;
        }
      }

      // fallback: استخدم كاميرا النظام عبر image_picker
      await _openSystemCameraFallback();
    } catch (e) {
      debugPrint('[FoodCamera] take photo failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الالتقاط: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openSystemCameraFallback() async {
    try {
      await _disposeCamera();
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (x != null) {
        await _goToAnalysis(x);
      } else if (mounted) {
        // لو المستخدم لغى كاميرا النظام، أعد المعاينة الحية.
        await _initCamera(force: true);
      }
    } catch (e) {
      debugPrint('[FoodCamera] system camera fallback failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح كاميرا النظام: $e')),
      );
      await _initCamera(force: true);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (x != null) {
        await _goToAnalysis(x);
      } else if (mounted) {
        await _initCamera(force: true);
      }
    } catch (e) {
      debugPrint('[FoodCamera] gallery failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر اختيار الصورة: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('صوِّر الطعام'),
          centerTitle: false,
          actions: [
            IconButton(
              onPressed: _isBusy ? null : () => _initCamera(force: true),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'إعادة تشغيل الكاميرا',
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),
            const _SquareOverlay(),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: _isBusy ? null : _takePhoto,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _isBusy ? 0.45 : 1,
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
            ),
            if (_cameraInitFailed)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.82),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'تعذّرت تهيئة المعاينة، اضغط زر التصوير لاستخدام كاميرا النظام.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    final initFuture = _initFuture;

    if (_cameraInitFailed || controller == null || initFuture == null) {
      return Container(color: Colors.black);
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.value.isInitialized) {
          return Container(color: Colors.black);
        }
        return Center(child: CameraPreview(controller));
      },
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
          Positioned.fill(child: Container(color: Colors.black26)),
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
          Positioned(
            bottom: h * 0.15,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                'ضع الطعام داخل الإطار',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

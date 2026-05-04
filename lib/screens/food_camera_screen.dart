// lib/screens/food_camera_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'food_ai_screen.dart';

// Ensures any supported image value is treated as XFile.
XFile _ensureXFile(Object fileLike) {
  if (fileLike is XFile) return fileLike;
  if (fileLike is File) return XFile(fileLike.path);
  if (fileLike is String) return XFile(fileLike);
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

/// كاميرا تحليل الطعام.
///
/// التعديل هنا يعالج مشكلة الصفحة السوداء:
/// - لا نعرض شاشة سوداء صامتة أثناء التهيئة.
/// - أزلنا imageFormatGroup من CameraController لأنه سبب مشاكل معاينة على بعض أجهزة iOS.
/// - أضفنا timeout للتهيئة حتى لا يعلق المستخدم.
/// - أضفنا زر فلاش اختياري داخل الواجهة، ويكون مطفأ افتراضيًا.
/// - الفلاش لا يعمل كإضاءة مستمرة؛ يتم استخدامه فقط عند الالتقاط إذا فعّله المستخدم.
/// - عند فشل المعاينة نفتح كاميرا النظام كخطة بديلة، وهي فيها زر الفلاش الأصلي.
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
  bool _isInitializing = true;
  bool _cameraInitFailed = false;
  bool _isDisposingCamera = false;
  bool _flashOn = false;
  bool _autoFallbackTried = false;

  String? _initError;
  int _cameraInitToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initCamera(force: true, openFallbackIfFailed: true);
    });
  }

  Future<void> _disposeCamera() async {
    final oldController = _controller;

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

  Future<void> _initCamera({
    bool force = false,
    bool openFallbackIfFailed = false,
  }) async {
    final token = ++_cameraInitToken;

    if (!mounted || _isDisposingCamera) return;

    try {
      if (!force && _controller?.value.isInitialized == true) return;

      setState(() {
        _isInitializing = true;
        _cameraInitFailed = false;
        _initError = null;
        _flashOn = false;
      });

      await _disposeCamera();
      if (!mounted || token != _cameraInitToken) return;

      final cams = await availableCameras().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('availableCameras timeout'),
      );

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
      );

      final initFuture = controller.initialize().timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('camera initialize timeout'),
      );

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

      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('[FoodCamera] flash off skipped: $e');
      }

      if (!mounted || token != _cameraInitToken) return;

      setState(() {
        _isInitializing = false;
        _cameraInitFailed = false;
        _initError = null;
      });
    } catch (e) {
      debugPrint('[FoodCamera] init failed: $e');
      await _disposeCamera();
      if (!mounted || token != _cameraInitToken) return;

      setState(() {
        _isInitializing = false;
        _cameraInitFailed = true;
        _initError = _friendlyCameraError(e);
        _flashOn = false;
      });

      // لا نترك المستخدم على شاشة سوداء. افتح كاميرا النظام مرة واحدة تلقائيًا.
      if (openFallbackIfFailed && !_autoFallbackTried && mounted) {
        _autoFallbackTried = true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) await _openSystemCameraFallback(restartPreviewOnCancel: false);
      }
    }
  }

  String _friendlyCameraError(Object e) {
    final text = e.toString();
    if (text.contains('CameraAccessDenied') || text.contains('denied')) {
      return 'صلاحية الكاميرا غير مفعّلة. فعّلها من إعدادات الجهاز ثم جرّب مرة ثانية.';
    }
    if (text.contains('timeout')) {
      return 'تهيئة الكاميرا أخذت وقت طويل. جرّب فتح كاميرا النظام أو أعد المحاولة.';
    }
    return 'تعذّر تشغيل معاينة الكاميرا. جرّب كاميرا النظام أو أعد المحاولة.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _disposeCamera();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _initCamera(force: true, openFallbackIfFailed: false);
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

    await _disposeCamera();
    if (!mounted) return;

    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoodAiScreen(imageFile: _ensureXFile(fileLike)),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(res);
  }

  Future<void> _toggleFlash() async {
    if (_isBusy) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('انتظر تشغيل الكاميرا أولًا')),
      );
      return;
    }

    final next = !_flashOn;
    try {
      // FlashMode.always يفعّل فلاش لحظة الالتقاط فقط.
      // لا نستخدم FlashMode.torch حتى لا يكون الفلاش شغالًا طوال الوقت.
      await controller.setFlashMode(next ? FlashMode.always : FlashMode.off);
      if (!mounted) return;
      setState(() => _flashOn = next);
    } catch (e) {
      debugPrint('[FoodCamera] flash toggle failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الفلاش غير مدعوم في هذه الكاميرا')),
      );
    }
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

  Future<void> _openSystemCameraFallback({
    bool restartPreviewOnCancel = true,
  }) async {
    final wasBusy = _isBusy;
    if (!wasBusy && mounted) {
      setState(() => _isBusy = true);
    }

    try {
      await _disposeCamera();
      if (!mounted) return;

      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (x != null) {
        await _goToAnalysis(x);
      } else if (mounted && restartPreviewOnCancel) {
        await _initCamera(force: true, openFallbackIfFailed: false);
      }
    } catch (e) {
      debugPrint('[FoodCamera] system camera fallback failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح كاميرا النظام: $e')),
      );
      if (restartPreviewOnCancel) {
        await _initCamera(force: true, openFallbackIfFailed: false);
      }
    } finally {
      if (!wasBusy && mounted) {
        setState(() => _isBusy = false);
      }
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
        await _initCamera(force: true, openFallbackIfFailed: false);
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
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('صوّر الطعام'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _isBusy ? null : _toggleFlash,
              icon: Icon(_flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
              tooltip: _flashOn ? 'التصوير بدون فلاش' : 'التصوير بفلاش',
            ),
            IconButton(
              onPressed: _isBusy
                  ? null
                  : () {
                      _autoFallbackTried = false;
                      _initCamera(force: true, openFallbackIfFailed: false);
                    },
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'إعادة تشغيل الكاميرا',
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),
            const _SquareOverlay(),
            _buildTopActions(),
            _buildBottomCaptureButton(),
            if (_isBusy) _buildBusyLayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActions() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('المعرض'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.16),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : () => _openSystemCameraFallback(),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('كاميرا النظام'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.16),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

  Widget _buildBottomCaptureButton() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _isBusy ? null : _takePhoto,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _isBusy ? 0.45 : 1,
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.black.withOpacity(0.08),
                    ),
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _flashOn ? 'الفلاش مفعّل عند الالتقاط' : 'بدون فلاش - اضغط زر الفلاش عند الحاجة',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusyLayer() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x55000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'جاري فتح الكاميرا...',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    final initFuture = _initFuture;

    if (_isInitializing && controller == null) {
      return const _CameraLoadingView();
    }

    if (_cameraInitFailed || controller == null || initFuture == null) {
      return _CameraErrorView(
        message: _initError ?? 'تعذّر تشغيل الكاميرا.',
        onRetry: () {
          _autoFallbackTried = false;
          _initCamera(force: true, openFallbackIfFailed: true);
        },
        onSystemCamera: () => _openSystemCameraFallback(),
      );
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _CameraLoadingView();
        }

        if (snap.hasError || !controller.value.isInitialized) {
          return _CameraErrorView(
            message: 'تعذّر تشغيل المعاينة. جرّب كاميرا النظام.',
            onRetry: () => _initCamera(force: true, openFallbackIfFailed: true),
            onSystemCamera: () => _openSystemCameraFallback(),
          );
        }

        return _CameraPreviewCover(controller: controller);
      },
    );
  }
}

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        final previewWidth = isPortrait ? previewSize.height : previewSize.width;
        final previewHeight = isPortrait ? previewSize.width : previewSize.height;

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraLoadingView extends StatelessWidget {
  const _CameraLoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'جاري تشغيل الكاميرا...',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.message,
    required this.onRetry,
    required this.onSystemCamera,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSystemCamera;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 44),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onSystemCamera,
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('فتح الكاميرا الآن'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// طبقة شفافة مع نافذة مربعة في الوسط + تلميح.
class _SquareOverlay extends StatelessWidget {
  const _SquareOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final size = (w * 0.8).clamp(220.0, h * 0.58).toDouble();
          final left = (w - size) / 2;
          final top = (h - size) / 2;

          return Stack(
            children: [
              Positioned.fill(child: Container(color: Colors.black12)),
              Positioned(
                left: left,
                top: top,
                width: size,
                height: size,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2.2),
                  ),
                ),
              ),
              Positioned(
                bottom: h * 0.18,
                left: 0,
                right: 0,
                child: const Center(
                  child: Text(
                    'ضع الطعام داخل الإطار',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

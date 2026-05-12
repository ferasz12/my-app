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

/// كاميرا وازن لتحليل الطعام.
///
/// التعديل هنا يجعل الصفحة تفتح كاميرا واحدة فقط داخل التطبيق:
/// - لا تفتح كاميرا النظام تلقائيًا ولا يوجد زر كاميرا نظام.
/// - يوجد زر معلومات يشرح طريقة التصوير الصحيحة.
/// - يوجد زر اختيار من المعرض بجانب المعلومات.
/// - عند اختيار صورة أو التقاطها يتم إغلاق الكاميرا قبل الانتقال للتحليل لتخفيف الذاكرة.
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

  String? _initError;
  int _cameraInitToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initCamera(force: true);
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
      debugPrint('[WazenCamera] dispose skipped: $e');
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
        ResolutionPreset.medium,
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
        debugPrint('[WazenCamera] flash off skipped: $e');
      }

      if (!mounted || token != _cameraInitToken) return;

      setState(() {
        _isInitializing = false;
        _cameraInitFailed = false;
        _initError = null;
      });
    } catch (e) {
      debugPrint('[WazenCamera] init failed: $e');
      await _disposeCamera();
      if (!mounted || token != _cameraInitToken) return;

      setState(() {
        _isInitializing = false;
        _cameraInitFailed = true;
        _initError = _friendlyCameraError(e);
        _flashOn = false;
      });
    }
  }

  String _friendlyCameraError(Object e) {
    final text = e.toString();
    if (text.contains('CameraAccessDenied') || text.contains('denied')) {
      return 'صلاحية الكاميرا غير مفعّلة. فعّلها من إعدادات الجهاز ثم جرّب مرة ثانية.';
    }
    if (text.contains('timeout')) {
      return 'تشغيل كاميرا وازن أخذ وقت أطول من المعتاد. أعد المحاولة أو اختر صورة من المعرض.';
    }
    return 'تعذّر تشغيل كاميرا وازن. أعد المحاولة أو اختر صورة من المعرض.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_disposeCamera());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera(force: true));
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

    // مهم جدًا للأداء على iPhone:
    // لا نخلي صفحة الكاميرا موجودة تحت صفحة التحليل.
    // pushReplacement يجعل المسار: Home -> Analysis بدل Home -> Camera -> Analysis
    // وهذا يمنع تراكم CameraController والصورة الثقيلة في الذاكرة.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FoodAiScreen(imageFile: _ensureXFile(fileLike)),
      ),
    );
  }

  Future<void> _toggleFlash() async {
    if (_isBusy) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('انتظر تشغيل كاميرا وازن أولًا')),
      );
      return;
    }

    final next = !_flashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.always : FlashMode.off);
      if (!mounted) return;
      setState(() => _flashOn = next);
    } catch (e) {
      debugPrint('[WazenCamera] flash toggle failed: $e');
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

      if (controller == null || initFuture == null) {
        throw Exception('كاميرا وازن غير جاهزة');
      }

      await initFuture;
      if (!mounted) return;

      if (!controller.value.isInitialized) {
        throw Exception('كاميرا وازن غير جاهزة');
      }

      if (controller.value.isTakingPicture) return;

      final shot = await controller.takePicture();
      await _goToAnalysis(shot);
    } catch (e) {
      debugPrint('[WazenCamera] take photo failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الالتقاط: ${_cleanError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _cleanError(Object e) {
    final raw = e.toString();
    return raw.replaceFirst('Exception: ', '').trim();
  }

  Future<void> _pickFromGallery() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      await _disposeCamera();
      if (!mounted) return;

      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (x != null) {
        await _goToAnalysis(x);
      } else if (mounted) {
        await _initCamera(force: true);
      }
    } catch (e) {
      debugPrint('[WazenCamera] gallery failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر اختيار الصورة: ${_cleanError(e)}')),
      );
      await _initCamera(force: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showShootingTipsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'كيف تصور عشان تطلع أدق نتيجة؟',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _CameraTipTile(
                    icon: Icons.crop_free_rounded,
                    title: 'خل الوجبة كاملة داخل الإطار',
                    body: 'لا تقص أطراف الطبق أو الكوب لأن الكمية تتأثر.',
                  ),
                  const _CameraTipTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'استخدم إضاءة واضحة',
                    body: 'ابتعد عن الظل القوي أو التصوير المظلم.',
                  ),
                  const _CameraTipTile(
                    icon: Icons.zoom_out_map_rounded,
                    title: 'لا تقرّب زيادة عن اللزوم',
                    body: 'صوّر من فوق أو بزاوية بسيطة بحيث يظهر حجم الوجبة.',
                  ),
                  const _CameraTipTile(
                    icon: Icons.storefront_rounded,
                    title: 'للمطاعم: وضّح الشعار أو اسم الطلب',
                    body: 'إذا فيه كيس/علبة/فاتورة أو شعار، خله ظاهر عشان نعرف المطعم.',
                  ),
                  const _CameraTipTile(
                    icon: Icons.edit_note_rounded,
                    title: 'اكتب توضيح بعد الصورة عند الحاجة',
                    body: 'مثل: بيج ماك، بطاطس وسط، كولا دايت، أو 150 جم دجاج.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'فهمت',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
          title: const Text(
            'كاميرا وازن',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _isBusy ? null : _showShootingTipsSheet,
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'تعليمات التصوير',
            ),
            IconButton(
              onPressed: _isBusy ? null : _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: 'اختيار من المعرض',
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),
            const _WazenCameraOverlay(),
            _buildTopGuideBar(),
            _buildBottomCaptureButton(),
            if (_isBusy) _buildBusyLayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopGuideBar() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: _GlassActionButton(
                  icon: Icons.info_outline_rounded,
                  label: 'طريقة التصوير',
                  onTap: _isBusy ? null : _showShootingTipsSheet,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlassActionButton(
                  icon: Icons.photo_library_outlined,
                  label: 'اختيار من المعرض',
                  onTap: _isBusy ? null : _pickFromGallery,
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
          padding: const EdgeInsets.only(left: 18, right: 18, bottom: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundToolButton(
                    icon: _flashOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    label: _flashOn ? 'فلاش' : 'بدون فلاش',
                    onTap: _isBusy ? null : _toggleFlash,
                  ),
                  const SizedBox(width: 22),
                  GestureDetector(
                    onTap: _isBusy ? null : _takePhoto,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _isBusy ? 0.45 : 1,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: Colors.white.withOpacity(0.10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.30),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  _RoundToolButton(
                    icon: Icons.refresh_rounded,
                    label: 'تحديث',
                    onTap: _isBusy ? null : () => _initCamera(force: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'صوّر الوجبة كاملة وبوضوح',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontWeight: FontWeight.w800,
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
        color: const Color(0x66000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.74),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(.10)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'جاري تجهيز كاميرا وازن...',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
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
        message: _initError ?? 'تعذّر تشغيل كاميرا وازن.',
        onRetry: () => _initCamera(force: true),
        onGallery: _pickFromGallery,
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
            message: 'تعذّر تشغيل المعاينة. أعد المحاولة أو اختر صورة من المعرض.',
            onRetry: () => _initCamera(force: true),
            onGallery: _pickFromGallery,
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
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 14),
            Text(
              'جاري تشغيل كاميرا وازن...',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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
    required this.onGallery,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(22),
      child: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.10),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  'كاميرا وازن غير جاهزة',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.82),
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onGallery,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(.35)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('اختيار من المعرض'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
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

class _RoundToolButton extends StatelessWidget {
  const _RoundToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _CameraTipTile extends StatelessWidget {
  const _CameraTipTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
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

/// طبقة شفافة مع نافذة مربعة في الوسط + تلميح.
class _WazenCameraOverlay extends StatelessWidget {
  const _WazenCameraOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final size = (w * 0.82).clamp(230.0, h * 0.58).toDouble();
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
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white, width: 2.4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.22),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: h * 0.18,
                left: 18,
                right: 18,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.40),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(.14)),
                    ),
                    child: const Text(
                      'ضع الطعام داخل الإطار بوضوح',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
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

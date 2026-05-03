import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// ✅ قص أفتار بدون أي باكج إضافي.
/// - يدعم Mobile + Web
/// - قص دائري (PNG مع شفافية)
///
/// الاستخدام:
/// final cropped = await Navigator.push<Uint8List>(context,
///   MaterialPageRoute(builder: (_) => AvatarCropperPage(imageBytes: bytes))
/// );
class AvatarCropperPage extends StatefulWidget {
  final Uint8List imageBytes;
  const AvatarCropperPage({super.key, required this.imageBytes});

  @override
  State<AvatarCropperPage> createState() => _AvatarCropperPageState();
}

class _AvatarCropperPageState extends State<AvatarCropperPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _tx = TransformationController();

  double _zoom = 1.0;
  bool _saving = false;

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  void _setZoom(double value) {
    setState(() => _zoom = value);
    final m = Matrix4.identity()..scale(_zoom);
    _tx.value = m;
  }

  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        if (mounted) Navigator.pop(context);
        return;
      }

      // pixelRatio 2 لتوازن الجودة والحجم
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();

      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cropSize = (size.shortestSide - 48).clamp(220.0, 360.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('قص الأفتار'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _done,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('تم', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // ✅ منطقة القص نفسها
                    RepaintBoundary(
                      key: _boundaryKey,
                      child: ClipOval(
                        child: SizedBox(
                          width: cropSize,
                          height: cropSize,
                          child: InteractiveViewer(
                            transformationController: _tx,
                            minScale: 1,
                            maxScale: 4,
                            boundaryMargin: const EdgeInsets.all(9999),
                            child: Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ✅ إطار خفيف فوق القص
                    IgnorePointer(
                      child: Container(
                        width: cropSize,
                        height: cropSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.85), width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      min: 1,
                      max: 4,
                      divisions: 30,
                      onChanged: _saving ? null : _setZoom,
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white70),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

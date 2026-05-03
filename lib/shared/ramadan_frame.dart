import 'dart:math' as math;

import 'package:flutter/material.dart';

/// إطار زخرفي رمضاني خفيف يضاف فوق كل الصفحات عند تفعيل مظهر رمضان.
///
/// - لا يؤثر على اللمس (IgnorePointer)
/// - مرن مع SafeArea
class RamadanFrame extends StatelessWidget {
  final Widget child;
  const RamadanFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SizedBox(
              height: topPad + 160,
              child: CustomPaint(
                painter: _LanternStringPainter(topPadding: topPad),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanternStringPainter extends CustomPainter {
  final double topPadding;
  _LanternStringPainter({required this.topPadding});

  @override
  void paint(Canvas canvas, Size size) {
    // ألوان قريبة من المرجع
    final wire = Paint()
      ..color = const Color(0xFF6B4E3D).withOpacity(0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final dot = Paint()
      ..color = const Color(0xFF6B4E3D).withOpacity(0.28)
      ..style = PaintingStyle.fill;

    final lantern = Paint()
      ..color = const Color(0xFF6B4E3D).withOpacity(0.55)
      ..style = PaintingStyle.fill;

    final baseY = topPadding + 12;
    final w = size.width;

    // 3 أسلاك منحنية
    for (int i = 0; i < 3; i++) {
      final y = baseY + 18.0 * i;
      final p = Path();
      p.moveTo(-12, y);
      p.cubicTo(w * 0.25, y + 20 + 6 * i, w * 0.65, y - 14 + 6 * i, w + 12, y + 10);
      canvas.drawPath(p, wire);

      // نقاط/لمبات صغيرة على السلك
      for (int k = 0; k < 9; k++) {
        final t = (k + 1) / 10.0;
        final x = w * t;
        // نحاكي الانحناء تقريباً
        final yy = y + math.sin((t * math.pi * 1.1) + i) * (10 + i * 2);
        canvas.drawCircle(Offset(x, yy), 4.2, dot);
      }
    }

    // فوانيس بسيطة
    final lanternXs = <double>[w * 0.12, w * 0.36, w * 0.58, w * 0.82];
    final lanternYs = <double>[baseY + 32, baseY + 58, baseY + 40, baseY + 66];

    for (int i = 0; i < lanternXs.length; i++) {
      _drawLantern(
        canvas,
        center: Offset(lanternXs[i], lanternYs[i]),
        paint: lantern,
        wirePaint: wire,
      );
    }
  }

  void _drawLantern(
    Canvas canvas, {
    required Offset center,
    required Paint paint,
    required Paint wirePaint,
  }) {
    // خيط صغير للأعلى
    canvas.drawLine(
      Offset(center.dx, center.dy - 32),
      Offset(center.dx, center.dy - 18),
      wirePaint..strokeWidth = 1.6,
    );

    // جسم الفانوس
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 24, height: 34),
      const Radius.circular(7),
    );
    canvas.drawRRect(body, paint);

    // سقف
    final roof = Path();
    roof.moveTo(center.dx - 12, center.dy - 18);
    roof.lineTo(center.dx, center.dy - 30);
    roof.lineTo(center.dx + 12, center.dy - 18);
    roof.close();
    canvas.drawPath(roof, paint);

    // قاعدة
    final base = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 20), width: 22, height: 10),
      const Radius.circular(6),
    );
    canvas.drawRRect(base, paint);

    // نافذة داخلية (تفريغ بسيط)
    final cut = Paint()
      ..color = Colors.white.withOpacity(0.20)
      ..style = PaintingStyle.fill;
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 1), width: 12, height: 18),
      const Radius.circular(4),
    );
    canvas.drawRRect(window, cut);
  }

  @override
  bool shouldRepaint(covariant _LanternStringPainter oldDelegate) {
    return oldDelegate.topPadding != topPadding;
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// إطار رمضاني خفيف أعلى التطبيق (بدون صور) — فوانيس + أسلاك.
/// يُستخدم فقط عند اختيار AppThemeId.ramadan.
class RamadanFrame extends StatelessWidget {
  final Widget child;
  const RamadanFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    // مساحة الزينة (مع مراعاة النوتش)
    final h = 110.0 + (topPad > 0 ? math.min(24.0, topPad) : 0);

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: h,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RamadanTopPainter(),
            ),
          ),
        ),
      ],
    );
  }
}

class _RamadanTopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final wire = Paint()
      ..color = const Color(0xFF8B6B4E).withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final bulb = Paint()
      ..color = const Color(0xFF8B6B4E).withOpacity(0.28)
      ..style = PaintingStyle.fill;

    // 3 أسلاك مقوسة
    void curve(double y, double amp, double phase) {
      final p = Path()..moveTo(-12, y);
      for (double x = -12; x <= w + 12; x += 12) {
        final t = x / w * math.pi * 2;
        final yy = y + math.sin(t + phase) * amp;
        p.lineTo(x, yy);
      }
      canvas.drawPath(p, wire);

      // لمبات صغيرة
      for (int i = 0; i < 10; i++) {
        final x = (w / 10) * i + (i.isEven ? 8 : -4);
        final t = x / w * math.pi * 2;
        final yy = y + math.sin(t + phase) * amp;
        canvas.drawCircle(Offset(x, yy), 5.2, bulb);
        canvas.drawCircle(Offset(x, yy), 2.0, wire..strokeWidth = 1.0);
        wire.strokeWidth = 1.6;
      }
    }

    curve(h * 0.22, 10, 0.4);
    curve(h * 0.32, 12, 1.2);
    curve(h * 0.42, 9, 2.0);

    // فوانيس بسيطة (أيقونة مرسومة)
    void lantern(Offset c, double s) {
      final body = Paint()
        ..color = const Color(0xFF6F5238).withOpacity(0.9)
        ..style = PaintingStyle.fill;

      final stroke = Paint()
        ..color = const Color(0xFF3B2A1A).withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      // تعليقة
      canvas.drawLine(c + Offset(0, -26 * s), c + Offset(0, -16 * s), stroke);

      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c + Offset(0, -2 * s), width: 18 * s, height: 26 * s),
        Radius.circular(4 * s),
      );
      canvas.drawRRect(r, body);
      canvas.drawRRect(r, stroke);

      // فتحات
      final window = Paint()
        ..color = const Color(0xFFF3EFE7).withOpacity(0.55)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + Offset(0, -2 * s), width: 8 * s, height: 14 * s),
          Radius.circular(2.8 * s),
        ),
        window,
      );

      // قاعدة وغطاء
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + Offset(0, -16 * s), width: 14 * s, height: 6 * s),
          Radius.circular(3 * s),
        ),
        body,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + Offset(0, 12 * s), width: 14 * s, height: 6 * s),
          Radius.circular(3 * s),
        ),
        body,
      );
    }

    lantern(Offset(w * 0.12, h * 0.18), 0.9);
    lantern(Offset(w * 0.48, h * 0.30), 0.8);
    lantern(Offset(w * 0.86, h * 0.22), 0.95);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

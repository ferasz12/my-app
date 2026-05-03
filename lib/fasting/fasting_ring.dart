// =============================================================
// FILE: lib/fasting/fasting_ring.dart
// مؤشّر دائري واضح: مسار خلفي فاتح + تقدّم باللون الأحمر (من الثيم)
// =============================================================
import 'package:flutter/material.dart';

class FastingRing extends StatelessWidget {
  final double percent; // 0..1
  final String centerTop;     // نص علوي داخل الدائرة (مثلاً: المتبقي 05:12)
  final String centerBottom;  // نص سفلي (مثلاً: ينتهي 2:30 م)
  const FastingRing({
    super.key,
    required this.percent,
    required this.centerTop,
    required this.centerBottom,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0.0, 1.0);
    final cs = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _RingPainter(
          progress: p,
          bgColor: cs.surfaceVariant.withOpacity(0.45),
          fgColor: cs.error, // أحمر من الثيم
          strokeWidth: 14,
        ),
        child: Center(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  centerTop,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  centerBottom,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;   // 0..1
  final Color bgColor;
  final Color fgColor;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.bgColor,
    required this.fgColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth;

    final bg = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fg = Paint()
      ..color = fgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const deg2rad = 3.141592653589793 / 180.0;

    // المسار الخلفي
    canvas.drawArc(rect, -90 * deg2rad, 360 * deg2rad, false, bg);
    // التقدم
    canvas.drawArc(rect, -90 * deg2rad, (360 * progress) * deg2rad, false, fg);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// lib/widgets/points_earned_toast.dart
// Drop-in replacement (خفيف جدًا) لويدجت النقاط: نفس API السابقة
// PointsEarnedToast.show(context, points: 10, title: '...', message: '...', icon: ...)
// يعتمد SnackBar عائم يشبه البطاقة — بدون Overlay أو مؤثرات — بدون أي حزم خارجية.

import 'package:flutter/material.dart';

class PointsEarnedToast {
  /// إظهار بطاقة نقاط خفيفة جدًا بأسلوب SnackBar عائم.
  /// نفس التوقيع السابق لضمان التوافق.
  static void show(
    BuildContext context, {
    required int points,
    String title = 'تم إضافة نقاط',
    String? message,
    Duration duration = const Duration(seconds: 2),
    IconData icon = Icons.check_circle_rounded,
    bool withConfetti = true, // غير مستخدمة هنا — للإبقاء على التوافق
    VoidCallback? onDismissed,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // أيقونة داخل كبسولة صغيرة
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: cs.primary, size: 22),
        ),
        const SizedBox(width: 10),
        // نصوص: العنوان + السبب
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((message ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.9),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        // شارة النقاط
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '+$points',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final bar = SnackBar(
      content: Directionality(
        textDirection: Directionality.of(context), // يحترم RTL/LTR
        child: content,
      ),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.surface, // يشبه لون البطاقة
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant, width: 1),
      ),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    );

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(bar).closed.whenComplete(() {
        if (onDismissed != null) onDismissed();
      });
  }
}

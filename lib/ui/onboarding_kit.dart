import 'dart:ui';
import 'package:flutter/material.dart';

/// أدوات تصميم موحّدة لصفحات الأونبوردنق/التسجيل (UI فقط)
class OnboardingKit {
  // ألوان وازن الأساسية كقيمة احتياطية فقط.
  // الصفحات الآن تقرأ ألوانها من Theme.of(context) عند توفر السياق.
  static const Color primary = Color(0xFF0B6E6A);
  static const Color bgTop = Color(0xFFEAF7F2);
  static const Color bgBottom = Color(0xFF86B8B0);
  static const Color cardBg = Color(0xFFF3FAF7);
  static const Color cardBorder = Color(0xFFD3E2DE);
  static const Color textMuted = Color(0xFF6F7D7A);

  static const double cardRadius = 34;

  static Color primaryOf(BuildContext context) => Theme.of(context).colorScheme.primary;

  static Color mutedTextOf(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  static Color _softSurface(BuildContext context, {double primaryOpacity = 0.04}) {
    final cs = Theme.of(context).colorScheme;
    return Color.alphaBlend(cs.primary.withOpacity(primaryOpacity), cs.surface);
  }

  static Widget background({required Widget child}) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;

        final top = isDark
            ? cs.background
            : Color.alphaBlend(cs.primary.withOpacity(0.08), cs.surface);
        final bottom = isDark
            ? cs.surface
            : Color.alphaBlend(cs.primary.withOpacity(0.18), cs.surfaceContainerHighest);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -120,
                left: -120,
                child: _BlurBlob(
                  color: cs.surface,
                  size: 260,
                  sigma: 28,
                  opacity: isDark ? 0.08 : 0.24,
                ),
              ),
              Positioned(
                bottom: -140,
                right: -140,
                child: _BlurBlob(
                  color: isDark ? cs.surfaceVariant : cs.primary,
                  size: 320,
                  sigma: 32,
                  opacity: isDark ? 0.10 : 0.12,
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }

  static Widget card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.fromLTRB(22, 22, 22, 18),
  }) {
    return Builder(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: _softSurface(context, primaryOpacity: 0.035),
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.65), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.06),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }

  static Widget logo({double width = 240, double height = 90}) {
    return Hero(
      tag: 'app_logo',
      child: Image.asset(
        'assets/images/app_logo.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  static ButtonStyle primaryButtonStyle(TextTheme tt, {BuildContext? context}) {
    final cs = context == null ? null : Theme.of(context).colorScheme;
    return ElevatedButton.styleFrom(
      backgroundColor: cs?.primary ?? primary,
      foregroundColor: cs?.onPrimary ?? Colors.white,
      disabledBackgroundColor: cs?.onSurface.withOpacity(0.12),
      disabledForegroundColor: cs?.onSurface.withOpacity(0.38),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: (tt.titleMedium ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    );
  }

  static ButtonStyle secondaryButtonStyle(TextTheme tt, {BuildContext? context}) {
    final cs = context == null ? null : Theme.of(context).colorScheme;
    final color = cs?.primary ?? primary;
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withOpacity(0.55), width: 1.2),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: (tt.titleMedium ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    );
  }

  static InputDecoration inputDecoration({
    BuildContext? context,
    required String label,
    IconData? icon,
    String? hint,
    Widget? suffixIcon,
    String? helperText,
  }) {
    final cs = context == null ? null : Theme.of(context).colorScheme;
    final fill = context == null ? Colors.white.withOpacity(0.88) : _softSurface(context, primaryOpacity: 0.025);
    final borderColor = cs?.outlineVariant ?? cardBorder;
    final focusedColor = cs?.primary ?? primary;
    final textColor = cs?.onSurfaceVariant;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      prefixIcon: icon == null ? null : Icon(icon, color: textColor),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: borderColor, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: borderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: focusedColor, width: 1.4),
      ),
    );
  }

  static Widget softDividerOr(TextTheme tt, {BuildContext? context}) {
    final cs = context == null ? null : Theme.of(context).colorScheme;
    final lineColor = (cs?.outlineVariant ?? Colors.black).withOpacity(0.45);
    final labelColor = cs?.onSurfaceVariant ?? textMuted;
    return Row(
      children: [
        Expanded(child: Divider(color: lineColor, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'أو',
            style: (tt.bodyMedium ?? const TextStyle()).copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: lineColor, thickness: 1)),
      ],
    );
  }
}

class _BlurBlob extends StatelessWidget {
  final Color color;
  final double size;
  final double sigma;
  final double opacity;
  const _BlurBlob({
    required this.color,
    required this.size,
    required this.sigma,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(opacity),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

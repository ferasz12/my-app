import 'dart:ui';
import 'package:flutter/material.dart';

/// أدوات تصميم موحّدة لصفحات الأونبوردنق/التسجيل (UI فقط)
class OnboardingKit {
  // Palette مطابق للمرجع
  static const Color primary = Color(0xFF0B6E6A);
  static const Color bgTop = Color(0xFFEAF7F2);
  static const Color bgBottom = Color(0xFF86B8B0);
  static const Color cardBg = Color(0xFFF3FAF7);
  static const Color cardBorder = Color(0xFFD3E2DE);
  static const Color textMuted = Color(0xFF6F7D7A);

  static const double cardRadius = 34;

  static Widget background({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgTop, bgBottom],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -120,
            left: -120,
            child: _BlurBlob(color: Colors.white, size: 260, sigma: 28, opacity: 0.18),
          ),
          const Positioned(
            bottom: -140,
            right: -140,
            child: _BlurBlob(color: primary, size: 320, sigma: 32, opacity: 0.12),
          ),
          child,
        ],
      ),
    );
  }

  static Widget card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.fromLTRB(22, 22, 22, 18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
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

  static ButtonStyle primaryButtonStyle(TextTheme tt) {
    return ElevatedButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: (tt.titleMedium ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    );
  }

  static ButtonStyle secondaryButtonStyle(TextTheme tt) {
    return OutlinedButton.styleFrom(
      foregroundColor: primary,
      side: BorderSide(color: primary.withOpacity(0.55), width: 1.2),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: (tt.titleMedium ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    );
  }

  static InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    String? hint,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withOpacity(0.88),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: cardBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: cardBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: primary, width: 1.4),
      ),
    );
  }

  static Widget softDividerOr(TextTheme tt) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.black.withOpacity(0.12), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'أو',
            style: (tt.bodyMedium ?? const TextStyle()).copyWith(
              color: textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.black.withOpacity(0.12), thickness: 1)),
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

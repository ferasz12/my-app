import 'package:flutter/material.dart';

/// أيقونة الشريط السفلي بدون أي صور أو SVG.
///
/// هذا الكلاس لا يقرأ من ملفات خارجية نهائيًا.
class WazenNavIcon extends StatelessWidget {
  final String name;
  final IconData fallbackIcon;
  final bool selected;
  final double size;

  const WazenNavIcon({
    super.key,
    required this.name,
    required this.fallbackIcon,
    this.selected = false,
    this.size = 25,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    final iconSize = selected ? size + 2 : size;

    return Icon(
      fallbackIcon,
      color: color,
      size: iconSize,
    );
  }
}

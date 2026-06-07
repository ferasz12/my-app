import 'package:flutter/material.dart';

/// أيقونة الشريط السفلي مع دعم صور مخصصة.
///
/// ضع صورك داخل:
/// assets/nav/
///
/// الأسماء المطلوبة:
/// home.png / home_selected.png
/// my_data.png / my_data_selected.png
/// tracking.png / tracking_selected.png
/// regimen.png / regimen_selected.png
/// guide.png / guide_selected.png
/// achievements.png / achievements_selected.png
/// settings.png / settings_selected.png
///
/// وإذا ما كانت الصور موجودة يرجع تلقائيًا لأيقونات وازن الأصلية.
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

  String get _path => 'assets/nav/${name}${selected ? '_selected' : ''}.png';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallbackColor = selected ? cs.primary : cs.onSurfaceVariant;
    final iconSize = selected ? size + 3 : size;

    return Image.asset(
      _path,
      width: iconSize,
      height: iconSize,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        fallbackIcon,
        color: fallbackColor,
        size: iconSize,
      ),
    );
  }
}

import 'package:flutter/material.dart';

class WazenCoachAvatar extends StatelessWidget {
  final double size;
  final bool headOnly;
  final bool withCircle;

  const WazenCoachAvatar({
    super.key,
    this.size = 40,
    this.headOnly = true,
    this.withCircle = true,
  });

  String get _assetPath => headOnly
      ? 'assets/images/wazen_coach_head.png'
      : 'assets/images/wazen_coach_full.png';

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      _assetPath,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return Icon(
          Icons.psychology_alt_rounded,
          size: size * 0.58,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        );
      },
    );

    final content = SizedBox(
      width: size,
      height: size,
      child: headOnly ? ClipOval(child: image) : image,
    );

    if (!withCircle) return content;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

// lib/screens/splash_screen.dart
// شاشة سبلّاش "عرض فقط": بدون أي Navigator أو Firebase.
// استخدم نفس الثوابت في AuthGate لضمان تزامن المدة.

import 'package:flutter/material.dart';

// ✅ ثوابت المدة (استعمل نفس القيم في AuthGate)
const int kSplashAnimMs = 1800;       // مدة الأنيميشن الكاملة
const int kSplashPostDelayMs = 300;   // تأخير بسيط بعد الأنيميشن
const int kSplashTotalMs = kSplashAnimMs + kSplashPostDelayMs;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade1;
  late final Animation<double> _fade2;
  late final Animation<double> _fade3;
  late final Animation<double> _fade4;

  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;
  late final Animation<Offset> _slide4;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kSplashAnimMs),
    );

    _fade1 = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.00, 0.40, curve: Curves.easeOut),
    );
    _fade2 = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.20, 0.60, curve: Curves.easeOut),
    );
    _fade3 = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.40, 0.80, curve: Curves.easeOut),
    );
    _fade4 = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.60, 1.00, curve: Curves.easeOut),
    );

    _slide1 = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.00, 0.40, curve: Curves.easeOutBack)),
    );
    _slide2 = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.20, 0.60, curve: Curves.easeOutBack)),
    );
    _slide3 = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.40, 0.80, curve: Curves.easeOutBack)),
    );
    _slide4 = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.60, 1.00, curve: Curves.easeOutBack)),
    );

    // شغّل الأنيميشن — بدون أي توجيه هنا
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.primary,
      body: SafeArea(
        child: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 360;
                final fontSize = isSmall ? 56.0 : 72.0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // عنوان متحرك "وازن" حرفًا حرفًا
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DropLetter(letter: 'و', slide: _slide1, fade: _fade1, size: fontSize),
                        const SizedBox(width: 6),
                        _DropLetter(letter: 'ا', slide: _slide2, fade: _fade2, size: fontSize),
                        const SizedBox(width: 6),
                        _DropLetter(letter: 'ز', slide: _slide3, fade: _fade3, size: fontSize),
                        const SizedBox(width: 6),
                        _DropLetter(letter: 'ن', slide: _slide4, fade: _fade4, size: fontSize),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // السطر التعريفي
                    FadeTransition(
                      opacity: _fade4,
                      child: Text(
                        'وازن اكلك… واحسب سعراتك ',
                        style: TextStyle(
                          color: cs.onPrimary.withOpacity(.9),
                          fontSize: isSmall ? 14 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // ===== [إضافة] شارة "صُنع في السعودية" + "تطبيق وازن" =====
                    const SizedBox(height: 20),
                    FadeTransition(
                      opacity: _fade4,
                      child: _SaudiMadeBadge(
                        // حجم الأيقونة متجاوب حسب العنوان
                        iconSize: isSmall ? 22 : 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeTransition(
                      opacity: _fade4,
                      child: Text(
                        'تطبيق وازن',
                        style: TextStyle(
                          color: cs.onPrimary.withOpacity(.85),
                          fontSize: isSmall ? 11 : 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DropLetter extends StatelessWidget {
  final String letter;
  final Animation<Offset> slide;
  final Animation<double> fade;
  final double size;

  const _DropLetter({
    required this.letter,
    required this.slide,
    required this.fade,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: Text(
          letter,
          style: TextStyle(
            color: cs.onPrimary,
            fontSize: size,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// شارة "صُنع في السعودية" مع دعم صورة علامة من الأصول.
/// ضع صورتك (اختياري) هنا: assets/saudi_made/saudi_made.png وأضِفها في pubspec.yaml.
/// إن لم توجد الصورة، تظهر أيقونة بديلة تلقائيًا.
class _SaudiMadeBadge extends StatelessWidget {
  final double iconSize;
  const _SaudiMadeBadge({required this.iconSize});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.onPrimary.withOpacity(.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: cs.onPrimary.withOpacity(.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // جرّب تحميل العلامة من الأصول، وإلا استخدم أيقونة بديلة
          _SaudiMadeMark(size: iconSize),
          const SizedBox(width: 8),
          Text(
            'صُنع في السعودية',
            style: TextStyle(
              color: cs.onPrimary,
              fontSize: iconSize * 0.48, // متوازن مع حجم الأيقونة
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaudiMadeMark extends StatelessWidget {
  final double size;
  const _SaudiMadeMark({required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Image.asset(
      'assets/saudi_made/saudi_made.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      // fallback لو ما كانت الصورة مضافة
      errorBuilder: (_, __, ___) => Icon(
        Icons.verified_rounded,
        size: size * 0.95,
        color: cs.onPrimary,
      ),
    );
  }
}

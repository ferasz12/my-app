// lib/screens/welcome_screen.dart
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';

// يُفضَّل استخدام استيراد بصيغة package لتفادي مشاكل المسارات
import 'package:my_app/screens/login_page.dart';
import 'package:my_app/screens/register_page.dart';

import '../services/auth/social_auth.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  bool get _isAppleSignInAvailable {
    // يعمل على iOS/macOS فقط (تجاهل لو على أندرويد)
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // خلفية فاخرة: تدرّج + أشكال شفافة
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    cs.primary.withOpacity(.08),
                    cs.primaryContainer.withOpacity(.14),
                    cs.surfaceVariant.withOpacity(.06),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: _SoftBlob(color: cs.primary.withOpacity(.16), size: 220),
          ),
          Positioned(
            bottom: -90,
            left: -50,
            child: _SoftBlob(color: cs.secondary.withOpacity(.12), size: 260),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                children: [
                  const SizedBox(height: 6),

                  // عنوان رئيسي أنيق
                  _GlassHeader(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'مرحبًا بك في وازن',
                          textAlign: TextAlign.center,
                          style: tt.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'وازن صحتك ببساطة وأناقة',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // بطاقة أزرار التسجيل الاجتماعية/البريد — تصميم زجاجي
                  _GlassCard(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      children: [
                        // إنشاء حساب → RegisterPage (نفس المنطق)
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              textStyle: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegisterPage()),
                              );
                            },
                            child: const Text('إنشاء حساب'),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // فاصل بسيط
                        Row(
                          children: [
                            Expanded(child: Divider(color: cs.outlineVariant)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'أو',
                                style: tt.labelMedium?.copyWith(
                                  color: cs.outline,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: cs.outlineVariant)),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // زر Google (نفس المنطق)
                        _socialButton(
                          context,
                          label: 'التسجيل عبر Google',
                          icon: Icons.g_mobiledata, // يمكن لاحقًا استبداله بأيقونة Google SVG
                          background: cs.surface,
                          border: cs.outlineVariant,
                          foreground: tt.labelLarge?.color ?? cs.onSurface,
                          onPressed: () => SocialAuth.signInWithGoogle(context),
                        ),

                        const SizedBox(height: 10),

                        // زر Apple على iOS/macOS فقط (نفس المنطق)
                        if (_isAppleSignInAvailable)
                          _socialButton(
                            context,
                            label: 'التسجيل عبر Apple',
                            icon: Icons.apple,
                            background: Colors.black,
                            border: Colors.black,
                            foreground: Colors.white,
                            onPressed: () => SocialAuth.signInWithApple(context),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // سطر تسجيل الدخول (نفس المنطق)
                  _GlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      children: [
                        Text(
                          'لديك حساب بالفعل؟',
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: cs.primary, width: 1.2),
                              foregroundColor: cs.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginPage()),
                              );
                            },
                            icon: const Icon(Icons.login),
                            label: const Text('تسجيل الدخول'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color background,
    required Color border,
    required Color foreground,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: border),
          ),
        ),
      ),
    );
  }
}

/// بطاقة زجاجية عامة
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(.4)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// هيدر زجاجي أنيق
class _GlassHeader extends StatelessWidget {
  final Widget child;
  const _GlassHeader({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// عنصر خلفية ناعم
class _SoftBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _SoftBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        boxShadow: [
          BoxShadow(color: color.withOpacity(.35), blurRadius: 40, spreadRadius: 10),
        ],
        shape: BoxShape.circle,
      ),
    );
  }
}

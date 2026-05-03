import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:my_app/screens/login_page.dart';
import 'package:my_app/screens/register_page.dart';
import 'package:my_app/settings/privacy_page.dart';

import '../services/auth/social_auth.dart';
import '../services/auth_service.dart';
import '../services/auth/recent_accounts_store.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {

  static const String _kHeroAssetPath = 'assets/images/app_logo.png';

  bool get _isAppleSignInAvailable {
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false; // Web
    }
  }

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  List<RecentAccount> _recent = const <RecentAccount>[];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final list = await RecentAccountsStore.load();
      if (!mounted) return;
      setState(() {
        _recent = list;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = const <RecentAccount>[];
        _loadingRecent = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _removeRecent(String uid) async {
    await RecentAccountsStore.removeByUid(uid);
    await _loadRecent();
  }

  Future<void> _switchToAccount(RecentAccount acc) async {
    // حساب بريد/كلمة مرور: لا يمكن تسجيل دخول صامت (بدون حفظ كلمة مرور)
    if (acc.providerId == 'password') {
      try {
        Navigator.of(context).pushNamed('/login', arguments: {'prefillEmail': acc.email});
      } catch (_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        // لا نقدر نمرر الإيميل في هذا المسار بدون تعديل LoginPage route، لكن عندك /login موجود.
      }
      if ((acc.email).trim().isNotEmpty) {
        _snack('تم تعبئة البريد — أدخل كلمة المرور لإكمال الدخول');
      }
      return;
    }

    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);

    // Loader
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: const [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6)),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'جاري تبديل الحساب…',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    String? error;

    try {
      // 1) تسجيل خروج كامل لمنع تداخل البيانات بين حسابين
      await AuthService.signOut();

      // 2) تسجيل دخول حسب المزود
      if (acc.providerId == 'google.com') {
        await AuthService.signInWithGoogle(context: context);
      } else if (acc.providerId == 'apple.com') {
        await AuthService.signInWithApple(context: context);
      } else {
        // مزود غير معروف: نفتح صفحة تسجيل الدخول العامة
        error = 'هذا النوع من الحسابات يحتاج تسجيل دخول يدوي من صفحة الدخول.';
      }
    } on FirebaseAuthException catch (e) {
      error = _mapSwitchError(e);

      // حالات نفضّل فيها حذف الحساب من "الحسابات السابقة" لأنه لم يعد صالحاً
      final c = e.code.toLowerCase();
      final shouldRemove = c == 'user-disabled' || c == 'user-not-found' || c == 'invalid-credential';
      if (shouldRemove) {
        // Best-effort
        // ignore: unawaited_futures
        _removeRecent(acc.uid);
      }
    } catch (e) {
      error = 'حدث خطأ غير متوقع: $e';
    } finally {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await nav.maybePop();
      } catch (_) {}
    }

    if (error != null) {
      _snack(error);
      return;
    }

    // نجاح: ارجع للجذر (AuthGate يقرر الوجهة)
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      nav.pushNamedAndRemoveUntil('/', (route) => false);
    } catch (_) {}
  }

  String _mapSwitchError(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    switch (code) {
      // ✅ حالات شائعة عند محاولة الدخول بحساب لم يعد صالحاً
      case 'user-not-found':
        return 'هذا الحساب غير موجود (قد يكون محذوفًا).';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب.';
      case 'invalid-credential':
      case 'invalid-email':
        return 'بيانات الدخول غير صالحة. جرّب تسجيل الدخول من جديد.';

      // ✅ حالات المزود/الطريقة
      case 'account-exists-with-different-credential':
        return 'هذا البريد مسجّل بطريقة دخول مختلفة. جرّب الدخول بالطريقة السابقة.';
      case 'operation-not-allowed':
        return 'مزود تسجيل الدخول غير مفعّل.';

      // ✅ الشبكة/الإلغاء
      case 'network-request-failed':
        return 'مشكلة في الاتصال. تأكد من الشبكة ثم حاول مرة أخرى.';
      case 'canceled':
      case 'popup-closed-by-user':
        return 'تم الإلغاء.';

      default:
        return e.message ?? 'تعذّر تبديل الحساب.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final primary = scheme.primary;
    final base = isDark ? scheme.surface : Colors.white;

    // خلفية صحية ناعمة تتكيّف مع الثيم وتعطي الصفحة طابع وازن الأصلي
    final bgTop = _mix(base, primary, isDark ? 0.16 : 0.08);
    final bgBottom = _mix(base, primary, isDark ? 0.34 : 0.34);
    final cardBg = _mix(base, primary, isDark ? 0.12 : 0.045);
    final cardBorder = _mix(base, primary, isDark ? 0.28 : 0.16);

    final titleColor = isDark ? scheme.onSurface : Colors.black.withOpacity(0.88);
    final mutedColor = isDark ? scheme.onSurface.withOpacity(0.70) : Colors.black.withOpacity(0.55);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, _mix(bgTop, bgBottom, 0.55), bgBottom],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(
            children: [
              PositionedDirectional(
                top: -90,
                end: -80,
                child: _SoftGlowCircle(color: primary.withOpacity(isDark ? 0.18 : 0.16), size: 210),
              ),
              PositionedDirectional(
                top: 190,
                start: -95,
                child: _SoftGlowCircle(color: scheme.secondary.withOpacity(isDark ? 0.14 : 0.12), size: 230),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // الصفحة صارت ثابتة بدون Scroll، لذلك نستخدم قياسات مرنة
                    // حتى ما تصير طويلة أو تسمح للمستخدم ينزل تحت.
                    final compact = constraints.maxHeight < 720;
                    final heroHeight = compact ? 205.0 : 232.0;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 6),

                          // ===== صورة الترحيب فقط بدون عبارات إضافية =====
                          Center(
                            child: _ThemedWelcomeHero(
                              assetPath: _kHeroAssetPath,
                              color: primary,
                              isDark: isDark,
                              height: heroHeight,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // ===== بطاقة الأزرار =====
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  width: constraints.maxWidth - 40,
                                  child: _WelcomeCard(
                                    title: 'وازن أكلك واحسب سعراتك',
                                    subtitle: '',
                                    titleStyle: (tt.headlineSmall ?? const TextStyle()).copyWith(
                                      fontWeight: FontWeight.w900,
                                      fontSize: compact ? 24 : 27,
                                      height: 1.18,
                                      color: titleColor,
                                    ),
                                    subtitleStyle: (tt.bodyLarge ?? const TextStyle()).copyWith(
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                      color: mutedColor,
                                    ),
                                    cardBg: cardBg,
                                    cardBorder: cardBorder,
                                    primary: primary,
                                    isAppleAvailable: _isAppleSignInAvailable,
                                    // في الشاشات القصيرة نخفي الحسابات السابقة عشان تبقى الصفحة ثابتة.
                                    recentAccounts: compact ? const <RecentAccount>[] : _recent,
                                    loadingRecent: compact ? false : _loadingRecent,
                                    onPickRecent: _switchToAccount,
                                    onRemoveRecent: _removeRecent,
                                    onCreateAccount: () {
                                      try {
                                        Navigator.of(context).pushNamed('/signup');
                                      } catch (_) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const RegisterPage()),
                                        );
                                      }
                                    },
                                    onLogin: () {
                                      try {
                                        Navigator.of(context).pushNamed('/login');
                                      } catch (_) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const LoginPage()),
                                        );
                                      }
                                    },
                                    onApple: () => SocialAuth.signInWithApple(context),
                                    onGoogle: () => SocialAuth.signInWithGoogle(context),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // ===== سياسة الخصوصية (قابلة للنقر) =====
                          _PrivacyLine(
                            textStyle: (tt.bodySmall ?? const TextStyle()).copyWith(
                              color: isDark ? scheme.onSurface.withOpacity(0.70) : Colors.black.withOpacity(0.46),
                              fontWeight: FontWeight.w600,
                            ),
                            linkStyle: (tt.bodySmall ?? const TextStyle()).copyWith(
                              color: isDark ? scheme.onSurface.withOpacity(0.86) : Colors.black.withOpacity(0.68),
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w800,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PrivacyPage()),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemedWelcomeHero extends StatelessWidget {
  final String assetPath;
  final Color color;
  final bool isDark;
  final double height;

  const _ThemedWelcomeHero({
    required this.assetPath,
    required this.color,
    required this.isDark,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final heroW = screenW.clamp(300.0, 420.0).toDouble();

    return SizedBox(
      height: height,
      width: heroW,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.white.withOpacity(isDark ? 0.05 : 0.18),
                    color.withOpacity(isDark ? 0.10 : 0.08),
                    Colors.white.withOpacity(isDark ? 0.03 : 0.10),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(isDark ? 0.07 : 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(isDark ? 0.16 : 0.20),
                    blurRadius: 34,
                    spreadRadius: -8,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: height * 0.12,
            child: Opacity(
              opacity: isDark ? 0.10 : 0.14,
              child: Transform.scale(
                scale: 1.55,
                child: _tintedAsset(width: heroW * 0.72, height: height * 0.42, opacity: 1),
              ),
            ),
          ),
          Center(
            child: _tintedAsset(width: heroW * 0.82, height: height * 0.58, opacity: 0.98),
          ),
        ],
      ),
    );
  }

  Widget _tintedAsset({required double width, required double height, required double opacity}) {
    return Opacity(
      opacity: opacity,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) {
            // fallback بدون أي كراش لو اختلف اسم الصورة عندك
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fitness_center_rounded, size: 42, color: color),
                const SizedBox(width: 12),
                Icon(Icons.directions_run_rounded, size: 42, color: color),
                const SizedBox(width: 12),
                Icon(Icons.self_improvement_rounded, size: 42, color: color),
                const SizedBox(width: 12),
                Icon(Icons.sports_handball_rounded, size: 42, color: color),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SoftGlowCircle extends StatelessWidget {
  const _SoftGlowCircle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeatureStrip extends StatelessWidget {
  const _WelcomeFeatureStrip({required this.primary, required this.mutedColor});

  final Color primary;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _WelcomeFeatureChip(icon: Icons.local_fire_department_rounded, label: 'سعرات', primary: primary, mutedColor: mutedColor),
        _WelcomeFeatureChip(icon: Icons.restaurant_rounded, label: 'وجبات', primary: primary, mutedColor: mutedColor),
        _WelcomeFeatureChip(icon: Icons.fitness_center_rounded, label: 'تمارين', primary: primary, mutedColor: mutedColor),
      ],
    );
  }
}

class _WelcomeFeatureChip extends StatelessWidget {
  const _WelcomeFeatureChip({
    required this.icon,
    required this.label,
    required this.primary,
    required this.mutedColor,
  });

  final IconData icon;
  final String label;
  final Color primary;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: mutedColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final Color cardBg;
  final Color cardBorder;
  final Color primary;
  final bool isAppleAvailable;
  final List<RecentAccount> recentAccounts;
  final bool loadingRecent;
  final Future<void> Function(RecentAccount acc) onPickRecent;
  final Future<void> Function(String uid) onRemoveRecent;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogin;
  final VoidCallback onApple;
  final VoidCallback onGoogle;

  const _WelcomeCard({
    required this.title,
    required this.subtitle,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.cardBg,
    required this.cardBorder,
    required this.primary,
    required this.isAppleAvailable,
    required this.recentAccounts,
    required this.loadingRecent,
    required this.onPickRecent,
    required this.onRemoveRecent,
    required this.onCreateAccount,
    required this.onLogin,
    required this.onApple,
    required this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: BoxDecoration(
        color: cardBg.withOpacity(0.96),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: cardBorder, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.11),
            blurRadius: 36,
            spreadRadius: -8,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.22),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (title.trim().isNotEmpty) ...[
            Text(title, textAlign: TextAlign.center, style: titleStyle),
          ],
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(subtitle, textAlign: TextAlign.center, style: subtitleStyle),
          ],

          // ===== الحسابات السابقة =====
          if (loadingRecent) ...[
            const SizedBox(height: 14),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ] else if (recentAccounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            _RecentAccountsSection(
              accounts: recentAccounts,
              onPick: onPickRecent,
              onRemove: onRemoveRecent,
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: onCreateAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                textStyle: (tt.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              child: const Text('إنشاء حساب'),
            ),
          ),

          const SizedBox(height: 10),

          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: onLogin,
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withOpacity(0.55), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                textStyle: (tt.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              child: const Text('تسجيل الدخول'),
            ),
          ),

          const SizedBox(height: 14),
          _SoftDividerOr(primary: primary),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isAppleAvailable)
                _SocialIcon(icon: Icons.apple, onTap: onApple),
              if (isAppleAvailable) const SizedBox(width: 18),
              _SocialIcon(icon: Icons.g_mobiledata_rounded, onTap: onGoogle),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentAccountsSection extends StatelessWidget {
  final List<RecentAccount> accounts;
  final Future<void> Function(RecentAccount acc) onPick;
  final Future<void> Function(String uid) onRemove;

  const _RecentAccountsSection({
    required this.accounts,
    required this.onPick,
    required this.onRemove,
  });

  IconData _providerIcon(String providerId) {
    switch (providerId) {
      case 'google.com':
        return Icons.g_mobiledata_rounded;
      case 'apple.com':
        return Icons.apple;
      case 'password':
      default:
        return Icons.email_outlined;
    }
  }

  String _providerLabel(String providerId) {
    switch (providerId) {
      case 'google.com':
        return 'Google';
      case 'apple.com':
        return 'Apple';
      case 'password':
      default:
        return 'بريد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final scheme = theme.colorScheme;

    // نعرض 3 فقط، والباقي في "عرض المزيد" (BottomSheet)
    final visible = accounts.take(3).toList();
    final hasMore = accounts.length > visible.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.58),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withOpacity(0.10), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: scheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'الحسابات السابقة',
                  style: (tt.titleSmall ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (hasMore)
                TextButton(
                  onPressed: () => _openAll(context),
                  child: const Text('عرض المزيد'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...visible.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecentAccountTile(
                  account: a,
                  providerIcon: _providerIcon(a.providerId),
                  providerLabel: _providerLabel(a.providerId),
                  onTap: () => onPick(a),
                  onRemove: () => onRemove(a.uid),
                ),
              )),
        ],
      ),
    );
  }

  void _openAll(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final a = accounts[i];
              return _RecentAccountTile(
                account: a,
                providerIcon: _providerIcon(a.providerId),
                providerLabel: _providerLabel(a.providerId),
                onTap: () async {
                  Navigator.of(sheetContext).maybePop();
                  await onPick(a);
                },
                onRemove: () async {
                  await onRemove(a.uid);
                  // اغلاق وإعادة فتح (بسيط)؛ الواجهة ستتحدث من WelcomeScreen بعد reload
                  // ignore: use_build_context_synchronously
                  Navigator.of(sheetContext).maybePop();
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _RecentAccountTile extends StatelessWidget {
  final RecentAccount account;
  final IconData providerIcon;
  final String providerLabel;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentAccountTile({
    required this.account,
    required this.providerIcon,
    required this.providerLabel,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final scheme = theme.colorScheme;

    final hasPhoto = account.photoUrl.trim().isNotEmpty;

    return Material(
      color: theme.colorScheme.surface.withOpacity(0.72),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primary.withOpacity(0.12),
                backgroundImage: hasPhoto ? NetworkImage(account.photoUrl) : null,
                child: hasPhoto
                    ? null
                    : Text(
                        account.title.trim().isNotEmpty
                            ? account.title.trim().substring(0, 1)
                            : 'و',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (account.subtitle.isNotEmpty)
                      Text(
                        account.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (tt.bodySmall ?? const TextStyle()).copyWith(
                          color: scheme.onSurface.withOpacity(0.55),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: scheme.primary.withOpacity(0.20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(providerIcon, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      providerLabel,
                      style: (tt.bodySmall ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'إزالة من هذا الجهاز',
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: scheme.onSurface.withOpacity(0.60)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftDividerOr extends StatelessWidget {
  final Color primary;
  const _SoftDividerOr({required this.primary});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.75), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'أو',
            style: (tt.bodyMedium ?? const TextStyle()).copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.50),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.75), thickness: 1)),
      ],
    );
  }
}

class _SocialIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SocialIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.80),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

class _PrivacyLine extends StatelessWidget {
  final TextStyle textStyle;
  final TextStyle linkStyle;
  final VoidCallback onTap;

  const _PrivacyLine({
    required this.textStyle,
    required this.linkStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('بالاطلاع والمتابعة، أنت توافق على ', style: textStyle),
        InkWell(
          onTap: onTap,
          child: Text('سياسة الخصوصية', style: linkStyle),
        ),
      ],
    );
  }
}

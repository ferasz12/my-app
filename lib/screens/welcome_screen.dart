import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_page.dart';
import 'register_page.dart';
import '../settings/privacy_page.dart';

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          content: _WelcomeNotice(message: msg),
        ),
      );
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
        _snack('جهزنا بريد حساب وازن. اكتب كلمة المرور وكمل دخولك.');
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
        error = 'هذا الحساب يحتاج دخول يدوي من صفحة وازن.';
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
      error = 'صار خلل بسيط أثناء تبديل الحساب. جرّب مرة ثانية.';
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
        return 'هذا الحساب غير موجود في وازن أو تم حذفه.';
      case 'user-disabled':
        return 'هذا الحساب متوقف حاليًا. تواصل مع دعم وازن.';
      case 'invalid-credential':
      case 'invalid-email':
        return 'بيانات هذا الحساب لم تعد صالحة. سجل دخولك من جديد.';

      // ✅ حالات المزود/الطريقة
      case 'account-exists-with-different-credential':
        return 'هذا البريد مرتبط بطريقة دخول مختلفة. استخدم نفس الطريقة السابقة.';
      case 'operation-not-allowed':
        return 'طريقة الدخول هذه غير متاحة حاليًا في وازن.';

      // ✅ الشبكة/الإلغاء
      case 'network-request-failed':
        return 'ما وصلنا بسيرفرات وازن. تأكد من الشبكة ثم حاول.';
      case 'canceled':
      case 'popup-closed-by-user':
        return 'تم إلغاء الدخول، تقدر تحاول في أي وقت.';

      default:
        return 'تعذر تبديل الحساب الآن. جرّب مرة ثانية.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final primary = scheme.primary;
    final base = isDark ? scheme.background : Colors.white;

    // في الوضع الداكن نستخدم طبقات رمادية هادئة بدل التوهج التركوازي.
    final bgTop = isDark ? scheme.background : _mix(base, primary, 0.08);
    final bgBottom = isDark ? scheme.surface : _mix(base, primary, 0.34);
    final cardBg = isDark ? scheme.surfaceVariant : _mix(base, primary, 0.045);
    final cardBorder = isDark ? scheme.outlineVariant : _mix(base, primary, 0.16);

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
                child: _SoftGlowCircle(color: (isDark ? scheme.surfaceVariant : primary).withOpacity(isDark ? 0.10 : 0.16), size: 210),
              ),
              PositionedDirectional(
                top: 190,
                start: -95,
                child: _SoftGlowCircle(color: (isDark ? scheme.surfaceVariant : scheme.secondary).withOpacity(isDark ? 0.08 : 0.12), size: 230),
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
                                    title: 'ابدأ رحلتك في وازن',
                                    subtitle: 'كل يوم أوضح: تابع أكلك، ماءك، وزنك، وتمارينك بتجربة عربية مرتبة تناسب أسلوبك.',
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


class _WelcomeNotice extends StatelessWidget {
  const _WelcomeNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.primary.withOpacity(0.16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.spa_rounded, color: scheme.primary, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: (tt.bodySmall ?? const TextStyle()).copyWith(
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
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
    final heroW = screenW.clamp(300.0, 430.0).toDouble();

    return SizedBox(
      height: height,
      width: heroW,
      child: Center(
        child: Image.asset(
          assetPath,
          width: heroW * 0.42,
          height: height * 0.62,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(
            Icons.fitness_center_rounded,
            color: color,
            size: 54,
          ),
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
          const SizedBox(height: 16),

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
              child: const Text('عندي حساب في وازن'),
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
                  'حسابات وازن على هذا الجهاز',
                  style: (tt.titleSmall ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (hasMore)
                TextButton(
                  onPressed: () => _openAll(context),
                  child: const Text('كل الحسابات'),
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
        Text('بياناتك الصحية خاصة — وبالمتابعة توافق على ', style: textStyle),
        InkWell(
          onTap: onTap,
          child: Text('سياسة الخصوصية', style: linkStyle),
        ),
      ],
    );
  }
}

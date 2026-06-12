// lib/screens/login_page.dart
// تصميم فخم ومتناسق مع صفحة الترحيب/التسجيل — مناسب لتطبيق صحي (RTL)
// المنطق كما هو: FirebaseAuth + تذكير التفعيل + استعادة كلمة المرور

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../ui/onboarding_kit.dart';
import '../services/auth/recent_accounts_store.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _busy = false;
  bool _obsc = true;

  @override
  void initState() {
    super.initState();
    // دعم تعبئة البريد من شاشة الترحيب (الحسابات السابقة)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final v = args['prefillEmail'];
        if (v is String && v.trim().isNotEmpty) {
          _emailCtrl.text = v.trim();
        }
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'اكتب بريدك المرتبط بوازن عشان نرجعك لحسابك.';
    final s = v.trim();
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s)) return 'تأكد من صيغة البريد، مثال: name@example.com';
    return null;
  }

  String? _validatePass(String? v) {
    if (v == null || v.isEmpty) return 'اكتب كلمة مرور حساب وازن.';
    if (v.length < 6) return 'كلمة المرور لازم تكون 6 أحرف على الأقل.';
    return null;
  }

  void _showNotice({
    required String title,
    required String message,
    _NoticeType type = _NoticeType.info,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          duration: Duration(seconds: type == _NoticeType.success ? 4 : 5),
          content: _NoticeSnackContent(
            title: title,
            message: message,
            type: type,
          ),
        ),
      );
  }


  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text;

      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass);
      final user = cred.user;

      if (user == null) {
        _showNotice(
          title: 'تعذر الدخول',
          message: 'ما قدرنا نرجعك لحسابك الصحي الآن. تأكد من بياناتك وحاول مرة ثانية.',
          type: _NoticeType.error,
        );
        return;
      }

      await user.reload();
      if (!user.emailVerified) {
        if (!mounted) return;
        final resend = await _showUnverifiedEmailDialog(email);
        if (resend == true) {
          await user.sendEmailVerification();
          _showNotice(
            title: 'تم إرسال رسالة التحقق',
            message: 'افتح بريدك واضغط رابط التفعيل، بعدها ارجع لوازن وكمل رحلتك.',
            type: _NoticeType.success,
          );
        }
        return;
      }

      // ✅ احفظ الحساب ضمن "الحسابات السابقة" (بدون كلمة مرور)
      try {
        await RecentAccountsStore.rememberUser(user);
      } catch (_) {}

      if (!mounted) return;
      // نجاح: رجوع لبداية التطبيق (AuthGate)
      // ✅ مهم: نمسح أي صفحات سابقة (Welcome/Login) عشان ما يظهر زر الرجوع
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } on FirebaseAuthException catch (e) {
      _showNotice(
        title: 'ما قدرنا ندخلك لوازن',
        message: _mapAuthError(e),
        type: _NoticeType.error,
      );
    } on TimeoutException {
      _showNotice(
        title: 'الاتصال غير مستقر',
        message: 'تأكد من اتصالك بالإنترنت عشان نقدر نزامن بيانات وازن.',
        type: _NoticeType.warning,
      );
    } catch (e) {
      _showNotice(
        title: 'صار خطأ غير متوقع',
        message: 'صار خلل بسيط أثناء الدخول. أعد المحاولة، وإذا تكرر أعد فتح التطبيق.',
        type: _NoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onForgotPassword() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !_isEmail(email)) {
      _showNotice(
        title: 'اكتب بريدك أولًا',
        message: 'اكتب البريد المسجل في وازن عشان نرسل لك رابط تعيين كلمة مرور جديدة.',
        type: _NoticeType.warning,
      );
      return;
    }
    try {
      final acs = ActionCodeSettings(
        url: 'https://wazenfapp.web.app/verify.html',
        handleCodeInApp: false,
      );
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: acs,
      );
      _showNotice(
        title: 'أرسلنا لك رابط الاسترجاع',
        message: 'افتح بريدك واتبع الرابط. إذا ما وصل، شيّك البريد غير الهام ثم ارجع لوازن.',
        type: _NoticeType.success,
      );
    } on FirebaseAuthException catch (e) {
      _showNotice(
        title: 'تعذر إرسال رابط كلمة المرور',
        message: _mapAuthError(e),
        type: _NoticeType.error,
      );
    } catch (e) {
      _showNotice(
        title: 'تعذر إرسال الرابط',
        message: 'ما قدرنا نرسل رابط الاسترجاع الآن. تأكد من البريد والاتصال ثم حاول.',
        type: _NoticeType.error,
      );
    }
  }

  bool _isEmail(String s) => RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s);

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'ما لقينا حساب وازن بهذا البريد. تأكد من البريد أو أنشئ حسابًا جديدًا.';
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'بيانات الدخول ما تطابقت مع حساب وازن. جرّب مرة ثانية أو استخدم استرجاع كلمة المرور.';
      case 'invalid-email':
        return 'صيغة البريد غير واضحة. اكتبها بهذا الشكل: name@example.com';
      case 'user-disabled':
        return 'هذا الحساب متوقف حاليًا. تواصل مع دعم وازن ونساعدك.';
      case 'too-many-requests':
        return 'حاولت أكثر من مرة. خذ دقيقة وارجع جرّب بهدوء.';
      case 'network-request-failed':
        return 'ما وصلنا بسيرفرات وازن. تأكد من الشبكة ثم حاول.';
      case 'operation-not-allowed':
        return 'الدخول بالبريد غير متاح حاليًا. جرّب طريقة دخول أخرى أو تواصل مع الدعم.';
      default:
        return 'تعذر فتح حساب وازن الآن. حاول مرة ثانية بعد لحظات.';
    }
  }

  Future<bool?> _showUnverifiedEmailDialog(String email) {
    final tt = Theme.of(context).textTheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.mark_email_unread_rounded, color: Color(0xFFB7791F)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'فعّل بريدك أولًا',
                  style: (tt.titleLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Text(
            'حساب وازن موجود، لكن نحتاج تفعيل البريد قبل الدخول. نقدر نرسل رابط التحقق مرة ثانية على: $email',
            style: (tt.bodyMedium ?? const TextStyle()).copyWith(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقًا'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('أرسل الرابط'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final insets = MediaQuery.of(context).viewInsets;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: OnboardingKit.background(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + insets.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // زر رجوع بسيط فقط — بدون شارة علوية
                      Row(
                        children: [
                          _IconCircle(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 12),

                      _AuthHero(
                        title: 'أهلًا بعودتك إلى وازن',
                        subtitle: 'ادخل لحسابك وكمل متابعة يومك الصحي من نفس المكان.',
                        chips: const [],
                      ),
                      const SizedBox(height: 18),

                      _GlassCard(
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textDirection: TextDirection.ltr,
                                decoration: OnboardingKit.inputDecoration(
                                  context: context,
                                  label: 'بريد حساب وازن',
                                  icon: Icons.email_outlined,
                                  hint: 'example@mail.com',
                                ),
                                validator: _validateEmail,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passCtrl,
                                textDirection: TextDirection.ltr,
                                obscureText: _obsc,
                                decoration: OnboardingKit.inputDecoration(
                                  context: context,
                                  label: 'كلمة مرور وازن',
                                  icon: Icons.lock_outline,
                                  suffixIcon: IconButton(
                                    onPressed: _busy ? null : () => setState(() => _obsc = !_obsc),
                                    icon: Icon(_obsc ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: _validatePass,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _busy ? null : _onLogin(),
                              ),

                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: _busy ? null : _onForgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context).colorScheme.primary,
                                    textStyle: (tt.titleSmall ?? const TextStyle()).copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  child: const Text('نسيت كلمة المرور؟'),
                                ),
                              ),

                              const SizedBox(height: 4),

                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _busy ? null : _onLogin,
                                  style: OnboardingKit.primaryButtonStyle(tt, context: context),
                                  child: _busy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('دخول إلى وازن'),
                                ),
                              ),

                              const SizedBox(height: 12),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'جديد في وازن؟',
                                    style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => Navigator.of(context).pushReplacementNamed('/signup'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                      textStyle: (tt.titleSmall ?? const TextStyle()).copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    child: const Text('ابدأ حسابك'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'بياناتك الصحية خاصة — وبمتابعتك توافق على سياسة الخصوصية',
                        textAlign: TextAlign.center,
                        style: (tt.bodySmall ?? const TextStyle()).copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.72),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class _HeroChipData {
  final IconData icon;
  final String label;
  const _HeroChipData(this.icon, this.label);
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({
    required this.title,
    required this.subtitle,
    required this.chips,
  });

  final String title;
  final String subtitle;
  final List<_HeroChipData> chips;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.surface.withOpacity(isDark ? 0.58 : 0.72),
            cs.surfaceContainerHighest.withOpacity(isDark ? 0.34 : 0.52),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.52)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(isDark ? 0.18 : 0.10),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          const _WazenHeroMark(),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: (tt.headlineSmall ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w900,
              height: 1.15,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: (tt.bodyMedium ?? const TextStyle()).copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _WazenHeroMark extends StatelessWidget {
  const _WazenHeroMark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/app_logo.png',
      width: 112,
      height: 92,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.fitness_center_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: 42,
      ),
    );
  }
}

enum _NoticeType { success, error, warning, info }

class _NoticeSnackContent extends StatelessWidget {
  const _NoticeSnackContent({
    required this.title,
    required this.message,
    required this.type,
  });

  final String title;
  final String message;
  final _NoticeType type;

  Color _accentColor(BuildContext context) {
    switch (type) {
      case _NoticeType.success:
        return const Color(0xFF16A34A);
      case _NoticeType.warning:
        return const Color(0xFFF59E0B);
      case _NoticeType.error:
        return const Color(0xFFDC2626);
      case _NoticeType.info:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData get _icon {
    switch (type) {
      case _NoticeType.success:
        return Icons.check_circle_rounded;
      case _NoticeType.warning:
        return Icons.info_rounded;
      case _NoticeType.error:
        return Icons.error_rounded;
      case _NoticeType.info:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final accent = _accentColor(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_icon, color: accent, size: 23),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: (tt.titleSmall ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: (tt.bodySmall ?? const TextStyle()).copyWith(
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface.withOpacity(isDark ? 0.62 : 0.74),
                cs.surfaceContainerHighest.withOpacity(isDark ? 0.34 : 0.50),
              ],
            ),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.55), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.24 : 0.08),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconCircle({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(isDark ? 0.42 : 0.62),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.52)),
            ),
            child: Center(
              child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextTheme textTheme;
  const _Pill({required this.icon, required this.label, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary.withOpacity(0.9)),
          const SizedBox(width: 8),
          Text(
            label,
            style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

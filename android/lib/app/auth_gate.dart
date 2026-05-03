// lib/app/auth_gate.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostics/onb_log.dart';
import '../data/legacy_user_repository.dart';

// 👇 الشاشات
import '../screens/splash_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/lifestyle_questions_page.dart';
import '../screens/user_input_page.dart';
import '../screens/set_goal_page.dart';
import '../screens/summary_page.dart';
import '../screens/main_navigation_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _authSub;
  Widget _child = const SplashScreen();
  bool _deciding = false;
  int _ver = 0;

  @override
  void initState() {
    super.initState();
    _decideFor(FirebaseAuth.instance.currentUser);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (u) => _decideFor(u),
      onError: (e) {
        OnbLog.e('AuthGate', 'AUTH_STREAM_ERROR', e, StackTrace.current);
        _set(const WelcomeScreen());
      },
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _set(Widget w) {
    if (!mounted) return;
    setState(() => _child = w);
  }

  bool _same(int me) => mounted && me == _ver;

  Future<void> _decideFor(User? user) async {
    if (_deciding) return;
    _deciding = true;
    final me = ++_ver;

    OnbLog.i('AuthGate', 'DECIDE_START', ctx: {
      'ver': me,
      'userNull': user == null,
      'uid': user?.uid,
      'anon': user?.isAnonymous,
      'emailVerified': user?.emailVerified,
    });

    // ✅ ابقِ شاشة السبلّاش أثناء اتخاذ القرار
    if (_same(me)) _set(const SplashScreen());

    try {
      // 1) غير مسجّل → Welcome
      final u0 = user;
      if (u0 == null || u0.isAnonymous) {
        OnbLog.i('AuthGate', 'NO_USER_SHOW_WELCOME', ctx: {'ver': me});
        if (_same(me)) _set(const WelcomeScreen());
        return;
      }

      User u = u0;

      // 2) reload (Best-effort)
      try {
        await u.reload();
        final cu = FirebaseAuth.instance.currentUser;
        if (cu != null) u = cu;
      } catch (e) {
        OnbLog.w('AuthGate', 'USER_RELOAD_FAILED', ctx: {'err': e.toString()});
      }

      OnbLog.i('AuthGate', 'AFTER_RELOAD', ctx: {
        'uid': u.uid,
        'email': u.email,
        'emailVerified': u.emailVerified,
      });

      // 2.1) تحديث التوكن (Best-effort)
      final ok = await _isSessionValid(u);
      OnbLog.i('AuthGate', 'SESSION_VALID_CHECK', ctx: {'ok': ok});
      if (!ok) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        if (_same(me)) _set(const WelcomeScreen());
        return;
      }

      // 3) بريد غير مفعّل → التحقق
      if (!u.emailVerified) {
        OnbLog.i('AuthGate', 'EMAIL_NOT_VERIFIED_SHOW_VERIFY', ctx: {'email': u.email});
        if (_same(me)) _set(_VerifyEmailInline(email: u.email ?? ''));
        return;
      }

      // 3.5) ضمان وجود وثيقة المستخدم الأساسية users/{uid}
      try {
        OnbLog.i('AuthGate', 'ENSURE_LEGACY_ROOT_START');
        await const LegacyUserRepository()
            .ensureLegacyUserDocExists()
            .timeout(const Duration(seconds: 25));
        OnbLog.i('AuthGate', 'ENSURE_LEGACY_ROOT_OK');
      } catch (e, st) {
        OnbLog.e('AuthGate', 'ENSURE_LEGACY_ROOT_FAILED', e, st);
        if (kDebugMode) debugPrint('[AuthGate] ensureLegacyUserDocExists failed: $e');
      }

      // 4) حالة الأونبوردنغ
      OnbLog.i('AuthGate', 'LOAD_ONBOARDING_STATUS_START');
      final st = await const LegacyUserRepository().loadOnboardingStatus(uid: u.uid);
      OnbLog.i('AuthGate', 'LOAD_ONBOARDING_STATUS_OK', ctx: {
        'done': st.done,
        'step': st.step,
        'lifestyleScore': st.lifestyleScore,
      });

      if (st.done) {
        if (_same(me)) _set(const MainNavigationScreen());
        return;
      }

      Widget target;
      switch (st.step) {
        case 0:
          target = const LifestyleQuestionsPage();
          break;
        case 1:
          target = UserInputPage(lifestyleScore: st.lifestyleScore ?? 0);
          break;
        case 2:
          target = const SetGoalPage();
          break;
        case 3:
          target = const SummaryPage();
          break;
        default:
          target = const LifestyleQuestionsPage();
      }

      OnbLog.i('AuthGate', 'NAVIGATE_TARGET', ctx: {'step': st.step, 'widget': target.runtimeType.toString()});
      if (_same(me)) _set(target);
    } catch (e, st) {
      OnbLog.e('AuthGate', 'DECIDE_FATAL', e, st);
      if (kDebugMode) debugPrint('[AuthGate] decide error: $e');

      final cur = FirebaseAuth.instance.currentUser;
      if (cur != null && !cur.isAnonymous) {
        try {
          await cur.reload();
        } catch (_) {}

        if (cur.emailVerified) {
          if (_same(me)) _set(const LifestyleQuestionsPage());
        } else {
          if (_same(me)) _set(_VerifyEmailInline(email: cur.email ?? ''));
        }
      } else {
        if (_same(me)) _set(const WelcomeScreen());
      }
    } finally {
      _deciding = false;
      OnbLog.i('AuthGate', 'DECIDE_END', ctx: {'ver': me});
    }
  }

  /// يتحقق بصرامة من أن الجلسة صالحة: token صالح + ليس حسابًا مجهولًا
  Future<bool> _isSessionValid(User user) async {
    if (user.isAnonymous) return false;
    try {
      final tok = await user.getIdToken(true).timeout(const Duration(seconds: 8));
      // بعض إصدارات firebase_auth تعيد String? لذلك نتعامل مع null بأمان.
      if ((tok ?? '').isEmpty) return false;
      return true;
    } on TimeoutException {
      // شبكة بطيئة: نعتبرها صالحة مؤقتاً ونكمل
      OnbLog.w('AuthGate', 'TOKEN_REFRESH_TIMEOUT');
      return true;
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      OnbLog.w('AuthGate', 'TOKEN_REFRESH_AUTH_ERROR', ctx: {'code': code});

      if (code == 'network-request-failed' ||
          code == 'too-many-requests' ||
          code == 'unavailable') {
        return true;
      }

      if (code == 'user-disabled' ||
          code == 'user-token-expired' ||
          code == 'invalid-user-token' ||
          code == 'requires-recent-login') {
        return false;
      }

      return true;
    } catch (e) {
      OnbLog.w('AuthGate', 'TOKEN_REFRESH_UNKNOWN_ERROR', ctx: {'err': e.toString()});
      return true;
    }
  }

  @override
  Widget build(BuildContext context) => _child;
}

// ====== Verify Email (inline مبسطة) ======
class _VerifyEmailInline extends StatefulWidget {
  final String email;
  const _VerifyEmailInline({required this.email});
  @override
  State<_VerifyEmailInline> createState() => _VerifyEmailInlineState();
}

class _VerifyEmailInlineState extends State<_VerifyEmailInline> {
  bool _sending = false;
  bool _checking = false;
  String? _msg;

  Future<void> _send() async {
    try {
      setState(() => _sending = true);
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      setState(() {
        _sending = false;
        _msg = 'تم إرسال رابط التفعيل إلى بريدك.';
      });
    } catch (_) {
      setState(() {
        _sending = false;
        _msg = 'تعذّر الإرسال حاليًا.';
      });
    }
  }

  Future<void> _refresh() async {
    try {
      setState(() => _checking = true);
      await FirebaseAuth.instance.currentUser?.reload();
      final ok = FirebaseAuth.instance.currentUser?.emailVerified == true;
      if (ok) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      } else {
        setState(() {
          _checking = false;
          _msg = 'لسّه ما تم التفعيل.';
        });
      }
    } catch (_) {
      setState(() {
        _checking = false;
        _msg = 'تعذّر التحقق الآن.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تفعيل البريد')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تم إنشاء الحساب: ${widget.email}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text(
              'افتح بريدك واضغط رابط التفعيل ثم ارجع واضغط "تحقّق".',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: Text(_sending ? 'جارٍ الإرسال...' : 'إرسال رابط التفعيل'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _checking ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_checking ? 'جارٍ التحقق...' : 'تحقّق'),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 12),
              Text(_msg!, style: TextStyle(color: cs.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

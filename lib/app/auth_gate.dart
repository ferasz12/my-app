// lib/app/auth_gate.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/legacy_user_repository.dart';
import '../shared/session_manager.dart';

// 👇 الشاشات
import '../screens/splash_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/lifestyle_questions_page.dart';
import '../screens/user_input_page.dart';
import '../screens/set_goal_page.dart';
import '../screens/goal_progress_onboarding_page.dart';
import '../screens/summary_page.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/banned_screen.dart';

// ✅ بوابة الاشتراك (Trial من المتجر) + قفل كامل عند عدم وجود اشتراك
// نستخدمها فقط بعد إكمال الأونبوردنغ (بعد صفحة الملخص الصحي) عند دخول الشاشة الرئيسية.

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

  /// Cache آخر حالة حظر لتقليل الوميض عند تبديل الشجرة.
  bool? _lastBanned;

  @override
  void initState() {
    super.initState();
    _decideFor(FirebaseAuth.instance.currentUser);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (u) => _decideFor(u),
      // ✅ لا نطرد المستخدم عند انقطاع الشبكة/أخطاء مؤقتة.
      // بعض الأجهزة قد ترمي خطأ مؤقت من stream عند مشاكل شبكة.
      onError: (e) {
        if (kDebugMode) debugPrint('[AuthGate] authStateChanges error: $e');
        // لا تغيّر الشاشة هنا.
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

  Future<void> _decideFor(User? user) async {
    if (_deciding) return;
    _deciding = true;
    final me = ++_ver;

    try {
      // 1) غير مسجّل → Welcome
      if (user == null || user.isAnonymous) {
        // ✅ مهم: تنظيف مفاتيح الجلسة حتى لا تبقى بيانات حساب سابق
        await SessionManager.clearSessionKeys();
        if (_same(me)) _set(const WelcomeScreen());
        return;
      }
      // ✅ مزامنة currentUid/currentEmail (حتى لو كانت موجودة من حساب سابق)
      final bool accountChanged = await SessionManager.didAccountChange(user);
      await SessionManager.syncFromFirebaseUser(user);
      if (accountChanged) {
        // ننظف كاش Firestore لتقليل احتمالية ظهور بيانات حساب سابق
        await SessionManager.clearFirestoreCacheSafe();
      }



      // 2) تحقق صارم من صلاحية الجلسة
      final ok = await _isSessionValid(user);
      if (!ok) {
        try {
          await SessionManager.fullSignOut();
        } catch (_) {}
        if (_same(me)) _set(const WelcomeScreen());
        return;
      }

      // 3) بريد غير مفعّل → التحقق (فقط لحسابات البريد/كلمة المرور)
      final usesPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
      if (usesPasswordProvider && !user.emailVerified) {
        if (_same(me)) _set(_VerifyEmailInline(email: user.email ?? ''));
        return;
      }

      // 3.5) ضمان وجود وثيقة المستخدم الأساسية users/{uid} (Legacy root)
      // مهم جدًا لأن بعض القواعد تمنع كتابة أي شيء قبل وجود الوثيقة الأساسية.
      try {
        await const LegacyUserRepository()
            .ensureLegacyUserDocExists()
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        if (kDebugMode) debugPrint('[AuthGate] ensureLegacyUserDocExists failed: $e');
      }

      // 4) حالة الأونبوردنغ (✅ cache أولاً ثم server، مع منع "الرجوع للخلف")
      final st = await const LegacyUserRepository().loadOnboardingStatus(uid: user.uid);

      // نحدد الوجهة (أونبوردنغ أو الرئيسية)
      Widget target;
      if (st.done) {
        target = const MainNavigationScreen();
      } else {
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
            // ✅ صفحة تحفيزية بعد تحديد هدف الوزن (رسم مسار الوزن)
            target = const GoalProgressOnboardingPage();
            break;
          case 4:
            target = const SummaryPage();
            break;
          default:
            target = const LifestyleQuestionsPage();
        }
      }

      // ✅ صار التطبيق مجاني بشكل أساسي، والميزات المحددة فقط هي اللي تقفل بالاشتراك.
      if (_same(me)) {
        _set(target);
      }
      return;

      } catch (e) {
      if (kDebugMode) debugPrint('[AuthGate] decide error: $e');

      // ✅ وضع بدون إنترنت: لا ترجع المستخدم لشاشة الترحيب ولا تطلب تسجيل دخول من جديد.
      // إذا كان المستخدم موجودًا، نسمح بالدخول ونترك الميزات التي تحتاج شبكة تفشل بشكل طبيعي.
      if (user != null && !user.isAnonymous) {
        if (_same(me)) _set(const MainNavigationScreen());
      } else {
        if (_same(me)) _set(const WelcomeScreen());
      }
    } finally {
      _deciding = false;
    }
  }

  bool _same(int me) => mounted && me == _ver;

  /// يتحقق بصرامة من أن الجلسة صالحة: token صالح + ليس حسابًا مجهولًا
  Future<bool> _isSessionValid(User user) async {
    if (user.isAnonymous) return false;

    // وجود provider = علامة أن الحساب "حقيقي" وليس حالة شاذة.
    final hasProvider = user.providerData.any((p) => (p.providerId).isNotEmpty);
    if (!hasProvider) return false;

    try {
      // ✅ لا نجبر refresh للـ token عند فتح التطبيق.
      // refresh (true) قد يفشل بدون إنترنت ويؤدي لطرد المستخدم.
      final tok = await user.getIdToken(false);
      if ((tok ?? '').isEmpty) {
        // حتى لو فاضي نعتبره صالح في وضع offline إذا الحساب موجود.
        return true;
      }
      return true;
    } on FirebaseAuthException catch (e) {
      // ✅ إذا فشل بسبب الشبكة: لا نسجّل خروج.
      if (e.code == 'network-request-failed') return true;
      return false;
    } catch (e) {
      // ✅ أي أخطاء شبكة/سوكت/أوفلاين: اعتبرها صالحة.
      final s = e.toString().toLowerCase();
      if (s.contains('network') ||
          s.contains('socket') ||
          s.contains('offline') ||
          s.contains('unreachable') ||
          s.contains('timed out')) {
        return true;
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    // غير مسجّل: لا نعرض بوابة الحظر.
    if (u == null || u.isAnonymous) return _child;

    // ✅ بوابة حظر مباشرة (تعمل حتى لو تم الحظر أثناء استخدام التطبيق)
    return _UserBanGate(
      uid: u.uid,
      initialBanned: _lastBanned,
      onBannedChanged: (v) => _lastBanned = v,
      child: _child,
    );
  }
}

/// بوابة بسيطة تراقب users/{uid}.isBanned
/// إذا كان true: تعرض شاشة الحظر، وإذا أزيل الحظر تعيد المستخدم تلقائيًا.
class _UserBanGate extends StatelessWidget {
  final String uid;
  final Widget child;
  final bool? initialBanned;
  final void Function(bool banned)? onBannedChanged;

  const _UserBanGate({
    required this.uid,
    required this.child,
    this.initialBanned,
    this.onBannedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        bool banned = initialBanned ?? false;

        final data = snap.data?.data();
        if (data != null) {
          banned = (data['isBanned'] == true);
        }

        onBannedChanged?.call(banned);

        if (banned) {
          // Key لإعادة بناء الشاشة عند الانتقال من/إلى الحظر.
          return const BannedScreen(key: ValueKey('banned_screen'));
        }

        // لو ما عندنا بيانات بعد، نعرض child بدل تعطيل المستخدم.
        // (الحظر الحقيقي سيظهر فور وصول الداتا أو عند وجودها في الكاش)
        return KeyedSubtree(
          key: const ValueKey('app_unbanned'),
          child: child,
        );
      },
    );
  }
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


  Future<void> _signOutAndGoBack() async {
    try {
      // ✅ تنظيف جلسة التطبيق ثم تسجيل خروج
      await SessionManager.fullSignOut();
    } catch (_) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }

    if (!mounted) return;

    // ✅ ارجع لجذر التطبيق (AuthGate) بدل دفع WelcomeScreen كـ Route مستقل
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _handleBack() async {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    await _signOutAndGoBack();
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفعيل البريد'),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _handleBack,
        ),
        actions: [
          TextButton(
            onPressed: _signOutAndGoBack,
            child: const Text('تسجيل خروج'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('أرسلنا رابط تفعيل إلى: ${widget.email}'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mail),
                    label: const Text('إرسال رابط التفعيل'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checking ? null : _refresh,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: const Text('تم التفعيل، حدّث الحالة'),
                  ),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 12),
                  Text(_msg!, style: TextStyle(color: cs.primary)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

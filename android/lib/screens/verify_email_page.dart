// lib/screens/verify_email_page.dart
// Final hardened version:
// - Polling + manual check + resume-from-background
// - يعتمد على LegacyUserRepository لتأسيس users/{uid} (الجذر فقط)
// - بعد التحقق يرجع لنقطة الدخول (AuthGate) بدل القفز مباشرة
// - Unfocus keyboard before navigation (fixes iOS warnings)

import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/auth_gate.dart';
import '../data/legacy_user_repository.dart';
import '../core/diagnostics/onboarding_log.dart';
import '../core/diagnostics/firestore_diag.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../services/auth_service.dart';
import '../community/local_repos.dart';
import '../community/models.dart';

class VerifyEmailPage extends StatefulWidget {
  final String email;
  const VerifyEmailPage({super.key, required this.email});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>
    with WidgetsBindingObserver {
  bool _sentOnce = false;
  bool _sending = false;
  bool _checking = false;
  bool _navigated = false; // يمنع تكرار التنقل
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sendIfNeeded();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    super.dispose();
  }

  /// لما ترجع من الخلفية (بعد فتح رابط التحقق والرجوع للتطبيق) نعيد الفحص
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _manualCheck();
    }
  }

  Future<void> _sendIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified && !_sentOnce) {
      try {
        setState(() => _sending = true);
        await AuthService.resendVerificationEmail(useDeepLink: false);
        if (!mounted) return;
        setState(() {
          _sentOnce = true;
          _sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال رسالة التحقق إلى بريدك')),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إرسال رسالة التحقق: $e')),
        );
      }
    }
  }

  void _startPolling() {
    _poller = Timer.periodic(const Duration(seconds: 4), (_) async {
      final ok = await _reloadAndIsVerified();
      if (ok) {
        _poller?.cancel();
        if (!mounted) return;
        await _onVerifiedAndProceed();
      }
    });
  }

  /// إعادة تحميل المستخدم + إجبار تحديث التوكن + مهلة خفيفة
  Future<bool> _reloadAndIsVerified() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;

      await refreshed?.getIdToken(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final verified = (refreshed?.emailVerified ?? false);
      dev.log('emailVerified=$verified', name: 'VerifyEmailPage');
      return verified;
    } catch (e) {
      dev.log('reload failed: $e', name: 'VerifyEmailPage', level: 900);
      return false;
    }
  }

  /// يضمن تأسيس وثيقة المستخدم اللازمة للأونبوردنق (Legacy root):
  /// - users/{uid}
  Future<void> _bootstrapUserDocs() async {
    try {
      await const LegacyUserRepository()
          .ensureLegacyUserDocExists()
          .timeout(const Duration(seconds: 20));
      OnbLog.i('VerifyEmailPage', 'BOOTSTRAP_DOCS_OK');
    } on FirebaseException catch (e, st) {
      OnbLog.e('VerifyEmailPage', 'BOOTSTRAP_DOCS_FIREBASE_EXCEPTION', e, st);
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await FirestoreDiag.diagnoseWrite(
          tag: 'verify_bootstrap_${e.code}',
          ref: FirebaseFirestore.instance.collection('users').doc(u.uid),
          payload: {'diagPing': DateTime.now().toIso8601String()},
        );
      }
      dev.log('bootstrap user docs failed: $e', name: 'VerifyEmailPage', level: 900);
    } catch (e, st) {
      OnbLog.e('VerifyEmailPage', 'BOOTSTRAP_DOCS_UNKNOWN_EXCEPTION', e, st);
      dev.log('bootstrap user docs failed: $e', name: 'VerifyEmailPage', level: 900);
    }
  }

  Future<void> _onVerifiedAndProceed() async {
    OnbLog.i('VerifyEmailPage', 'VERIFIED_PROCEED_START');
    try {
      final faUser = FirebaseAuth.instance.currentUser!;
      if (!faUser.emailVerified) {
        // double-check في حال تم نداء الدالة بدون تحقق
        await faUser.reload();
        if (!FirebaseAuth.instance.currentUser!.emailVerified) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لسه ما تم التحقق. افتح الرابط ثم اضغط متابعة.')),
          );
          return;
        }
      }

      // (1) تهيئة وثيقة المستخدم (users/{uid} الجذر فقط)
      await _bootstrapUserDocs();
      OnbLog.i('VerifyEmailPage', 'BOOTSTRAP_DOCS_DONE');

      final prefs = await SharedPreferences.getInstance();
      final emailKey = widget.email;

      // (قراءات اختيارية من Prefs)
      final firstName = prefs.getString('firstName_$emailKey') ?? '';
      final lastName  = prefs.getString('lastName_$emailKey')  ?? '';
      final username  = prefs.getString('username_$emailKey')  ?? '';

      // (2) تزامن AppUser — محمي
      AppUser? me;
      try {
        final authRepo = LocalAuthRepo();
        me = await authRepo.currentUser();
      } catch (e) {
        dev.log('LocalAuthRepo.currentUser failed: $e', name: 'VerifyEmailPage', level: 800);
      }

      // (3) تطبيق username المخزّن (اختياري) — محمي
      if (me != null && username.trim().isNotEmpty) {
        try {
          final authRepo = LocalAuthRepo();
          await authRepo.markUsernameExplicit(me.uid, explicit: true);
          final patched = AppUser(
            uid: me.uid,
            username: username.trim(),
            email: me.email,
            gender: me.gender,
            createdAt: me.createdAt,
            followers: me.followers,
            following: me.following,
            bio: me.bio,
            profileImagePath: me.profileImagePath,
          );
          await authRepo.updateUser(patched); // لو تكتب حقول غير مسموحة بالقواعد، ما يوقف التسلسل
        } catch (e) {
          dev.log('updateUser(username) failed: $e', name: 'VerifyEmailPage', level: 800);
        }
      }

      // (اختياري) تخزين محلي للأسماء فقط
      if (firstName.isNotEmpty) {
        await prefs.setString('firstName_${faUser.uid}', firstName);
      }
      if (lastName.isNotEmpty) {
        await prefs.setString('lastName_${faUser.uid}', lastName);
      }

      // (4) مفاتيح محلية أساسية
      await prefs.setString('currentEmail', faUser.email ?? emailKey);
      await prefs.setBool('isLoggedIn', true);
      await prefs.setBool('hasLaunchedBefore', true);

      // (5) انتقال مضمون
      _navToQuestions();

    } on FirebaseException catch (e, st) {
      OnbLog.e('VerifyEmailPage', 'VERIFIED_PROCEED_FIREBASE_EXCEPTION', e, st);
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await FirestoreDiag.diagnoseWrite(
          tag: 'verify_proceed_${e.code}',
          ref: FirebaseFirestore.instance.collection('users').doc(u.uid),
          payload: {'diagPing': DateTime.now().toIso8601String()},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إكمال التهيئة بعد التحقق: ${e.code}')),
      );
    } catch (e, st) {
      OnbLog.e('VerifyEmailPage', 'VERIFIED_PROCEED_UNKNOWN_EXCEPTION', e, st);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إكمال التهيئة بعد التحقق: $e')),
      );
    }
  }

  void _navToQuestions() {
    if (_navigated) return;
    _navigated = true;

    // ✅ اقفل أي فوكس/كيبورد قبل التنقل (يمنع تحذيرات iOS)
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.hasFocus) focus.unfocus();

    dev.log('Navigating back to AuthGate ...', name: 'VerifyEmailPage');

    final navigator = Navigator.of(context, rootNavigator: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    });
  }

  Future<void> _manualCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await _reloadAndIsVerified();
    setState(() => _checking = false);

    if (ok) {
      await _onVerifiedAndProceed();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لسّا ما تم التحقق — افتح الرابط من الإيميل ثم ارجع هنا'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('تحقق من بريدك الإلكتروني')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('أرسلنا رابط تفعيل إلى:', style: tt.titleMedium),
            const SizedBox(height: 8),
            Text(widget.email,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
                'افتح بريدك واضغط على رابط التحقق. بعدها ارجع للتطبيق — سنتحقق تلقائيًا أو اضغط متابعة.'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : _sendIfNeeded,
                    icon: const Icon(Icons.refresh),
                    label: Text(_sentOnce ? 'إعادة الإرسال' : 'إرسال رسالة التحقق'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _checking ? null : _manualCheck,
                    icon: _checking
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified),
                    label: Text(_checking ? 'جارٍ التحقّق...' : 'تم التحقق — تابع'),
                  ),
                ),
              ],
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await AuthService.signOut();
                if (!mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
              },
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل خروج'),
            ),
          ],
        ),
      ),
    );
  }
}

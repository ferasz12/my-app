// lib/screens/verify_email_page.dart
// Final hardened version:
// - Polling + manual check + resume-from-background
// - يعتمد على LegacyUserRepository لتأسيس users/{uid} (الجذر فقط)
// - بعد التحقق يرجع لنقطة الدخول (AuthGate) بدل القفز مباشرة
// - Unfocus keyboard before navigation (fixes iOS warnings)

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/auth_gate.dart';
import '../data/legacy_user_repository.dart';

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

  String _displayEmail = '';
  String? _pendingEmail; // بريد جديد بانتظار التحقق (تعديل البريد)
  bool _updatingEmail = false;

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
  if (user == null) return;

  // لا ترسل إذا كان متحقق بالفعل
  if (user.emailVerified) return;

  // منع تكرار الضغط أثناء الإرسال
  if (_sending) return;
  
// ✅ منع الإرسال المتكرر مباشرة بعد التسجيل/الإرسال الأخير (يقلل too-many-requests)
  try {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt('verify_email_last_sent_${user.uid}');
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      final diff = DateTime.now().difference(last);
      // إذا تم الإرسال خلال آخر 45 ثانية، لا تعِد الإرسال—اكتفِ برسالة لطيفة
      if (diff < const Duration(seconds: 45) &&
          (_pendingEmail == null || _pendingEmail!.trim().isEmpty)) {
        setState(() => _sentOnce = true);
        

      // حفظ وقت الإرسال لمنع التكرار السريع
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'verify_email_last_sent_${user.uid}',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال رسالة التحقق إلى بريدك')),
          );
        }
        return;
      }
    }
  } catch (_) {}

  try {
    setState(() => _sending = true);

    // لو المستخدم طلب تعديل البريد: نرسل رابط التحقق للبريد الجديد
    if (_pendingEmail != null && _pendingEmail!.trim().isNotEmpty) {
      final next = _pendingEmail!.trim();
      await user.verifyBeforeUpdateEmail(next);
      setState(() {
        _displayEmail = next;
        _sentOnce = true;
      });

      
      // حفظ وقت الإرسال لمنع التكرار السريع
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'verify_email_last_sent_${user.uid}',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال رابط التحقق إلى $next')),
      );
    } else {
      // إرسال التحقق للبريد الحالي (الافتراضي)
      await AuthService.resendVerificationEmail(useDeepLink: false);
      setState(() => _sentOnce = true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رسالة التحقق إلى بريدك')),
      );
    }
  } on FirebaseAuthException catch (e) {
    if (!mounted) return;
    final code = e.code.toLowerCase();
    String msg;
    if (code == 'too-many-requests') {
      msg = 'تم إرسال رسالة التحقق مسبقًا. انتظر قليلًا ثم حاول إعادة الإرسال.';
    } else if (code == 'network-request-failed') {
      msg = 'مشكلة في الاتصال. تأكد من الشبكة ثم حاول مرة أخرى.';
    } else {
      msg = 'تعذّر إرسال رسالة التحقق الآن. حاول بعد قليل.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذّر إرسال رسالة التحقق الآن. حاول بعد قليل.')),
    );
  } finally {
    if (mounted) setState(() => _sending = false);
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
    } catch (e) {
      dev.log('bootstrap user docs failed: $e', name: 'VerifyEmailPage', level: 900);
    }
  }

  Future<void> _onVerifiedAndProceed() async {
    try {
      final faUser = FirebaseAuth.instance.currentUser!;
      if (!faUser.emailVerified) {
        // double-check في حال تم نداء الدالة بدون تحقق
        await faUser.reload();
        if (!FirebaseAuth.instance.currentUser!.emailVerified) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('باقي ماتم التحقق افتح الرابط ثم اضغط متابعة')),
          );
          return;
        }
      }

      // (1) تهيئة وثيقة المستخدم (users/{uid} الجذر فقط)
      await _bootstrapUserDocs();

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

    } catch (e) {
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
          content: Text('باقي ماتم التحقق افتح الرابط من الايميل وارجع هنا'),
        ),
      );
    }
  }

  
  bool _isValidEmail(String value) {
    final v = value.trim();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(v);
  }

  Future<void> _openEditEmailSheet() async {
    final controller = TextEditingController(text: _displayEmail);
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final mq = MediaQuery.of(sheetCtx);
        return Padding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                            color: Colors.black.withOpacity(0.12),
                          ),
                        ],
                      ),
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                                  ),
                                  child: Icon(
                                    Icons.email_outlined,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'تعديل البريد الإلكتروني',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'إذا كتبته غلط، غيّره هنا ثم بنرسل لك رابط تحقق جديد.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
                                  ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: controller,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'البريد الإلكتروني',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                              validator: (v) {
                                final value = (v ?? '').trim();
                                if (value.isEmpty) return 'اكتب البريد الإلكتروني';
                                if (!_isValidEmail(value)) return 'صيغة البريد غير صحيحة';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _updatingEmail ? null : () => Navigator.pop(sheetCtx),
                                    child: const Text('إلغاء'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _updatingEmail
                                        ? null
                                        : () async {
                                            if (!formKey.currentState!.validate()) return;
                                            Navigator.pop(sheetCtx);
                                            await _updateEmailAndResend(controller.text.trim());
                                          },
                                    child: const Text('حفظ'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateEmailAndResend(String newEmail) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final current = (user.email ?? '').trim();
    final next = newEmail.trim();

    if (next.isEmpty || !_isValidEmail(next)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('صيغة البريد غير صحيحة')),
      );
      return;
    }

    if (current.isNotEmpty && current.toLowerCase() == next.toLowerCase()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا هو نفس البريد الحالي')),
      );
      return;
    }

    setState(() => _updatingEmail = true);
    try {
            // في firebase_auth 6.x تم إزالة updateEmail واستخدم verifyBeforeUpdateEmail
      _pendingEmail = next;
      await user.verifyBeforeUpdateEmail(next);

      // نعرض البريد الجديد فورًا (سيُحدّث رسميًا بعد الضغط على رابط التحقق)
      setState(() {
        _displayEmail = next;
        _sentOnce = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث البريد وإرسال رابط تحقق جديد')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String msg = 'تعذّر تحديث البريد';
      if (e.code == 'requires-recent-login') {
        msg = 'لأمان حسابك: سجّل دخول مرة ثانية ثم غيّر البريد.';
      } else if (e.code == 'email-already-in-use') {
        msg = 'هذا البريد مستخدم من قبل.';
      } else if (e.code == 'invalid-email') {
        msg = 'صيغة البريد غير صحيحة.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$msg (${e.code})')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تحديث البريد: $e')),
      );
    } finally {
      if (mounted) setState(() => _updatingEmail = false);
    }
  }


  
@override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final emailToShow = (_displayEmail.isNotEmpty)
        ? _displayEmail
        : (FirebaseAuth.instance.currentUser?.email ?? widget.email);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Tooltip(
          message: 'رجوع',
          child: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: const Text('تحقق من بريدك'),
      ),
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    cs.primary.withOpacity(0.20),
                    cs.secondary.withOpacity(0.12),
                    cs.surface,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.85, -0.9),
                  radius: 1.2,
                  colors: [
                    cs.primary.withOpacity(0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withOpacity(0.12),
                            ),
                            child: Icon(Icons.verified_outlined, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'باقي خطوة أخيرة ✨',
                                  style: tt.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'فعّل بريدك ثم ارجع هنا واضغط متابعة.',
                                  style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurface.withOpacity(0.70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Glass card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.surface.withOpacity(0.78),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: cs.onSurface.withOpacity(0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 26,
                                  offset: const Offset(0, 14),
                                  color: Colors.black.withOpacity(0.10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'أرسلنا رابط التحقق إلى:',
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: cs.primary.withOpacity(0.12),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          emailToShow,
                                          style: tt.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      OutlinedButton.icon(
                                        onPressed: _updatingEmail ? null : _openEditEmailSheet,
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        label: const Text('تعديل'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '''نصائح سريعة:
• افتح بريدك وابحث عن رسالة "تفعيل الحساب".
• إذا ما وصلت، جرّب مجلد Spam / Junk.
• بعد الضغط على الرابط، ارجع هنا واضغط متابعة.''',
                                  style: tt.bodyMedium?.copyWith(
                                    height: 1.35,
                                    color: cs.onSurface.withOpacity(0.78),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_sending || _updatingEmail) ? null : _sendIfNeeded,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh),
                              label: Text(_sentOnce ? 'إعادة الإرسال' : 'إرسال رسالة التحقق'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (_checking || _updatingEmail) ? null : _manualCheck,
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

                      const SizedBox(height: 10),

                      // Secondary actions
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const BackButtonIcon(),
                            label: const Text('رجوع للصفحة السابقة'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () async {
                              await AuthService.signOut();
                              if (!mounted) return;
                              Navigator.of(context)
                                  .pushNamedAndRemoveUntil('/login', (r) => false);
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('تسجيل خروج'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),
                      Text(
                        'ملاحظة: سيتم تفعيل حسابك مباشرة بعد التحقق والعودة للتطبيق.',
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
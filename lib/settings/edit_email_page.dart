import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تغيير البريد الإلكتروني (Flow مضبوط ومضمون):
/// 1) المستخدم يكتب بريده القديم → نتحقق أنه نفس البريد الحالي.
/// 2) يكتب البريد الجديد → نرسل رسالة تفعيل للبريد الجديد عبر verifyBeforeUpdateEmail.
/// 3) بعد ما يفعّل من الإيميل يرجع ويضغط "تحقّق" → إذا تغير بريد Firebase Auth فعليًا
///    نحدّث Firestore (users/{uid}) ونرحّل القيم المحلية في SharedPreferences.
class EditEmailPage extends StatefulWidget {
  const EditEmailPage({super.key});

  @override
  State<EditEmailPage> createState() => _EditEmailPageState();
}

class _EditEmailPageState extends State<EditEmailPage>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _oldEmailCtl = TextEditingController();
  final _newEmailCtl = TextEditingController();

  bool _sending = false;
  bool _checking = false;

  bool _sent = false;
  String? _pendingNewEmail;
  String? _oldEmailAtRequest;

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final currentEmail = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    if (currentEmail.isNotEmpty) {
      _oldEmailCtl.text = currentEmail;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _oldEmailCtl.dispose();
    _newEmailCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // بعد ما يفتح رابط التفعيل ويرجع للتطبيق
    if (state == AppLifecycleState.resumed && _sent) {
      _checkCompletion(silentIfNotDone: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تغيير البريد الإلكتروني')),
        body: const Center(child: Text('لا يوجد مستخدم مسجّل دخول.')),
      );
    }

    final currentEmail = (user.email ?? '').trim();
    final canUseEmail = currentEmail.isNotEmpty;

    if (!canUseEmail) {
      return Scaffold(
        appBar: AppBar(title: const Text('تغيير البريد الإلكتروني')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _infoCard(
            context,
            icon: Icons.info_outline,
            title: 'لا يوجد بريد مرتبط بالحساب',
            message:
                'حسابك الحالي لا يحتوي على بريد إلكتروني في Firebase Auth.\n\nإذا كنت مسجّل عن طريق Apple/Google وبريدك مخفي، يلزم إعادة تسجيل الدخول بحساب يحتوي بريد قابل للتعديل.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('تغيير البريد الإلكتروني')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(context, currentEmail),
            const SizedBox(height: 14),

            _stepCard(
              context,
              step: '1',
              title: 'البريد الحالي',
              subtitle:
                  'اكتب بريدك الحالي للتأكد أنه نفس بريد الحساب (أمانًا).',
              child: TextFormField(
                controller: _oldEmailCtl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'البريد الحالي',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'اكتب البريد الحالي';
                  if (!_isValidEmail(value)) return 'صيغة البريد غير صحيحة';
                  if (value.toLowerCase() != currentEmail.toLowerCase()) {
                    return 'البريد لا يطابق بريد حسابك الحالي';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 12),

            _stepCard(
              context,
              step: '2',
              title: 'البريد الجديد',
              subtitle:
                  'بنرسل رسالة تفعيل للبريد الجديد. ما راح يتغير بريدك فعليًا إلا بعد التفعيل.',
              child: TextFormField(
                controller: _newEmailCtl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'البريد الجديد',
                  prefixIcon: Icon(Icons.mark_email_unread_outlined),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'اكتب البريد الجديد';
                  if (!_isValidEmail(value)) return 'صيغة البريد غير صحيحة';
                  if (value.toLowerCase() == currentEmail.toLowerCase()) {
                    return 'اكتب بريد مختلف عن الحالي';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 14),

            FilledButton.icon(
              onPressed: _sending ? null : _sendVerification,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('إرسال رسالة التفعيل للبريد الجديد'),
            ),

            const SizedBox(height: 12),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _sent
                  ? _successWaitingCard(context, cs, tt)
                  : _infoCard(
                      context,
                      icon: Icons.verified_user_outlined,
                      title: 'معلومة مهمة',
                      message:
                          'بعد ما توصلك الرسالة على البريد الجديد، افتح الرابط وفعّل البريد،\nثم ارجع هنا واضغط "تحقّق".',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------
  // Actions
  // ---------------------------

  Future<void> _sendVerification() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) return;

    if (user.isAnonymous) {
      _snack('لا يمكن تغيير البريد لحساب الضيف. سجّل دخولًا عاديًا.');
      return;
    }

    final currentEmail = (user.email ?? '').trim();
    final oldEmail = _oldEmailCtl.text.trim();
    final newEmail = _newEmailCtl.text.trim();

    if (oldEmail.toLowerCase() != currentEmail.toLowerCase()) {
      _snack('البريد الحالي غير مطابق لبريد الحساب.');
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _verifyBeforeUpdateEmailWithReauth(user, currentEmail, newEmail);

      // خزّن pending في Firestore حتى لو المستخدم قفل الصفحة
      final db = FirebaseFirestore.instance;
      final now = Timestamp.now();

      await db.collection('users').doc(user.uid).set({
        'pendingEmail': newEmail,
        'emailChangeOld': currentEmail,
        'emailChangeRequestedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      await db
          .collection('users')
          .doc(user.uid)
          .collection('security_events')
          .add({
        'type': 'email_change_requested',
        'at': now,
        'platform': Platform.operatingSystem,
        'oldEmail': currentEmail,
        'newEmail': newEmail,
      });

      if (!mounted) return;

      setState(() {
        _sent = true;
        _pendingNewEmail = newEmail;
        _oldEmailAtRequest = currentEmail;
      });

      _startPolling();

      _snack('تم إرسال رسالة التفعيل للبريد الجديد.');
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _snack('حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startPolling() {
    _poller?.cancel();
    // Polling خفيف... إذا خلّصت التفعيل وهو خارج التطبيق، يرجع ويلقاه يتحدث تلقائيًا.
    _poller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_sent || _checking) return;
      _checkCompletion(silentIfNotDone: true);
    });
  }

  Future<void> _checkCompletion({bool silentIfNotDone = false}) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    final pending = _pendingNewEmail?.trim();
    if (user == null || pending == null || pending.isEmpty) return;

    if (_checking) return;
    setState(() => _checking = true);

    try {
      await user.reload();
      final refreshed = auth.currentUser;
      await refreshed?.getIdToken(true);

      final actualEmail = (refreshed?.email ?? '').trim();
      final completed = actualEmail.isNotEmpty &&
          actualEmail.toLowerCase() == pending.toLowerCase();

      if (!completed) {
        if (!silentIfNotDone) {
          _snack('باقي ما تم تفعيل البريد الجديد. افتح الرابط من الإيميل ثم جرّب.');
        }
        return;
      }

      // ✅ اكتمل التغيير في Firebase Auth ... الآن نحدّث قاعدة البيانات + نرحّل المفاتيح
      final oldEmail = (_oldEmailAtRequest ?? _oldEmailCtl.text).trim();
      await _finalizeEmailInDatabase(uid: refreshed!.uid, oldEmail: oldEmail, newEmail: actualEmail);
      await _migratePrefsEmailSuffix(oldEmail: oldEmail, newEmail: actualEmail);

      if (!mounted) return;

      _poller?.cancel();

      setState(() {
        _sent = false;
        _pendingNewEmail = null;
        _oldEmailAtRequest = null;
        _oldEmailCtl.text = actualEmail;
        _newEmailCtl.clear();
      });

      _snack('تم تغيير البريد بنجاح ✅');
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _snack('تعذّر التحقق: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _finalizeEmailInDatabase({
    required String uid,
    required String oldEmail,
    required String newEmail,
  }) async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    final userRef = db.collection('users').doc(uid);

    await userRef.set({
      'email': newEmail,
      'email_lower': newEmail.toLowerCase(),
      'pendingEmail': FieldValue.delete(),
      'emailChangeOld': FieldValue.delete(),
      'emailChangeRequestedAt': FieldValue.delete(),
      'emailChangeCompletedAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await userRef.collection('security_events').add({
      'type': 'email_change_completed',
      'at': now,
      'platform': Platform.operatingSystem,
      'oldEmail': oldEmail,
      'newEmail': newEmail,
    });
  }

  Future<void> _verifyBeforeUpdateEmailWithReauth(
    User user,
    String currentEmail,
    String newEmail,
  ) async {
    try {
      await user.verifyBeforeUpdateEmail(newEmail);
      return;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;

      // جرّب إعادة توثيق لو حساب بريد/كلمة مرور
      final isPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
      if (!isPasswordProvider) {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message:
              'لأمان حسابك: سجّل خروج ثم سجّل دخول مرة ثانية ثم أعد محاولة تغيير البريد.',
        );
      }

      final pass = await _askPassword(context);
      if (pass == null || pass.trim().isEmpty) {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: 'تم إلغاء التأكيد.',
        );
      }

      final cred = EmailAuthProvider.credential(email: currentEmail, password: pass.trim());
      await user.reauthenticateWithCredential(cred);

      // أعد المحاولة بعد إعادة التوثيق
      await user.verifyBeforeUpdateEmail(newEmail);
    }
  }

  static Future<String?> _askPassword(BuildContext context) async {
    final ctl = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('تأكيد الهوية'),
              content: TextField(
                controller: ctl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setLocal(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('تأكيد')),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------
  // UI helpers
  // ---------------------------

  Widget _header(BuildContext context, String currentEmail) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.18),
            cs.secondary.withOpacity(0.12),
            cs.surface,
          ],
        ),
        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withOpacity(0.12),
            ),
            child: Icon(Icons.email_outlined, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تغيير البريد', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'بريدك الحالي: $currentEmail',
                  style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard(
    BuildContext context, {
    required String step,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surface,
        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withOpacity(0.12),
                ),
                child: Text(
                  step,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.secondaryContainer.withOpacity(0.35),
        border: Border.all(color: cs.onSurface.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(message, style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _successWaitingCard(BuildContext context, ColorScheme cs, TextTheme tt) {
    final pending = _pendingNewEmail ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.primaryContainer.withOpacity(0.35),
        border: Border.all(color: cs.onSurface.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم إرسال رسالة التفعيل إلى: $pending',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'افتح البريد الجديد واضغط رابط التفعيل.\nبعدها ارجع واضغط زر (تحقّق).',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.75)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : () => _checkCompletion(silentIfNotDone: false),
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('تحقّق'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sending ? null : _sendVerification,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة الإرسال'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Validation / utils
  // ---------------------------

  bool _isValidEmail(String value) {
    final v = value.trim();
    // بسيط ومتين
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(v);
  }

  Future<void> _migratePrefsEmailSuffix({
    required String oldEmail,
    required String newEmail,
  }) async {
    if (oldEmail.trim().isEmpty || newEmail.trim().isEmpty) return;
    if (oldEmail.toLowerCase() == newEmail.toLowerCase()) return;

    final prefs = await SharedPreferences.getInstance();

    // تحديث currentEmail (مهم للشاشات القديمة)
    await prefs.setString('currentEmail', newEmail);

    // رحّل أي مفتاح ينتهي بـ oldEmail إلى newEmail
    final keys = prefs.getKeys().toList();
    for (final k in keys) {
      if (!k.endsWith(oldEmail)) continue;
      final newKey = k.substring(0, k.length - oldEmail.length) + newEmail;
      final val = prefs.get(k);
      if (val == null) continue;

      if (val is String) {
        await prefs.setString(newKey, val);
      } else if (val is int) {
        await prefs.setInt(newKey, val);
      } else if (val is double) {
        await prefs.setDouble(newKey, val);
      } else if (val is bool) {
        await prefs.setBool(newKey, val);
      } else if (val is List<String>) {
        await prefs.setStringList(newKey, val);
      }
    }

    // خزن آخر بريدين للتشخيص (اختياري)
    await prefs.setString('lastEmailChange_old', oldEmail);
    await prefs.setString('lastEmailChange_new', newEmail);
  }

  void _handleAuthError(FirebaseAuthException e) {
    String msg;
    switch (e.code) {
      case 'invalid-email':
        msg = 'صيغة البريد غير صحيحة';
        break;
      case 'email-already-in-use':
        msg = 'هذا البريد مستخدم من قبل';
        break;
      case 'requires-recent-login':
        msg = e.message ??
            'لأمان حسابك: يلزم إعادة تسجيل الدخول (Sign out ثم Sign in) ثم أعد المحاولة.';
        break;
      case 'wrong-password':
        msg = 'كلمة المرور غير صحيحة';
        break;
      case 'network-request-failed':
        msg = 'مشكلة اتصال بالشبكة';
        break;
      default:
        msg = 'خطأ: ${e.code}';
    }
    _snack(msg);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

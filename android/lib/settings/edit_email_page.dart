import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditEmailPage extends StatefulWidget {
  const EditEmailPage({super.key});

  @override
  State<EditEmailPage> createState() => _EditEmailPageState();
}

class _EditEmailPageState extends State<EditEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passCtl  = TextEditingController();

  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('تغيير البريد الإلكتروني')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: s.secondaryContainer.withOpacity(.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: s.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سنقوم بإعادة المصادقة بكلمة المرور الحالية، ثم نرسل رابط تأكيد للبريد الجديد. سيتم تغيير البريد بعد الضغط على الرابط.',
                      style: t.bodySmall?.copyWith(color: s.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'البريد الجديد',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'أدخل البريد';
                final ok = RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$")
                    .hasMatch(s);
                if (!ok) return 'بريد غير صالح';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _passCtl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية (لإعادة التوثيق)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
            ),

            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
            const SizedBox(height: 12),
            const Text(
              '💡 ملاحظة: لا نحدّث بريدك في قاعدة البيانات إلا بعد إتمام تأكيد البريد الجديد.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد مستخدم مسجل. قم بتسجيل الدخول أولاً.')),
      );
      return;
    }
    if (user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن تغيير بريد حساب الضيف. سجّل دخولًا عاديًا.')),
      );
      return;
    }

    final newEmail = _emailCtl.text.trim();
    final currentPass = _passCtl.text.trim();

    setState(() => _busy = true);

    try {
      // 1) إعادة مصادقة بالبريد/كلمة المرور الحالية
      final currentEmail = user.email;
      if (currentEmail == null || currentEmail.isEmpty) {
        throw FirebaseAuthException(
          code: 'no-email-on-user',
          message: 'حسابك ليس Email/Password. أعد تسجيل الدخول بمقدّم اعتماد يدعم البريد.',
        );
      }

      final cred = EmailAuthProvider.credential(email: currentEmail, password: currentPass);
      await user.reauthenticateWithCredential(cred);

      // 2) إرسال رابط تأكيد وتحديث البريد بعد التحقق (بدل updateEmail)
      //    IMPORTANT: عدّل ActionCodeSettings حسب تطبيقك (روابط عميقة/الـ bundleId).
      final acs = ActionCodeSettings(
        url: 'https://your-domain.example/finishEmailUpdate?email=$newEmail',
        handleCodeInApp: true,
        iOSBundleId: 'com.your.bundleId',
        androidPackageName: 'com.your.package',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );
      await user.verifyBeforeUpdateEmail(newEmail, acs);

      // 3) وضع pendingEmail في Firestore + سجل أمني
      final db = FirebaseFirestore.instance;
      final now = Timestamp.now();

      await db.collection('users').doc(user.uid).set({
        'pendingEmail': newEmail,
        'emailChangeRequestedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      await db.collection('users').doc(user.uid).collection('security_events').add({
        'type': 'email_change_requested',
        'at': now,
        'platform': Platform.operatingSystem,
        'newEmail': newEmail,
        'oldEmail': currentEmail,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رابط التأكيد للبريد الجديد. افتح الرابط لإتمام التغيير.')),
      );

      // 4) افتح صفحة انتظار التحقق (ستقوم هناك بعمل reload وتحديث Firestore إن اكتمل التغيير)
      Navigator.pushNamed(context, '/verifyEmail', arguments: {'email': newEmail});
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    String msg;
    switch (e.code) {
      case 'invalid-email':
        msg = 'البريد الجديد غير صالح';
        break;
      case 'email-already-in-use':
        msg = 'هذا البريد مستخدم سابقًا';
        break;
      case 'requires-recent-login':
        msg = 'يلزم تسجيل الدخول مؤخرًا. تأكد من كلمة المرور الحالية ثم أعد المحاولة.';
        break;
      case 'wrong-password':
        msg = 'كلمة المرور الحالية غير صحيحة';
        break;
      case 'user-mismatch':
      case 'user-not-found':
        msg = 'حساب غير موجود أو غير متطابق';
        break;
      case 'network-request-failed':
        msg = 'مشكلة اتصال بالشبكة';
        break;
      default:
        msg = 'خطأ: ${e.code}';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditPasswordPage extends StatefulWidget {
  const EditPasswordPage({super.key});

  @override
  State<EditPasswordPage> createState() => _EditPasswordPageState();
}

class _EditPasswordPageState extends State<EditPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtl = TextEditingController();
  final _newCtl = TextEditingController();
  final _confirmCtl = TextEditingController();

  bool _busy = false;
  bool _ob1 = true, _ob2 = true, _ob3 = true;

  @override
  void dispose() {
    _oldCtl.dispose();
    _newCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('تغيير كلمة المرور')),
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
                      'الحد الأدنى 6 أحرف. إذا ظهر تنبيه “يلزم تسجيل الدخول مؤخرًا”، سنعيد المصادقة تلقائيًا بكلمة المرور الحالية.',
                      style: t.bodySmall?.copyWith(color: s.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _oldCtl,
              obscureText: _ob1,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_ob1 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _ob1 = !_ob1),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور الحالية' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _newCtl,
              obscureText: _ob2,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                prefixIcon: const Icon(Icons.lock_person_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_ob2 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _ob2 = !_ob2),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'أدخل كلمة المرور الجديدة';
                if (v.length < 6) return 'يجب أن تكون 6 أحرف فأكثر';
                if (v == _oldCtl.text) return 'اختر كلمة مرور مختلفة عن الحالية';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _confirmCtl,
              obscureText: _ob3,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                prefixIcon: const Icon(Icons.lock_reset),
                suffixIcon: IconButton(
                  icon: Icon(_ob3 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _ob3 = !_ob3),
                ),
              ),
              validator: (v) => (v != _newCtl.text) ? 'غير متطابقة' : null,
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('حفظ'),
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
        const SnackBar(content: Text('لا يمكن تغيير كلمة مرور حساب الضيف. سجّل دخولًا عاديًا.')),
      );
      return;
    }

    setState(() => _busy = true);

    final newPass = _newCtl.text.trim();
    try {
      // محاولة مباشرة لتغيير كلمة المرور
      await user.updatePassword(newPass);
      await _postUpdateSecurityLog(user.uid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كلمة المرور')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      // إذا احتاج إعادة مصادقة
      if (e.code == 'requires-recent-login') {
        final ok = await _reauthWithEmailPassword(user);
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('فشل التحقق من كلمة المرور الحالية')),
            );
          }
          setState(() => _busy = false);
          return;
        }
        // بعد إعادة المصادقة جرّب التحديث مرة ثانية
        try {
          await user.updatePassword(newPass);
          await _postUpdateSecurityLog(user.uid);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تغيير كلمة المرور')),
          );
          Navigator.pop(context);
        } on FirebaseAuthException catch (ee) {
          _handleAuthError(ee);
          setState(() => _busy = false);
        }
      } else {
        _handleAuthError(e);
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
      setState(() => _busy = false);
    }
  }

  Future<bool> _reauthWithEmailPassword(User user) async {
    try {
      final email = user.email;
      if (email == null || email.isEmpty) {
        // الحساب ليس Email/Password (غالباً موصول Google/Apple فقط)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حسابك ليس Email/Password. أعد تسجيل الدخول ثم حاول مرة أخرى.')),
          );
        }
        return false;
      }

      final cred = EmailAuthProvider.credential(
        email: email,
        password: _oldCtl.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);
      return true;
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
      return false;
    } catch (_) {
      return false;
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    String msg;
    switch (e.code) {
      case 'wrong-password':
        msg = 'كلمة المرور الحالية غير صحيحة';
        break;
      case 'weak-password':
        msg = 'كلمة المرور الجديدة ضعيفة. استخدم 6 أحرف فأكثر';
        break;
      case 'too-many-requests':
        msg = 'طلبات كثيرة. حاول لاحقًا';
        break;
      case 'network-request-failed':
        msg = 'مشكلة اتصال بالشبكة';
        break;
      case 'user-mismatch':
      case 'user-not-found':
        msg = 'حساب غير موجود أو غير متطابق';
        break;
      case 'requires-recent-login':
        msg = 'يلزم تسجيل الدخول مؤخرًا. سنحاول إعادة التحقق تلقائيًا.';
        break;
      default:
        msg = 'خطأ: ${e.code}';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _postUpdateSecurityLog(String uid) async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    // تحديث users/{uid}
    await db.collection('users').doc(uid).set({
      'passwordChangedAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    // سجل أمني
    await db.collection('users').doc(uid).collection('security_events').add({
      'type': 'password_change',
      'at': now,
      'platform': Platform.operatingSystem, // android / ios / macos / windows / linux / fuchsia
    });
  }
}

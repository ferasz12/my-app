// lib/screens/login_page.dart — تصميم متوافق مع صفحة التسجيل (أفخم/RTL) بدون أي طباعات
// - بطاقة وسط الشاشة + خلفية متدرّجة مماثلة
// - نفس أسلوب الحقول والمكونات البصرية
// - FirebaseAuth (تسجيل دخول بالبريد/كلمة مرور) + تهيئة رسائل الخطأ بالعربية
// - تذكير بالتحقق من البريد + خيار إعادة إرسال رسالة التحقق
// - رابط "نسيت كلمة المرور" + رابط للانتقال إلى صفحة التسجيل

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'أدخل البريد الإلكتروني';
    final s = v.trim();
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s)) return 'بريد غير صالح';
    return null;
  }

  String? _validatePass(String? v) {
    if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
    if (v.length < 6) return 'ستة أحرف على الأقل';
    return null;
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : null),
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
        _snack('تعذر تسجيل الدخول، حاول لاحقًا');
        return;
      }

      await user.reload();
      if (!user.emailVerified) {
        if (!mounted) return;
        final resend = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('تفعيل البريد مطلوب'),
            content: Text('حسابك لم يُفعَّل بعد. هل تريد إرسال رسالة تحقق إلى\n${_emailCtrl.text.trim()}؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لاحقًا')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('أرسل الآن')),
            ],
          ),
        );
        if (resend == true) {
          await user.sendEmailVerification();
          _snack('تم إرسال رسالة التحقق إلى بريدك', ok: true);
        }
        return; // نبقي المستخدم في صفحة الدخول حتى يفعّل
      }

      if (!mounted) return;
      // نجاح: انتقل للصفحة الرئيسية (حدّد المسار المناسب عندك)
      Navigator.of(context).pushReplacementNamed('/');
    } on FirebaseAuthException catch (e) {
      _snack(_mapAuthError(e));
    } on TimeoutException {
      _snack('الاتصال بطيء أو غير متاح حالياً');
    } catch (e) {
      _snack('خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onForgotPassword() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !_isEmail(email)) {
      _snack('أدخل بريدًا صحيحًا أولاً');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('تم إرسال رابط استعادة كلمة المرور', ok: true);
    } on FirebaseAuthException catch (e) {
      _snack(_mapAuthError(e));
    } catch (e) {
      _snack('تعذر إرسال الاستعادة: $e');
    }
  }

  bool _isEmail(String s) => RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s);

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'لا يوجد مستخدم بهذا البريد';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة';
      case 'invalid-email':
        return 'بريد إلكتروني غير صالح';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب';
      case 'too-many-requests':
        return 'محاولات كثيرة، حاول لاحقًا';
      case 'network-request-failed':
        return 'تعذر الاتصال بالشبكة';
      default:
        return 'تعذر تسجيل الدخول (${e.code})';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primary.withOpacity(0.06),
                theme.colorScheme.surface,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  elevation: 8,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Text('تسجيل الدخول',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _emailCtrl,
                            label: 'البريد الإلكتروني',
                            icon: Icons.email,
                            validator: _validateEmail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _passCtrl,
                            label: 'كلمة المرور',
                            icon: Icons.lock,
                            validator: _validatePass,
                            obscure: _obsc,
                            toggleObscure: () => setState(() => _obsc = !_obsc),
                            textInputAction: TextInputAction.done,
                          ),

                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _busy ? null : _onForgotPassword,
                              child: const Text('نسيت كلمة المرور؟'),
                            ),
                          ),

                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _onLogin,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('دخول'),
                            ),
                          ),

                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('ما عندك حساب؟'),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        Navigator.of(context).pushReplacementNamed('/register');
                                      },
                                child: const Text('أنشئ حسابًا'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- نفس نمط حقول صفحة التسجيل ----
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscure = false,
    VoidCallback? toggleObscure,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: toggleObscure != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: toggleObscure,
              )
            : null,
        filled: true,
        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      obscureText: obscure,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
    );
  }
}

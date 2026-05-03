// lib/screens/register_page.dart (updated)
// - إنشاء Auth
// - ثم Transaction: (حجز usernames/{handle} + تأسيس users/{uid})
// - ثم إرسال رابط التحقق
// - رفع الصورة اختياري (Non-blocking)

import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../core/diagnostics/onb_log.dart';
import '../data/legacy_user_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // --- ثابت اسم الحقل المستخدم لتخزين رابط الصورة ---
  static const String kProfilePhotoField = 'photoUrl';

  final _formKey = GlobalKey<FormState>();
  final _handleCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _handleFocus = FocusNode();

  bool _busy = false;
  bool _obsc1 = true, _obsc2 = true;

  bool? _handleAvailable; // null = لم يتم الفحص / جاري الفحص
  String? _handleSuggestion;
  Timer? _handleDebounce;

  final _picker = ImagePicker();
  XFile? _pickedImage;

  // ===== Helpers =====
  String _normalizeHandle(String raw) => raw.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _handleCtrl.addListener(() {
      _handleDebounce?.cancel();
      _handleAvailable = null;
      _handleSuggestion = null;
      _handleDebounce = Timer(const Duration(milliseconds: 350), () {
        _checkHandleAvailability();
      });
      setState(() {});
    });
    _handleFocus.addListener(() {
      if (!_handleFocus.hasFocus) _checkHandleAvailability();
    });
  }

  @override
  void dispose() {
    _handleDebounce?.cancel();
    _handleCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _handleFocus.dispose();
    super.dispose();
  }

  // ---------------- Firestore helpers ----------------

  Future<bool> _isHandleAvailable(String handleKey) async {
    if (handleKey.isEmpty) return false;
    final doc = await FirebaseFirestore.instance.doc('usernames/$handleKey').get();
    return !doc.exists;
  }

  /// أهم خطوة: Transaction تحجز usernames/{handle} + تؤسس users/{uid}
  Future<void> _bootstrapUserAndReserveHandle({
    required User user,
    required String handleKey,
    required String email,
  }) async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    final userRef = db.doc('users/${user.uid}');
    final unameRef = db.doc('usernames/$handleKey');

    await db.runTransaction((tx) async {
      // 1) تأكد أن اليوزرنيم غير محجوز
      final unameSnap = await tx.get(unameRef);
      if (unameSnap.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-exists',
          message: 'اسم المستخدم محجوز بالفعل',
        );
      }

      // 2) تأسيس users/{uid} (إنشاء أول مرة فقط يكتب role/isBanned)
      final userSnap = await tx.get(userRef);

      if (!userSnap.exists) {
        tx.set(userRef, {
          'uid': user.uid,
          'email': email,
          'username': handleKey,
          'username_lower': handleKey,
          'displayName': (user.displayName?.trim().isNotEmpty == true) ? user.displayName : handleKey,
          'photoUrl': (user.photoURL ?? '').toString(),
          'role': 'user',       // ✅ مسموح في create فقط حسب قواعدك
          'isBanned': false,    // ✅ نخزنها مرة في create
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        // إذا الوثيقة موجودة مسبقاً: لا نحاول إضافة role/isBanned لتجنب رفض القواعد
        tx.set(userRef, {
          'email': email,
          'username': handleKey,
          'username_lower': handleKey,
          'displayName': (user.displayName?.trim().isNotEmpty == true) ? user.displayName : handleKey,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      // 3) احجز اليوزرنيم
      tx.set(unameRef, {
        'ownerUid': user.uid,
        'createdAt': now,
      });
    });
  }

  // رفع الصورة (اختياري وغير حرِجي)
  Future<void> _uploadProfilePhotoNonBlocking(String uid) async {
    if (_pickedImage == null) return;
    try {
      final ref = FirebaseStorage.instance.ref().child('users/$uid/profile.jpg');
      if (kIsWeb) {
        final data = await _pickedImage!.readAsBytes();
        await ref.putData(data, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(_pickedImage!.path));
      }

      final url = await ref.getDownloadURL();
      final now = Timestamp.now();

      // تحديث Firestore (مسموح)
      await FirebaseFirestore.instance.doc('users/$uid').set({
        kProfilePhotoField: url,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // تحديث Auth (اختياري)
      try {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null && u.uid == uid) {
          await u.updatePhotoURL(url);
        }
      } catch (_) {}
    } on FirebaseException catch (e, st) {
      debugPrint('[RegisterPage] uploadProfilePhoto failed: ${e.code} ${e.message}\n$st');
    } catch (e, st) {
      debugPrint('[RegisterPage] uploadProfilePhoto failed: $e\n$st');
    }
  }

  // فحص توفر اليوزرنيم + اقتراح
  Future<void> _checkHandleAvailability() async {
    final raw = _handleCtrl.text.trim();
    final handleKey = _normalizeHandle(raw);

    if (raw.isEmpty ||
        raw.length < 3 ||
        raw.length > 20 ||
        !RegExp(r'^[A-Za-z]').hasMatch(raw) ||
        !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(raw) ||
        raw.contains('__')) {
      if (mounted) setState(() => _handleAvailable = null);
      return;
    }

    try {
      final ok = await _isHandleAvailable(handleKey);
      if (!mounted) return;
      setState(() {
        _handleAvailable = ok;
        if (!ok) _handleSuggestion = '${handleKey}_${DateTime.now().millisecondsSinceEpoch % 999}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _handleAvailable = null);
    }
  }

  Future<void> _rollbackAuthUser(User user) async {
    try {
      await user.delete();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  // ---------------- submit ----------------
  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    OnbLog.i('RegisterPage', 'SUBMIT_PRESSED', ctx: {
      'handle': _normalizeHandle(_handleCtrl.text),
      'email': _emailCtrl.text.trim(),
    });

    final rawHandle = _handleCtrl.text.trim();
    final handleKey = _normalizeHandle(rawHandle);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final pass2 = _pass2Ctrl.text;

    if (pass != pass2) {
      _snack('كلمتا المرور غير متطابقتين');
      return;
    }

    await _checkHandleAvailability();
    if (_handleAvailable == false) {
      _snack('اسم المستخدم مستخدم بالفعل');
      return;
    }

    setState(() => _busy = true);
    User? createdUser;

    try {
      // (1) إنشاء مستخدم Auth
      OnbLog.i('RegisterPage', 'AUTH_CREATE_START');
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      createdUser = cred.user!;

      OnbLog.i('RegisterPage', 'AUTH_CREATE_OK', ctx: {'uid': createdUser.uid});
      await createdUser.updateDisplayName(handleKey);
      await createdUser.reload();
      createdUser = FirebaseAuth.instance.currentUser;

      if (createdUser == null) {
        throw FirebaseAuthException(code: 'unknown', message: 'تعذر تثبيت الجلسة بعد التسجيل');
      }

      // (2) Transaction: تأسيس users/{uid} + حجز usernames/{handle}
      OnbLog.i('RegisterPage', 'BOOTSTRAP_FIRESTORE_START', ctx: {'uid': createdUser.uid, 'handle': handleKey});
      await _bootstrapUserAndReserveHandle(
        user: createdUser,
        handleKey: handleKey,
        email: email,
      );
      OnbLog.i('RegisterPage', 'BOOTSTRAP_FIRESTORE_OK', ctx: {'uid': createdUser.uid});

      // (2.5) تأكيد وجود وثيقة المستخدم بالجذر (Legacy root) (غير حرِجي)
      try {
        OnbLog.i('RegisterPage', 'ENSURE_LEGACY_ROOT_START', ctx: {'uid': createdUser.uid});
        await const LegacyUserRepository().ensureLegacyUserDocExists();
        OnbLog.i('RegisterPage', 'ENSURE_LEGACY_ROOT_OK', ctx: {'uid': createdUser.uid});
      } catch (e) {
        debugPrint('[RegisterPage] ensureLegacyUserDocExists failed: $e');
        OnbLog.w('RegisterPage', 'ENSURE_LEGACY_ROOT_FAILED', ctx: {'err': e.toString()});
      }

      // (3) إرسال رسالة التحقق (بعد نجاح كتابة Firestore)
      OnbLog.i('RegisterPage', 'SEND_VERIFY_EMAIL_START', ctx: {'email': email});
      await createdUser.sendEmailVerification();
      OnbLog.i('RegisterPage', 'SEND_VERIFY_EMAIL_OK');

      // (4) كتابات غير حرجة
      // ignore: discarded_futures
      // ignore: discarded_futures
      _uploadProfilePhotoNonBlocking(createdUser.uid);

      // (5) الانتقال لصفحة التحقق
      if (!mounted) return;
      OnbLog.i('RegisterPage', 'NAVIGATE_VERIFY_EMAIL');
      Navigator.of(context).pushReplacementNamed(
        '/verifyEmail',
        arguments: {'email': email},
      );
    } on FirebaseAuthException catch (e) {
      _snack(_mapAuthError(e));
    } on FirebaseException catch (e) {
      // إذا فشل Firestore بعد إنشاء auth → نظّف المستخدم عشان ما يصير عندك حساب بدون وثيقة
      if (createdUser != null) {
        await _rollbackAuthUser(createdUser);
      }

      if (e.code == 'already-exists') {
        _snack('اسم المستخدم محجوز بالفعل، جرّب اسمًا آخر');
      } else if (e.code == 'permission-denied') {
        _snack('صلاحيات Firestore تمنع إنشاء بيانات الحساب (permission-denied)');
      } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        _snack('المزامنة بطيئة/الشبكة غير متاحة حاليًا، حاول مرة أخرى');
      } else {
        _snack('تعذر إنشاء بيانات الحساب: ${e.code}');
      }
    } on TimeoutException {
      if (createdUser != null) {
        await _rollbackAuthUser(createdUser);
      }
      _snack('الاتصال بطيء أو غير متاح حالياً');
    } catch (e) {
      if (createdUser != null) {
        await _rollbackAuthUser(createdUser);
      }
      _snack('خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'هذا البريد مستخدم بالفعل';
      case 'invalid-email':
        return 'بريد إلكتروني غير صالح';
      case 'weak-password':
        return 'كلمة المرور ضعيفة';
      case 'network-request-failed':
        return 'تعذر الاتصال بالشبكة';
      default:
        return 'خطأ في التسجيل (${e.code})';
    }
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green : null,
    ));
  }

  // --- اختيار صورة ---
  Future<void> _pickImage() async {
    final res = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (res != null) setState(() => _pickedImage = res);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    Widget logo() => Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(.10),
            shape: BoxShape.circle,
            border: Border.all(color: cs.primary.withOpacity(.25)),
          ),
          child: Icon(Icons.person_add_alt_1_rounded, color: cs.primary, size: 34),
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(0.06),
                cs.surface,
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
                        children: [
                          Center(child: logo()),
                          const SizedBox(height: 12),
                          Text(
                            'إنشاء حساب',
                            textAlign: TextAlign.center,
                            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 18),

                          // صورة شخصية
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: cs.primary.withOpacity(.12),
                                backgroundImage: _pickedImage == null
                                    ? null
                                    : (kIsWeb
                                        ? NetworkImage(_pickedImage!.path) as ImageProvider
                                        : FileImage(File(_pickedImage!.path))),
                                child: _pickedImage == null
                                    ? Icon(Icons.person, color: cs.onSurfaceVariant)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'صورة شخصية (اختياري)',
                                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _pickImage,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('اختيار'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // handle
                          TextFormField(
                            controller: _handleCtrl,
                            focusNode: _handleFocus,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              prefixIcon: const Icon(Icons.alternate_email),
                              suffixIcon: _handleSuffixIcon(),
                              helperText: _buildHandleHelperText(),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'أدخل اسم مستخدم';
                              if (t.length < 3 || t.length > 20) return 'من 3 إلى 20 حرفًا';
                              if (!RegExp(r'^[A-Za-z]').hasMatch(t)) return 'يجب أن يبدأ بحرف';
                              if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(t)) {
                                return 'مسموح: حروف/أرقام/underscore';
                              }
                              if (t.contains('__')) return 'لا تكرر underscore';
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // email
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'البريد الإلكتروني',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'أدخل البريد الإلكتروني';
                              if (!t.contains('@') || !t.contains('.')) return 'بريد غير صالح';
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // pass
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obsc1,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: _busy ? null : () => setState(() => _obsc1 = !_obsc1),
                                icon: Icon(_obsc1 ? Icons.visibility_off : Icons.visibility),
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '');
                              if (t.isEmpty) return 'أدخل كلمة المرور';
                              if (t.length < 6) return 'على الأقل 6 أحرف';
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // pass2
                          TextFormField(
                            controller: _pass2Ctrl,
                            obscureText: _obsc2,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: 'تأكيد كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: _busy ? null : () => setState(() => _obsc2 = !_obsc2),
                                icon: Icon(_obsc2 ? Icons.visibility_off : Icons.visibility),
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '');
                              if (t.isEmpty) return 'أعد إدخال كلمة المرور';
                              if (t != _passCtrl.text) return 'غير متطابقة';
                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _busy ? null : _onSubmit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('إنشاء حساب'),
                            ),
                          ),

                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _busy ? null : () => Navigator.pop(context),
                            child: const Text('لديك حساب؟ تسجيل الدخول'),
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

  Widget? _handleSuffixIcon() {
    if (_handleCtrl.text.trim().isEmpty) return null;
    if (_handleAvailable == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_handleAvailable == true) return const Icon(Icons.check_circle, color: Colors.green);
    if (_handleAvailable == false) return const Icon(Icons.cancel, color: Colors.redAccent);
    return null;
  }

  String? _buildHandleHelperText() {
    if (_handleAvailable == false && _handleSuggestion != null) {
      return 'مقترح: ${_handleSuggestion!}';
    }
    // تنبيه بسيط: نخزنها lowercase
    if (_handleCtrl.text.trim().isNotEmpty) {
      final k = _normalizeHandle(_handleCtrl.text);
      if (k != _handleCtrl.text.trim()) return 'سيتم حفظه كـ: $k';
    }
    return null;
  }
}

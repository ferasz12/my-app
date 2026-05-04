// lib/screens/register_page.dart
// تصميم فخم ومتناسق مع صفحات الأونبوردنق (RTL) — مناسب لتطبيق صحي
// + إضافة حقل (الاسم) كما طلبت
//
// المنطق كما هو:
// - إنشاء Auth
// - ثم Transaction: (حجز usernames/{handle} + تأسيس users/{uid})
// - ثم إرسال رابط التحقق
// - رفع الصورة اختياري (Non-blocking)

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/legacy_user_repository.dart';
import '../ui/onboarding_kit.dart';
import '../widgets/avatar_cropper_page.dart';
import '../services/auth/recent_accounts_store.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // --- ثابت اسم الحقل المستخدم لتخزين رابط الصورة ---
  static const String kProfilePhotoField = 'photoUrl';

  final _formKey = GlobalKey<FormState>();

  // ✅ جديد: الاسم
  final _nameCtrl = TextEditingController();

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
  Uint8List? _pickedAvatarBytes;

  // Avatar size (diameter in pixels) — will be saved to Firestore as users/{uid}.avatarSize
  double _avatarSize = 92;
  static const double _avatarSizeMin = 72;
  static const double _avatarSizeMax = 128;

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
    _nameCtrl.dispose();
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

  /// Transaction تحجز usernames/{handle} + تؤسس users/{uid}
  Future<void> _bootstrapUserAndReserveHandle({
    required User user,
    required String handleKey,
    required String email,
    required String displayName,
    required double avatarSize,
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

      // 2) تأسيس users/{uid}
      final userSnap = await tx.get(userRef);

      if (!userSnap.exists) {
        tx.set(userRef, {
          'uid': user.uid,
          'email': email,
          'username': handleKey,
          'username_lower': handleKey,

          // ✅ الاسم الظاهر
          'displayName': displayName,
          'name': displayName,

          'photoUrl': (user.photoURL ?? '').toString(),
          'avatarSize': avatarSize,
          'role': 'user', // مسموح في create فقط حسب القواعد
          'isBanned': false,
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        // إذا الوثيقة موجودة مسبقاً: لا نحاول إضافة role/isBanned لتجنب رفض القواعد
        tx.set(
          userRef,
          {
            'email': email,
            'username': handleKey,
            'username_lower': handleKey,
            'displayName': displayName,
            'name': displayName,
            'avatarSize': avatarSize,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
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
    if (_pickedAvatarBytes == null) return;
    try {
      final ref = FirebaseStorage.instance.ref().child('users/$uid/profile.jpg');
      await ref.putData(
        _pickedAvatarBytes!,
        SettableMetadata(contentType: 'image/png'),
      );

      final url = await ref.getDownloadURL();
      final now = Timestamp.now();

      // تحديث Firestore (مسموح)
      await FirebaseFirestore.instance.doc('users/$uid').set(
        {
          kProfilePhotoField: url,
          // توافق مع أجزاء أخرى من التطبيق
          'avatarUrl': url,
          'image': url,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

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
        raw.length < 5 ||
        raw.length > 20 ||
        !RegExp(r'^[A-Za-z]').hasMatch(raw) ||
        !RegExp(r'^[A-Za-z0-9]+$').hasMatch(raw)) {
      if (mounted) setState(() => _handleAvailable = null);
      return;
    }

    try {
      final ok = await _isHandleAvailable(handleKey);
      if (!mounted) return;
      setState(() {
        _handleAvailable = ok;
        if (!ok) {
          _handleSuggestion = '${handleKey}${DateTime.now().millisecondsSinceEpoch % 999}';
        }
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

    final displayName = _nameCtrl.text.trim();
    final rawHandle = _handleCtrl.text.trim();
    final handleKey = _normalizeHandle(rawHandle);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final pass2 = _pass2Ctrl.text;

    if (pass != pass2) {
      _showNotice(
        title: 'كلمة المرور غير متطابقة',
        message: 'تأكد أن كلمة المرور وتأكيدها متطابقين تمامًا.',
        type: _NoticeType.warning,
      );
      return;
    }

    await _checkHandleAvailability();
    if (_handleAvailable == false) {
      _showNotice(
        title: 'اسم المستخدم غير متاح',
        message: 'هذا الاسم مستخدم بالفعل. جرّب الاسم المقترح أو اكتب اسمًا آخر.',
        type: _NoticeType.warning,
      );
      return;
    }

    setState(() => _busy = true);
    User? createdUser;

    try {
      // (1) إنشاء مستخدم Auth
      final cred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      createdUser = cred.user!;
      // ✅ الاسم الظاهر في Auth
      await createdUser.updateDisplayName(displayName);
      await createdUser.reload();
      createdUser = FirebaseAuth.instance.currentUser;

      if (createdUser == null) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'تعذر تثبيت الجلسة بعد التسجيل',
        );
      }

      // (2) Transaction: تأسيس users/{uid} + حجز usernames/{handle}
      await _bootstrapUserAndReserveHandle(
        user: createdUser,
        handleKey: handleKey,
        email: email,
        displayName: displayName,
        avatarSize: _avatarSize,
      );

      // (2.5) تأكيد وجود وثيقة المستخدم بالجذر (Legacy root) (غير حرِجي)
      try {
        await const LegacyUserRepository().ensureLegacyUserDocExists();
      } catch (e) {
        debugPrint('[RegisterPage] ensureLegacyUserDocExists failed: $e');
      }

      // (2.8) تخزين محلي بسيط للاسم واليوزر (يساعد صفحات أخرى داخل التطبيق)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name_$email', displayName);
        await prefs.setString('username_$email', handleKey);
        await prefs.setString('displayName_$email', displayName);
        await prefs.setDouble('avatarSize_$email', _avatarSize);
      } catch (_) {}

      // (3) إرسال رسالة التحقق (بعد نجاح كتابة Firestore)
      try {
              await createdUser.sendEmailVerification();
            } on FirebaseAuthException catch (e) {
              // بعض الأجهزة/الحالات قد ترجع too-many-requests حتى لو تم إرسال الرسالة بالفعل
              if (e.code.toLowerCase() != 'too-many-requests') rethrow;
            }

            // حفظ وقت إرسال التحقق لتفادي "too-many-requests" عند فتح صفحة التحقق مباشرة
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(
                'verify_email_last_sent_${createdUser.uid}',
                DateTime.now().millisecondsSinceEpoch,
              );
            } catch (_) {}
      // (4) كتابات غير حرجة
      // ignore: discarded_futures
      _uploadProfilePhotoNonBlocking(createdUser.uid);

      // ✅ احفظ الحساب ضمن "الحسابات السابقة" (بدون كلمة مرور)
      try {
        await RecentAccountsStore.rememberUser(createdUser);
      } catch (_) {}

      // (5) الانتقال لصفحة التحقق
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/verifyEmail',
        arguments: {'email': email},
      );
    } on FirebaseAuthException catch (e) {
      _showNotice(
        title: 'تعذر إنشاء الحساب',
        message: _mapAuthError(e),
        type: _NoticeType.error,
      );
    } on FirebaseException catch (e) {
      // إذا فشل Firestore بعد إنشاء auth → نظّف المستخدم
      if (createdUser != null) {
        await _rollbackAuthUser(createdUser);
      }

      if (e.code == 'already-exists') {
        _showNotice(
          title: 'اسم المستخدم محجوز',
          message: 'جرّب اسمًا آخر أو استخدم الاسم المقترح إذا ظهر لك.',
          type: _NoticeType.warning,
        );
      } else if (e.code == 'permission-denied') {
        _showNotice(
          title: 'تعذر حفظ بيانات الحساب',
          message: 'قواعد Firestore تمنع إنشاء بيانات المستخدم. راجع صلاحيات users و usernames.',
          type: _NoticeType.error,
        );
      } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        _showNotice(
          title: 'المزامنة بطيئة',
          message: 'تأكد من الإنترنت ثم حاول إنشاء الحساب مرة ثانية.',
          type: _NoticeType.warning,
        );
      } else {
        _showNotice(
          title: 'تعذر إنشاء بيانات الحساب',
          message: 'ما قدرنا نحفظ بيانات الحساب الآن. حاول مرة أخرى بعد لحظات.',
          type: _NoticeType.error,
        );
      }
    } on TimeoutException {
      if (createdUser != null) {
        await _rollbackAuthUser(createdUser);
      }
      _showNotice(
        title: 'الاتصال غير مستقر',
        message: 'تأكد من الإنترنت ثم حاول مرة ثانية.',
        type: _NoticeType.warning,
      );
    } catch (e) {
      if (createdUser != null) {
        await _rollbackAuthUser(createdUser);
      }
      _showNotice(
        title: 'صار خطأ غير متوقع',
        message: 'حاول مرة ثانية. إذا استمرت المشكلة أعد فتح التطبيق.',
        type: _NoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'هذا البريد مستخدم بالفعل. سجل دخولك أو استخدم بريدًا آخر.';
      case 'invalid-email':
        return 'صيغة البريد غير صحيحة. اكتب البريد مثل: name@example.com';
      case 'weak-password':
        return 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل، والأفضل تضيف رقمًا وحرفًا كبيرًا.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت. تأكد من الشبكة ثم حاول.';
      case 'too-many-requests':
        return 'تمت محاولات كثيرة خلال وقت قصير. انتظر قليلًا ثم حاول مرة أخرى.';
      case 'operation-not-allowed':
        return 'إنشاء الحساب بالبريد غير مفعّل حاليًا. راجع إعدادات Firebase Authentication.';
      default:
        return 'تعذر إنشاء الحساب الآن. حاول مرة أخرى بعد لحظات.';
    }
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

  // --- اختيار/قص الأفتار ---
  Future<void> _pickImage() async {
    if (_busy) return;

    final cs = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('اختيار الأفتار', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('من المعرض'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('التقاط صورة'),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                if (_pickedAvatarBytes != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('إزالة الصورة', style: TextStyle(color: Colors.redAccent)),
                    onTap: () => Navigator.pop(ctx, 'remove'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'remove') {
      setState(() => _pickedAvatarBytes = null);
      return;
    }

    final source = (action == 'camera') ? ImageSource.camera : ImageSource.gallery;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final croppedBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarCropperPage(imageBytes: bytes),
      ),
    );

    if (!mounted || croppedBytes == null) return;
    setState(() => _pickedAvatarBytes = croppedBytes);
  }


  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final insets = MediaQuery.of(context).viewInsets;

    return Directionality(
      textDirection: TextDirection.ltr,
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
                      const SizedBox(height: 10),

                      Center(child: OnboardingKit.logo(width: 310, height: 118)),
                      const SizedBox(height: 8),

                      Text(
                        'إنشاء حساب',
                        textAlign: TextAlign.center,
                        style: (tt.headlineSmall ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ابدأ رحلتك — أدخل بياناتك عشان نضبط لك الأهداف.',
                        textAlign: TextAlign.center,
                        style: (tt.bodyLarge ?? const TextStyle()).copyWith(
                          color: OnboardingKit.textMuted,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 18),

                      _GlassCard(
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // صورة شخصية
                              _PhotoPickerRow(
                                busy: _busy,
                                pickedBytes: _pickedAvatarBytes,
                                avatarSize: _avatarSize,
                                minSize: _avatarSizeMin,
                                maxSize: _avatarSizeMax,
                                onSizeChanged: (v) => setState(() => _avatarSize = v),
                                onPick: _pickImage,
                              ),
                              const SizedBox(height: 16),

                              // ✅ الاسم
                              TextFormField(
                                controller: _nameCtrl,
                                textDirection: TextDirection.ltr,
                                decoration: OnboardingKit.inputDecoration(
                                  label: 'الاسم',
                                  icon: Icons.badge_outlined,
                                  hint: 'مثال:  محمد',
                                ),
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return 'أدخل الاسم';
                                  if (t.length < 2) return 'الاسم قصير جدًا';
                                  if (t.length > 40) return 'الاسم طويل جدًا';
                                  if (RegExp(r'\s{2,}').hasMatch(t)) return 'قلّل المسافات المتتالية';
                                  return null;
                                },
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),

                              // username
                              TextFormField(
                                controller: _handleCtrl,
                                focusNode: _handleFocus,
                                textDirection: TextDirection.ltr,
                                decoration: OnboardingKit.inputDecoration(
                                  label: 'اسم المستخدم (Username)',
                                  icon: Icons.alternate_email,
                                  helperText: _buildHandleHelperText(),
                                  suffixIcon: _handleSuffixIcon(),
                                ),
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return 'أدخل اسم مستخدم';
                                  if (t.length < 5 || t.length > 20) return 'من 5 إلى 20 حرفًا';
                                  if (!RegExp(r'^[A-Za-z]').hasMatch(t)) return 'يجب أن يبدأ بحرف';
                                  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(t)) {
                                    return 'مسموح: حروف/أرقام (إنجليزي) فقط';
                                  }
return null;
                                },
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),

                              // email
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textDirection: TextDirection.ltr,
                                decoration: OnboardingKit.inputDecoration(
                                  label: 'البريد الإلكتروني',
                                  icon: Icons.email_outlined,
                                  hint: 'example@mail.com',
                                ),
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return 'أدخل البريد الإلكتروني';
                                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t)) return 'بريد غير صالح';
                                  return null;
                                },
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),

                              // pass
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: _obsc1,
                                textDirection: TextDirection.ltr,
                                decoration: OnboardingKit.inputDecoration(
                                  label: 'كلمة المرور',
                                  icon: Icons.lock_outline,
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
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),

                              // pass2
                              TextFormField(
                                controller: _pass2Ctrl,
                                obscureText: _obsc2,
                                textDirection: TextDirection.ltr,
                                decoration: OnboardingKit.inputDecoration(
                                  label: 'تأكيد كلمة المرور',
                                  icon: Icons.lock_outline,
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
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _busy ? null : _onSubmit(),
                              ),

                              const SizedBox(height: 18),

                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _busy ? null : _onSubmit,
                                  style: OnboardingKit.primaryButtonStyle(tt),
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
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).pushReplacementNamed('/login'),
                                child: Text(
                                  'عندك حساب؟ سجل دخولك',
                                  style: (tt.titleSmall ?? const TextStyle()).copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: OnboardingKit.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'بالاطلاع والمتابعة، أنت توافق على سياسة الخصوصية',
                        textAlign: TextAlign.center,
                        style: (tt.bodySmall ?? const TextStyle()).copyWith(
                          color: Colors.black.withOpacity(0.45),
                          height: 1.3,
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

  Widget? _handleSuffixIcon() {
    if (_handleCtrl.text.trim().isEmpty) return null;
    if (_handleAvailable == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_handleAvailable == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (_handleAvailable == false) {
      return const Icon(Icons.cancel, color: Colors.redAccent);
    }
    return null;
  }

  String? _buildHandleHelperText() {
    if (_handleAvailable == false && _handleSuggestion != null) {
      return 'مقترح: ${_handleSuggestion!}';
    }
    // تنبيه بسيط: نخزنها lowercase
    if (_handleCtrl.text.trim().isNotEmpty) {
      final k = _normalizeHandle(_handleCtrl.text);
      if (k != _handleCtrl.text.trim()) {
        return 'سيتم حفظه كـ: $k';
      }
    }
    return null;
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

  Color get _accent {
    switch (type) {
      case _NoticeType.success:
        return const Color(0xFF16A34A);
      case _NoticeType.warning:
        return const Color(0xFFF59E0B);
      case _NoticeType.error:
        return const Color(0xFFDC2626);
      case _NoticeType.info:
        return OnboardingKit.primary;
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _accent.withOpacity(0.18)),
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
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_icon, color: _accent, size: 23),
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
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: (tt.bodySmall ?? const TextStyle()).copyWith(
                      height: 1.45,
                      color: const Color(0xFF4B5563),
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

class _PhotoPickerRow extends StatelessWidget {
  final bool busy;
  final Uint8List? pickedBytes;

  /// Avatar diameter in pixels.
  final double avatarSize;
  final double minSize;
  final double maxSize;
  final ValueChanged<double> onSizeChanged;

  final VoidCallback onPick;

  const _PhotoPickerRow({
    required this.busy,
    required this.pickedBytes,
    required this.avatarSize,
    required this.minSize,
    required this.maxSize,
    required this.onSizeChanged,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    ImageProvider? provider;
    if (pickedBytes != null) {
      provider = MemoryImage(pickedBytes!);
    }

    final cs = Theme.of(context).colorScheme;
    final double size = avatarSize.clamp(minSize, maxSize);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: size,
                    height: size,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: OnboardingKit.primary.withOpacity(0.25)),
                    ),
                    child: ClipOval(
                      child: Container(
                        color: cs.surface.withOpacity(0.15),
                        child: provider != null
                            ? Image(
                                image: provider,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.person, size: size * 0.46, color: Colors.black.withOpacity(0.35)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: InkWell(
                      onTap: busy ? null : onPick,
                      borderRadius: BorderRadius.circular(50),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: OnboardingKit.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أفتار الحساب',
                      style: (tt.titleMedium ?? const TextStyle()).copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      provider == null ? 'ارفع صورة واختر الحجم المناسب' : 'تم اختيار صورة — تقدر تعدّل الحجم',
                      style: (tt.bodySmall ?? const TextStyle()).copyWith(
                        color: OnboardingKit.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'حجم الأفتار',
                style: (tt.bodyMedium ?? const TextStyle()).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Slider(
                  value: size,
                  min: minSize,
                  max: maxSize,
                  divisions: (maxSize - minSize).round(),
                  onChanged: busy ? null : onSizeChanged,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  size.toInt().toString(),
                  textAlign: TextAlign.end,
                  style: (tt.bodySmall ?? const TextStyle()).copyWith(color: OnboardingKit.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
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
                Colors.white.withOpacity(0.60),
                Colors.white.withOpacity(0.34),
              ],
            ),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withOpacity(0.42), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
              color: Colors.white.withOpacity(0.34),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.40)),
            ),
            child: Center(
              child: Icon(icon, size: 18, color: Colors.black.withOpacity(0.72)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: OnboardingKit.primary.withOpacity(0.9)),
          const SizedBox(width: 8),
          Text(
            label,
            style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black.withOpacity(0.70),
            ),
          ),
        ],
      ),
    );
  }
}

// lib/settings/profile_page.dart — ملف شخصي قابل للتحرير (بايو + سوشيال + صورة)
// Legacy Source of Truth:
//  - users/{uid} => { bio, social {instagram,snapchat,tiktok}, photoUrl/avatarUrl, updatedAt }
//
// ملاحظات مهمة:
//  - يحافظ على نفس منطق القراءة/الحفظ القديم (Firestore + SharedPreferences)
//  - إضافة تعديل الصورة الشخصية من نفس الصفحة (ImagePicker + FirebaseStorage)
//  - واجهة فخمة (Glass + Gradient) ومناسبة لتطبيق صحي
//  - زر رجوع واضح للعودة للصفحة السابقة

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/legacy_user_repository.dart';
import '../data/user_repository.dart';
import '../widgets/avatar_cropper_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // نستخدم نفس اسم الحقل المتبع في صفحات أخرى
  static const String kProfilePhotoField = 'photoUrl';
  static const Object _kAvatarHeroTag = 'profile_avatar_hero';


  final _formKey = GlobalKey<FormState>();

  // Basic info
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _usernameFocus = FocusNode();

  bool _dirtyName = false;
  bool _dirtyUsername = false;
  bool _dirtyAvatarSize = false;

  bool? _usernameAvailable; // null = not checked / checking
  bool _checkingUsername = false;
  Timer? _usernameDebounce;

  // Avatar size (diameter in px)
  double _avatarSize = 92;
  static const double _avatarSizeMin = 72;
  static const double _avatarSizeMax = 128;

  // Bio
  final _bioCtrl = TextEditingController();

  // Social
  final _igCtrl = TextEditingController();
  final _scCtrl = TextEditingController();
  final _tkCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // Avatar
  final _picker = ImagePicker();
  bool _uploadingPhoto = false;
  String? _photoUrl;

  // Header identity (read-only)
  String _displayName = '';
  String _username = '';
  String _email = '';

  DocumentReference<Map<String, dynamic>>? _userRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  @override
  void initState() {
    super.initState();

    _usernameCtrl.addListener(() {
      if (!_dirtyUsername) _dirtyUsername = true;
      _usernameDebounce?.cancel();
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = true;
      });
      _usernameDebounce = Timer(const Duration(milliseconds: 350), () {
        _checkUsernameAvailability();
      });
    });

    _nameCtrl.addListener(() {
      if (!_dirtyName) _dirtyName = true;
    });

    _usernameFocus.addListener(() {
      if (!_usernameFocus.hasFocus) _checkUsernameAvailability();
    });

    _initRefsAndLoad();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _usernameFocus.dispose();

    _bioCtrl.dispose();
    _igCtrl.dispose();
    _scCtrl.dispose();
    _tkCtrl.dispose();
    _userSub?.cancel();
    super.dispose();
  }

  Future<void> _initRefsAndLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    // Best-effort: تأكيد وجود الجذر + مهاجرة أي بيانات ناقصة (إن وجدت)
    try {
      await const LegacyUserRepository().ensureLegacyUserDocExists();
    } catch (_) {}

    final userRef = FirebaseFirestore.instance.doc('users/${user.uid}');

    setState(() {
      _userRef = userRef;
      _email = user.email ?? '';
      _photoUrl = user.photoURL;
    });

    // استمع للتغييرات الحية واملأ الحقول من الجذر
    _userSub = userRef.snapshots().listen((snap) {
      final data = snap.data();
      if (data != null) {
        // ===== Identity =====
        final displayName = (data['displayName'] as String?)?.trim() ?? '';
        final name = (data['name'] as String?)?.trim() ?? '';
        final username = (data['username'] as String?)?.trim() ?? '';
        final email = (data['email'] as String?)?.trim() ?? '';

        final resolvedName = name.isNotEmpty ? name : displayName;
        _displayName = resolvedName;
        _username = username;
        if (email.isNotEmpty) _email = email;

        // Sync editable fields (do not overwrite while user is typing)
        if (!_dirtyName && _nameCtrl.text != resolvedName) {
          _nameCtrl.value = TextEditingValue(
            text: resolvedName,
            selection: TextSelection.collapsed(offset: resolvedName.length),
          );
        }

        if (!_dirtyUsername && _usernameCtrl.text != username) {
          _usernameCtrl.value = TextEditingValue(
            text: username,
            selection: TextSelection.collapsed(offset: username.length),
          );
          _usernameAvailable = username.isNotEmpty ? true : null;
        }

        final storedSize = (data['avatarSize'] as num?)?.toDouble();
        if (!_dirtyAvatarSize && storedSize != null) {
          _avatarSize = storedSize.clamp(_avatarSizeMin, _avatarSizeMax);
        }

        // ===== Photo =====
        String? raw = (data[kProfilePhotoField] as String?)?.trim();
        raw = (raw?.isNotEmpty == true)
            ? raw
            : (data['avatarUrl'] as String?)?.trim();
        raw = (raw?.isNotEmpty == true)
            ? raw
            : (data['image'] as String?)?.trim();
        if (raw?.isNotEmpty == true) {
          _photoUrl = raw;
        }

        // ===== Bio =====
        final bio = (data['bio'] as String?)?.trim();
        if (bio != null) {
          _bioCtrl.text = bio;
        }

        // ===== Social =====
        final social = data['social'];
        if (social is Map) {
          final m = Map<String, dynamic>.from(social as Map);
          final ig = (m['instagram'] as String?)?.trim();
          final sc = (m['snapchat'] as String?)?.trim();
          final tk = (m['tiktok'] as String?)?.trim();
          if (ig != null) _igCtrl.text = ig;
          if (sc != null) _scCtrl.text = sc;
          if (tk != null) _tkCtrl.text = tk;
        }
      }
      if (mounted) setState(() {});
    });

    // تحميل بدائي من SharedPreferences لو متوفّر
    final prefs = await SharedPreferences.getInstance();
    final emailKey = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
    final bioLocal = prefs.getString('bio_$emailKey');
    final igLocal = prefs.getString('social_instagram_$emailKey');
    final scLocal = prefs.getString('social_snapchat_$emailKey');
    final tkLocal = prefs.getString('social_tiktok_$emailKey');

    if (bioLocal != null && bioLocal.isNotEmpty && _bioCtrl.text.isEmpty) _bioCtrl.text = bioLocal;
    if (igLocal != null && igLocal.isNotEmpty && _igCtrl.text.isEmpty) _igCtrl.text = igLocal;
    if (scLocal != null && scLocal.isNotEmpty && _scCtrl.text.isEmpty) _scCtrl.text = scLocal;
    if (tkLocal != null && tkLocal.isNotEmpty && _tkCtrl.text.isEmpty) _tkCtrl.text = tkLocal;

    setState(() => _loading = false);
  }

  // ----------------------------
  // Username rules + availability
  // ----------------------------

  String _normalizeHandle(String raw) => raw.trim().toLowerCase();

  String? _usernameRuleError(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'أدخل اسم المستخدم';
    if (RegExp(r'\s').hasMatch(t)) return 'اليوزر لا يقبل المسافات';

    final normalized = _normalizeHandle(t);
    final current = _normalizeHandle(_username);

    // ✅ سماح للأسماء القديمة فقط إذا كانت متوافقة مع القواعد الجديدة.
    // إذا كان اليوزر الحالي يحتوي مسافة/عربي، لازم المستخدم يغيّره.
    final currentOk = current.isNotEmpty &&
        !RegExp(r'\s').hasMatch(current) &&
        !RegExp(r'[\u0600-\u06FF]').hasMatch(current) &&
        RegExp(r'^[a-z][a-z0-9]{4,19}$').hasMatch(current);
    if (currentOk && normalized == current) return null;

    if (normalized.length < 5) return 'اليوزر لازم يكون ٥ أحرف أو أكثر';
    if (normalized.length > 20) return 'اليوزر طويل جدًا';
    if (!RegExp(r'^[a-z]').hasMatch(normalized)) return 'لازم يبدأ بحرف إنجليزي';
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(normalized)) {
      return 'إنجليزي فقط (حروف/أرقام) بدون رموز';
    }
    return null;
  }
  Future<void> _checkUsernameAvailability() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final raw = _usernameCtrl.text.trim();
    final err = _usernameRuleError(raw);
    if (err != null) {
      if (mounted) {
        setState(() {
          _usernameAvailable = null;
          _checkingUsername = false;
        });
      }
      return;
    }

    final handle = _normalizeHandle(raw);

    try {
      final doc = await FirebaseFirestore.instance.doc('usernames/$handle').get();
      final available = !doc.exists || (doc.data()?['ownerUid']?.toString() == user.uid);
      if (!mounted) return;
      setState(() {
        _usernameAvailable = available;
        _checkingUsername = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = false;
      });
    }
  }

  Widget? _usernameSuffixIcon() {
    final raw = _usernameCtrl.text.trim();
    if (raw.isEmpty) return null;

    final err = _usernameRuleError(raw);
    if (err != null) {
      return const Icon(Icons.error_outline, color: Colors.redAccent);
    }

    if (_checkingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_usernameAvailable == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }

    if (_usernameAvailable == false) {
      return const Icon(Icons.cancel, color: Colors.redAccent);
    }

    return null;
  }

  String? _usernameHelperText() {
    final raw = _usernameCtrl.text.trim();
    if (raw.isEmpty) return null;

    final err = _usernameRuleError(raw);
    if (err != null) return err;

    final k = _normalizeHandle(raw);
    final parts = <String>[];
    if (k != raw) parts.add('سيتم حفظه كـ: $k');
    if (_usernameAvailable == true) parts.add('متاح');
    if (_usernameAvailable == false) parts.add('مستخدم بالفعل');

    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_saving) return;

    setState(() => _saving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يلزم تسجيل الدخول أولاً')),
        );
      }
      setState(() => _saving = false);
      return;
    }

    final name = _nameCtrl.text.trim();
    final rawUsername = _usernameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final ig = _igCtrl.text.trim();
    final sc = _scCtrl.text.trim();
    final tk = _tkCtrl.text.trim();

    final uErr = _usernameRuleError(rawUsername);
    if (uErr != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uErr)));
      }
      setState(() => _saving = false);
      return;
    }

    final newHandle = _normalizeHandle(rawUsername);
    final currentHandle = _normalizeHandle(_username);

    final socialData = <String, dynamic>{
      'instagram': ig,
      'snapchat': sc,
      'tiktok': tk,
    };

    final now = Timestamp.now();

    try {
      // 1) Username change (reserve usernames/{handle})
      if (newHandle != currentHandle) {
        // فحص سريع لإظهار علامة صح/خطأ قبل الترانزكشن
        final doc = await FirebaseFirestore.instance.doc('usernames/$newHandle').get();
        final owner = doc.data()?['ownerUid']?.toString();
        final available = !doc.exists || owner == user.uid;
        if (!available) {
          throw Exception('اسم المستخدم مستخدم بالفعل');
        }

        await const UserRepository().updateUsername(username: newHandle);
      }

      // 2) Update root user doc (name/bio/social/avatarSize)
      final ref = _userRef ?? FirebaseFirestore.instance.doc('users/${user.uid}');
      await ref.set({
        'name': name,
        'displayName': name,
        'bio': bio,
        'social': socialData,
        'avatarSize': _avatarSize,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // 3) Update Auth displayName (best-effort)
      try {
        await user.updateDisplayName(name);
      } catch (_) {}

      // 4) Local cache for legacy screens
      final prefs = await SharedPreferences.getInstance();
      final emailKey = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';

      await prefs.setString('name_$emailKey', name);
      await prefs.setString('displayName_$emailKey', name);
      await prefs.setString('username_$emailKey', newHandle);
      await prefs.setString('currentUsername_$emailKey', newHandle);
      await prefs.setString('bio_$emailKey', bio);
      await prefs.setString('social_instagram_$emailKey', ig);
      await prefs.setString('social_snapchat_$emailKey', sc);
      await prefs.setString('social_tiktok_$emailKey', tk);
      await prefs.setDouble('avatarSize_$emailKey', _avatarSize);

      // نسخة UID (تستخدمها بعض الشاشات)
      await prefs.setString('username_${user.uid}', newHandle);

      if (mounted) {
        setState(() {
          _dirtyName = false;
          _dirtyUsername = false;
          _dirtyAvatarSize = false;
          _usernameAvailable = true;
          _checkingUsername = false;
          _username = newHandle;
          _displayName = name;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الملف الشخصي بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر الحفظ: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ===== Avatar Editing =====

  void _openAvatarViewer() {
    final url = _photoUrl;
    if (url == null || url.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageView(imageUrl: url, heroTag: _kAvatarHeroTag),
      ),
    );
  }



  Future<void> _showAvatarActions() async {
    if (_uploadingPhoto) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                Text('تعديل الصورة الشخصية',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.photo_library_outlined,
                  title: 'اختيار من المعرض',
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                _ActionTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'التقاط صورة',
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                if ((_photoUrl ?? '').isNotEmpty)
                  _ActionTile(
                    icon: Icons.delete_outline,
                    title: 'إزالة الصورة',
                    danger: true,
                    onTap: () => Navigator.pop(ctx, 'remove'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'gallery') {
      await _pickAndUploadAvatar(ImageSource.gallery);
    } else if (action == 'camera') {
      await _pickAndUploadAvatar(ImageSource.camera);
    } else if (action == 'remove') {
      await _removeAvatar();
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1400,
      );
      if (picked == null) return;

      // ✅ قص قبل الرفع (بدون أي باكج إضافي)
      final originalBytes = await picked.readAsBytes();
      if (!mounted) return;

      final croppedBytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => AvatarCropperPage(imageBytes: originalBytes),
        ),
      );
      if (!mounted || croppedBytes == null) return;

      setState(() => _uploadingPhoto = true);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/${user.uid}/profile.jpg');

      await storageRef.putData(
        croppedBytes,
        SettableMetadata(contentType: 'image/png'),
      );

      final url = await storageRef.getDownloadURL();
      final now = Timestamp.now();

      final ref = _userRef ?? FirebaseFirestore.instance.doc('users/${user.uid}');
      await ref.set(
        {
          kProfilePhotoField: url,
          // حقول إضافية للتوافق مع أجزاء أخرى من التطبيق
          'avatarUrl': url,
          'image': url,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      // تحديث Auth (اختياري)
      try {
        await user.updatePhotoURL(url);
      } catch (_) {}

      // كاش محلي لواجهات قديمة (Best-effort)
      try {
        final prefs = await SharedPreferences.getInstance();
        final emailKey = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
        await prefs.setString('photoUrl_$emailKey', url);
        await prefs.setString('avatarUrl_$emailKey', url);
        await prefs.setString('image_$emailKey', url);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _photoUrl = url;
          _uploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الصورة الشخصية'), backgroundColor: Colors.green),
        );
      }
    } on FirebaseException catch (e, st) {
      debugPrint('[ProfilePage] avatar upload failed: ${e.code} ${e.message}\n$st');
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر رفع الصورة، حاول مجددًا')),
        );
      }
    } catch (e, st) {
      debugPrint('[ProfilePage] avatar upload failed: $e\n$st');
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر رفع الصورة، حاول مجددًا')),
        );
      }
    }
  }

  Future<void> _removeAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (mounted) setState(() => _uploadingPhoto = true);

      // Best-effort delete from storage
      try {
        await FirebaseStorage.instance
            .ref()
            .child('users/${user.uid}/profile.jpg')
            .delete();
      } catch (_) {}

      final ref = _userRef ?? FirebaseFirestore.instance.doc('users/${user.uid}');
      await ref.set(
        {
          kProfilePhotoField: FieldValue.delete(),
          'avatarUrl': FieldValue.delete(),
          'image': FieldValue.delete(),
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      // تحديث Auth (اختياري)
      try {
        await user.updatePhotoURL(null);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _photoUrl = null;
          _uploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إزالة الصورة الشخصية')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إزالة الصورة الآن')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;


    final liveName = _nameCtrl.text.trim();
    final liveHandleRaw = _usernameCtrl.text.trim();

    final display = liveName.isNotEmpty
        ? liveName
        : (_displayName.isNotEmpty
            ? _displayName
            : (_username.isNotEmpty
                ? _username
                : (_email.isNotEmpty ? _email.split('@').first : 'مستخدم')));

    final shownUsername = liveHandleRaw.isNotEmpty ? _normalizeHandle(liveHandleRaw) : _username;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('الملف الشخصي'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Tooltip(
            message: 'رجوع',
            child: BackButton(
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ),
        body: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withOpacity(0.14),
                    cs.surface,
                    cs.surface,
                  ],
                ),
              ),
            ),

            // Decorative bubbles
            Positioned(
              top: -80,
              right: -60,
              child: _BlurBubble(color: cs.primary.withOpacity(0.22), size: 180),
            ),
            Positioned(
              top: 110,
              left: -70,
              child: _BlurBubble(color: cs.secondary.withOpacity(0.18), size: 170),
            ),

            SafeArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),

                          // Header (Glass Card)
                          _Glass(
                            borderRadius: 26,
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Glow
                                    Container(
                                      width: (_avatarSize + 12).clamp(_avatarSizeMin + 12, _avatarSizeMax + 12),
                                      height: (_avatarSize + 12).clamp(_avatarSizeMin + 12, _avatarSizeMax + 12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: cs.primary.withOpacity(0.10),
                                      ),
                                    ),
                                    _Avatar(
                                      size: _avatarSize,
                                      photoUrl: _photoUrl,
                                      uploading: _uploadingPhoto,
                                      heroTag: _kAvatarHeroTag,
                                      onView: _openAvatarViewer,
                                      onEdit: _showAvatarActions,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                Text(
                                  display,
                                  style: tt.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                if (shownUsername.isNotEmpty)
                                  Text(
                                    '@$shownUsername',
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.onSurface.withOpacity(0.65),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                else if (_email.isNotEmpty)
                                  Text(
                                    _email,
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.onSurface.withOpacity(0.60),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                const SizedBox(height: 14),

                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _uploadingPhoto ? null : _showAvatarActions,
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('تعديل الصورة'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _saving ? null : _save,
                                        icon: _saving
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.check_circle_outline),
                                        label: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Form card
                          _Glass(
                            borderRadius: 24,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.badge_outlined, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Text('بيانات الحساب', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  TextFormField(
                                    controller: _nameCtrl,
                                    textDirection: TextDirection.ltr,
                                    decoration: InputDecoration(
                                      labelText: 'الاسم',
                                      prefixIcon: const Icon(Icons.person_outline),
                                      filled: true,
                                      fillColor: cs.surface.withOpacity(0.65),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    validator: (v) {
                                      final t = (v ?? '').trim();
                                      if (t.isEmpty) return 'أدخل الاسم';
                                      if (t.length < 2) return 'الاسم قصير جدًا';
                                      if (t.length > 40) return 'الاسم طويل جدًا';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _usernameCtrl,
                                    focusNode: _usernameFocus,
                                    textDirection: TextDirection.ltr,
                                    decoration: InputDecoration(
                                      labelText: 'اسم المستخدم',
                                      prefixText: '@',
                                      suffixIcon: _usernameSuffixIcon(),
                                      helperText: _usernameHelperText(),
                                      filled: true,
                                      fillColor: cs.surface.withOpacity(0.65),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    validator: (v) => _usernameRuleError(v ?? ''),
                                  ),

                                  const SizedBox(height: 12),

                                  Row(
                                    children: [
                                      Icon(Icons.photo_size_select_large_outlined, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Text('حجم الأفتار', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Slider(
                                          value: _avatarSize.clamp(_avatarSizeMin, _avatarSizeMax),
                                          min: _avatarSizeMin,
                                          max: _avatarSizeMax,
                                          divisions: (_avatarSizeMax - _avatarSizeMin).round(),
                                          onChanged: _saving
                                              ? null
                                              : (v) {
                                                  setState(() {
                                                    _dirtyAvatarSize = true;
                                                    _avatarSize = v;
                                                  });
                                                },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 44,
                                        child: Text(
                                          _avatarSize.toInt().toString(),
                                          textAlign: TextAlign.end,
                                          style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.60)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Divider(color: cs.onSurface.withOpacity(0.12)),
                                  const SizedBox(height: 14),

                                  Row(
                                    children: [
                                      Icon(Icons.person_outline, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Text('نبذة عني', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  TextFormField(
                                    controller: _bioCtrl,
                                    maxLines: 4,
                                    decoration: InputDecoration(
                                      hintText: 'اكتب نبذة قصيرة عنك…',
                                      filled: true,
                                      fillColor: cs.surface.withOpacity(0.65),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  Row(
                                    children: [
                                      Icon(Icons.share_outlined, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Text('حسابات التواصل', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  _SocialField(
                                    controller: _igCtrl,
                                    label: 'Instagram',
                                    icon: FontAwesomeIcons.instagram,
                                    platform: 'instagram',
                                  ),
                                  const SizedBox(height: 12),
                                  _SocialField(
                                    controller: _scCtrl,
                                    label: 'Snapchat',
                                    icon: FontAwesomeIcons.snapchatGhost,
                                    platform: 'snapchat',
                                  ),
                                  const SizedBox(height: 12),
                                  _SocialField(
                                    controller: _tkCtrl,
                                    label: 'TikTok',
                                    icon: FontAwesomeIcons.tiktok,
                                    platform: 'tiktok',
                                  ),

                                  const SizedBox(height: 12),

                                  Text(
                                    'ملاحظة: الروابط/المعرفات اختيارية وتظهر للآخرين حسب شاشات التطبيق.',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Bottom actions
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('حفظ التعديلات'),
                          ),
                          const SizedBox(height: 10),

                          TextButton.icon(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const BackButtonIcon(),
                            label: const Text('رجوع'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- UI helpers ----------

class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  const _Glass({
    required this.child,
    required this.padding,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.72),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: cs.onSurface.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BlurBubble extends StatelessWidget {
  final Color color;
  final double size;

  const _BlurBubble({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final bool uploading;

  final double size;

  /// Called when user wants to view the photo in full screen (only when [photoUrl] is not empty).
  final VoidCallback? onView;

  /// Called when user wants to edit/change the photo.
  final VoidCallback onEdit;

  /// Hero tag used for the transition to the full screen viewer.
  final Object heroTag;

  const _Avatar({
    required this.size,
    required this.photoUrl,
    required this.uploading,
    required this.onEdit,
    required this.heroTag,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final s = size.clamp(72, 128).toDouble();
    final iconSize = s * 0.48;

    final hasPhoto = (photoUrl ?? '').isNotEmpty;

    void handleViewTap() {
      if (uploading) return;

      // If we have a photo, we open the viewer; otherwise we fall back to edit actions.
      if (hasPhoto) {
        onView?.call();
      } else {
        onEdit();
      }
    }

    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        // Avatar itself (tap = view full photo if exists)
        GestureDetector(
          onTap: handleViewTap,
          child: Container(
            width: s,
            height: s,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  cs.primary.withOpacity(0.85),
                  cs.secondary.withOpacity(0.85),
                ],
              ),
            ),
            child: ClipOval(
              child: Container(
                color: cs.surface,
                child: hasPhoto
                    ? Hero(
                        tag: heroTag,
                        child: Image.network(
                          photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.person, size: iconSize, color: cs.onSurface.withOpacity(0.55)),
                        ),
                      )
                    : Icon(Icons.person, size: iconSize, color: cs.onSurface.withOpacity(0.55)),
              ),
            ),
          ),
        ),

        // Edit badge (tap = edit/change photo)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: uploading ? null : onEdit,
            customBorder: const CircleBorder(),
            child: Container(
              margin: const EdgeInsets.only(left: 2, bottom: 2),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.edit, size: 16, color: Colors.white),
            ),
          ),
        ),

        // Uploading overlay
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.35),
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FullScreenImageView extends StatelessWidget {
  final String imageUrl;
  final Object heroTag;

  const _FullScreenImageView({
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Tap anywhere to close
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),

          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Hero(
                tag: heroTag,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator.adaptive(),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 56, color: Colors.white70),
                ),
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 6,
            child: SafeArea(
              bottom: false,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'إغلاق',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  /// instagram | snapchat | tiktok
  final String platform;

  const _SocialField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.platform,
  });

  String _normalizeHandle(String raw) {
    var h = raw.trim();
    if (h.isEmpty) return '';
    // If user pasted a URL, keep it
    final lower = h.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return h;
    if (lower.startsWith('www.')) return 'https://$h';

    // Remove leading @
    if (h.startsWith('@')) h = h.substring(1).trim();
    return h;
  }

  Uri? _buildUri() {
    final raw = controller.text;
    final h = _normalizeHandle(raw);
    if (h.isEmpty) return null;

    final lower = h.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return Uri.tryParse(h);
    }

    switch (platform) {
      case 'instagram':
        return Uri.tryParse('https://www.instagram.com/$h');
      case 'snapchat':
        return Uri.tryParse('https://www.snapchat.com/add/$h');
      case 'tiktok':
        // TikTok usernames are usually without @ in URL
        return Uri.tryParse('https://www.tiktok.com/@$h');
      default:
        return null;
    }
  }

  Future<void> _open(BuildContext context) async {
    final uri = _buildUri();
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = controller.text.trim().isNotEmpty;

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FaIcon(icon, size: 18, color: cs.onSurfaceVariant),
        ),
        suffixIcon: IconButton(
          tooltip: 'فتح',
          onPressed: hasValue ? () => _open(context) : null,
          icon: Icon(Icons.open_in_new_rounded, color: cs.onSurfaceVariant),
        ),
        filled: true,
        fillColor: cs.surface.withOpacity(0.65),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = danger ? Colors.red : cs.onSurface;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (danger ? Colors.red : cs.primary).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: danger ? Colors.red : cs.primary),
      ),
      title: Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      trailing: Icon(Icons.chevron_right_rounded, color: c.withOpacity(0.6)),
      onTap: onTap,
    );
  }
}
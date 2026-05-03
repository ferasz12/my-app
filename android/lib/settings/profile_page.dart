// lib/settings/profile_page.dart — ملف شخصي قابل للتحرير (بايو + سوشيال)
// Legacy Source of Truth:
//  - users/{uid} => { bio, social {instagram,snapchat,tiktok}, updatedAt }
// - تصميم مماثل لصفحات التسجيل/الدخول (Card وسط + خلفية متدرجة)
// - يدعم القراءة الحية من Firestore + التحرير والحفظ بزر واحد

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/legacy_user_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  // Bio
  final _bioCtrl = TextEditingController();

  // Social
  final _igCtrl = TextEditingController();
  final _scCtrl = TextEditingController();
  final _tkCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>>? _userRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  @override
  void initState() {
    super.initState();
    _initRefsAndLoad();
  }

  @override
  void dispose() {
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
    });

    // استمع للتغييرات الحية واملأ الحقول من الجذر
    _userSub = userRef.snapshots().listen((snap) {
      final data = snap.data();
      if (data != null) {
        final bio = (data['bio'] as String?)?.trim();
        if (bio != null) {
          _bioCtrl.text = bio;
        }

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
    final email = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
    final bioLocal = prefs.getString('bio_$email');
    final igLocal = prefs.getString('social_instagram_$email');
    final scLocal = prefs.getString('social_snapchat_$email');
    final tkLocal = prefs.getString('social_tiktok_$email');

    if (bioLocal != null && bioLocal.isNotEmpty && _bioCtrl.text.isEmpty) _bioCtrl.text = bioLocal;
    if (igLocal != null && igLocal.isNotEmpty && _igCtrl.text.isEmpty) _igCtrl.text = igLocal;
    if (scLocal != null && scLocal.isNotEmpty && _scCtrl.text.isEmpty) _scCtrl.text = scLocal;
    if (tkLocal != null && tkLocal.isNotEmpty && _tkCtrl.text.isEmpty) _tkCtrl.text = tkLocal;

    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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

    final bio = _bioCtrl.text.trim();
    final ig = _igCtrl.text.trim();
    final sc = _scCtrl.text.trim();
    final tk = _tkCtrl.text.trim();

    final now = Timestamp.now();

    final socialData = <String, dynamic>{};
    if (ig.isNotEmpty) socialData['instagram'] = ig;
    if (sc.isNotEmpty) socialData['snapchat'] = sc;
    if (tk.isNotEmpty) socialData['tiktok'] = tk;

    try {
      final ref = _userRef ?? FirebaseFirestore.instance.doc('users/${user.uid}');
      await ref.set({
        'bio': bio,
        if (socialData.isNotEmpty) 'social': socialData,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // خزّن محليًا أيضًا (لتحسين الإحساس بالتزامن بين الصفحات)
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
      await prefs.setString('bio_$email', bio);
      await prefs.setString('social_instagram_$email', ig);
      await prefs.setString('social_snapchat_$email', sc);
      await prefs.setString('social_tiktok_$email', tk);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الملف الشخصي بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الحفظ الآن، حاول مجددًا')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ملفي الشخصي')),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.primary.withOpacity(0.06), cs.surface],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Card(
                  elevation: 8,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: _loading
                        ? const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Form(
                            key: _formKey,
                            child: ListView(
                              children: [
                                Text('الملف الشخصي',
                                    textAlign: TextAlign.center,
                                    style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 14),

                                // Bio
                                Text('النبذة', style: tt.titleMedium),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _bioCtrl,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText: 'اكتب نبذة قصيرة عنك…',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Social
                                Text('حسابات التواصل', style: tt.titleMedium),
                                const SizedBox(height: 10),

                                TextFormField(
                                  controller: _igCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Instagram',
                                    prefixIcon: Icon(Icons.camera_alt_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                TextFormField(
                                  controller: _scCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Snapchat',
                                    prefixIcon: Icon(Icons.chat_bubble_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                TextFormField(
                                  controller: _tkCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'TikTok',
                                    prefixIcon: Icon(Icons.music_note_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),

                                const SizedBox(height: 18),

                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: _saving ? null : _save,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.save_outlined),
                                    label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
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
        ),
      ),
    );
  }
}

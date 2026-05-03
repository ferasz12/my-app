// lib/screens/edit_username_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditUsernamePage extends StatefulWidget {
  const EditUsernamePage({super.key});

  @override
  State<EditUsernamePage> createState() => _EditUsernamePageState();
}

class _EditUsernamePageState extends State<EditUsernamePage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _dirty = false; // إذا المستخدم عدّل يدويًا ما نطغى على الكتابة القادمة من الستريم

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;
  User? _faUser;

  @override
  void initState() {
    super.initState();
    _faUser = FirebaseAuth.instance.currentUser;
    if (_faUser != null) {
      _userDocStream = FirebaseFirestore.instance
          .doc('users/${_faUser!.uid}')
          .snapshots(includeMetadataChanges: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _resolveUsername({
    Map<String, dynamic>? userDoc,
    User? faUser,
    String? prefsName,
  }) {
    // 1) Firestore (username > displayName)
    final fsUsername = userDoc?['username'] as String?;
    final fsDisplay = userDoc?['displayName'] as String?;

    if (fsUsername != null && fsUsername.trim().isNotEmpty) return fsUsername.trim();
    if (fsDisplay != null && fsDisplay.trim().isNotEmpty) return fsDisplay.trim();

    // 2) FirebaseAuth
    final authName = faUser?.displayName;
    if (authName != null && authName.trim().isNotEmpty) return authName.trim();

    // 3) SharedPreferences (اختياري للتماشي)
    if (prefsName != null && prefsName.trim().isNotEmpty) return prefsName.trim();

    // 4) قبل @ من الإيميل
    final email = faUser?.email ?? '';
    final fallback = email.contains('@') ? email.split('@').first : '';
    if (fallback.isNotEmpty) return fallback;

    return 'مستخدم';
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final user = _faUser ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(code: 'no-user', message: 'لا يوجد مستخدم مسجّل');
      }

      final newUsername = _controller.text.trim();
      final uid = user.uid;
      final email = user.email;

      final rootRef = FirebaseFirestore.instance.doc('users/$uid');

      // اكتب في Firestore (جذر المستخدم) — نفس المصدر اللي تعتمد عليه بقية الشاشات
      await rootRef.set({
        'username': newUsername,
        'displayName': newUsername,
        'lowerUsername': newUsername.toLowerCase(),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      // حدث عرض الاسم في FirebaseAuth
      await user.updateDisplayName(newUsername);

      // حفظ محلي للتوافق مع مفاتيحك السابقة
      final prefs = await SharedPreferences.getInstance();
      if (email != null) {
        await Future.wait([
          prefs.setString('currentUsername_$email', newUsername),
          prefs.setString('displayName_$email', newUsername),
          prefs.setString('username_$email', newUsername),
        ]);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ اسم المستخدم بنجاح')),
      );

      // رجوع موحّد
      Navigator.of(context, rootNavigator: true).maybePop();
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذّر الحفظ: ${e.message ?? e.code}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('صار خطأ غير متوقع أثناء الحفظ')));
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
        appBar: AppBar(
          title: const Text('تعديل اسم المستخدم'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ),
        body: _faUser == null
            ? const Center(child: Text('لا يوجد مستخدم مسجّل حالياً'))
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userDocStream,
                builder: (context, snap) {
                  final docData = snap.data?.data();
                  return FutureBuilder<SharedPreferences>(
                    future: SharedPreferences.getInstance(),
                    builder: (context, prefsSnap) {
                      final prefs = prefsSnap.data;
                      final email = _faUser?.email;
                      final prefsName = (email != null)
                          ? (prefs?.getString('currentUsername_$email') ??
                              prefs?.getString('displayName_$email') ??
                              prefs?.getString('username_$email'))
                          : null;

                      final resolved =
                          _resolveUsername(userDoc: docData, faUser: _faUser, prefsName: prefsName);

                      // أول ما تجي البيانات من الستريم/الفال‌بك، لو المستخدم ما لمس الحقل، نحدثه
                      if (!_dirty && _controller.text != resolved) {
                        // ما نستخدم setState هنا عشان ما نعمل إعادة بناء إضافية
                        _controller.value = TextEditingValue(
                          text: resolved,
                          selection: TextSelection.collapsed(offset: resolved.length),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('اسم المستخدم',
                                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _controller,
                                decoration: const InputDecoration(
                                  hintText: 'أدخل اسمك الظاهر',
                                  border: OutlineInputBorder(),
                                ),
                                textInputAction: TextInputAction.done,
                                onChanged: (_) {
                                  if (!_dirty) setState(() => _dirty = true);
                                },
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) return 'الاسم لا يمكن أن يكون فارغًا';
                                  if (s.length < 2) return 'الاسم قصير جدًا';
                                  if (s.length > 40) return 'الاسم طويل جدًا';
                                  // مثال: منع مسافات مكررة
                                  if (RegExp(r'\s{2,}').hasMatch(s)) {
                                    return 'قلّل المسافات المتتالية';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'سيظهر هذا الاسم في الشاشة الرئيسية والوصفات وخططك.',
                                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.check_rounded),
                                  label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

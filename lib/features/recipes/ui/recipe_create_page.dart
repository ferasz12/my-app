// lib/features/recipes/ui/recipe_create_page.dart
//
// صفحة إنشاء وصفة:
// - يتحقق من isBanned و recipesSuspendedUntil قبل السماح بالنشر.
// - يضمن وجود users/{uid} عبر _ensureUserDocMinimal (create vs update آمن).
// - يدعم رفع صورة (كاميرا/معرض) بشكل اختياري وحفظ رابطها داخل Firestore.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/premium_feature.dart';
import '../../../shared/premium_gate.dart';

class _GuardState {
  final bool allowed;
  final String? message;
  const _GuardState({required this.allowed, this.message});
}

class _PostingGuard {
  static Future<_GuardState> loadForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const _GuardState(
        allowed: false,
        message: 'الرجاء تسجيل الدخول للمتابعة',
      );
    }
    final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
    final data = (snap.data() ?? {}) as Map<String, dynamic>;

    if ((data['isBanned'] ?? false) == true) {
      return const _GuardState(
        allowed: false,
        message: 'حسابك محظور من استخدام التطبيق',
      );
    }

    final ts = data['recipesSuspendedUntil'];
    if (ts is Timestamp) {
      final until = ts.toDate();
      if (DateTime.now().isBefore(until)) {
        return _GuardState(
          allowed: false,
          message: 'نشر الوصفات معلّق لحسابك حتى ${until.toLocal()}',
        );
      }
    }

    return const _GuardState(allowed: true);
  }
}

class RecipeCreatePage extends StatefulWidget {
  const RecipeCreatePage({Key? key}) : super(key: key);

  @override
  State<RecipeCreatePage> createState() => _RecipeCreatePageState();
}

class _RecipeCreatePageState extends State<RecipeCreatePage> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _captionCtrl = TextEditingController(); // وصف مختصر (اختياري)
  final _ingredientsCtrl = TextEditingController(); // سطر لكل مكوّن
  final _methodCtrl = TextEditingController();

  final _proteinCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();

  String? _selectedGoal; // cutting / maintenance / bulking / weight_loss / weight_gain

  final ImagePicker _picker = ImagePicker();
  File? _imageFile;

  bool _loadingGuard = true;
  _GuardState _guard = const _GuardState(allowed: false);
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadGuard();
  }

  Future<void> _loadGuard() async {
    final g = await _PostingGuard.loadForCurrentUser();
    if (!mounted) return;
    setState(() {
      _guard = g;
      _loadingGuard = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    _ingredientsCtrl.dispose();
    _methodCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    _caloriesCtrl.dispose();
    super.dispose();
  }

  // -------- تطبيع الأرقام لمنع NaN --------
  String _normalizeNum(String input) {
    const arabicIndic = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9'
    };
    final replaced = input.trim().replaceAll(',', '.');
    final buf = StringBuffer();
    for (final ch in replaced.runes) {
      final s = String.fromCharCode(ch);
      buf.write(arabicIndic[s] ?? s);
    }
    return buf.toString();
  }

  double? _tryParseDouble(String? v) {
    if (v == null) return null;
    final norm = _normalizeNum(v);
    return double.tryParse(norm);
  }

  // -------- Validators --------
  String? _vRequired(String? v, {String msg = 'حقل مطلوب'}) {
    if (v == null || v.trim().isEmpty) return msg;
    return null;
  }

  String? _vNum(String? v, {String msg = 'رقم غير صالح'}) {
    if (v == null || v.trim().isEmpty) return 'حقل مطلوب';
    final n = _tryParseDouble(v);
    if (n == null) return msg;
    if (n.isNaN || n.isInfinite) return msg;
    if (n < 0) return 'لا يقبل القيم السالبة';
    return null;
  }

  // -------- تأكيد وثيقة المستخدم (create vs update آمن) --------
  Future<void> _ensureUserDocMinimal(User user) async {
    final ref = FirebaseFirestore.instance.doc('users/${user.uid}');
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'email': user.email ?? '',
          'displayName': user.displayName ?? '',
          'photoUrl': user.photoURL,
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'role': 'user',
        });
      } else {
        tx.set(
          ref,
          {
            'email': user.email ?? '',
            'displayName': user.displayName ?? '',
            'photoUrl': user.photoURL,
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  // ----------------------------
  // اختيار/رفع صورة الوصفة
  // ----------------------------
  Future<void> _pickImage(ImageSource source) async {
    if (_submitting) return;
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() => _imageFile = File(x.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار الصورة: $e')),
      );
    }
  }

  Future<String> _uploadRecipeImage({
    required String uid,
    required String recipeId,
    required File file,
  }) async {
    final lower = file.path.toLowerCase();
    final isPng = lower.endsWith('.png');
    final ext = isPng ? 'png' : 'jpg';
    final contentType = isPng ? 'image/png' : 'image/jpeg';

    final ref = FirebaseStorage.instance
        .ref()
        .child('users/$uid/recipes/$recipeId.$ext');

    final meta = SettableMetadata(contentType: contentType);
    await ref.putFile(file, meta);
    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (!_guard.allowed) {
      if (_guard.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_guard.message!)),
        );
      }
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تسجيل الدخول')),
      );
      return;
    }
    if (_selectedGoal == null || _selectedGoal!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الهدف')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // 1) تأكيد users/{uid} حسب القواعد
      await _ensureUserDocMinimal(user);

      // 2) تجهيز البيانات + رفع الصورة (إن وجدت)
      final ingredients = _ingredientsCtrl.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final protein = _tryParseDouble(_proteinCtrl.text)!;
      final fat = _tryParseDouble(_fatCtrl.text)!;
      final carbs = _tryParseDouble(_carbsCtrl.text)!;
      final calories = _tryParseDouble(_caloriesCtrl.text)!;

      // ننشئ docId مسبقًا حتى نستخدمه كاسم ملف للصورة
      final docRef = FirebaseFirestore.instance.collection('recipes').doc();
      final recipeId = docRef.id;

      String? imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadRecipeImage(
          uid: user.uid,
          recipeId: recipeId,
          file: _imageFile!,
        );
      }

      final caption = _captionCtrl.text.trim().isEmpty
          ? null
          : _captionCtrl.text.trim();

      final data = <String, dynamic>{
        'userId': user.uid,
        'title': _titleCtrl.text.trim(),
        if (caption != null) 'caption': caption,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'ingredients': ingredients,
        'method': _methodCtrl.text.trim(),
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        'calories': calories,
        'goal': _selectedGoal,
        'likeCount': 0,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };

      // حقول اختيارية فقط إذا لها قيمة نصية غير فاضية
      final dn = (user.displayName ?? '').trim();
      if (dn.isNotEmpty) data['userName'] = dn;
      final pu = (user.photoURL ?? '').trim();
      if (pu.isNotEmpty) data['userPhotoUrl'] = pu;

      // 3) الإرسال
      await docRef.set(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر الوصفة بنجاح')),
      );
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر نشر الوصفة: ${e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر نشر الوصفة: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _imagePickerCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  color: Colors.black.withOpacity(0.04),
                  child: _imageFile == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.image_outlined, size: 34),
                            SizedBox(height: 8),
                            Text(
                              'أضف صورة للوجبة (اختياري)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        )
                      : Image.file(_imageFile!, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('التقاط صورة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('اختيار من المعرض'),
                  ),
                ),
              ],
            ),
            if (_imageFile != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _imageFile = null),
                  icon: const Icon(Icons.close),
                  label: const Text('إزالة الصورة'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingGuard) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final banner = (!_guard.allowed && _guard.message != null)
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(.35)),
            ),
            child: Text(
              _guard.message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        : const SizedBox.shrink();

    return PremiumGate(
      feature: PremiumFeature.recipes,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(title: const Text('إنشاء وصفة')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (!_guard.allowed) banner,
                  Expanded(
                    child: AbsorbPointer(
                      absorbing: !_guard.allowed,
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          children: [
                            _imagePickerCard(),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _titleCtrl,
                              decoration: const InputDecoration(
                                labelText: 'عنوان الوصفة',
                                border: OutlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (v) => _vRequired(v, msg: 'الرجاء إدخال العنوان'),
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _captionCtrl,
                              decoration: const InputDecoration(
                                labelText: 'وصف مختصر (اختياري)',
                                border: OutlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.next,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),

                            DropdownButtonFormField<String>(
                              value: _selectedGoal,
                              items: const [
                                DropdownMenuItem(value: 'cutting', child: Text('تنشيف')),
                                DropdownMenuItem(value: 'bulking', child: Text('تضخيم')),
                                DropdownMenuItem(value: 'maintenance', child: Text('المحافظة')),
                                DropdownMenuItem(value: 'weight_loss', child: Text('تنزيل الوزن')),
                                DropdownMenuItem(value: 'weight_gain', child: Text('رفع الوزن')),
                              ],
                              onChanged: (v) => setState(() => _selectedGoal = v),
                              decoration: const InputDecoration(
                                labelText: 'الهدف',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _ingredientsCtrl,
                              decoration: const InputDecoration(
                                labelText: 'المكونات (سطر لكل مكوّن)',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.newline,
                              minLines: 4,
                              maxLines: 8,
                              validator: (v) {
                                final hasAny = v != null &&
                                    v.split('\n').any((e) => e.trim().isNotEmpty);
                                return hasAny ? null : 'أدخل مكوّنًا واحدًا على الأقل';
                              },
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _methodCtrl,
                              decoration: const InputDecoration(
                                labelText: 'الطريقة/الخطوات',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.newline,
                              minLines: 5,
                              maxLines: 10,
                              validator: (v) => _vRequired(v, msg: 'أدخل خطوات التحضير'),
                            ),
                            const SizedBox(height: 12),

                            // ---- الماكروز ----
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _proteinCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'البروتين (غ)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: _vNum,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _carbsCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'الكارب (غ)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: _vNum,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _fatCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'الدهون (غ)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: _vNum,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _caloriesCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'السعرات (ك.س)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: _vNum,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_submitting || !_guard.allowed) ? null : _submit,
                      child: _submitting
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : const Text('نشر الوصفة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

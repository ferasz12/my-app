import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../community/local_repos.dart';
import 'local_repos.dart';

class BecomeTrainerScreen extends StatefulWidget {
  const BecomeTrainerScreen({super.key});
  @override
  State<BecomeTrainerScreen> createState() => _BecomeTrainerScreenState();
}

class _BecomeTrainerScreenState extends State<BecomeTrainerScreen> {
  final _form = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final bioCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '9900'); // هللات/سنتات
  final specCtrl = TextEditingController(text: 'تخسيس, مقاومة');

  String? personalImagePath; // صورة شخصية
  String? idImagePath; // صورة الهوية
  bool agreed = false;

  bool submitting = false;

  final _picker = ImagePicker();

  Future<void> _pickPersonal() async {
    final x =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => personalImagePath = x.path);
  }

  Future<void> _pickId() async {
    final x =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => idImagePath = x.path);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    bioCtrl.dispose();
    priceCtrl.dispose();
    specCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('أصبح مدربًا')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // الاسم
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'الاسم المعروض *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
            ),
            const SizedBox(height: 12),

            // نبذة
            TextFormField(
              controller: bioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'نبذة مختصرة'),
            ),
            const SizedBox(height: 12),

            // السعر
            TextFormField(
              controller: priceCtrl,
              decoration: const InputDecoration(
                  labelText: 'سعر الاشتراك الشهري (بالهللة/السنت) *'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'أدخل سعرًا صحيحًا';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // التخصصات
            TextFormField(
              controller: specCtrl,
              decoration:
                  const InputDecoration(labelText: 'التخصصات (مفصولة بفواصل)'),
            ),
            const SizedBox(height: 16),

            // صور مطلوبة (مستوى واحد: صورة شخصية + صورة هوية)
            Text('الصور المطلوبة',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _ImagePickTile(
                    title: 'صورة شخصية *',
                    path: personalImagePath,
                    onPick: _pickPersonal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ImagePickTile(
                    title: 'صورة الهوية *',
                    path: idImagePath,
                    onPick: _pickId,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // الشروط (مستوى واحد)
            CheckboxListTile(
              value: agreed,
              onChanged: (v) => setState(() => agreed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('أوافق على شروط المدربين وسياسة الاستخدام'),
              subtitle: const Text(
                  'يشمل ذلك الالتزام بالمحتوى اللائق وعدم تقديم وعود صحية مضللة.'),
            ),
            const SizedBox(height: 8),

            // زر الإرسال
            FilledButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إرسال الطلب'),
            ),
            const SizedBox(height: 8),
            Text(
              'المتطلبات: صورة شخصية واضحة + صورة هوية + الموافقة على الشروط. '
              'بعد المراجعة سيتم إشعارك بالنتيجة.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    // تحقق الصور والشروط
    if (personalImagePath == null || personalImagePath!.isEmpty) {
      _snack('الرجاء إرفاق صورة شخصية.');
      return;
    }
    if (idImagePath == null || idImagePath!.isEmpty) {
      _snack('الرجاء إرفاق صورة الهوية.');
      return;
    }
    if (!agreed) {
      _snack('الرجاء الموافقة على الشروط.');
      return;
    }

    setState(() => submitting = true);

    try {
      final me = await LocalAuthRepo().currentUser();
      await LocalTrainersRepo().submitApplication(
        userId: me.uid,
        name: nameCtrl.text.trim(),
        bio: bioCtrl.text.trim(),
        priceMonthlyCents: int.tryParse(priceCtrl.text.trim()) ?? 0,
        specialties: specCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        personalImagePath: personalImagePath!, // جديد
        idImagePath: idImagePath!, // جديد
      );

      if (!mounted) return;
      _snack('تم إرسال الطلب. سيتم مراجعته.');
      Navigator.pop(context);
    } catch (e) {
      _snack('حدث خطأ أثناء الإرسال: $e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

class _ImagePickTile extends StatelessWidget {
  final String title;
  final String? path;
  final VoidCallback onPick;

  const _ImagePickTile({
    required this.title,
    required this.path,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: path == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_a_photo),
                    SizedBox(height: 6),
                    Text('اختيار صورة'),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(path!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image)),
                ),
              ),
      ),
    );
  }
}

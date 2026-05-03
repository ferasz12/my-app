import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'announcement_service.dart';
import 'announcement_model.dart';

class AnnouncementEditorPage extends StatefulWidget {
  const AnnouncementEditorPage({super.key});

  @override
  State<AnnouncementEditorPage> createState() => _AnnouncementEditorPageState();
}

class _AnnouncementEditorPageState extends State<AnnouncementEditorPage> {
  final _svc = AnnouncementService();

  // حقول
  final _msgCtrl = TextEditingController();
  final _fontFamilyCtrl = TextEditingController(text: 'Tajawal');
  final _fontSizeCtrl = TextEditingController(text: '16');
  final _textColorCtrl = TextEditingController(text: '#0F172A');
  final _bgColorCtrl = TextEditingController(text: '#ECFDF5');
  final _linkTextCtrl = TextEditingController();
  final _linkUrlCtrl = TextEditingController();

  bool _enabled = true;
  bool _bold = true;
  bool _italic = false;
  String _type = 'info'; // info | warning | maintenance
  DateTime? _startAt;
  DateTime? _endAt;

  String? _imageUrl; // الحالية
  File? _pickedImage; // الجديدة

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _svc.ensureInitialized();
      final cfg = await _svc.getOnce();
      if (cfg != null) {
        _enabled = cfg.enabled;
        _msgCtrl.text = cfg.message;
        _fontFamilyCtrl.text = cfg.fontFamily ?? 'Tajawal';
        _fontSizeCtrl.text = (cfg.fontSize ?? 16).toString();
        _bold = cfg.bold;
        _italic = cfg.italic;
        _textColorCtrl.text = _colorToHex(cfg.textColor);
        _bgColorCtrl.text = _colorToHex(cfg.backgroundColor);
        _linkTextCtrl.text = cfg.linkText ?? '';
        _linkUrlCtrl.text = cfg.linkUrl ?? '';
        _type = cfg.type;
        _imageUrl = cfg.imageUrl;
        _startAt = cfg.startAt;
        _endAt = cfg.endAt;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _colorToHex(Color c) =>
      '#${c.alpha.toRadixString(16).padLeft(2, '0')}${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _pickedImage = File(x.path));
  }

  Future<String?> _uploadImage(File f) async {
    final ref = FirebaseStorage.instance
        .ref('appBanners/banner_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final task = await ref.putFile(f);
    return task.ref.getDownloadURL();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startAt ?? now) : (_endAt ?? now.add(const Duration(days: 7)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    final dt = DateTime(
      date.year, date.month, date.day,
      time?.hour ?? 0, time?.minute ?? 0,
    );
    setState(() {
      if (isStart) _startAt = dt; else _endAt = dt;
    });
  }

  Future<void> _save() async {
    if (_msgCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب الرسالة أولاً')));
      return;
    }
    setState(() => _saving = true);
    try {
      String? newUrl = _imageUrl;
      if (_pickedImage != null) {
        newUrl = await _uploadImage(_pickedImage!);
      }
      final data = <String, dynamic>{
        'enabled': _enabled,
        'message': _msgCtrl.text.trim(),
        'fontFamily': _fontFamilyCtrl.text.trim(),
        'fontSize': double.tryParse(_fontSizeCtrl.text.trim()),
        'bold': _bold,
        'italic': _italic,
        'textColor': _textColorCtrl.text.trim(),
        'backgroundColor': _bgColorCtrl.text.trim(),
        'linkText': _linkTextCtrl.text.trim(),
        'linkUrl': _linkUrlCtrl.text.trim(),
        'type': _type,
        'imageUrl': newUrl ?? '',
        'startAt': _startAt != null ? Timestamp.fromDate(_startAt!) : FieldValue.delete(),
        'endAt': _endAt != null ? Timestamp.fromDate(_endAt!) : FieldValue.delete(),
      };
      await _svc.update(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إدارة الإعلان العام')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    title: const Text('تفعيل الإعلان'),
                  ),
                  TextField(
                    controller: _msgCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'الرسالة',
                      hintText: 'مثال: صيانة اليوم من 10:00 حتى 12:00',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // تنسيق
                  Text('التنسيق', style: t.titleMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _fontFamilyCtrl,
                          decoration: const InputDecoration(labelText: 'Font family (اختياري)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _fontSizeCtrl,
                          decoration: const InputDecoration(labelText: 'حجم الخط'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textColorCtrl,
                          decoration: const InputDecoration(labelText: 'لون النص #HEX'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _bgColorCtrl,
                          decoration: const InputDecoration(labelText: 'لون الخلفية #HEX'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _type,
                          items: const [
                            DropdownMenuItem(value: 'info', child: Text('إشعار')),
                            DropdownMenuItem(value: 'warning', child: Text('تحذير')),
                            DropdownMenuItem(value: 'maintenance', child: Text('صيانة')),
                          ],
                          onChanged: (v) => setState(() => _type = v ?? 'info'),
                          decoration: const InputDecoration(labelText: 'النوع'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _bold,
                            onChanged: (v) => setState(() => _bold = v ?? false),
                          ),
                          const Text('غامق'),
                          const SizedBox(width: 12),
                          Checkbox(
                            value: _italic,
                            onChanged: (v) => setState(() => _italic = v ?? false),
                          ),
                          const Text('مائل'),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // الصورة
                  Text('صورة (اختياري)', style: t.titleMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (_imageUrl != null && _imageUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(_imageUrl!, width: 64, height: 64, fit: BoxFit.cover),
                        ),
                      if (_imageUrl != null && _imageUrl!.isNotEmpty) const SizedBox(width: 8),
                      if (_pickedImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_pickedImage!, width: 64, height: 64, fit: BoxFit.cover),
                        ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('اختيار صورة'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // رابط (اختياري)
                  Text('رابط (اختياري)', style: t.titleMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _linkTextCtrl,
                          decoration: const InputDecoration(labelText: 'نص الرابط'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _linkUrlCtrl,
                          decoration: const InputDecoration(labelText: 'الرابط'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // الجدولة (اختياري)
                  Text('الجدولة (اختياري)', style: t.titleMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDateTime(isStart: true),
                          icon: const Icon(Icons.date_range),
                          label: Text(_startAt == null
                              ? 'بداية العرض'
                              : 'من: ${_startAt!.toLocal()}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDateTime(isStart: false),
                          icon: const Icon(Icons.event),
                          label: Text(_endAt == null
                              ? 'نهاية العرض'
                              : 'إلى: ${_endAt!.toLocal()}'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('حفظ'),
                  ),
                ],
              ),
      ),
    );
  }
}

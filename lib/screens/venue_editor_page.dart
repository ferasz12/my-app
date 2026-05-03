// lib/screens/venue_editor_page.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/restaurants_firestore_repository.dart';
import '../models/venue.dart';

class VenueEditorPage extends StatefulWidget {
  final VenueType type;
  final Venue? existing;

  const VenueEditorPage({
    super.key,
    required this.type,
    this.existing,
  });

  @override
  State<VenueEditorPage> createState() => _VenueEditorPageState();
}

class _VenueEditorPageState extends State<VenueEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  final _repo = RestaurantsFirestoreRepository();

  late final String _venueId;
  String? _imageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _venueId = ex?.id ?? _repo.newVenueId();
    _name.text = ex?.name ?? '';
    _imageUrl = ex?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _title {
    final isNew = widget.existing == null;
    if (widget.type == VenueType.cafe) {
      return isNew ? 'إضافة مقهى' : 'تعديل المقهى';
    }
    return isNew ? 'إضافة مطعم' : 'تعديل المطعم';
  }

  Future<void> _pickImage() async {
    try {
      final url = await _repo.pickAndUploadImage(
        storagePath: 'restaurants/$_venueId/cover.jpg',
      );
      if (!mounted) return;
      if (url == null) return;
      setState(() => _imageUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر رفع الصورة: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await _repo.upsertVenue(
        id: _venueId,
        type: widget.type,
        name: _name.text.trim(),
        imageUrl: _imageUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Stack(
        children: [
          // خلفية خفيفة
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.10),
                    cs.secondary.withOpacity(0.06),
                    cs.surface,
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ImageBox(
                      imageUrl: _imageUrl,
                      onPick: _pickImage,
                      label: widget.type == VenueType.cafe ? 'صورة المقهى' : 'صورة المطعم',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _name,
                      // لا يمكن استخدام const هنا لأن labelText يعتمد على widget.type
                      decoration: InputDecoration(
                        labelText: widget.type == VenueType.cafe ? 'اسم المقهى' : 'اسم المطعم',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'اكتب الاسم';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ID: $_venueId',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onPick;
  final String label;

  const _ImageBox({
    required this.imageUrl,
    required this.onPick,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
              child: imageUrl == null
                  ? const Center(child: Icon(Icons.image, size: 44))
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Icon(Icons.broken_image, size: 44)),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.photo_library),
          label: Text('اختيار/تغيير $label'),
        ),
      ],
    );
  }
}

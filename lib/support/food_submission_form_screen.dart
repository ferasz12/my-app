
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// شاشة: إضافة عنصر غذائي من المستخدم لمراجعة الأدمن
class FoodSubmissionFormScreen extends StatefulWidget {
  const FoodSubmissionFormScreen({super.key});

  @override
  State<FoodSubmissionFormScreen> createState() => _FoodSubmissionFormScreenState();
}

class _FoodSubmissionFormScreenState extends State<FoodSubmissionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _cal = TextEditingController();
  final _pro = TextEditingController();
  final _carb = TextEditingController();
  final _fat = TextEditingController();

  String _unit = 'gram'; // 'gram' | 'count'
  int _perAmount = 100;  // 100g أو 1 piece
  bool _confirm = false;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _cal.dispose();
    _pro.dispose();
    _carb.dispose();
    _fat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || !_confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكمل الحقول ووافق على الإقرار')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;
      await db.collection('food_submissions').add({
        'status': 'pending',
        'name': _name.text.trim(),
        'unitType': _unit,
        'perAmount': _perAmount,
        'caloriesKcal': double.parse(_cal.text),
        'proteinG': double.parse(_pro.text),
        'carbsG': double.parse(_carb.text),
        'fatG': double.parse(_fat.text),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'submittedAt': Timestamp.now(),
        'submittedBy': uid,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال العنصر للمراجعة 👌')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الإرسال: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة عنصر للقائمة')),
      body: AbsorbPointer(
        absorbing: _sending,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم العنصر'),
                validator: (v) => (v==null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      items: const [
                        DropdownMenuItem(value: 'gram', child: Text('بالغرام')),
                        DropdownMenuItem(value: 'count', child: Text('بالعدد')),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _unit = v!;
                          _perAmount = _unit == 'gram' ? 100 : 1;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'نوع الوحدة'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: '100',
                      key: ValueKey(_unit),
                      decoration: InputDecoration(
                        labelText: _unit == 'gram' ? 'لكل (غ)' : 'لكل (قطعة)',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _perAmount = int.tryParse(v) ?? (_unit=='gram'?100:1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _numField(_cal, 'السعرات (kcal)'),
              Row(children: [
                Expanded(child: _numField(_pro, 'بروتين (غ)')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_carb, 'كارب (غ)')),
                const SizedBox(width: 8),
                Expanded(child: _numField(_fat, 'دهون (غ)')),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'ملاحظات إضافية (اختياري)'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _confirm,
                onChanged: (v) => setState(() => _confirm = v ?? false),
                title: const Text('أقرّ بأن المعلومات صحيحة بقدر علمي'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _submit,
                icon: _sending ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.send),
                label: const Text('إرسال للمراجعة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) => TextFormField(
    controller: c,
    decoration: InputDecoration(labelText: label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (v) => (v==null || double.tryParse(v)==null) ? 'أدخل رقمًا صالحًا' : null,
  );
}

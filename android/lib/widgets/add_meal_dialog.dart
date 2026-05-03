import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/meal.dart';
import '../repos/meals_repo.dart';
import '../repos/points_repo.dart';

class AddMealDialog extends StatefulWidget {
  const AddMealDialog({super.key});

  @override
  State<AddMealDialog> createState() => _AddMealDialogState();
}

class _AddMealDialogState extends State<AddMealDialog> {
  final _formKey = GlobalKey<FormState>();

  String name = '';
  double calories = 0;
  double protein = 0;
  double carbs = 0;
  double fats = 0;

  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    // نبني كائن الوجبة (لو موديلك مختلف عدّل الحقول حسب Model عندك)
    final meal = Meal(
      // لو ما عندك id في الموديل احذف السطرين التاليين
      id: UniqueKey().toString(),
      name: name,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fats: fats,
      // أزل أي حقول غير موجودة في موديلك
    );

    setState(() => _submitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid != null) {
        // مستخدم مسجّل: خزّن في فايرستور + امنح نقطة/نقاط
        await MealsRepo.addMeal(uid, meal);
        await PointsRepo.award(
          uid: uid,
          eventKey: 'meal_logged',
          points: 1, // عدّل عدد النقاط إذا عندك سياسة مختلفة
          meta: {'mealName': meal.name},
        );

        if (mounted) {
          Navigator.of(context).pop(meal); // نرجّع الوجبة للواجهة اللي فتحت الدايالوغ
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت إضافة الوجبة ومزامنتها')),
          );
        }
      } else {
        // زائر: سلوكك المحلي القديم (يرجع الوجبة للأب)
        if (mounted) {
          Navigator.of(context).pop(meal);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت إضافة الوجبة محلياً (زائر)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّرت الإضافة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة وجبة'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'اسم الوجبة'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'أدخل اسم الوجبة' : null,
                onSaved: (val) => name = val!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'السعرات الحرارية'),
                keyboardType: TextInputType.number,
                validator: (val) =>
                    (val == null || double.tryParse(val) == null)
                        ? 'أدخل رقم صحيح'
                        : null,
                onSaved: (val) => calories = double.parse(val!),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'البروتين (جرام)'),
                keyboardType: TextInputType.number,
                validator: (val) =>
                    (val == null || double.tryParse(val) == null)
                        ? 'أدخل رقم صحيح'
                        : null,
                onSaved: (val) => protein = double.parse(val!),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'الكارب (جرام)'),
                keyboardType: TextInputType.number,
                validator: (val) =>
                    (val == null || double.tryParse(val) == null)
                        ? 'أدخل رقم صحيح'
                        : null,
                onSaved: (val) => carbs = double.parse(val!),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'الدهون (جرام)'),
                keyboardType: TextInputType.number,
                validator: (val) =>
                    (val == null || double.tryParse(val) == null)
                        ? 'أدخل رقم صحيح'
                        : null,
                onSaved: (val) => fats = double.parse(val!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator())
              : const Text('إضافة'),
        ),
      ],
    );
  }
}

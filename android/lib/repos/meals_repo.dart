import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/meal.dart';

class MealsRepo {
  static final _fs = FirebaseFirestore.instance;

  /// yyyy-MM-dd
  static String _ymd(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  /// ستريم بيانات يوم المستخدم (لو احتجته لاحقاً)
  static Stream<Map<String, dynamic>> streamToday(String uid) {
    final id = _ymd(DateTime.now());
    return _fs
        .collection('users')
        .doc(uid)
        .collection('days')
        .doc(id)
        .snapshots()
        .map((d) => (d.data() ?? <String, dynamic>{}));
  }

  /// إضافة وجبة لليوم الحالي وتحديث المجاميع
  static Future<void> addMeal(String uid, Meal m) async {
    final id = _ymd(DateTime.now());
    final dayRef = _fs.collection('users').doc(uid).collection('days').doc(id);

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(dayRef);
      final base = (snap.data() ?? <String, dynamic>{});

      final List meals =
          (base['meals'] as List?)?.toList(growable: true) ?? <Map<String, dynamic>>[];
      final Map<String, num> totals = (base['totals'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num))) ??
          <String, num>{};

      // نولّد id بسيط للعنصر داخل المصفوفة (اختياري)
      final mealId = DateTime.now().microsecondsSinceEpoch.toString();

      meals.add({
        'id': mealId,
        'name': m.name,
        'calories': m.calories,
        'protein': m.protein,
        'carbs': m.carbs,
        'fats': m.fats, // نستخدم اسم الحقل كما في موديلك
        'createdAt': Timestamp.now(),
      });

      final newTotals = <String, num>{
        'calories': (totals['calories'] ?? 0) + m.calories,
        'protein': (totals['protein'] ?? 0) + m.protein,
        'carbs': (totals['carbs'] ?? 0) + m.carbs,
        'fats': (totals['fats'] ?? 0) + m.fats, // نفس التسمية
      };

      tx.set(
        dayRef,
        {
          'meals': meals,
          'totals': newTotals,
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );
    });
  }
}

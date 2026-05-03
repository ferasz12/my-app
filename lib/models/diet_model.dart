import 'package:flutter/material.dart';

/// نموذج الرجيم المستخدم في الـ Provider.
/// ملاحظات:
/// - نستخدم نصوصًا جاهزة (benefits/risks/tips/recommendedFoods) كما بنيتها في الـ Provider.
/// - الحقول الاختيارية لتغطية أنظمة مختلفة (كيتو، صيام، DASH...).
class DietModel {
  final String id;
  final String name;
  final String goalType; // مثال: "إنقاص الوزن" / "بناء العضلات"...

  // وصف نصي جاهز
  final String? benefits;
  final String? risks;
  final String? tips;
  final String? recommendedFoods;

  // قيود/إرشادات كمية اختيارية
  final double? calorieDelta;   // +/- سعرات على سعرات المحافظة
  final double? proteinPerKg;   // غ/كجم
  final double? carbCapGrams;   // حد أعلى للكارب (غ/يوم)
  final double? fatPctMax;      // أقصى نسبة دهون من السعرات (0..1)
  final int? sodiumCapMg;       // حد صوديوم (ملغم/يوم)

  // للصيام المتقطع
  final TimeOfDay? eatStart;
  final TimeOfDay? eatEnd;

  const DietModel({
    required this.id,
    required this.name,
    required this.goalType,
    this.benefits,
    this.risks,
    this.tips,
    this.recommendedFoods,
    this.calorieDelta,
    this.proteinPerKg,
    this.carbCapGrams,
    this.fatPctMax,
    this.sodiumCapMg,
    this.eatStart,
    this.eatEnd,
  });
}

// =============================================================
// FILE: lib/fasting/fasting_stage_engine.dart
// محرك مراحل الصيام — يعرض رسائل حسب الزمن المنقضي
// =============================================================
import 'package:flutter/material.dart';

class FastingStage {
  final Duration threshold;
  final String title;
  final String description;
  const FastingStage({required this.threshold, required this.title, required this.description});
}

class FastingStageEngine {
  static const stages = <FastingStage>[
    FastingStage(
      threshold: Duration(hours: 0),
      title: 'بدء الصيام',
      description: 'ينخفض الإنسولين تدريجيًا ويبدأ الجسم بالاعتماد على مخزون الطاقة.',
    ),
    FastingStage(
      threshold: Duration(hours: 2),
      title: 'مرحلة الاستقرار',
      description: 'ينخفض السكر في الدم للمستوى الطبيعي ويقلّ هرمون الجوع عند البعض.',
    ),
    FastingStage(
      threshold: Duration(hours: 6),
      title: 'تحفيز حرق الدهون',
      description: 'يتزايد الاعتماد على الدهون كمصدر للطاقة تدريجيًا.',
    ),
    FastingStage(
      threshold: Duration(hours: 12),
      title: 'استخدام أجسام كيتونية خفيف',
      description: 'قد يبدأ الجسم بإنتاج أجسام كيتونية بشكل طفيف لدى بعض الأشخاص.',
    ),
    FastingStage(
      threshold: Duration(hours: 16),
      title: 'ذروة بروتوكول 16/8',
      description: 'الوصول لنهاية نافذة الصيام — وقت مثالي لبدء وجبة متوازنة.',
    ),
  ];

  static FastingStage current(Duration elapsed) {
    FastingStage cur = stages.first;
    for (final s in stages) {
      if (elapsed >= s.threshold) {
        cur = s;
      } else {
        break;
      }
    }
    return cur;
  }

  static List<FastingStage> timeline(Duration total) {
    return stages.where((s) => s.threshold <= total).toList();
  }
}

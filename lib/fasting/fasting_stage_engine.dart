// =============================================================
// FILE: lib/fasting/fasting_stage_engine.dart
// محرك مراحل الصيام — مراحل مرتبة للصيام المتقطع
// =============================================================
import 'package:flutter/material.dart';

class FastingStage {
  final Duration threshold;
  final String title;
  final String description;
  final IconData icon;

  const FastingStage({
    required this.threshold,
    required this.title,
    required this.description,
    this.icon = Icons.timelapse_rounded,
  });
}

class FastingStageEngine {
  static const stages = <FastingStage>[
    FastingStage(
      threshold: Duration.zero,
      title: 'بداية الصيام',
      description: 'الجسم يستخدم طاقة آخر وجبة. ركز على الماء وخذ البداية بهدوء.',
      icon: Icons.play_circle_fill_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 2),
      title: 'تثبيت البداية',
      description: 'قد تظهر رغبة بسيطة بالأكل بسبب العادة. اشغل نفسك ولا تستعجل.',
      icon: Icons.self_improvement_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 4),
      title: 'استقرار الشهية',
      description: 'الجوع يبدأ يهدأ عند كثير من الناس. الماء والقهوة السوداء يساعدونك.',
      icon: Icons.water_drop_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 8),
      title: 'استخدام المخزون',
      description: 'الجسم يبدأ يعتمد أكثر على مخزون الطاقة حسب أكلك ونشاطك.',
      icon: Icons.local_fire_department_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 12),
      title: 'مرحلة متقدمة',
      description: 'وصلت لمرحلة ممتازة. لا تكسر الصيام بسناكات عشوائية.',
      icon: Icons.bolt_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 16),
      title: 'اكتمال 16/8',
      description: 'أنجزت بروتوكول 16/8. افتح نافذة الأكل بوجبة متوازنة وغنية بالبروتين.',
      icon: Icons.emoji_events_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 18),
      title: 'صيام طويل',
      description: 'أنت في مدة متقدمة. لا تطول إذا تحس بدوخة أو تعب غير طبيعي.',
      icon: Icons.shield_moon_rounded,
    ),
    FastingStage(
      threshold: Duration(hours: 20),
      title: 'بروتوكول 20/4',
      description: 'انتهت مدة 20/4. اكسر الصيام تدريجيًا واهتم بالسوائل والمعادن.',
      icon: Icons.workspace_premium_rounded,
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
    final safeTotal = total <= Duration.zero ? const Duration(hours: 16) : total;
    return stages.where((s) => s.threshold <= safeTotal).toList(growable: false);
  }

  static FastingStage next(Duration elapsed, Duration total) {
    final list = timeline(total);
    for (final s in list) {
      if (elapsed < s.threshold) return s;
    }
    return list.isEmpty ? stages.last : list.last;
  }

  static FastingStage? nextOrNull(Duration elapsed, Duration total) {
    final list = timeline(total);
    for (final s in list) {
      if (elapsed < s.threshold) return s;
    }
    return null;
  }
}

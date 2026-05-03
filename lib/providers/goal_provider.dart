// lib/providers/goal_provider.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/weight_goal.dart';

class GoalProvider extends ChangeNotifier {
  WeightGoal? _goal;
  WeightGoal? get goal => _goal;

  void setGoal(WeightGoal g) {
    _goal = g;
    notifyListeners();
  }

  WeightGoal buildGoal({
    required double currentWeight,
    required double targetWeight,
    required DateTime targetDate,
    required int age,
    required String activityLevel, // 'low' | 'moderate' | 'high'
  }) {
    final now = DateTime.now();
    final days = max(1, targetDate.difference(now).inDays);
    final weeks = max(1, (days / 7).floor());
    final diffKg = (currentWeight - targetWeight).abs();
    final weekly = diffKg / weeks;

    GoalDifficulty base;
    final isLoss = targetWeight < currentWeight;

    if (isLoss) {
      if (weekly <= 0.5) base = GoalDifficulty.easy;
      else if (weekly <= 1.0) base = GoalDifficulty.feasible;
      else if (weekly <= 1.5) base = GoalDifficulty.hard;
      else base = GoalDifficulty.unrealistic;
    } else {
      if (weekly <= 0.25) base = GoalDifficulty.easy;
      else if (weekly <= 0.5) base = GoalDifficulty.feasible;
      else if (weekly <= 0.75) base = GoalDifficulty.hard;
      else base = GoalDifficulty.unrealistic;
    }

    GoalDifficulty adjust(GoalDifficulty d, int step) {
      final idx = d.index + step;
      return GoalDifficulty.values[idx.clamp(0, GoalDifficulty.values.length - 1)];
    }

    var difficulty = base;
    if (activityLevel == 'high' && age < 35) difficulty = adjust(difficulty, -1);
    if (activityLevel == 'low' || age >= 50) difficulty = adjust(difficulty, 1); // ← هنا

    final sign = isLoss ? -1.0 : 1.0;
    final dailyDelta = sign * (weekly * 7700.0) / 7.0;

    final note = _buildAnalysisNote(
      age: age,
      activityLevel: activityLevel,
      difficulty: difficulty,
      isLoss: isLoss,
    );

    return WeightGoal(
      currentWeight: currentWeight,
      targetWeight: targetWeight,
      targetDate: targetDate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      difficulty: difficulty,
      weeklyChangeKg: weekly,
      dailyCalorieDelta: dailyDelta,
      analysisNote: note,
    );
  }

  String _buildAnalysisNote({
    required int age,
    required String activityLevel,
    required GoalDifficulty difficulty,
    required bool isLoss,
  }) {
    final dir = isLoss ? "تخفيض الوزن" : "زيادة الوزن";
    final act = {
      'low': 'نشاطك اليومي منخفض',
      'moderate': 'نشاطك اليومي متوسط',
      'high': 'نشاطك اليومي عالٍ',
    }[activityLevel] ?? 'نشاطك اليومي غير محدد';

    final diff = {
      GoalDifficulty.easy: 'هدفك واقعي وسهل التنفيذ.',
      GoalDifficulty.feasible: 'هدفك ممكن مع التزام جيّد.',
      GoalDifficulty.hard: 'هدفك صعب ويحتاج انضباط قوي.',
      GoalDifficulty.unrealistic: 'الهدف غير صحي/غير واقعي بالفترة المحددة.',
    }[difficulty]!;

    return '$diff $act، وسنركز على $dir بخطّة مناسبة لعاداتك.';
  }
}

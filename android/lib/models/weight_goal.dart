import 'package:cloud_firestore/cloud_firestore.dart';

enum GoalDifficulty { easy, feasible, hard, unrealistic }

class WeightGoal {
  final double currentWeight;
  final double targetWeight;
  final DateTime targetDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final GoalDifficulty difficulty;
  final double weeklyChangeKg;      // كجم/أسبوع (قيمة موجبة دومًا)
  final double dailyCalorieDelta;   // + فائض / - عجز
  final String analysisNote;        // نص التحليل المختصر

  WeightGoal({
    required this.currentWeight,
    required this.targetWeight,
    required this.targetDate,
    required this.createdAt,
    required this.updatedAt,
    required this.difficulty,
    required this.weeklyChangeKg,
    required this.dailyCalorieDelta,
    required this.analysisNote,
  });

  Map<String, dynamic> toMap() => {
    'currentWeight': currentWeight,
    'targetWeight': targetWeight,
    'targetDate': Timestamp.fromDate(targetDate),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'difficulty': difficulty.name,
    'weeklyChangeKg': weeklyChangeKg,
    'dailyCalorieDelta': dailyCalorieDelta,
    'analysisNote': analysisNote,
  };

  factory WeightGoal.fromMap(Map<String, dynamic> m) {
    return WeightGoal(
      currentWeight: (m['currentWeight'] ?? 0).toDouble(),
      targetWeight: (m['targetWeight'] ?? 0).toDouble(),
      targetDate: (m['targetDate'] as Timestamp).toDate(),
      createdAt: (m['createdAt'] as Timestamp).toDate(),
      updatedAt: (m['updatedAt'] as Timestamp).toDate(),
      difficulty: GoalDifficulty.values.firstWhere(
        (d) => d.name == (m['difficulty'] ?? 'feasible'),
        orElse: () => GoalDifficulty.feasible,
      ),
      weeklyChangeKg: (m['weeklyChangeKg'] ?? 0).toDouble(),
      dailyCalorieDelta: (m['dailyCalorieDelta'] ?? 0).toDouble(),
      analysisNote: (m['analysisNote'] ?? '') as String,
    );
  }
}

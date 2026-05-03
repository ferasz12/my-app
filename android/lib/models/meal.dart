// lib/models/meal.dart
class Meal {
  final String id;
  final String restaurant; // اسم المنشأة (مطعم/مقهى)
  final String name;
  final String category;
  final String serving;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  const Meal({
    required this.id,
    required this.restaurant,
    required this.name,
    required this.category,
    required this.serving,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

import 'package:flutter/material.dart';
import '../models/meal.dart';

class CaloriesProvider extends ChangeNotifier {
  final List<Meal> _meals = [];

  List<Meal> get meals => _meals;

  double get totalCalories => _meals.fold(0, (sum, m) => sum + m.calories);
  double get totalProtein => _meals.fold(0, (sum, m) => sum + m.protein);
  double get totalFat => _meals.fold(0, (sum, m) => sum + m.fat);
  double get totalCarbs => _meals.fold(0, (sum, m) => sum + m.carbs);

  void addMeal(Meal meal) {
    _meals.add(meal);
    notifyListeners();
  }

  void removeMeal(Meal meal) {
    _meals.remove(meal);
    notifyListeners();
  }

  void clearMeals() {
    _meals.clear();
    notifyListeners();
  }
}

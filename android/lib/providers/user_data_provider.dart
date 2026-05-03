import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserDataProvider extends ChangeNotifier {
  double weight = 60.0;
  double height = 170.0;
  double calories = 0;
  double protein = 0;
  double fat = 0;
  double carbs = 0;

  Future<void> loadUserData(String email) async {
    final prefs = await SharedPreferences.getInstance();
    weight = prefs.getDouble('weight_$email') ?? 60.0;
    height = prefs.getDouble('height_$email') ?? 170.0;
    _calculateMacros(email);
  }

  void updateWeight(String email, double newWeight) async {
    weight = newWeight;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('weight_$email', newWeight);
    _calculateMacros(email);
  }

  void updateHeight(String email, double newHeight) async {
    height = newHeight;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('height_$email', newHeight);
    _calculateMacros(email);
  }

  void _calculateMacros(String email) async {
    final prefs = await SharedPreferences.getInstance();
    calories = weight * 24 * 1.2;
    protein = weight * 2.0;
    fat = weight * 0.8;
    carbs = (calories - (protein * 4 + fat * 9)) / 4;

    await prefs.setDouble('caloriesNeeded', calories);
    await prefs.setDouble('protein', protein);
    await prefs.setDouble('fat', fat);
    await prefs.setDouble('carbs', carbs);

    notifyListeners();
  }
}

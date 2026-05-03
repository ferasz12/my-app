import 'package:shared_preferences/shared_preferences.dart';

class UserStorage {
  /// حفظ بيانات المستخدم
  static Future<void> saveUserMetrics({
    required String email,
    required double weight,
    required double height,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    required String goal,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble('weight_$email', weight);
    await prefs.setDouble('height_$email', height);
    await prefs.setDouble('calories_$email', calories);
    await prefs.setDouble('protein_$email', protein);
    await prefs.setDouble('fat_$email', fat);
    await prefs.setDouble('carbs_$email', carbs);
    await prefs.setString('goal_$email', goal);
  }

  /// استرجاع بيانات المستخدم
  static Future<Map<String, dynamic>> getUserMetrics(String email) async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'weight': prefs.getDouble('weight_$email'),
      'height': prefs.getDouble('height_$email'),
      'calories': prefs.getDouble('calories_$email'),
      'protein': prefs.getDouble('protein_$email'),
      'fat': prefs.getDouble('fat_$email'),
      'carbs': prefs.getDouble('carbs_$email'),
      'goal': prefs.getString('goal_$email'),
    };
  }

  /// حذف بيانات المستخدم بالكامل (مثلاً عند حذف الحساب)
  static Future<void> clearUserMetrics(String email) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('weight_$email');
    await prefs.remove('height_$email');
    await prefs.remove('calories_$email');
    await prefs.remove('protein_$email');
    await prefs.remove('fat_$email');
    await prefs.remove('carbs_$email');
    await prefs.remove('goal_$email');
  }
}

import 'package:cloud_functions/cloud_functions.dart';

class MealTextAnalyzer {
  // المنطقة حسب نشرك أنت (ظهرت عندك europe-west1)
  static final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// يستدعي analyzeMealText بوصف حر للوجبة
  static Future<Map<String, dynamic>> analyze(String description) async {
    final callable = _functions.httpsCallable('analyzeMealText');
    final res = await callable.call(<String, dynamic>{
      'description': description,
    });
    // يرجع JSON موحّد: name, calories_kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, confidence, notes
    return Map<String, dynamic>.from(res.data as Map);
  }
}

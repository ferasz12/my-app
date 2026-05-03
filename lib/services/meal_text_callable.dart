import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MealTextAnalyzer {
  // المنطقة حسب نشرك أنت (ظهرت عندك europe-west1)
  static final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// يستدعي analyzeMealText بوصف حر للوجبة
  static Future<Map<String, dynamic>> analyze(
    String description, {
    List<Map<String, dynamic>>? clarificationAnswers,
  }) async {
    // ✅ ضمان وجود جلسة + تحديث التوكن قبل استدعاء Cloud Functions
    // (يقلّل ظهور خطأ Unauthenticated بسبب توكن قديم/غير جاهز)
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'سجّل دخولك أولاً.',
        details: null,
      );
    }
    try {
      await user.getIdToken(true);
    } catch (_) {
      // نتجاهل ونجرّب الاستدعاء مباشرة
    }

    final callable = _functions.httpsCallable('analyzeMealText');
    try {
      final res = await callable.call(<String, dynamic>{
        'description': description,
        if (clarificationAnswers != null && clarificationAnswers.isNotEmpty)
          'clarificationAnswers': clarificationAnswers,
      });
      // يرجع JSON موحّد: name, calories_kcal, protein_g, carbs_g, fat_g, ...
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      // ✅ Retry مرة واحدة لو كانت المشكلة Unauthenticated (أحياناً بسبب توكن قديم)
      if (e.code == 'unauthenticated') {
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          final res = await callable.call(<String, dynamic>{
            'description': description,
            if (clarificationAnswers != null && clarificationAnswers.isNotEmpty)
              'clarificationAnswers': clarificationAnswers,
          });
          return Map<String, dynamic>.from(res.data as Map);
        } catch (_) {
          // نكمل ونرمي الخطأ الأصلي
        }
      }
      rethrow;
    }
  }
}

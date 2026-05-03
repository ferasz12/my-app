import 'package:cloud_functions/cloud_functions.dart';

/// بديل آمن لـ "Gemini helper" بدون أي مفاتيح داخل التطبيق.
/// يعتمد على Cloud Function: askWazenCoach (تخزين الأسرار في Firebase Secrets).
class GeminiHelper {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final callable = _functions.httpsCallable('askWazenCoach');
    final res = await callable.call(<String, dynamic>{
      'mode': 'chat',
      'message': message,
      'history': history,
    });
    final data = (res.data as Map?) ?? const {};
    final reply = (data['reply'] ?? data['text'] ?? data['message']).toString();
    return reply.isEmpty ? '...' : reply;
  }
}

// lib/services/ask_wazen_coach_api.dart
// واجهة استدعاء Cloud Function الخاصة بميزة "اسأل وازن".

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AskWazenCoachApi {
  AskWazenCoachApi._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static HttpsCallable get _callable => _fn.httpsCallable('askWazenCoach');

  // بعض الردود قد تصل كنص JSON مثل:
  // {"response":"..."} أو ```json {...}```
  // هذا يضمن عرض النص فقط داخل واجهة الشات.
  static String _cleanReply(dynamic raw) {
    if (raw == null) return '';
    if (raw is Map) {
      final v = raw['response'] ?? raw['reply'] ?? raw['text'] ?? raw['message'];
      return _cleanReply(v);
    }
    if (raw is List) {
      return raw.map((e) => _cleanReply(e)).where((s) => s.isNotEmpty).join('\n').trim();
    }

    var s = raw.toString().trim();
    if (s.isEmpty) return '';

    // strip fenced code blocks ```json ... ```
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      s = s.replaceFirst(RegExp(r'```\s*$'), '');
      s = s.trim();
    }

    // Try parse JSON (common when Gemini returns application/json)
    if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          final v = decoded['response'] ??
              decoded['reply'] ??
              decoded['text'] ??
              decoded['message'] ??
              decoded['content'];
          if (v != null) return v.toString().trim();
        }
        if (decoded is List) {
          return decoded.map((e) => _cleanReply(e)).where((x) => x.isNotEmpty).join('\n').trim();
        }
      } catch (_) {
        // ignore
      }
    }

    // fallback: إذا كان النص يحتوي "response": داخل JSON غير مكتمل/غير قابل للـ decode
    final m = RegExp(r'"response"\s*:\s*"([\s\S]*)"\s*\}?\s*$').firstMatch(s);
    if (m != null) {
      return (m.group(1) ?? '').replaceAll('\\n', '\n').trim();
    }

    return s;
  }

  /// إرسال تقرير اليوم (مرة واحدة في اليوم) وتلقي رد المدرب.
  static Future<String> sendDailyReport({
    required Map<String, dynamic> report,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لاستخدام مدرب وازن الذكي.',
        details: null,
      );
    }

    final ymd = (report['ymd'] ?? '').toString();
    final res = await _callable.call({
      'mode': 'daily',
      'ymd': ymd,
      'report': report,
    });

    final data =
        (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return _cleanReply(data['reply']);
  }

  /// رسالة دردشة عادية (بدون إعادة إرسال البيانات الكاملة).
  /// [history] قائمة من آخر الرسائل: {role: 'user'|'assistant', text: '...'}
  static Future<String> chat({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لاستخدام مدرب وازن الذكي.',
        details: null,
      );
    }

    final res = await _callable.call({
      'mode': 'chat',
      'message': message,
      'history': history,
    });

    final data =
        (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return _cleanReply(data['reply']);
  }
}

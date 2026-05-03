import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// أدوات لتوحيد رسائل الأخطاء للمستخدم (خصوصاً أخطاء الشبكة).
///
/// الهدف: عدم عرض رسائل تقنية طويلة مثل SocketException أو stack traces.
class FriendlyErrors {
  static const String _noInternetMsg =
      'انقطع الاتصال بالإنترنت. تأكد من الشبكة ثم جرّب مرة ثانية.';
  static const String _timeoutMsg =
      'الاتصال بطيء أو انتهت المهلة. تأكد من الشبكة ثم جرّب مرة ثانية.';
  static const String _genericMsg =
      'صار خطأ غير متوقع. جرّب مرة ثانية.';

  /// يحوّل أي خطأ/استثناء إلى رسالة عربية قصيرة.
  static String message(Object? error) {
    if (error == null) return _genericMsg;

    // Exceptions
    if (error is SocketException) return _noInternetMsg;
    if (error is TimeoutException) return _timeoutMsg;

    if (error is FirebaseFunctionsException) {
      final code = (error.code).toLowerCase();
      if (code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'network-error') {
        return _noInternetMsg;
      }
      if (code == 'unauthenticated') {
        return 'سجّل دخولك ثم حاول مرة أخرى.';
      }
      if (code == 'permission-denied') {
        return 'لا تملك صلاحية لتنفيذ هذه العملية.';
      }
      // لو الرسالة قصيرة ومفهومة نعرضها
      final msg = (error.message ?? '').trim();
      if (msg.isNotEmpty && msg.length <= 120 && !_looksTechnical(msg)) {
        return msg;
      }
      return _genericMsg;
    }

    if (error is FirebaseAuthException) {
      final code = error.code.toLowerCase();
      if (code.contains('network')) return _noInternetMsg;
      if (code == 'user-not-found' || code == 'wrong-password') {
        return 'بيانات الدخول غير صحيحة.';
      }
      if (code == 'email-already-in-use') {
        return 'هذا البريد مستخدم مسبقاً.';
      }
      if (code == 'too-many-requests') {
        return 'تمت محاولات كثيرة. جرّب لاحقاً.';
      }
      final msg = (error.message ?? '').trim();
      if (msg.isNotEmpty && msg.length <= 120 && !_looksTechnical(msg)) {
        return msg;
      }
      return _genericMsg;
    }

    // Strings or others
    final raw = error.toString().trim();
    if (raw.isEmpty) return _genericMsg;

    final lower = raw.toLowerCase();

    // Network-ish strings (when error comes as string)
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('no route to host') ||
        lower.contains('connection timed out') ||
        lower.contains('timed out') ||
        lower.contains('connection refused') ||
        lower.contains('not connected') ||
        lower.contains('errno') ||
        lower.contains('network error')) {
      return _noInternetMsg;
    }

    if (lower.contains('timeout') || lower.contains('deadline')) {
      return _timeoutMsg;
    }

    // If message is short and not technical, show it.
    if (raw.length <= 120 && !_looksTechnical(raw)) return raw;

    return _genericMsg;
  }

  static bool _looksTechnical(String s) {
    final lower = s.toLowerCase();
    return lower.contains('exception') ||
        lower.contains('stack') ||
        lower.contains('http') ||
        lower.contains('firebase') ||
        lower.contains('cloud functions') ||
        lower.contains('socket') ||
        lower.contains('errno') ||
        lower.contains('trace') ||
        lower.contains('line ') ||
        lower.contains('dart:') ||
        lower.contains('type ') ||
        lower.contains('null');
  }
}

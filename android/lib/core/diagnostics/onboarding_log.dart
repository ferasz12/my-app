// lib/core/diagnostics/onboarding_log.dart
//
// Lightweight, high-signal logs for onboarding + Firestore writes.
// الهدف: يعطيك "سبب دقيق" ليه ما كتب في Firestore/ليه ما انتقل للصفحة التالية.
//
// Usage:
//   OnbLog.i('Tag', 'message', ctx: {'uid': uid});
//   OnbLog.e('Tag', 'failed', err, st);

import 'dart:convert';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class OnbLog {
  static String _ts() => DateTime.now().toIso8601String();

  static void i(String tag, String msg, {Map<String, Object?>? ctx}) {
    debugPrint(_fmt('INFO', tag, msg, ctx));
  }

  static void w(String tag, String msg, {Map<String, Object?>? ctx}) {
    debugPrint(_fmt('WARN', tag, msg, ctx));
  }

  static void e(String tag, String msg, Object err, StackTrace st, {Map<String, Object?>? ctx}) {
    debugPrint(_fmt('ERROR', tag, msg, {
      ...?ctx,
      'error': _describeErr(err),
    }));
    if (kDebugMode) {
      debugPrint('[$tag] stack:\n$st');
    }
  }

  static String _fmt(String level, String tag, String msg, Map<String, Object?>? ctx) {
    final safeCtx = ctx == null ? '' : ' ctx=${_safeJson(ctx)}';
    return '${_ts()} [$level][$tag] $msg$safeCtx';
  }

  static String _describeErr(Object err) {
    if (err is FirebaseException) {
      // FirebaseException: plugin, code, message
      final plugin = err.plugin;
      final code = err.code;
      final message = err.message ?? '';
      return 'FirebaseException(plugin=$plugin, code=$code, message=$message)';
    }
    return err.toString();
  }

  static String _safeJson(Object? v, {int maxLen = 1200}) {
    try {
      final s = jsonEncode(v, toEncodable: (o) => o.toString());
      if (s.length <= maxLen) return s;
      return '${s.substring(0, maxLen)}…(truncated ${s.length - maxLen} chars)';
    } catch (_) {
      final s = v.toString();
      if (s.length <= maxLen) return s;
      return '${s.substring(0, maxLen)}…(truncated ${s.length - maxLen} chars)';
    }
  }
}

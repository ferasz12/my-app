import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Logger خفيف للأونبوردنق.
///
/// - يطبع فقط في Debug mode.
/// - يعطي tag + event + context.
class OnbLog {
  static void i(String tag, String event, {Map<String, Object?>? ctx}) {
    if (!kDebugMode) return;
    debugPrint(_fmt('ℹ️', tag, event, ctx));
  }

  static void w(String tag, String event, {Map<String, Object?>? ctx}) {
    if (!kDebugMode) return;
    debugPrint(_fmt('⚠️', tag, event, ctx));
  }

  static void e(
    String tag,
    String event,
    Object error,
    StackTrace st, {
    Map<String, Object?>? ctx,
  }) {
    if (!kDebugMode) return;
    debugPrint(_fmt('❌', tag, event, ctx));
    debugPrint('   error=$error');
    debugPrint('   stack=$st');
  }

  static String _fmt(
    String icon,
    String tag,
    String event,
    Map<String, Object?>? ctx,
  ) {
    final ts = DateTime.now().toIso8601String();
    final c = (ctx == null || ctx.isEmpty) ? '' : ' ctx=$ctx';
    return '$icon [ONB][$ts][$tag] $event$c';
  }
}

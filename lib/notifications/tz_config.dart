// =============================================================
// FILE: lib/notifications/tz_config.dart
//
// ✅ إصلاح مشكلة فرق التوقيت في الإشعارات (مثل +3 ساعات)
//
// الفكرة:
// flutter_local_notifications مع package:timezone يعتمد على tz.local.
// إذا بقي tz.local = UTC (يحدث أحيانًا على بعض الأجهزة/الإعدادات)
// فستُجدول الإشعارات بتوقيت UTC بدل توقيت الجهاز، وهذا ينتج فرقًا يساوي
// فرق منطقتك الزمنية (في السعودية غالبًا +3 ساعات).
//
// هذا الملف يضمن ضبط tz.local قبل أي جدولة، ويجرب أكثر من اسم منطقة
// (IANA) مع fallback حسب offset.
//
// ملاحظة:
// لتفادي أي مشاكل مستقبلية مع DST أو السفر، نفضل مناطق IANA الحقيقية
// مثل Asia/Riyadh بدل Etc/GMT فقط عندما نقدر.
// =============================================================

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class TzConfig {
  TzConfig._();

  static bool _initialized = false;

  /// Call once on startup before using tz.TZDateTime (قبل جدولة أي إشعار).
  static void ensureInitialized() {
    if (_initialized) return;

    tzdata.initializeTimeZones();

    final offset = DateTime.now().timeZoneOffset;

    // نجرب أسماء IANA أولًا (أفضل من Etc/GMT لأنها تدعم DST لو احتاجت).
    final candidates = <String>[];

    // السعودية (والخليج غالبًا) — يحل مشكلة +3 ساعات مباشرة
    if (offset == const Duration(hours: 3)) {
      candidates.addAll(const [
        'Asia/Riyadh',
        'Asia/Kuwait',
        'Asia/Qatar',
        'Asia/Bahrain',
      ]);
    }

    // الإمارات/عمان (+4)
    if (offset == const Duration(hours: 4)) {
      candidates.addAll(const [
        'Asia/Dubai',
        'Asia/Muscat',
      ]);
    }

    // Fall back: Etc/GMT (sign is inverted: Etc/GMT-3 == UTC+3)
    if (offset.inMinutes % 60 == 0) {
      final hours = offset.inHours; // قد تكون سالبة
      if (hours != 0) {
        final sign = hours > 0 ? '-' : '+';
        candidates.add('Etc/GMT$sign${hours.abs()}');
      }
    }

    // أخيرًا: UTC (افتراضي) — فقط إذا كانت المنطقة فعلاً UTC
    if (offset == Duration.zero) {
      candidates.add('UTC');
    }

    // جرّب حتى تنجح
    for (final name in candidates) {
      if (_trySetLocal(name, expectedOffset: offset)) break;
    }

    _initialized = true;
  }

  static bool _trySetLocal(String name, {required Duration expectedOffset}) {
    try {
      final loc = tz.getLocation(name);
      tz.setLocalLocation(loc);

      // تحقق سريع: إذا ما زال UTC بينما offset ليس صفرًا، نعتبرها فشل
      final now = tz.TZDateTime.now(tz.local);
      final ok = (expectedOffset == Duration.zero) ||
          (now.timeZoneOffset.inMinutes == expectedOffset.inMinutes);

      return ok;
    } catch (_) {
      return false;
    }
  }
}

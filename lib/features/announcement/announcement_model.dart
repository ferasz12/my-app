import 'package:flutter/material.dart';

/// نموذج إعدادات الإعلان العام (البانر)
class AnnouncementConfig {
  final bool enabled;
  final String message;

  // تنسيق
  final String? fontFamily;
  final double? fontSize;
  final bool bold;
  final bool italic;
  final Color textColor;
  final Color backgroundColor;

  // وسائط إضافية
  final String? imageUrl;
  final String? linkText;
  final String? linkUrl;
  final String type; // info | warning | maintenance

  // مدة العرض (اختياري)
  final DateTime? startAt;
  final DateTime? endAt;

  // لتحديث الإصدارات والإخفاء المحلي
  final DateTime? updatedAt;

  AnnouncementConfig({
    required this.enabled,
    required this.message,
    required this.textColor,
    required this.backgroundColor,
    this.fontFamily,
    this.fontSize,
    this.bold = false,
    this.italic = false,
    this.imageUrl,
    this.linkText,
    this.linkUrl,
    this.type = 'info',
    this.startAt,
    this.endAt,
    this.updatedAt,
  });

  // ===== Helpers =====

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final v = hex.replaceAll('#', '');
    // لو 6 خانات نضيف ألفا FF
    final parsed = int.tryParse(v.length == 6 ? 'FF$v' : v, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  static DateTime? _asDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    // دعم Firestore Timestamp بدون استيراد مباشر
    try {
      final toDate = (v as dynamic).toDate;
      if (toDate is Function) return toDate();
    } catch (_) {
      // ignore
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory AnnouncementConfig.fromMap(Map<String, dynamic> m) {
    return AnnouncementConfig(
      enabled: m['enabled'] == true,
      message: (m['message'] ?? '').toString(),
      fontFamily: (m['fontFamily'] as String?)?.trim(),
      fontSize: (m['fontSize'] is num) ? (m['fontSize'] as num).toDouble() : null,
      bold: m['bold'] == true,
      italic: m['italic'] == true,
      textColor: _parseColor(m['textColor'], const Color(0xFF0F172A)),
      backgroundColor: _parseColor(m['backgroundColor'], const Color(0xFFECFDF5)),
      imageUrl: (m['imageUrl'] as String?)?.trim(),
      linkText: (m['linkText'] as String?)?.trim(),
      linkUrl: (m['linkUrl'] as String?)?.trim(),
      type: (m['type'] as String?)?.trim() ?? 'info',
      startAt: _asDateTime(m['startAt']),
      endAt: _asDateTime(m['endAt']),
      updatedAt: _asDateTime(m['updatedAt']),
    );
  }

  /// داخل الفترة المحددة؟
  bool get withinSchedule {
    final now = DateTime.now();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }

  /// نشط وجاهز للعرض
  bool get isActive => enabled && withinSchedule;
}

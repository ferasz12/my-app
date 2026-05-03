// lib/utils/image_resize.dart
//
// تصغير الصور قبل الإرسال لتقليل التكلفة/الزمن — باستخدام حزمة image (دارت خالصة)
// لا يعتمد على flutter_image_compress ولا يحتاج Pods.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageResize {
  /// يصغّر الصورة بحيث لا يتجاوز أكبر ضلع [maxSide] مع الحفاظ على الأبعاد النسبية.
  /// يعيد ملفًا جديدًا (path + .resized.jpg) أو الأصلي إذا لم يكن هناك تحسّن بالحجم.
  static Future<File> downscaleIfNeeded(
    File src, {
    int maxSide = 1024,
    int quality = 75,
  }) async {
    try {
      final bytes = await src.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return src;

      final w = decoded.width, h = decoded.height;
      final maxDim = w > h ? w : h;

      // إذا أصلاً الصورة أصغر من الحد، فقط أعد ترميز JPEG بجودة معقولة (قد يخفّض الحجم)
      img.Image resized = decoded;
      if (maxDim > maxSide) {
        final scale = maxSide / maxDim;
        final newW = (w * scale).round();
        final newH = (h * scale).round();
        resized = img.copyResize(decoded, width: newW, height: newH, interpolation: img.Interpolation.average);
      }

      final outBytes = img.encodeJpg(resized, quality: quality.clamp(1, 100));
      // لو الناتج أكبر من الأصلي، رجّع الأصلي
      if (outBytes.length >= bytes.length) return src;

      final outPath = _buildTargetPath(src.path, ext: 'resized.jpg');
      final outFile = File(outPath)..writeAsBytesSync(outBytes);
      return outFile;
    } catch (e) {
      debugPrint('[ImageResize] downscaleIfNeeded error: $e');
      return src;
    }
  }

  /// يحاول النزول بالحجم تحت [maxBytes] عبر تقليل الجودة والحجم تدريجيًا.
  static Future<File> downscaleForNetwork(
    File src, {
    int maxSide = 1024,
    int maxBytes = 900 * 1024, // ~900KB
    List<int> qualitySteps = const [85, 75, 65, 55, 45, 35],
  }) async {
    try {
      // ابدأ بتصغير خفيف
      File current = await downscaleIfNeeded(src, maxSide: maxSide, quality: 80);
      var bytes = await current.readAsBytes();
      if (bytes.length <= maxBytes) return current;

      // decode مرة واحدة ثم أعِد التحجيم/الترميز بتدرّج
      final original = img.decodeImage(bytes);
      if (original == null) return current;

      var working = original;
      var side = maxSide;
      for (final q in qualitySteps) {
        // قلّل البعد الأكبر قليلًا مع كل دورة
        side = (side * 0.9).round().clamp(320, maxSide);
        final maxDim = working.width > working.height ? working.width : working.height;
        if (maxDim > side) {
          final scale = side / maxDim;
          final newW = (working.width * scale).round();
          final newH = (working.height * scale).round();
          working = img.copyResize(working, width: newW, height: newH, interpolation: img.Interpolation.average);
        }

        final out = img.encodeJpg(working, quality: q.clamp(1, 100));
        if (out.length <= maxBytes) {
          final outPath = _buildTargetPath(src.path, ext: 'net.jpg');
          final outFile = File(outPath)..writeAsBytesSync(out);
          return outFile;
        }
      }

      // لو ما وصلنا للحد، ارجع آخر محاولة (أصغر شيء طلع معنا)
      final out = img.encodeJpg(working, quality: qualitySteps.last.clamp(1, 100));
      final outPath = _buildTargetPath(src.path, ext: 'net.jpg');
      final outFile = File(outPath)..writeAsBytesSync(out);
      return outFile;
    } catch (e) {
      debugPrint('[ImageResize] downscaleForNetwork error: $e');
      return src;
    }
  }

  /// يصنع Thumbnail صغيرة Base64 (JPEG) — تنفع للكاش أو المعاينات
  static Future<String?> makeThumbnailBase64(
    File src, {
    int thumbSide = 256,
    int quality = 60,
  }) async {
    try {
      final bytes = await src.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final maxDim = decoded.width > decoded.height ? decoded.width : decoded.height;
      final scale = (thumbSide / maxDim).clamp(0.0, 1.0);
      final newW = (decoded.width * scale).round().clamp(1, decoded.width);
      final newH = (decoded.height * scale).round().clamp(1, decoded.height);
      final thumb = img.copyResize(decoded, width: newW, height: newH, interpolation: img.Interpolation.average);

      final out = img.encodeJpg(thumb, quality: quality.clamp(1, 100));
      final b64 = base64Encode(out);
      return 'data:image/jpeg;base64,$b64';
    } catch (e) {
      debugPrint('[ImageResize] makeThumbnailBase64 error: $e');
      return null;
    }
  }

  static String _buildTargetPath(String originalPath, {required String ext}) {
    final idx = originalPath.lastIndexOf('.');
    final base = idx > 0 ? originalPath.substring(0, idx) : originalPath;
    return '$base.$ext';
  }
}

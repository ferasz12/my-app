// lib/services/proxy_food_service.dart
//
// خدمة بروكسي وسيط لتحليل صورة الطعام عبر خادمك أنت (يوفّر كاش/تصغير/توجيه موديلات).
// - يقرأ FOOD_PROXY_URL من .env
// - يرسل: image (File), clarifier (String), profile (JSON)
// - يتوقع JSON نهائي متوافق مع FoodAnalysis المستخدم في التطبيق.
//
// ملاحظات:
// 1) أضف في .env (على العميل):
//    FOOD_PROXY_URL=https://YOUR_SERVER/api/food/analyze
// 2) تأكد من تحميل .env في main.dart:
//    await dotenv.load(fileName: ".env");
// 3) على الخادم: أرجِع JSON يحتوي الحقول التالية قدر الإمكان:
//    { label | food_name, calories | calories_kcal | energy.kcal | macros.energy_kcal,
//      protein|macros.protein_g, carbs|macros.carbs_g, fat|macros.fat_g,
//      serving | portion.{grams,desc}, decision, confidence, reasons[], bbox? }
//
// التحديثات المضافة هنا تحل مشاكل رجوع القيم صفر/فاضية:
// - فك تغليف شائع: {data:{...}}, {result:{...}}, {output:{...}}, {prediction:{...}}, {predictions:[{...}]}
// - دعم مفاتيح بديلة للسعرات والماكروز
// - تحويل قيم نصية مثل "120 kcal" -> 120.0
// - بناء serving من portion_desc/portion_grams عند الحاجة
// - طباعة سبب واضح عند calories<=0 للمساعدة في التشخيص

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// نعيد استعمال النماذج الموجودة عندك:
import 'openai_food_service.dart' show DietProfile, FoodAnalysis;

class ProxyFoodService {
  /// يحلل صورة الطعام عبر السيرفر الوسيط
  static Future<FoodAnalysis?> analyzeImage(
    String imagePath, {
    DietProfile? profile,
    String? clarifier,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = _proxyUri();
    if (uri == null) {
      debugPrint('[Proxy] FOOD_PROXY_URL غير مضبوط في .env');
      return null;
    }

    try {
      final req = http.MultipartRequest('POST', uri)
        ..fields['clarifier'] = (clarifier ?? '').trim()
        ..fields['profile'] = profile != null ? jsonEncode(profile.toMap()) : '{}'
        ..files.add(await http.MultipartFile.fromPath('image', imagePath));

      final streamed = await req.send().timeout(timeout);
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode != 200) {
        debugPrint('[Proxy] status=${res.statusCode}, body=${res.body}');
        return null;
      }

      final Map<String, dynamic> j = jsonDecode(res.body);
      debugPrint('[PARSE] top-level keys=${j.keys.join(",")}');

      if (j['raw'] is String) {
        debugPrint('[PARSE] raw present, length=${(j['raw'] as String).length}');
      }

      // 1) معالجة raw fenced JSON إن وُجد
      final Map<String, dynamic> fromRaw = _compatFromRaw(j);

      // 2) فكّ التغليف الشائع
      final Map<String, dynamic> core = _unwrap(fromRaw);
      debugPrint('[PARSE] core keys=${core.keys.join(",")}');

      // 3) تحويل إلى شكل متوافق موحّد للقراءة
      final Map<String, dynamic> compat = _toCompat(core);

      // Debug ممتدّ للسعرات
      try {
        final cands = [
          core['calories'],
          core['calories_kcal'],
          (core['energy'] is Map) ? (core['energy'] as Map)['kcal'] : null,
          (core['nutrition'] is Map) ? (core['nutrition'] as Map)['calories'] : null,
          (core['macros'] is Map) ? (core['macros'] as Map)['energy_kcal'] : null,
          (core['macros'] is Map) ? (core['macros'] as Map)['calories'] : null,
        ];
        debugPrint('[PARSE] calorie candidates=${cands.map((e)=> e==null? "null" : e.toString()).join(" | ")}');
        debugPrint('[PARSE] compat calories=${compat['calories']?.toString() ?? "null"}');
      } catch (_) {}

      // 4) القراءة النهائية من compat فقط (لتفادي قيم صفر/فاضية)
      String _s(Object? v) => (v ?? '').toString();
      double _d(Object? v) => _numToDouble(v); // مساعدة احتياطية

      final String label = (_s(compat['label']).trim().isNotEmpty)
          ? _s(compat['label'])
          : (_s(core['food_name']).trim().isNotEmpty ? _s(core['food_name']) : ''); // fallback بسيط

      final double calories = _num(compat['calories']);
      final double protein  = _num(compat['protein']);
      final double carbs    = _num(compat['carbs']);
      final double fat      = _num(compat['fat']);

      // serving إمّا جاهزة من compat أو من portion_* أو null
      String? serving = _servingText(compat);

      final String decision =
          _s(compat['decision']).trim().isNotEmpty ? _s(compat['decision']) : 'غير محدد';

      final double? confidence = _nullableNum(compat['confidence']);

      final List<String> reasons = (compat['reasons'] is List)
          ? List<String>.from((compat['reasons'] as List).map((e) => e.toString()))
          : const <String>[];

      final result = FoodAnalysis(
        label: label,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        serving: serving,
        decision: decision,
        confidence: confidence,
        reasons: reasons,
      );

      if (calories <= 0) {
        debugPrint('flutter: [REASON] calories<=0 keys=[label, serving, calories, protein, carbs, fat, confidence, decision, reasons, bbox] '
                   'map={label: $label, serving: ${serving ?? "null"}, calories: $calories, protein: $protein, carbs: $carbs, fat: $fat, '
                   'confidence: ${confidence?.toString() ?? "null"}, decision: $decision, reasons: $reasons, '
                   'bbox: ${compat["bbox"] is Map ? compat["bbox"] : {"x":0.3,"y":0.3,"w":0.4,"h":0.4}}}');
      }

      return result;
    } on TimeoutException {
      debugPrint('[Proxy] timeout بعد ${timeout.inSeconds}s');
      return null;
    } on SocketException catch (e) {
      debugPrint('[Proxy] SocketException: $e');
      return null;
    } catch (e) {
      debugPrint('[Proxy] unexpected error: $e');
      return null;
    }
  }

  /// إعادة محاولة خفيفة (في حال رغبت باستعمالها من الخارج)
  static Future<T> withRetry<T>(
    Future<T> Function() run, {
    int maxTries = 2,
    int backoffMs = 400,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await run();
      } catch (e) {
        if (attempt >= maxTries) rethrow;
        await Future.delayed(Duration(milliseconds: backoffMs * attempt));
      }
    }
  }

  // ----------------- Helpers -----------------

  static Uri? _proxyUri() {
    final url = dotenv.env['FOOD_PROXY_URL'];
    if (url == null || url.trim().isEmpty) return null;
    try {
      return Uri.parse(url.trim());
    } catch (_) {
      return null;
    }
  }

  // يلتقط JSON داخل حقل raw إذا كان نصًا محاطًا بـ ```json ... ```
  static Map<String, dynamic> _compatFromRaw(Map<String, dynamic> j) {
    if (j['raw'] is! String) return j;
    final raw = (j['raw'] as String).trim();
    final fenceRe = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
    final m = fenceRe.firstMatch(raw);
    final inner = m != null ? m.group(1)!.trim() : raw;
    try {
      final innerMap = jsonDecode(inner) as Map<String, dynamic>;
      return innerMap;
    } catch (_) {
      return j;
    }
  }

  // فك تغليف شائع
  static Map<String, dynamic> _unwrap(Map<String, dynamic> j) {
    if (j['result'] is Map) return Map<String, dynamic>.from(j['result']);
    if (j['data'] is Map) return Map<String, dynamic>.from(j['data']);
    if (j['output'] is Map) return Map<String, dynamic>.from(j['output']);
    if (j['food'] is Map) return Map<String, dynamic>.from(j['food']);
    if (j['prediction'] is Map) return Map<String, dynamic>.from(j['prediction']);
    if (j['predictions'] is List && (j['predictions'] as List).isNotEmpty && (j['predictions'] as List).first is Map) {
      return Map<String, dynamic>.from((j['predictions'] as List).first as Map);
    }
    // في بعض البروكسيات تكون بهذا الشكل: { response: { data: {...} } }
    if (j['response'] is Map && (j['response'] as Map)['data'] is Map) {
      return Map<String, dynamic>.from((j['response'] as Map)['data'] as Map);
    }
    return j;
  }

  // تحويل رقم مرن من num/String (مثل "120 kcal" أو "١٢٠" -> 120.0)
  static String _normalizeDigits(String input) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    const ascii = '0123456789';

    final sb = StringBuffer();
    for (final ch in input.split('')) {
      final i1 = arabicIndic.indexOf(ch);
      if (i1 != -1) {
        sb.write(ascii[i1]);
        continue;
      }
      final i2 = easternArabic.indexOf(ch);
      if (i2 != -1) {
        sb.write(ascii[i2]);
        continue;
      }
      sb.write(ch);
    }

    // Arabic separators:
    // ٫ decimal separator, ٬ thousand separator, ، comma
    return sb
        .toString()
        .replaceAll('٬', '')
        .replaceAll('٫', '.')
        .replaceAll('،', '.');
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;

    final s = _normalizeDigits(v.toString()).trim();
    if (s.isEmpty) return 0.0;

    final normalized = s.replaceAll(',', '.');
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(normalized);
    if (m == null) return 0.0;

    return double.tryParse(m.group(0)!) ?? 0.0;
  }

  static double? _nullableNum(dynamic v) {
    final n = _num(v);
    return n == 0.0 ? null : n;
  }

  static String? _servingText(Map<String, dynamic> compat) {
    String s = (compat['serving'] ?? '').toString().trim();
    if (s.isNotEmpty) return s;

    final grams = _num(compat['portion_grams']);
    final desc = (compat['portion_desc'] ?? '').toString().trim();
    if (grams > 0 && desc.isNotEmpty) return '$desc (${grams.toStringAsFixed(0)} g)';
    if (grams > 0) return '${grams.toStringAsFixed(0)} g';
    return null;
  }

  // توحيد الحقول لمفاتيح متوقعة
  static Map<String, dynamic> _toCompat(Map<String, dynamic> src) {
    final energy = (src['energy'] is Map) ? Map<String, dynamic>.from(src['energy']) : const {};
    final nutrition = (src['nutrition'] is Map) ? Map<String, dynamic>.from(src['nutrition']) : const {};
    final macros = (src['macros'] is Map) ? Map<String, dynamic>.from(src['macros']) : const {};

    final double cals =
        _num(src['calories']) > 0 ? _num(src['calories']) :
        _num(src['calories_kcal']) > 0 ? _num(src['calories_kcal']) :
        _num(energy['kcal']) > 0 ? _num(energy['kcal']) :
        _num(nutrition['calories']) > 0 ? _num(nutrition['calories']) :
        _num(macros['energy_kcal']) > 0 ? _num(macros['energy_kcal']) :
        _num(macros['calories']) > 0 ? _num(macros['calories']) :
        0.0;

    double protein = _num(src['protein']);
    if (protein == 0) protein = _num(src['protein_g']);
    if (protein == 0) protein = _num(macros['protein_g']);

    double carbs = _num(src['carbs']);
    if (carbs == 0) carbs = _num(src['carbs_g']);
    if (carbs == 0) carbs = _num(macros['carbs_g']);

    double fat = _num(src['fat']);
    if (fat == 0) fat = _num(src['fat_g']);
    if (fat == 0) fat = _num(macros['fat_g']);

    final portion = (src['portion'] is Map) ? Map<String, dynamic>.from(src['portion']) : const {};
    final serving = src['serving'] ?? src['serving_text'] ?? src['serving_size'] ?? src['serving_size_g'];

    return {
      'label': (src['label'] ?? src['food_name'] ?? src['name'] ?? '').toString(),
      'serving': serving,
      'portion_desc': src['portion_desc'] ?? portion['desc'],
      'portion_grams': src['portion_grams'] ?? portion['grams'],
      'calories': cals,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'confidence': src['confidence'],
      'decision': (src['decision'] ?? '').toString(),
      'reasons': (src['reasons'] is List) ? src['reasons'] : const [],
      'bbox': (src['bbox'] is Map) ? src['bbox'] : {'x': 0.3, 'y': 0.3, 'w': 0.4, 'h': 0.4},
    };
  }

  static double _numToDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

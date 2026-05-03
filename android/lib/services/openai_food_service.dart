// lib/services/openai_food_service.dart
//
// ✅ يرسل الصور بحجم صغير (افتراضي maxEdge=1024) + detail:"low" لتقليل التكلفة.
// ✅ يطلب من النموذج إرجاع BBox طبيعي (x,y,w,h ∈ [0..1]) ويعيده في الناتج.
// ✅ إن لم يرجع النموذج bbox، نوفّر واحدًا افتراضيًا في المنتصف.
// ✅ واجهات متوافقة: analyzeFromXFile / analyzeImage.
// ✅ يدعم Proxy اختياريًا ويمرر له detail/max_edge + Authorization (Firebase ID Token عند التوفر).
// ✅ لا يرمي استثناء عند غياب المفاتيح؛ يرجع null بهدوء.
// ✅ (جديد) Parsing مرن: يفك تغليف JSON الشائع + يدعم مفاتيح بديلة للسعرات/الماكروز/serving
//
// يلزم: flutter_dotenv, http, image_picker, image, firebase_auth
//
// ملاحظات التحديث:
// - تمّت إضافة دوال: _compatFromRaw, _unwrap, _toCompat, _num, _nullableNum, _servingText, _extractJsonFromOpenAI
// - مسار OpenAI ومسار البروكسي الآن يستخدمان نفس آلية التوافق لتفادي رجوع أصفار.
// - يُطبع لوج تشخيصي إذا كانت السعرات <= 0 ليسهل تتبّع السبب.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:firebase_auth/firebase_auth.dart';

// ===== نماذج بياناتك =====

class DietProfile {
  final int dailyCalories;
  final int proteinTarget;
  final int carbsTarget;
  final int fatTarget;
  final String goal;     // "خسارة وزن" | "ثبات" | "زيادة" ... إلخ
  final String dietType; // "متوازن" | "منخفض كارب" | ...

  const DietProfile({
    required this.dailyCalories,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
    required this.goal,
    required this.dietType,
  });

  Map<String, dynamic> toMap() => {
        'dailyCalories': dailyCalories,
        'proteinTarget': proteinTarget,
        'carbsTarget': carbsTarget,
        'fatTarget': fatTarget,
        'goal': goal,
        'dietType': dietType,
      };
}

class TodayTotals {
  final double consumedKcal;
  final double consumedProtein;
  final double consumedCarbs;
  final double consumedFat;

  const TodayTotals({
    required this.consumedKcal,
    required this.consumedProtein,
    required this.consumedCarbs,
    required this.consumedFat,
  });

  Map<String, dynamic> toMap() => {
        'consumedKcal': consumedKcal,
        'consumedProtein': consumedProtein,
        'consumedCarbs': consumedCarbs,
        'consumedFat': consumedFat,
      };
}

class BBox {
  final double x; // left (0..1)
  final double y; // top  (0..1)
  final double w; // width (0..1)
  final double h; // height(0..1)
  const BBox({required this.x, required this.y, required this.w, required this.h});
}

class FoodAnalysis {
  final String label;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final String? serving;
  final String decision;     // من الـ LLM (قد لا يُستخدم للحكم النهائي)
  final double? confidence;  // 0..1
  final List<String>? reasons;
  final BBox? bbox;          // مربع الطعام (0..1)

  FoodAnalysis({
    required this.label,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.decision,
    this.serving,
    this.confidence,
    this.reasons,
    this.bbox,
  });
}

// ===== إعدادات الرؤية =====

enum VisionDetail { low, high }
extension _VisionDetailApi on VisionDetail {
  String get apiValue => this == VisionDetail.low ? 'low' : 'high';
}

// ===== الخدمة =====

class OpenAIFoodService {
  static const String _base = 'https://api.openai.com/v1';
  static const String _defaultModel = 'gpt-4o-mini'; // غيّره لـ 'gpt-4o' إذا احتجت دقة أعلى

  // حدود الحكم (غير مستخدمة في هذا الملف إلا إذا أردت استعمالها خارجياً)
  static const double _kCalorieCompletionRatio = 0.95;
  static const double _kMacroCloseTolerance   = 0.20;
  static const double _kMaintainTol           = 0.05;
  static const double _kGainHeadroom          = 0.10;

  /// واجهة مريحة من XFile (كما تستدعيها الشاشة)
  static Future<Map<String, dynamic>?> analyzeFromXFile(
    XFile image, {
    DietProfile? profile,
    TodayTotals? today,
    String? clarifier,
    String? model,
    VisionDetail detail = VisionDetail.low, // افتراضي منخفض
    int maxImageEdge = 1024,                // نصغِّر دائمًا لهذا الحد
  }) async {
    final fa = await analyzeImage(
      image.path,
      profile: profile,
      clarifier: clarifier,
      model: model,
      detail: detail,
      maxImageEdge: maxImageEdge,
    );
    if (fa == null) return null;

    // مخرجات على شكل Map متوافق مع شاشتك
    return {
      'label'      : fa.label,
      'serving'    : fa.serving,
      'calories'   : fa.calories,
      'protein'    : fa.protein,
      'carbs'      : fa.carbs,
      'fat'        : fa.fat,
      'confidence' : fa.confidence,
      'decision'   : fa.decision,
      'reasons'    : fa.reasons ?? const <String>[],
      'bbox'       : fa.bbox == null ? null : {
        'x': fa.bbox!.x, 'y': fa.bbox!.y, 'w': fa.bbox!.w, 'h': fa.bbox!.h
      },
    };
  }

  /// يحلل صورة على المسار المعطى.
  /// دائمًا نُصغِّر الصورة (maxImageEdge) ونمرّر detail.
  static Future<FoodAnalysis?> analyzeImage(
    String imagePath, {
    DietProfile? profile,
    String? clarifier,
    String? model,
    VisionDetail detail = VisionDetail.low,
    int maxImageEdge = 1024,
  }) async {
    // ❶ محاولة عبر البروكسي (لو مفعّل)
    try {
      final viaProxy = await _withRetry(() => _analyzeViaProxy(
            imagePath,
            profile: profile,
            clarifier: clarifier,
            detail: detail,
            maxImageEdge: maxImageEdge,
          ));
      if (viaProxy != null) return viaProxy;
    } catch (e) {
      debugPrint('[Proxy] failed: $e → fallback to OpenAI');
    }

    // ❷ OpenAI مباشر (لو عندنا مفتاح)
    final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('[OpenAI] no API key → return null');
      return null; // بدون رمي استثناء
    }

    // نصغِّر دائمًا قبل الإرسال (تخفيض تكلفة)
    Uint8List bytes = await File(imagePath).readAsBytes();
    final resized = await _shrinkToMaxEdge(bytes, maxImageEdge);
    if (resized != null) {
      bytes = resized;
      debugPrint('[OpenAI] resized to maxEdge=$maxImageEdge, bytes=${bytes.length}');
    }
    final b64 = base64Encode(bytes);

    // Prompt يطلب JSON + bbox
    final systemText =
        "أنت خبير تغذية دقيق. حلّل الصورة وحدد نوع الطعام والكمية والسعرات والماكروز."
        " إذا قدّم المستخدم clarifier مثل '100 غرام' فالتزم به."
        " أعد JSON صالح فقط بالمخطط التالي (بدون أي نص زائد):\n"
        "{"
        "  food_name: string,"
        "  confidence: number(0..1),"
        "  portion_grams: number|null,"
        "  portion_desc: string|null,"
        "  calories: number,"
        "  macros: { protein_g:number, carbs_g:number, fat_g:number },"
        "  decision: string,"
        "  reasons: string[],"
        "  bbox: { x:number, y:number, w:number, h:number }"
        "}\n"
        "حيث bbox إحداثيات نسبية بالنسبة للصورة (x,y أعلى-يسار، w=العرض، h=الارتفاع) وقيمها بين 0..1.";

    final userText = profile == null
        ? "حلّل الصورة التالية ثم قدّم أرقامًا دقيقة وأعد bbox."
        : "بيانات المستخدم: ${jsonEncode(profile.toMap())}.\nحلّل الصورة التالية وراعِ الهدف (الحكم النهائي محلي)، وأعد bbox نسبيًا للصورة.";

    final clarifierText = (clarifier != null && clarifier.trim().isNotEmpty)
        ? "\nUser Clarifier: ${clarifier.trim()}"
        : "\nUser Clarifier: (none)";

    final messages = [
      {
        "role": "system",
        "content": [
          {"type": "text", "text": systemText}
        ]
      },
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "$userText$clarifierText"},
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/jpeg;base64,$b64",
              "detail": detail.apiValue,
            }
          }
        ]
      }
    ];

    // Chat Completions
    try {
      final uri = Uri.parse('$_base/chat/completions');
      final body = jsonEncode({
        "model": model ?? _defaultModel,
        "messages": messages,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "max_tokens": 700,
      });

      final resp = await http
          .post(
            uri,
            headers: {
              "Authorization": "Bearer ${dotenv.env['OPENAI_API_KEY']}",
              "Content-Type": "application/json",
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode >= 400) {
        debugPrint('[OpenAI] status=${resp.statusCode}, body=${resp.body}');
        return null;
      }

      final decoded = jsonDecode(resp.body);
      // قد يكون content JSON مباشر أو ضمن صيغة Responses — نعالج الحالتين
      final Map<String, dynamic> rawJson = _extractJsonFromOpenAI(decoded);

      // 1) فك raw fenced JSON إن وُجد
      final Map<String, dynamic> fromRaw = _compatFromRaw(rawJson);
      // 2) فك التغليف الشائع
      final Map<String, dynamic> core = _unwrap(fromRaw);
      // 3) تحويل إلى شكل موحد
      final Map<String, dynamic> compat = _toCompat(core);

      // بناء FoodAnalysis من compat فقط
      final String label = (_s(compat['label']).trim().isNotEmpty)
          ? _s(compat['label'])
          : (_s(core['food_name']).trim().isNotEmpty ? _s(core['food_name']) : 'غير معروف');

      final double calories = _num(compat['calories']);
      final double protein  = _num(compat['protein']);
      final double carbs    = _num(compat['carbs']);
      final double fat      = _num(compat['fat']);
      final String decision = _s(compat['decision']).trim().isNotEmpty ? _s(compat['decision']) : 'غير محدد';
      final double? confidence = _nullableNum(compat['confidence']);

      final List<String> reasons = (compat['reasons'] is List)
          ? List<String>.from((compat['reasons'] as List).map((e) => e.toString()))
          : const <String>[];

      final bboxMap = (compat['bbox'] is Map) ? Map<String, dynamic>.from(compat['bbox']) : null;
      final BBox bbox = _parseBbox(bboxMap) ?? _defaultCenterBbox();

      final String? servingText = _servingText(compat);

      if (calories <= 0) {
        debugPrint('flutter: [REASON] calories<=0 keys=[label, serving, calories, protein, carbs, fat, confidence, decision, reasons, bbox] '
                   'map={label: $label, serving: ${servingText ?? "null"}, calories: $calories, protein: $protein, carbs: $carbs, fat: $fat, '
                   'confidence: ${confidence?.toString() ?? "null"}, decision: $decision, reasons: $reasons, '
                   'bbox: ${bboxMap ?? {"x":0.3,"y":0.3,"w":0.4,"h":0.4}}}');
      }

      return FoodAnalysis(
        label: label,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        serving: servingText,
        decision: decision,
        confidence: confidence,
        reasons: reasons,
        bbox: bbox,
      );
    } catch (e) {
      debugPrint('[OpenAI] parse/request error: $e');
      return null;
    }
  }

  /// مسار البروكسي (اختياري).
  static Future<FoodAnalysis?> _analyzeViaProxy(
    String imagePath, {
    DietProfile? profile,
    String? clarifier,
    VisionDetail detail = VisionDetail.low,
    int maxImageEdge = 1024,
  }) async {
    final url = dotenv.env['FOOD_PROXY_URL'];
    if (url == null || url.trim().isEmpty) return null;

    try {
      // نرفع الصورة كما هي (السيرفر يمكنه التصغير أيضاً) + نمرر detail/max_edge
      final uri = Uri.parse(url.trim());
      final req = http.MultipartRequest('POST', uri)
        ..fields['clarifier'] = clarifier?.trim() ?? ''
        ..fields['profile']   = profile != null ? jsonEncode(profile.toMap()) : '{}'
        ..fields['detail']    = detail.apiValue
        ..fields['max_edge']  = (maxImageEdge).toString()
        ..files.add(await http.MultipartFile.fromPath('image', imagePath));

      // تمرير Firebase ID Token إن وُجد
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken != null) {
        req.headers['Authorization'] = 'Bearer $idToken';
      }

      final streamed = await req.send().timeout(const Duration(seconds: 45));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) {
        debugPrint('[Proxy] status=${res.statusCode}, body=${res.body}');
        return null;
      }

      // نفس منطق التوافق الموحّد
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final Map<String, dynamic> fromRaw = _compatFromRaw(j);
      final Map<String, dynamic> core = _unwrap(fromRaw);
      final Map<String, dynamic> compat = _toCompat(core);

      final String label = (_s(compat['label']).trim().isNotEmpty)
          ? _s(compat['label'])
          : (_s(core['food_name']).trim().isNotEmpty ? _s(core['food_name']) : '');

      final double calories = _num(compat['calories']);
      final double protein  = _num(compat['protein']);
      final double carbs    = _num(compat['carbs']);
      final double fat      = _num(compat['fat']);
      final String decision = _s(compat['decision']).trim().isNotEmpty ? _s(compat['decision']) : 'غير محدد';
      final double? confidence = _nullableNum(compat['confidence']);

      final List<String> reasons = (compat['reasons'] is List)
          ? List<String>.from((compat['reasons'] as List).map((e) => e.toString()))
          : const <String>[];

      final bbox = _parseBbox(compat['bbox']) ?? _defaultCenterBbox();
      final String? servingText = _servingText(compat);

      if (calories <= 0) {
        debugPrint('flutter: [REASON] calories<=0 keys=[label, serving, calories, protein, carbs, fat, confidence, decision, reasons, bbox] '
                   'map={label: $label, serving: ${servingText ?? "null"}, calories: $calories, protein: $protein, carbs: $carbs, fat: $fat, '
                   'confidence: ${confidence?.toString() ?? "null"}, decision: $decision, reasons: $reasons, '
                   'bbox: ${compat["bbox"] ?? {"x":0.3,"y":0.3,"w":0.4,"h":0.4}}}');
      }

      return FoodAnalysis(
        label: label,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        serving: servingText,
        decision: decision,
        confidence: confidence,
        reasons: reasons,
        bbox: bbox,
      );
    } catch (e) {
      debugPrint('[Proxy] error: $e');
      return null;
    }
  }

  // ===== أدوات مساعدة (مشتركة) =====

  static String _s(Object? v) => (v ?? '').toString();

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

  // يفك التغليف الشائع
  static Map<String, dynamic> _unwrap(Map<String, dynamic> j) {
    if (j['result'] is Map) return Map<String, dynamic>.from(j['result']);
    if (j['data'] is Map) return Map<String, dynamic>.from(j['data']);
    if (j['output'] is Map) return Map<String, dynamic>.from(j['output']);
    if (j['food'] is Map) return Map<String, dynamic>.from(j['food']);
    if (j['prediction'] is Map) return Map<String, dynamic>.from(j['prediction']);
    if (j['predictions'] is List && (j['predictions'] as List).isNotEmpty && (j['predictions'] as List).first is Map) {
      return Map<String, dynamic>.from((j['predictions'] as List).first as Map);
    }
    // Responses-like: { response: { data: {...} } }
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

  // يدعم كلًا من Chat Completions و Responses-like envelopes
  static Map<String, dynamic> _extractJsonFromOpenAI(dynamic payload) {
    // Responses API style: { output: [{content: [{type:'output_text', text:'{...json...}'}]}] }
    try {
      final out = (payload['output'] as List?)?.first;
      final content = (out?['content'] as List?)?.first;
      final txt = content?['text'];
      if (txt is String && txt.trim().startsWith('{')) {
        return Map<String, dynamic>.from(jsonDecode(txt));
      }
    } catch (_) {}

    // Chat Completions: { choices:[{message:{content:'{...json...}'}}] }
    try {
      final choices = payload['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final msg = choices.first['message'];
        final content = msg['content'];
        if (content is String && content.trim().startsWith('{')) {
          return Map<String, dynamic>.from(jsonDecode(content));
        }
      }
    } catch (_) {}

    // Already a JSON map
    if (payload is Map<String, dynamic>) {
      return payload;
    }

    throw Exception('Unable to extract JSON from OpenAI response.');
  }

  static BBox _defaultCenterBbox() {
    // مربع صغير في الوسط (مثلاً 40% عرض × 40% ارتفاع)
    const w = 0.4, h = 0.4;
    const x = (1.0 - w) / 2.0;
    const y = (1.0 - h) / 2.0;
    return const BBox(x: x, y: y, w: w, h: h);
  }

  static BBox? _parseBbox(dynamic v) {
    try {
      if (v is Map) {
        double _d(Object? x) => _numToDouble(x);
        double x = _d(v['x']), y = _d(v['y']), w = _d(v['w']), h = _d(v['h']);
        bool valid =
            x >= 0 && y >= 0 && w > 0 && h > 0 && x <= 1 && y <= 1 && (x + w) <= 1.001 && (y + h) <= 1.001;
        if (!valid) return _defaultCenterBbox();
        // قصّ إلى [0..1]
        x = x.clamp(0.0, 1.0);
        y = y.clamp(0.0, 1.0);
        w = w.clamp(0.0, 1.0 - x);
        h = h.clamp(0.0, 1.0 - y);
        return BBox(x: x, y: y, w: w, h: h);
      }
      return _defaultCenterBbox();
    } catch (_) {
      return _defaultCenterBbox();
    }
  }

  static Future<Uint8List?> _shrinkToMaxEdge(Uint8List input, int maxEdge, {int quality = 85}) async {
    try {
      final src = img.decodeImage(input);
      if (src == null) return null;

      final w = src.width;
      final h = src.height;
      final maxWH = w > h ? w : h;
      if (maxWH <= maxEdge) {
        // حتى لو كانت أصغر، نعيد ترميز JPEG لتحسين الحجم
        return Uint8List.fromList(img.encodeJpg(src, quality: quality));
      }

      final scale = maxEdge / maxWH;
      final nw = (w * scale).round().clamp(1, 100000);
      final nh = (h * scale).round().clamp(1, 100000);

      final resized = img.copyResize(
        src,
        width: nw,
        height: nh,
        interpolation: img.Interpolation.average,
      );
      final jpg = img.encodeJpg(resized, quality: quality);
      return Uint8List.fromList(jpg);
    } catch (e) {
      debugPrint('resize failed: $e');
      return null;
    }
  }

  static Future<T> _withRetry<T>(Future<T> Function() run, {int maxTries = 2}) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await run();
      } catch (_) {
        if (attempt >= maxTries) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  static double _numToDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

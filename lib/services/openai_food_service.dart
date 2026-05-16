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
import 'package:firebase_core/firebase_core.dart';


Uint8List? _resizeFoodImageWorker(Map<String, dynamic> args) {
  try {
    final input = args['bytes'] as Uint8List;
    final maxEdge = args['maxEdge'] as int;
    final quality = args['quality'] as int;
    final centerCropSquare = args['centerCropSquare'] == true;

    final decoded = img.decodeImage(input);
    if (decoded == null) return null;

    img.Image working = decoded;
    if (centerCropSquare) {
      final w0 = working.width;
      final h0 = working.height;
      final side = w0 < h0 ? w0 : h0;
      final cropSide = ((side * 0.94).round().clamp(1, side)).toInt();
      final x0 = (((w0 - cropSide) / 2).round().clamp(0, w0 - cropSide)).toInt();
      final y0 = (((h0 - cropSide) / 2).round().clamp(0, h0 - cropSide)).toInt();
      working = img.copyCrop(working, x: x0, y: y0, width: cropSide, height: cropSide);
    }

    final w = working.width;
    final h = working.height;
    final maxWH = w > h ? w : h;
    if (maxWH <= maxEdge) {
      return Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }

    final scale = maxEdge / maxWH;
    final nw = ((w * scale).round().clamp(1, 100000)).toInt();
    final nh = ((h * scale).round().clamp(1, 100000)).toInt();
    final resized = img.copyResize(
      working,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (_) {
    return null;
  }
}


// خطأ واضح لحدود الاستخدام اليومية (Quota)
class DailyLimitExceeded implements Exception {
  final String message;
  const DailyLimitExceeded(this.message);

  @override
  String toString() => message;
}

/// خطأ مؤقت: خدمة التحليل تحت ضغط/محدودية من مزوّد الذكاء (مثل Gemini 429/503)
class ServiceBusy implements Exception {
  final String message;
  final int? retryAfterSeconds;
  const ServiceBusy(this.message, {this.retryAfterSeconds});

  @override
  String toString() =>
      retryAfterSeconds == null ? message : '$message (retryAfter=$retryAfterSeconds)';
}

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
    required this.dietType
  });

  Map<String, dynamic> toMap() => {
        'dailyCalories': dailyCalories,
        'proteinTarget': proteinTarget,
        'carbsTarget': carbsTarget,
        'fatTarget': fatTarget,
        'goal': goal,
        'dietType': dietType
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
    required this.consumedFat
  });

  Map<String, dynamic> toMap() => {
        'consumedKcal': consumedKcal,
        'consumedProtein': consumedProtein,
        'consumedCarbs': consumedCarbs,
        'consumedFat': consumedFat
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

  /// اسم الطبق بالعربية (إن توفر)
  final String? nameAr;

  /// اسم الطبق بالإنجليزية (اختياري)
  final String? nameEn;


  /// مكوّنات/محتويات الطبق (تقدير من الذكاء الاصطناعي) — بالعربية
  final List<String>? ingredients;

  /// مكوّنات الطبق بالإنجليزية (اختياري)
  final List<String>? ingredientsEn;

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  /// وزن الحصة بالجرام إن أمكن
  final double? portionGrams;

  /// وصف الحصة بالعربية (مثال: "١٠٠ غرام أرز أبيض مطبوخ")
  final String? portionDescAr;

  /// عناصر الطبق (إن كان يحتوي عدة أصناف)
  final List<Map<String, dynamic>>? items;

  /// الإجمالي النهائي (قد يساوي الماكروز الرئيسية)
  final Map<String, dynamic>? totals;

  final String? serving;
  final String decision; // من الـ LLM (قد لا يُستخدم للحكم النهائي)
  final double? confidence; // 0..1
  final List<String>? reasons;
  final BBox? bbox; // مربع الطعام (0..1)

  /// اقتراحات USDA (٣) في حال كان التطابق غير مؤكد
  final List<Map<String, dynamic>>? fdcSuggestions;
  final bool needsConfirmation;
  final String? source;
  final int? fdcId;
  final bool needClarification;
  final List<String>? clarificationQuestions;
  final String? wazinAnalysis;


  FoodAnalysis({
    required this.label,
    this.nameAr,
    this.nameEn,
    this.ingredients,
    this.ingredientsEn,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.portionGrams,
    this.portionDescAr,
    this.items,
    this.totals,
    required this.decision,
    this.serving,
    this.confidence,
    this.reasons,
    this.bbox,
    this.fdcSuggestions,
    this.needsConfirmation = false,
    this.source,
    this.fdcId,
    this.needClarification = false,
    this.clarificationQuestions,
    this.wazinAnalysis,
  });
}


// ===== إعدادات الرؤية =====

enum VisionDetail { low, high }
extension _VisionDetailApi on VisionDetail {
  String get apiValue => this == VisionDetail.low ? 'low' : 'high';
}

// ===== الخدمة =====

class OpenAIFoodService {
  // رابط البروكسي الافتراضي (Firebase Function analyzeFood) — بدون الحاجة لـ .env
  static String? _defaultProxyUrl() {
    try {
      final pid = Firebase.app().options.projectId;
      if (pid.isEmpty) return null;
      // ملاحظة: يتطابق مع region في functions (europe-west1)
      return 'https://europe-west1-$pid.cloudfunctions.net/analyzeFood';
    } catch (_) {
      return null;
    }
  }


  static const String _base = 'https://generativelanguage.googleapis.com/v1beta';
  static const String _defaultModel = 'gemini-2.5-flash'; // يمكنك ضبط GEMINI_MODEL=gemini-1.5-flash أو غيره

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
    bool countUsage = true,
  }) async {
    final fa = await analyzeImage(
      image.path,
      profile: profile,
      clarifier: clarifier,
      model: model,
      detail: detail,
      maxImageEdge: maxImageEdge,
      countUsage: countUsage,
    );
    if (fa == null) return null;

    // مخرجات على شكل Map متوافق مع شاشتك
    return {
      'label'          : fa.label,
      'name_ar'        : fa.nameAr,
      'name_en'        : fa.nameEn,
      'ingredients'    : fa.ingredients,
      'ingredients_en' : fa.ingredientsEn,
      'portion_grams'  : fa.portionGrams,
      'portion_desc_ar': fa.portionDescAr,
      // serving يُستخدم في الواجهة كـ "الحصّة". نعطيه وصفًا عربيًا إن توفر.
      'serving'        : (fa.portionDescAr != null && fa.portionDescAr!.trim().isNotEmpty)
          ? fa.portionDescAr
          : fa.serving,
      'calories'       : fa.calories,
      'protein'        : fa.protein,
      'carbs'          : fa.carbs,
      'fat'            : fa.fat,
      'confidence'     : fa.confidence,
      'decision'       : fa.decision,
      'reasons'        : fa.reasons ?? const <String>[],
      'items'          : fa.items,
      'totals'         : fa.totals,
      'source'        : fa.source,
      'fdcId'         : fa.fdcId,
      'needs_confirmation': fa.needsConfirmation,
      'fdc_suggestions': fa.fdcSuggestions,
            'need_clarification': fa.needClarification,
      'needClarification' : fa.needClarification,
      'questions'         : fa.clarificationQuestions,
      'clarification_questions': fa.clarificationQuestions,
      'wazin_analysis' : fa.wazinAnalysis,
      'description_ar' : fa.wazinAnalysis,
'bbox'           : fa.bbox == null ? null : {
        'x': fa.bbox!.x, 'y': fa.bbox!.y, 'w': fa.bbox!.w, 'h': fa.bbox!.h
      }
    };
  }


  /// تحليل وصف نصّي (بدون صورة) — مفيد لو المستخدم كتب اسم/وصف الوجبة بدل التصوير.
  /// يعيد نفس شكل Map المتوقع في الواجهة (label, calories, macros, ...).
  static Future<Map<String, dynamic>?> analyzeFromText(
    String description, {
    DietProfile? profile,
    String? clarifier,
    String? model
  }) async {
    final fa = await analyzeText(
      description,
      profile: profile,
      clarifier: clarifier,
      model: model,
    );
    if (fa == null) return null;
    return {
      'label'          : fa.label,
      'name_ar'        : fa.nameAr,
      'name_en'        : fa.nameEn,
      'ingredients'    : fa.ingredients,
      'ingredients_en' : fa.ingredientsEn,
      'portion_grams'  : fa.portionGrams,
      'portion_desc_ar': fa.portionDescAr,
      'serving'        : (fa.portionDescAr != null && fa.portionDescAr!.trim().isNotEmpty)
          ? fa.portionDescAr
          : fa.serving,
      'calories'       : fa.calories,
      'protein'        : fa.protein,
      'carbs'          : fa.carbs,
      'fat'            : fa.fat,
      'confidence'     : fa.confidence,
      'decision'       : fa.decision,
      'reasons'        : fa.reasons ?? const <String>[],
      'items'          : fa.items,
      'totals'         : fa.totals,
      'source'        : fa.source,
      'fdcId'         : fa.fdcId,
      'needs_confirmation': fa.needsConfirmation,
      'fdc_suggestions': fa.fdcSuggestions,
            'need_clarification': fa.needClarification,
      'needClarification' : fa.needClarification,
      'questions'         : fa.clarificationQuestions,
      'clarification_questions': fa.clarificationQuestions,
      'wazin_analysis' : fa.wazinAnalysis,
      'description_ar' : fa.wazinAnalysis,
'bbox'           : fa.bbox == null ? null : {
        'x': fa.bbox!.x, 'y': fa.bbox!.y, 'w': fa.bbox!.w, 'h': fa.bbox!.h
      }
    };
  }

  /// تحليل وصف نصّي وإرجاع FoodAnalysis مباشرة (بدون صورة).
  static Future<FoodAnalysis?> analyzeText(
    String description, {
    DietProfile? profile,
    String? clarifier,
    String? model
  }) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final chosenModel = (model ?? (dotenv.env['GEMINI_MODEL'] ?? _defaultModel)).trim();
    if (apiKey.isEmpty) {
      debugPrint('[Gemini] no API key (set GEMINI_API_KEY) → return null');
      return null;
    }

    try {
      return await _withRetry(() => _analyzeViaGeminiText(
            description,
            apiKey: apiKey,
            profile: profile,
            clarifier: clarifier,
            model: chosenModel,
          ));
    } catch (e) {
      debugPrint('[Gemini] text parse/request error: $e');
      return null;
    }
  }

  static Future<FoodAnalysis?> _analyzeViaGeminiText(
    String description, {
    required String apiKey,
    DietProfile? profile,
    String? clarifier,
    required String model
  }) async {
    final systemText = '''
أنت خبير تغذية. حلّل وصف الوجبة النصّي وحدد اسم الوجبة ومكوناتها وقدّر الكمية والماكروز بدقة واقعية.
إذا كان الوصف غير كافٍ، لا تخترع؛ خفّض confidence واذكر ما ينقص في reasons.
أعد JSON صالح فقط بالمفاتيح EXACTLY كما في المخطط.
''';

    final userText = profile == null
        ? "وصف الوجبة: ${description.trim()}"
        : "بيانات المستخدم: ${jsonEncode(profile.toMap())}.\nوصف الوجبة: ${description.trim()}";

    final clarifierText = (clarifier != null && clarifier.trim().isNotEmpty)
        ? "\nUser Clarifier: ${clarifier.trim()}"
        : "\nUser Clarifier: (none)";

    // نفس مخطط Gemini للصورة (bbox سيُعاد كقيمة افتراضية)
    final responseJsonSchema = {
      "type": "object",
      "additionalProperties": false,
      "required": ["name_ar", "confidence", "calories_kcal", "macros", "reasons"],
      "properties": {
        "name_ar": {"type": "string"},
        "name_en": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        "portion_grams": {"anyOf": [{"type": "number", "minimum": 0}, {"type": "null"}]},
        "portion_desc_ar": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "ingredients": {
          "anyOf": [
            {"type": "array", "items": {"type": "string"}},
            {"type": "null"}
          ]
        },
        "ingredients_en": {
          "anyOf": [
            {"type": "array", "items": {"type": "string"}},
            {"type": "null"}
          ]
        },
        "calories_kcal": {"type": "number", "minimum": 0},
        "macros": {
          "type": "object",
          "additionalProperties": false,
          "required": ["protein_g", "carbs_g", "fat_g"],
          "properties": {
            "protein_g": {"type": "number", "minimum": 0},
            "carbs_g": {"type": "number", "minimum": 0},
            "fat_g": {"type": "number", "minimum": 0}
          }
        },
        "items": {"anyOf": [{"type": "array"}, {"type": "null"}]},
        "totals": {"anyOf": [{"type": "object"}, {"type": "null"}]},
        "reasons": {"type": "array", "items": {"type": "string"}},
        "decision": {"anyOf": [{"type": "string"}, {"type": "null"}]}
      }
    };

    final uri = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');
    final body = jsonEncode({
      "systemInstruction": {
        "parts": [
          {"text": systemText}
        ]
      },
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": "$userText$clarifierText"}
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0,
        "maxOutputTokens": 700,
        "responseMimeType": "application/json",
        "responseSchema": responseJsonSchema,
        "response_mime_type": "application/json",
        "response_schema": responseJsonSchema}
    });

    final resp = await http
        .post(uri, headers: {"Content-Type": "application/json"}, body: body)
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode >= 400) {
      debugPrint('[Gemini] status=${resp.statusCode}, body=${resp.body}');
      return null;
    }

    final decoded = jsonDecode(resp.body);
    final Map<String, dynamic> rawJson = _extractJsonFromGemini(decoded);

    final Map<String, dynamic> fromRaw = _compatFromRaw(rawJson);
    final Map<String, dynamic> core = _unwrap(fromRaw);
    final Map<String, dynamic> compat = _toCompat(core);
    _applyNutritionSafety(compat, core, clarifier: clarifier);

    final String nameAr = _s(compat['name_ar']).trim().isNotEmpty ? _s(compat['name_ar']) : _s(core['name_ar']);
    final String nameEn = _s(compat['name_en']).trim().isNotEmpty ? _s(compat['name_en']) : _s(core['name_en']);
    final String label = nameAr.trim().isNotEmpty ? nameAr : (nameEn.trim().isNotEmpty ? nameEn : 'غير معروف');

    final ingredients = _pickIngredients(compat, core);
    final ingredientsEn = _pickIngredients(compat, core, english: true);

    final Map<String, dynamic> totalsMap =
        (compat['totals'] is Map) ? Map<String, dynamic>.from(compat['totals'] as Map) : const <String, dynamic>{};
    final Map<String, dynamic> totalsMacros =
        (totalsMap['macros'] is Map) ? Map<String, dynamic>.from(totalsMap['macros'] as Map) : const <String, dynamic>{};

    final double calories = _num(totalsMap['calories_kcal']) > 0 ? _num(totalsMap['calories_kcal']) : _num(compat['calories']);
    final double protein  = _num(totalsMacros['protein_g']) > 0 ? _num(totalsMacros['protein_g']) : _num(compat['protein']);
    final double carbs    = _num(totalsMacros['carbs_g']) > 0 ? _num(totalsMacros['carbs_g']) : _num(compat['carbs']);
    final double fat      = _num(totalsMacros['fat_g']) > 0 ? _num(totalsMacros['fat_g']) : _num(compat['fat']);
    final String decision = _s(compat['decision']).trim().isNotEmpty ? _s(compat['decision']) : 'غير محدد';
    final double? confidence = _nullableNum(compat['confidence']);

    final List<String> reasons = (compat['reasons'] is List)
        ? List<String>.from((compat['reasons'] as List).map((e) => e.toString()))
        : const <String>[];

    final String? servingText = _servingText(compat);
    final double? portionGrams = _nullableNum(compat['portion_grams']);
    final String portionDescArRaw = _s(compat['portion_desc_ar']).trim();
    final String? portionDescAr = portionDescArRaw.isNotEmpty ? portionDescArRaw : null;

    return FoodAnalysis(
      label: label,
      nameAr: nameAr.trim().isEmpty ? null : nameAr.trim(),
      nameEn: nameEn.trim().isEmpty ? null : nameEn.trim(),
      ingredients: ingredients,
      ingredientsEn: ingredientsEn,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      portionGrams: portionGrams,
      portionDescAr: portionDescAr,
      items: (compat['items'] is List) ? List<Map<String, dynamic>>.from((compat['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e))) : null,
      totals: (compat['totals'] is Map) ? Map<String, dynamic>.from(compat['totals'] as Map) : null,
      serving: servingText,
      decision: decision,
      confidence: confidence,
      reasons: reasons,
      bbox: _defaultCenterBbox(), // لا يوجد bbox بدون صورة
      wazinAnalysis: _s(compat['wazin_analysis']).trim().isNotEmpty ? _s(compat['wazin_analysis']) : null,
    );
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
    bool countUsage = true
  }) async {
    // ❶ محاولة عبر البروكسي (لو مفعّل)
    try {
      final viaProxy = await _withRetry(() => _analyzeViaProxy(
            imagePath,
            profile: profile,
            clarifier: clarifier,
            detail: detail,
            maxImageEdge: maxImageEdge,
            countUsage: countUsage,
          ));
      if (viaProxy != null) {
  // إذا رجّع البروكسي نتيجة فارغة (أرقام 0) فهذا غالبًا فشل تحليل/Schema → نجرّب Gemini مباشر كـ fallback.
  // نستثني الحالات المسموح فيها 0 (مثل مشروب دايت/بدون سكر) أو عند وجود اقتراحات USDA.
  final bool hasSuggestions = (viaProxy.fdcSuggestions != null && viaProxy.fdcSuggestions!.isNotEmpty) ||
      viaProxy.needsConfirmation ||
      viaProxy.needClarification;
  final bool looksEmpty = (viaProxy.calories <= 0 && viaProxy.protein <= 0 && viaProxy.carbs <= 0 && viaProxy.fat <= 0);
  final bool zeroOk = _isZeroMacrosOkText(
    '${viaProxy.label} ${viaProxy.nameAr ?? ''} ${viaProxy.nameEn ?? ''} ${(clarifier ?? '')} ${(viaProxy.serving ?? '')}',
  );
  if (!hasSuggestions && looksEmpty && !zeroOk) {
    debugPrint('[Proxy] empty macros → fallback to Gemini direct');
  } else {
    return viaProxy;
  }
}

} catch (e) {
      // ✅ لا تعمل fallback إذا المشكلة من نوع: حد يومي / ضغط الخدمة / مصادقة / AppCheck
      if (e is DailyLimitExceeded || e is ServiceBusy) rethrow;
      final s = e.toString();
      if (s.contains('تسجيل الدخول') || s.contains('App Check') || s.contains('app_check') || s.contains('unauth') || s.contains('401') || s.contains('403')) {
        rethrow;
      }
      debugPrint('[Proxy] failed: $e → fallback to Gemini');
    }

    // المسار الأدق للصور هو Cloud Function لأنها تطبّق استخراج عناصر + مطابقة USDA/FDC.
    // لذلك لا نسمح بالـ fallback المباشر إلى Gemini إلا إذا طُلِب صراحةً في بيئة التطوير.
    final allowDirectGeminiFallback = !kReleaseMode && ((dotenv.env['FOOD_ALLOW_DIRECT_GEMINI_FALLBACK'] ?? '').toLowerCase() == 'true');
    if (!allowDirectGeminiFallback) {
      debugPrint('[FoodAI] proxy-only image analysis enabled → return null');
      return null;
    }

    
    // ❷ Gemini مباشر (مسموح فقط إذا فُعّل FOOD_ALLOW_DIRECT_GEMINI_FALLBACK في التطوير)
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final chosenModel = (model ?? (dotenv.env['GEMINI_MODEL'] ?? _defaultModel)).trim();
    if (apiKey.isEmpty) {
      debugPrint('[Gemini] no API key (set GEMINI_API_KEY) → return null');
      return null; // بدون رمي استثناء
    }

    try {
      return await _withRetry(() => _analyzeViaGemini(
            imagePath,
            apiKey: apiKey,
            profile: profile,
            clarifier: clarifier,
            model: chosenModel,
            detail: detail,
            maxImageEdge: maxImageEdge,
          ));
    } catch (e) {
      debugPrint('[Gemini] parse/request error: $e');
      return null;
    }
  }

  /// تحليل الصورة عبر Gemini مباشرة (بدون بروكسي)
  static Future<FoodAnalysis?> _analyzeViaGemini(
    String imagePath, {
    required String apiKey,
    DietProfile? profile,
    String? clarifier,
    required String model,
    VisionDetail detail = VisionDetail.low,
    int maxImageEdge = 1024
  }) async {
    // نصغِّر الصورة دائمًا قبل الإرسال (أسرع + أرخص)
    Uint8List bytes = await File(imagePath).readAsBytes();
    final resized = await _shrinkToMaxEdge(
      bytes,
      maxImageEdge,
      quality: detail == VisionDetail.high ? 92 : 88,
      centerCropSquare: _centerCropSquareEnabled(),
    );
    if (resized != null) {
      bytes = resized;
      debugPrint('[Gemini] resized to maxEdge=$maxImageEdge, bytes=${bytes.length}');
    }
    final b64 = base64Encode(bytes);

    final systemText = '''
أنت خبير تغذية دقيق جدًا ومتخصص في أكلات الشرق الأوسط والخليج. حلّل الصورة وحدد الطعام بدقة عالية.
ركّز على شكل البروتين (دجاج/لحم/سمك)، القوام، اللون، وطريقة التقديم. إذا لم تكن متأكدًا اذكر ذلك في reasons وخفّض confidence.
إذا قدّم المستخدم clarifier مثل "100 غرام" أو وصف المكوّنات، اعتبره حقيقة والتزم به.
أعد JSON صالح فقط بالمفاتيح EXACTLY كما في المخطط.
''';

    final userText = profile == null
        ? "حلّل الصورة التالية وحدد اسم الوجبة ومكوناتها وقدّر الكمية والماكروز. أعد أيضًا bbox نسبيًا للصورة."
        : "بيانات المستخدم: ${jsonEncode(profile.toMap())}. حلّل الصورة التالية وحدد الوجبة ومكوناتها وقدّر الكمية والماكروز. أعد أيضًا bbox نسبيًا للصورة.";

    final clarifierText = (clarifier != null && clarifier.trim().isNotEmpty)
        ? "\nUser Clarifier: ${clarifier.trim()}"
        : "\nUser Clarifier: (none)";

    // مخطط JSON (Schema) لضمان مخرجات منظمة
    final responseJsonSchema = {
      "type": "object",
      "additionalProperties": false,
      "required": ["name_ar", "confidence", "calories_kcal", "macros", "reasons", "bbox"],
      "properties": {
        "name_ar": {"type": "string"},
        "name_en": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        "portion_grams": {"anyOf": [{"type": "number", "minimum": 0}, {"type": "null"}]},
        "portion_desc_ar": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "ingredients": {
          "anyOf": [
            {"type": "array", "items": {"type": "string"}},
            {"type": "null"}
          ]
        },
        "ingredients_en": {
          "anyOf": [
            {"type": "array", "items": {"type": "string"}},
            {"type": "null"}
          ]
        },
        "calories_kcal": {"type": "number", "minimum": 0},
        "macros": {
          "type": "object",
          "additionalProperties": false,
          "required": ["protein_g", "carbs_g", "fat_g"],
          "properties": {
            "protein_g": {"type": "number", "minimum": 0},
            "carbs_g": {"type": "number", "minimum": 0},
            "fat_g": {"type": "number", "minimum": 0}
          }
        },
        "items": {
          "anyOf": [
            {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["name_ar", "calories_kcal", "macros"],
                "properties": {
                  "name_ar": {"type": "string"},
                  "name_en": {"anyOf": [{"type": "string"}, {"type": "null"}]},
                  "grams": {"anyOf": [{"type": "number", "minimum": 0}, {"type": "null"}]},
                  "calories_kcal": {"type": "number", "minimum": 0},
                  "macros": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["protein_g", "carbs_g", "fat_g"],
                    "properties": {
                      "protein_g": {"type": "number", "minimum": 0},
                      "carbs_g": {"type": "number", "minimum": 0},
                      "fat_g": {"type": "number", "minimum": 0}
                    }
                  },
                  "confidence": {"anyOf": [{"type": "number", "minimum": 0, "maximum": 1}, {"type": "null"}]}
                }
              }
            },
            {"type": "null"}
          ]
        },
        "totals": {
          "anyOf": [
            {
              "type": "object",
              "additionalProperties": false,
              "required": ["calories_kcal", "macros"],
              "properties": {
                "calories_kcal": {"type": "number", "minimum": 0},
                "macros": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["protein_g", "carbs_g", "fat_g"],
                  "properties": {
                    "protein_g": {"type": "number", "minimum": 0},
                    "carbs_g": {"type": "number", "minimum": 0},
                    "fat_g": {"type": "number", "minimum": 0}
                  }
                }
              }
            },
            {"type": "null"}
          ]
        },
        "reasons": {"type": "array", "items": {"type": "string"}},
        "decision": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "bbox": {
          "type": "object",
          "additionalProperties": false,
          "required": ["x", "y", "w", "h"],
          "properties": {
            "x": {"type": "number", "minimum": 0, "maximum": 1},
            "y": {"type": "number", "minimum": 0, "maximum": 1},
            "w": {"type": "number", "minimum": 0, "maximum": 1},
            "h": {"type": "number", "minimum": 0, "maximum": 1}
          }
        }
      }
    };

    final uri = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');
    final body = jsonEncode({
      "systemInstruction": {
        "parts": [
          {"text": systemText}
        ]
      },
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": "$userText$clarifierText"},
            {
              "inline_data": {"mime_type": "image/jpeg", "data": b64}
            }
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0,
        "maxOutputTokens": 900,
        "responseMimeType": "application/json"}
    });

    final resp = await http
        .post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode >= 400) {
      debugPrint('[Gemini] status=${resp.statusCode}, body=${resp.body}');
      return null;
    }

    final decoded = jsonDecode(resp.body);
    final Map<String, dynamic> rawJson = _extractJsonFromGemini(decoded);

    // 1) فك raw fenced JSON إن وُجد
    final Map<String, dynamic> fromRaw = _compatFromRaw(rawJson);
    // 2) فك التغليف الشائع
    final Map<String, dynamic> core = _unwrap(fromRaw);
    // 3) تحويل إلى شكل موحد
    final Map<String, dynamic> compat = _toCompat(core);
    _applyNutritionSafety(compat, core, clarifier: clarifier);

    // اقتراحات USDA (إن وُجدت من السيرفر/البروكسي فقط عادة)
    List<Map<String, dynamic>>? fdcSuggestions;
    try {
      final v = core['fdc_suggestions'];
      if (v is List) {
        fdcSuggestions =
            v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    final bool needsConfirmation = core['needs_confirmation'] == true;
    final String? source = core['source']?.toString();
    final int? fdcId = (core['fdcId'] is num) ? (core['fdcId'] as num).toInt() : null;

    // بناء FoodAnalysis من compat فقط
    final String nameAr = _s(compat['name_ar']).trim().isNotEmpty
        ? _s(compat['name_ar'])
        : _s(core['name_ar']);

    final String nameEn = _s(compat['name_en']).trim().isNotEmpty
        ? _s(compat['name_en'])
        : _s(core['name_en']);

    final String label = nameAr.trim().isNotEmpty
        ? nameAr
        : ((_s(compat['label']).trim().isNotEmpty)
            ? _s(compat['label'])
            : (_s(core['food_name']).trim().isNotEmpty ? _s(core['food_name']) : 'غير معروف'));

    final ingredients = _pickIngredients(compat, core);
    final ingredientsEn = _pickIngredients(compat, core, english: true);

    final Map<String, dynamic> totalsMap =
        (compat['totals'] is Map) ? Map<String, dynamic>.from(compat['totals'] as Map) : const <String, dynamic>{};
    final Map<String, dynamic> totalsMacros =
        (totalsMap['macros'] is Map) ? Map<String, dynamic>.from(totalsMap['macros'] as Map) : const <String, dynamic>{};

    double calories = _num(totalsMap['calories_kcal']) > 0 ? _num(totalsMap['calories_kcal']) : _num(compat['calories']);
    double protein  = _num(totalsMacros['protein_g']) > 0 ? _num(totalsMacros['protein_g']) : _num(compat['protein']);
    double carbs    = _num(totalsMacros['carbs_g']) > 0 ? _num(totalsMacros['carbs_g']) : _num(compat['carbs']);
    double fat      = _num(totalsMacros['fat_g']) > 0 ? _num(totalsMacros['fat_g']) : _num(compat['fat']);
    final String decision = _s(compat['decision']).trim().isNotEmpty ? _s(compat['decision']) : 'غير محدد';
    final double? confidence = _nullableNum(compat['confidence']);

    final List<String> reasons = (compat['reasons'] is List)
        ? List<String>.from((compat['reasons'] as List).map((e) => e.toString()))
        : const <String>[];

    final bboxMap = (compat['bbox'] is Map) ? Map<String, dynamic>.from(compat['bbox']) : null;
    final BBox bbox = _parseBbox(bboxMap) ?? _defaultCenterBbox();

    final String? servingText = _servingText(compat);

    double? portionGrams = _nullableNum(compat['portion_grams']);
    final String portionDescArRaw = _s(compat['portion_desc_ar']).trim();
    String? portionDescAr = portionDescArRaw.isNotEmpty ? portionDescArRaw : null;

    // حمل totals إن وُجدت لكي نمرّرها للواجهة، ونحدّثها إن حصلنا على إعادة تقدير (retry).
    Map<String, dynamic>? totalsOut = totalsMap.isNotEmpty ? Map<String, dynamic>.from(totalsMap) : null;


    
    // إذا تعرّفنا على الوجبة لكن لم نحصل على سعرات/ماكروز، نطلب تقديرًا رقميًا سريعًا مرة إضافية.
    if (calories <= 0 && label.trim().isNotEmpty) {
      try {
        final uri2 = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');

        final retrySystem = '''
أنت خبير تغذية. هدفك الوحيد تقدير السعرات والماكروز (بروتين/كارب/دهون) وحجم الحصة بالجرام بدقة واقعية.
إذا كانت الصورة تحتوي على طعام، لا تضع 0. ضع 0 فقط إذا لا يوجد طعام في الصورة.
أعد JSON صالح فقط بالمفاتيح EXACTLY:
calories_kcal, macros{protein_g, carbs_g, fat_g}, portion_grams, portion_desc_ar
''';

        final ingText = (ingredients != null && (ingredients as List).isNotEmpty)
            ? (ingredients as List).take(8).join(', ')
            : '';
        final rText = (reasons.isNotEmpty) ? reasons.take(3).join(' ') : '';
        final userHint = (clarifier != null && clarifier.trim().isNotEmpty) ? 'ملاحظة المستخدم: ${clarifier.trim()}.' : '';

        final retryUserText = 'اسم الطبق: $label. $userHint'
            '${ingText.isNotEmpty ? ' مكونات محتملة: $ingText.' : ''}'
            '${rText.isNotEmpty ? ' ملاحظات: $rText.' : ''}'
            ' أعطني تقديرًا شائعًا لحصة واحدة.';

        final retrySchema = {
  "type": "object",
  "properties": {
    "calories_kcal": {"type": "number"},
    "macros": {
      "type": "object",
      "properties": {
        "protein_g": {"type": "number"},
        "carbs_g": {"type": "number"},
        "fat_g": {"type": "number"}
      },
      "required": ["protein_g", "carbs_g", "fat_g"]
    },
    "portion_grams": {"type": "number"},
    "portion_desc_ar": {"type": "string"}
  },
  "required": ["calories_kcal", "macros", "portion_grams", "portion_desc_ar"]
};

final body2 = jsonEncode({
          "systemInstruction": {"parts": [{"text": retrySystem}]},
          "contents": [
            {
              "parts": [
                {"text": retryUserText},
                {"inline_data": {"mime_type": "image/jpeg", "data": b64}}
              ]
            }
          ],
          "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 350,
            "responseMimeType": "application/json",
            "responseSchema": retrySchema,
            "response_mime_type": "application/json",
            "response_schema": retrySchema
          }
        });

        final resp2 = await http
            .post(uri2, headers: {"Content-Type": "application/json"}, body: body2)
            .timeout(const Duration(seconds: 25));

        if (resp2.statusCode < 400) {
          final decoded2 = jsonDecode(resp2.body);
          final Map<String, dynamic> raw2 = _extractJsonFromGemini(decoded2);

          final Map<String, dynamic> fromRaw2 = _compatFromRaw(raw2);
          final Map<String, dynamic> core2 = _unwrap(fromRaw2);
          final Map<String, dynamic> compat2 = _toCompat(core2);

          final double cal2 = _num(compat2['calories_kcal']) > 0
              ? _num(compat2['calories_kcal'])
              : _num(compat2['calories']);
          final Map<String, dynamic> macros2 = (compat2['macros'] is Map)
              ? Map<String, dynamic>.from(compat2['macros'] as Map)
              : const <String, dynamic>{};

          final double p2 = _num(macros2['protein_g']) > 0 ? _num(macros2['protein_g']) : _num(compat2['protein']);
          final double c2 = _num(macros2['carbs_g']) > 0 ? _num(macros2['carbs_g']) : _num(compat2['carbs']);
          final double f2 = _num(macros2['fat_g']) > 0 ? _num(macros2['fat_g']) : _num(compat2['fat']);

          if (cal2 > 0) {
            calories = cal2;
            if (p2 > 0) protein = p2;
            if (c2 > 0) carbs = c2;
            if (f2 > 0) fat = f2;

            portionGrams ??= _nullableNum(compat2['portion_grams']);
            final String pdesc2 = _s(compat2['portion_desc_ar']).trim();
            portionDescAr ??= (pdesc2.isNotEmpty ? pdesc2 : null);

            totalsOut ??= <String, dynamic>{};
            totalsOut!['calories_kcal'] = calories;
            final Map<String, dynamic> m = (totalsOut!['macros'] is Map)
                ? Map<String, dynamic>.from(totalsOut!['macros'] as Map)
                : <String, dynamic>{};
            m['protein_g'] = protein;
            m['carbs_g'] = carbs;
            m['fat_g'] = fat;
            totalsOut!['macros'] = m;
          }
        } else {
          debugPrint('[Gemini] retry status=${resp2.statusCode}, body=${resp2.body}');
        }
      } catch (e) {
        debugPrint('[Gemini] retry macro error: $e');
      }
    }

final List<Map<String, dynamic>>? items =
        (compat['items'] is List)
            ? List<Map<String, dynamic>>.from(
                (compat['items'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e as Map)),
              )
            : ((core['items'] is List)
                ? List<Map<String, dynamic>>.from(
                    (core['items'] as List)
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e as Map)),
                  )
                : null);

    
    final bool needClarificationFromServer =
        _truthy(core['need_clarification']) ||
        _truthy(core['needClarification']) ||
        _truthy(compat['need_clarification']) ||
        _truthy(compat['needClarification']);

    final List<String>? questionsFromServer =
        _stringList(core['questions'] ?? core['clarification_questions'] ?? core['clarificationQuestions'] ??
            compat['questions'] ?? compat['clarification_questions'] ?? compat['clarificationQuestions']);

    final String combinedForZeroOk = ("$label ${(core['clarifier'] ?? core['user_note'] ?? '').toString()}").trim();
    final bool zeroOk = _isZeroMacrosOkText(combinedForZeroOk);

    bool autoNeedClarification = false;
    List<String>? autoQuestions;

    if (!needClarificationFromServer && !zeroOk && calories <= 0 && protein == 0 && carbs == 0 && fat == 0) {
      final String d = decision.trim();
      final bool decisionUnknown = d.isEmpty || d == 'unknown' || d == 'غير محدد';
      final String l = label.trim();
      final bool generic = l.isEmpty || l == 'وجبة';
      if (generic || decisionUnknown) {
        autoNeedClarification = true;
        autoQuestions = const <String>[
          "وش اسم الوجبة أو العناصر اللي بالصورة؟",
          "كم تقريبًا الكمية/الحصة لكل عنصر؟",
          "هل فيه سكر/دايت/زيرو أو إضافات مثل صوص/مايونيز؟"
        ];
      }
    }

    final bool needClarification = needClarificationFromServer || autoNeedClarification;
    final List<String>? clarificationQuestions = needClarification
        ? (questionsFromServer ?? autoQuestions)
        : questionsFromServer;

    if (!needClarification && !zeroOk && calories <= 0) {
      debugPrint('flutter: [REASON] calories<=0 keys=[label, serving, calories, protein, carbs, fat, confidence, decision, reasons, bbox] '
          'map={label: $label, serving: ${servingText ?? "null"}, calories: $calories, protein: $protein, carbs: $carbs, fat: $fat, '
          'confidence: ${confidence?.toString() ?? "null"}, decision: $decision, reasons: $reasons, '
          'bbox: ${bboxMap ?? {"x":0.3,"y":0.3,"w":0.4,"h":0.4}}}');
    }

    return FoodAnalysis(
      label: label,
      nameAr: nameAr.trim().isEmpty ? null : nameAr.trim(),
      nameEn: nameEn.trim().isEmpty ? null : nameEn.trim(),
      ingredients: ingredients,
      ingredientsEn: ingredientsEn,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      portionGrams: portionGrams,
      portionDescAr: portionDescAr,
      items: items,
      totals: totalsOut,
      serving: servingText,
      decision: decision,
      confidence: confidence,
      reasons: reasons,
      bbox: bbox,
      fdcSuggestions: fdcSuggestions,
      needsConfirmation: needsConfirmation,
      source: source,
      fdcId: fdcId,
    
      needClarification: needClarification,
      clarificationQuestions: clarificationQuestions,
      wazinAnalysis: _s(compat['wazin_analysis']).trim().isNotEmpty ? _s(compat['wazin_analysis']) : (_s(core['wazin_analysis']).trim().isNotEmpty ? _s(core['wazin_analysis']) : null),
    );
  }

  /// مسار البروكسي (اختياري).
  static Future<FoodAnalysis?> _analyzeViaProxy(
    String imagePath, {
    DietProfile? profile,
    String? clarifier,
    VisionDetail detail = VisionDetail.low,
    int maxImageEdge = 1024,
    bool countUsage = true
  }) async {
    final url = (dotenv.env['FOOD_PROXY_URL'] ?? '').trim().isNotEmpty
        ? dotenv.env['FOOD_PROXY_URL']!.trim()
        : (_defaultProxyUrl() ?? '');
    if (url.isEmpty) return null;

    try {
      // نرفع الصورة كما هي (السيرفر يمكنه التصغير أيضاً) + نمرر detail/max_edge
      final uri = Uri.parse(url.trim());
      final req = http.MultipartRequest('POST', uri)
        ..fields['clarifier'] = clarifier?.trim() ?? ''
        ..fields['profile']   = profile != null ? jsonEncode(profile.toMap()) : '{}'
        ..fields['detail']    = detail.apiValue
        ..fields['max_edge']  = (maxImageEdge).toString();

      // ✅ رفع صورة محسّنة: قصّ مركزي + تصغير + JPEG جودة أعلى
      Uint8List bytes = await File(imagePath).readAsBytes();
      final resized = await _shrinkToMaxEdge(bytes, maxImageEdge, quality: detail == VisionDetail.high ? 92 : 88, centerCropSquare: _centerCropSquareEnabled());
      if (resized != null) bytes = resized;
      req.files.add(http.MultipartFile.fromBytes('image', bytes, filename: 'food.jpg'));


      // تمرير Firebase ID Token إن وُجد
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken != null) {
        req.headers['Authorization'] = 'Bearer $idToken';
      }
      // يُستخدم في السيرفر لتحديد هل نزيد العدّاد اليومي أم لا
      req.headers['X-Count-Usage'] = countUsage ? '1' : '0';

      // ✅ مسار V2 الذكي: مستخدمو النسخ القديمة لا يرسلون هذا الهيدر، لذلك يبقون على V1.
      // النسخة الجديدة فقط تستخدم برومبت المطاعم/الشعارات وقاعدة عدم إظهار الماكروز عند الغموض.
      req.headers['X-Wazen-Vision-Version'] = '2';

      // ✅ مهم: كثير من سيرفرات البروكسي (Firebase onRequest) لا تقرأ حقول multipart النصية
      // لذلك نمرّر التوضيح أيضًا كـ Header ليصل دائمًا.
      // ملاحظة: HTTP headers لازم تكون ASCII، لذلك نرسلها مُشفّرة (URI component) ثم نفكّها في السيرفر.
      final c = (clarifier ?? '').trim();
      if (c.isNotEmpty) {
        // Express يحوّلها إلى lowercase داخليًا
        req.headers['X-Clarifier'] = Uri.encodeComponent(c);
        req.headers['X-Clarifier-Enc'] = 'uri';
      }

      final streamed = await req.send().timeout(const Duration(seconds: 80));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) {
        debugPrint('[Proxy] status=${res.statusCode}, body=${res.body}');

        Map<String, dynamic>? j;
        try {
          j = jsonDecode(res.body) as Map<String, dynamic>;
        } catch (_) {
          j = null;
        }

        final String errCode = (j?['error'] ?? j?['code'] ?? '').toString();
        final String msg = (j?['message'] ?? j?['msg'] ?? res.body).toString();

        int? retryAfter;
        try {
          final raBody = (j?['retry_after'] ?? j?['retryAfter'] ?? j?['retry_after_seconds'] ?? '').toString();
          retryAfter = int.tryParse(raBody);
        } catch (_) {}
        // Header: Retry-After
        try {
          final raH = res.headers['retry-after'];
          if (raH != null && raH.toString().trim().isNotEmpty) {
            retryAfter ??= int.tryParse(raH.toString().trim());
          }
        } catch (_) {}

        final lowerMsg = msg.toLowerCase();

        // 429: إما حد يومي (من نظامك) أو ضغط من Gemini
        if (res.statusCode == 429) {
          final isDaily =
              errCode == 'quota_exceeded' ||
              lowerMsg.contains('الحد اليومي') ||
              lowerMsg.contains('quota');
          if (isDaily) {
            throw DailyLimitExceeded(msg.isNotEmpty ? msg : 'تم تجاوز الحد اليومي.');
          }

          final isBusy =
              errCode == 'service_busy' ||
              lowerMsg.contains('resource exhausted') ||
              lowerMsg.contains('too many requests') ||
              lowerMsg.contains('unavailable');
          if (isBusy) {
            throw ServiceBusy('خدمة التحليل تحت ضغط حالياً. جرّب بعد قليل.',
                retryAfterSeconds: retryAfter);
          }

          // افتراضي: اعتبرها حد يومي
          throw DailyLimitExceeded(msg.isNotEmpty ? msg : 'تم تجاوز الحد اليومي.');
        }

        // 503: خدمة مشغولة/ضغط
        if (res.statusCode == 503) {
          throw ServiceBusy('خدمة التحليل تحت ضغط حالياً. جرّب بعد قليل.',
              retryAfterSeconds: retryAfter);
        }

        // توافق للخلف: بعض النسخ القديمة كانت ترجع 500 مع رسالة Gemini 429
        if (res.statusCode == 500 &&
            (lowerMsg.contains('gemini api 429') ||
             lowerMsg.contains('resource exhausted'))) {
          throw ServiceBusy('خدمة التحليل تحت ضغط حالياً. جرّب بعد قليل.',
              retryAfterSeconds: retryAfter);
        }

        // 401/403 غالبًا AppCheck/Auth
        if (res.statusCode == 401) {
          throw Exception('يلزم تسجيل الدخول لاستخدام التحليل.');
        }
        if (res.statusCode == 403) {
          throw Exception('تعذّر التحقق من أمان التطبيق (App Check).');
        }

        return null;
      }

      // نفس منطق التوافق الموحّد
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final Map<String, dynamic> fromRaw = _compatFromRaw(j);
      final Map<String, dynamic> core = _unwrap(fromRaw);
      final Map<String, dynamic> compat = _toCompat(core);
    _applyNutritionSafety(compat, core, clarifier: clarifier);
      // اقتراحات USDA (إن وُجدت من السيرفر)
      List<Map<String, dynamic>>? fdcSuggestions;
      try {
        final v = core['fdc_suggestions'] ?? core['fdcSuggestions'];
        if (v is List) {
          fdcSuggestions = v
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
      final bool needsConfirmation =
          core['needs_confirmation'] == true || core['needsConfirmation'] == true;
      final String? source = core['source']?.toString();
      final dynamic fdcIdRaw = core['fdcId'] ?? core['fdc_id'];
      final int? fdcId = (fdcIdRaw is num)
          ? fdcIdRaw.toInt()
          : int.tryParse(fdcIdRaw?.toString() ?? '');

      // أسماء (عربي/إنجليزي) — مع fallback على name / name_en
      final String nameAr = _s(compat['name_ar']).trim().isNotEmpty
          ? _s(compat['name_ar'])
          : (_s(core['name_ar']).trim().isNotEmpty
              ? _s(core['name_ar'])
              : _s(core['name']));

      final String nameEn = _s(compat['name_en']).trim().isNotEmpty
          ? _s(compat['name_en'])
          : (_s(core['name_en']).trim().isNotEmpty
              ? _s(core['name_en'])
              : _s(core['nameEn']));


      final String label = (_s(compat['label']).trim().isNotEmpty)
          ? _s(compat['label'])
          : (_s(core['food_name']).trim().isNotEmpty ? _s(core['food_name']) : '');

      final ingredients = _pickIngredients(compat, core);
      final ingredientsEn = _pickIngredients(compat, core, english: true);

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


      // ==== دعم الحاجة لتوضيح (من السيرفر أو تلقائياً عند رجوع أصفار) ====
      final bool needClarificationFromServer =
          _truthy(core['need_clarification']) ||
          _truthy(core['needClarification']) ||
          _truthy(compat['need_clarification']) ||
          _truthy(compat['needClarification']);

      final List<String>? questionsFromServer = _stringList(
          core['questions'] ??
              core['clarification_questions'] ??
              core['clarificationQuestions'] ??
              compat['questions'] ??
              compat['clarification_questions'] ??
              compat['clarificationQuestions']);

      final String combinedForZeroOk =
          ("$label ${(clarifier ?? '').toString()}").trim();
      final bool zeroOk = _isZeroMacrosOkText(combinedForZeroOk);

      bool autoNeedClarification = false;
      List<String>? autoQuestions;

      if (!needClarificationFromServer &&
          !zeroOk &&
          calories <= 0 &&
          protein == 0 &&
          carbs == 0 &&
          fat == 0) {
        final String d = decision.trim();
        final bool decisionUnknown =
            d.isEmpty || d == 'unknown' || d == 'غير محدد';
        final String l = label.trim();
        final bool generic = l.isEmpty || l == 'وجبة';
        if (generic || decisionUnknown) {
          autoNeedClarification = true;
          autoQuestions = const <String>[
            "وش اسم الوجبة أو العناصر اللي بالصورة؟",
            "كم تقريبًا الكمية/الحصة لكل عنصر؟",
            "هل فيه سكر/دايت/زيرو أو إضافات مثل صوص/مايونيز؟"
          ];
        }
      }

      final bool needClarification =
          needClarificationFromServer || autoNeedClarification;
      final List<String>? clarificationQuestions = needClarification
          ? (questionsFromServer ?? autoQuestions)
          : questionsFromServer;


      if (!needClarification && !zeroOk && calories <= 0) {
        debugPrint('flutter: [REASON] calories<=0 keys=[label, serving, calories, protein, carbs, fat, confidence, decision, reasons, bbox] '
                   'map={label: $label, serving: ${servingText ?? "null"}, calories: $calories, protein: $protein, carbs: $carbs, fat: $fat, '
                   'confidence: ${confidence?.toString() ?? "null"}, decision: $decision, reasons: $reasons, '
                   'bbox: ${compat["bbox"] ?? {"x":0.3,"y":0.3,"w":0.4,"h":0.4}}}');
      }

      return FoodAnalysis(
        label: label,
        nameAr: nameAr.trim().isNotEmpty ? nameAr : null,
        nameEn: nameEn.trim().isNotEmpty ? nameEn : null,
        ingredients: ingredients,
        ingredientsEn: ingredientsEn,
        portionGrams: _nullableNum(compat['portion_grams']),
        portionDescAr: _s(compat['portion_desc_ar']).trim().isNotEmpty ? _s(compat['portion_desc_ar']) : null,
        items: (compat['items'] is List) ? List<Map<String, dynamic>>.from(compat['items'] as List) : null,
        totals: (compat['totals'] is Map) ? Map<String, dynamic>.from(compat['totals'] as Map) : null,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        serving: servingText,
        decision: decision,
        confidence: confidence,
        reasons: reasons,
        bbox: bbox,
        fdcSuggestions: fdcSuggestions,
        needsConfirmation: needsConfirmation,
        source: source,
        fdcId: fdcId,
      
        needClarification: needClarification,
        clarificationQuestions: clarificationQuestions,
        wazinAnalysis: _s(compat['wazin_analysis']).trim().isNotEmpty ? _s(compat['wazin_analysis']) : (_s(core['wazin_analysis']).trim().isNotEmpty ? _s(core['wazin_analysis']) : null),
);
    } catch (e) {
      // لا نخفي أخطاء مهمة مثل الضغط/الحد اليومي/المصادقة؛ لازم توصل للواجهة برسالة واضحة.
      if (e is DailyLimitExceeded || e is ServiceBusy) rethrow;
      final msg = e.toString().toLowerCase();
      if (msg.contains('تسجيل الدخول') ||
          msg.contains('app check') ||
          msg.contains('appcheck') ||
          msg.contains('401') ||
          msg.contains('403') ||
          msg.contains('unauth')) {
        rethrow;
      }
      debugPrint('[Proxy] error: $e');
      return null;
    }
  }

  // ===== أدوات مساعدة (مشتركة) =====

  static String _s(Object? v) => (v ?? '').toString();

  static List<String>? _stringList(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      final out = <String>[];
      for (final e in v) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
      return out.isEmpty ? null : out;
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // دعم "دجاج، ثوم، خبز" أو "دجاج - ثوم - خبز"
    final parts = s
        .split(RegExp(r'[,،;؛\n\-\u2013\u2014\|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts;
  }

  static bool _truthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  static bool _isZeroMacrosOkText(String text) {
    final t = _normFoodText(text);
    if (t.isEmpty) return false;

    if (_looksLikeWaterOrIce(t)) return true;
    if (_looksLikeDietSoda(t)) return true;
    if (_looksLikeBlackCoffeeOrTea(t) && !_hasSweetenerOrMilk(t)) return true;
    return false;
  }

  static String _normFoodText(String text) =>
      _normalizeDigits(text).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _containsAny(String text, List<String> needles) {
    final t = _normFoodText(text);

    return needles.any((n) {
      final needle = _normFoodText(n);
      if (needle.isEmpty) return false;

      // English words/phrases must match as real words.
      // This prevents false positives like: rice -> ice, spice -> ice.
      if (RegExp(r'[a-z]').hasMatch(needle)) {
        final phrase = needle
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .map(RegExp.escape)
            .join(r'\s+');

        return RegExp(
          '(^|[^a-z0-9])$phrase([^a-z0-9]|\$)',
          caseSensitive: false,
        ).hasMatch(t);
      }

      // Arabic matching can stay as contains because Arabic food words here are clear.
      return t.contains(needle);
    });
  }

  static bool _hasSweetenerOrMilk(String text) {
    return _containsAny(text, const [
      'سكر', 'محلى', 'محلاه', 'شيره', 'سيرب', 'كراميل', 'حليب', 'لاتيه', 'كابتشينو', 'موكا', 'كريمر', 'كريمة', 'قشطه',
      'sugar', 'sweet', 'sweetened', 'syrup', 'caramel', 'milk', 'latte', 'mocha', 'cappuccino', 'creamer', 'cream', 'honey',
    ]);
  }

  static bool _looksLikeWaterOrIce(String text) {
    return _containsAny(text, const [
      'ماء', 'موية', 'مياه', 'water', 'sparkling water', 'mineral water',
      'ثلج', 'مكعبات ثلج', 'ice', 'ice cubes', 'iced water',
    ]);
  }

  static bool _looksLikeDietSoda(String text) {
    final hasDiet = _containsAny(text, const ['دايت', 'زيرو', 'بدون سكر', 'خالي من السكر', 'diet', 'zero', 'sugar free', 'sugar-free', 'no sugar']);
    final hasSoda = _containsAny(text, const ['كولا', 'كوكا', 'بيبسي', 'سبرايت', 'صودا', 'غازي', 'cola', 'coke', 'pepsi', 'sprite', 'soda', '7up']);
    return hasDiet && hasSoda;
  }

  static bool _looksLikeBlackCoffeeOrTea(String text) {
    return _containsAny(text, const [
      'قهوة سوداء', 'قهوة امريكانو', 'قهوه سوداء', 'قهوه امريكانو', 'قهوة مثلجة', 'قهوه مثلجه', 'امريكانو', 'اسبريسو', 'إسبريسو',
      'black coffee', 'americano', 'espresso', 'iced coffee', 'iced americano',
      'شاي', 'شاي اخضر', 'شاي اسود', 'tea', 'green tea', 'black tea', 'iced tea',
    ]);
  }

  static void _forceZeroMacros(Map<String, dynamic> dst) {
    dst['calories_kcal'] = 0.0;
    dst['calories'] = 0.0;
    dst['protein_g'] = 0.0;
    dst['protein'] = 0.0;
    dst['carbs_g'] = 0.0;
    dst['carbs'] = 0.0;
    dst['fat_g'] = 0.0;
    dst['fat'] = 0.0;
    final macros = (dst['macros'] is Map)
        ? Map<String, dynamic>.from(dst['macros'] as Map)
        : <String, dynamic>{};
    macros['protein_g'] = 0.0;
    macros['carbs_g'] = 0.0;
    macros['fat_g'] = 0.0;
    dst['macros'] = macros;
  }

  static Map<String, dynamic> _sanitizeItemNutrition(Map<String, dynamic> item) {
    final out = Map<String, dynamic>.from(item);
    final name = [
      out['name_ar'],
      out['name_en'],
      out['label'],
      out['name'],
      out['fdc_description'],
    ].where((e) => e != null).join(' ');

    if (_looksLikeWaterOrIce(name) || _looksLikeDietSoda(name)) {
      _forceZeroMacros(out);
      return out;
    }

    if (_looksLikeBlackCoffeeOrTea(name) && !_hasSweetenerOrMilk(name)) {
      final grams = _num(out['grams'] ?? out['portion_g'] ?? out['portion_grams']);
      final factor = grams > 0 ? (grams / 240.0).clamp(0.4, 3.0) : 1.0;
      out['calories_kcal'] = (_num(out['calories_kcal']) <= 0 || _num(out['calories_kcal']) > 12)
          ? (2.0 * factor)
          : _num(out['calories_kcal']).clamp(0.0, 12.0);
      out['protein_g'] = 0.0;
      out['carbs_g'] = 0.0;
      out['fat_g'] = 0.0;
      final macros = (out['macros'] is Map)
          ? Map<String, dynamic>.from(out['macros'] as Map)
          : <String, dynamic>{};
      macros['protein_g'] = 0.0;
      macros['carbs_g'] = 0.0;
      macros['fat_g'] = 0.0;
      out['macros'] = macros;
      return out;
    }

    return out;
  }

  static void _applyNutritionSafety(
    Map<String, dynamic> compat,
    Map<String, dynamic> core, {
    String? clarifier,
  }) {
    try {
      final topText = [
        compat['label'],
        compat['name_ar'],
        compat['name_en'],
        core['name'],
        clarifier,
      ].where((e) => e != null).join(' ');

      if (compat['items'] is List) {
        final rawItems = (compat['items'] as List)
            .whereType<Map>()
            .map((e) => _sanitizeItemNutrition(Map<String, dynamic>.from(e)))
            .toList();
        compat['items'] = rawItems;

        if (rawItems.isNotEmpty) {
          double kcal = 0, p = 0, c = 0, f = 0;
          for (final item in rawItems) {
            kcal += _num(item['calories_kcal'] ?? item['calories']);
            final macros = (item['macros'] is Map) ? Map<String, dynamic>.from(item['macros'] as Map) : const <String, dynamic>{};
            p += _num(item['protein_g'] ?? macros['protein_g'] ?? item['protein']);
            c += _num(item['carbs_g'] ?? macros['carbs_g'] ?? item['carbs']);
            f += _num(item['fat_g'] ?? macros['fat_g'] ?? item['fat']);
          }
          compat['totals'] = {
            'calories_kcal': kcal,
            'macros': {
              'protein_g': p,
              'carbs_g': c,
              'fat_g': f,
            }
          };
          compat['calories'] = kcal;
          compat['protein'] = p;
          compat['carbs'] = c;
          compat['fat'] = f;
        }
      }

      if (_looksLikeWaterOrIce(topText) || _looksLikeDietSoda(topText)) {
        _forceZeroMacros(compat);
      } else if (_looksLikeBlackCoffeeOrTea(topText) && !_hasSweetenerOrMilk(topText)) {
        compat['calories'] = (_num(compat['calories']) <= 0 || _num(compat['calories']) > 12)
            ? 2.0
            : _num(compat['calories']).clamp(0.0, 12.0);
        compat['protein'] = 0.0;
        compat['carbs'] = 0.0;
        compat['fat'] = 0.0;
        final totals = (compat['totals'] is Map)
            ? Map<String, dynamic>.from(compat['totals'] as Map)
            : <String, dynamic>{};
        totals['calories_kcal'] = compat['calories'];
        final macros = (totals['macros'] is Map)
            ? Map<String, dynamic>.from(totals['macros'] as Map)
            : <String, dynamic>{};
        macros['protein_g'] = 0.0;
        macros['carbs_g'] = 0.0;
        macros['fat_g'] = 0.0;
        totals['macros'] = macros;
        compat['totals'] = totals;
      }
    } catch (_) {}
  }



  static List<String>? _pickIngredients(Map<String, dynamic> compat, Map<String, dynamic> core, {bool english = false}) {
    final keys = english
        ? const ['ingredients_en', 'ingredientsEn', 'ingredientsEnglish', 'ingredientsEN']
        : const ['ingredients', 'ingredients_ar', 'ingredientsAr', 'components', 'contents'];
    for (final k in keys) {
      final v = compat[k] ?? core[k];
      final list = _stringList(v);
      if (list != null && list.isNotEmpty) return list;
    }
    return null;
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
    final descAr = (compat['portion_desc_ar'] ?? '').toString().trim();
    final desc = descAr.isNotEmpty ? descAr : (compat['portion_desc'] ?? '').toString().trim();
    if (grams > 0 && desc.isNotEmpty) return '$desc (${grams.toStringAsFixed(0)} جم)';
    if (grams > 0) return '${grams.toStringAsFixed(0)} جم';
    return null;
  }


  static Map<String, dynamic> _responseFormat(String modelId) {
    final id = modelId.toLowerCase();
    final supportsSchema = id.startsWith('gpt-4o-mini') ||
        id.startsWith('gpt-4o-') ||
        id == 'gpt-4o' ||
        id == 'gpt-4o-mini';

    if (!supportsSchema) return {"type": "json_object"};

    return {
      "type": "json_schema",
      "json_schema": {
        "name": "food_analysis",
        "strict": true,
        "schema": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "name_ar": {"type": "string"},
            "name_en": {"type": ["string", "null"]},
            "ingredients": {"type": ["array", "null"], "items": {"type": "string"}},
            "ingredients_en": {"type": ["array", "null"], "items": {"type": "string"}},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "portion_grams": {"type": ["number", "null"], "minimum": 0},
            "portion_desc_ar": {"type": ["string", "null"]},
            "calories_kcal": {"type": "number", "minimum": 0},
            "macros": {
              "type": "object",
              "additionalProperties": false,
              "properties": {
                "protein_g": {"type": "number", "minimum": 0},
                "carbs_g": {"type": "number", "minimum": 0},
                "fat_g": {"type": "number", "minimum": 0}
              },
              "required": ["protein_g", "carbs_g", "fat_g"]
            },
            "items": {
              "type": ["array", "null"],
              "items": {
                "type": "object",
                "additionalProperties": false,
                "properties": {
                  "name_ar": {"type": "string"},
                  "name_en": {"type": ["string", "null"]},
            "ingredients": {"type": ["array", "null"], "items": {"type": "string"}},
            "ingredients_en": {"type": ["array", "null"], "items": {"type": "string"}},
                  "grams": {"type": ["number", "null"], "minimum": 0},
                  "calories_kcal": {"type": ["number", "null"], "minimum": 0},
                  "macros": {
                    "type": "object",
                    "additionalProperties": false,
                    "properties": {
                      "protein_g": {"type": "number", "minimum": 0},
                      "carbs_g": {"type": "number", "minimum": 0},
                      "fat_g": {"type": "number", "minimum": 0}
                    },
                    "required": ["protein_g", "carbs_g", "fat_g"]
                  },
                  "confidence": {"type": ["number", "null"], "minimum": 0, "maximum": 1}
                },
                "required": ["name_ar", "macros"]
              }
            },
            "totals": {
              "type": ["object", "null"],
              "additionalProperties": false,
              "properties": {
                "calories_kcal": {"type": "number", "minimum": 0},
                "macros": {
                  "type": "object",
                  "additionalProperties": false,
                  "properties": {
                    "protein_g": {"type": "number", "minimum": 0},
                    "carbs_g": {"type": "number", "minimum": 0},
                    "fat_g": {"type": "number", "minimum": 0}
                  },
                  "required": ["protein_g", "carbs_g", "fat_g"]
                }
              },
              "required": ["calories_kcal", "macros"]
            },
            "decision": {"type": "string"},
            "reasons": {"type": "array", "items": {"type": "string"}},
            "bbox": {
              "type": "object",
              "additionalProperties": false,
              "properties": {
                "x": {"type": "number", "minimum": 0, "maximum": 1},
                "y": {"type": "number", "minimum": 0, "maximum": 1},
                "w": {"type": "number", "minimum": 0, "maximum": 1},
                "h": {"type": "number", "minimum": 0, "maximum": 1}
              },
              "required": ["x", "y", "w", "h"]
            }
          },
          "required": ["name_ar", "confidence", "calories_kcal", "macros", "decision", "reasons", "bbox"]
        }
      }
    };
  }

  // توحيد الحقول لمفاتيح متوقعة
  static Map<String, dynamic> _toCompat(Map<String, dynamic> src) {
    final energy = (src['energy'] is Map) ? Map<String, dynamic>.from(src['energy']) : const <String, dynamic>{};
    final nutrition = (src['nutrition'] is Map) ? Map<String, dynamic>.from(src['nutrition']) : const <String, dynamic>{};
    final macros = (src['macros'] is Map) ? Map<String, dynamic>.from(src['macros']) : const <String, dynamic>{};
    final totalsSrc = (src['total_macros'] is Map)
        ? Map<String, dynamic>.from(src['total_macros'] as Map)
        : ((src['totals'] is Map) ? Map<String, dynamic>.from(src['totals'] as Map) : const <String, dynamic>{});
    final meal = (src['meal'] is Map) ? Map<String, dynamic>.from(src['meal'] as Map) : const <String, dynamic>{};

    final dynamic rawItems = src['items'];
    final bool itemsAreObjects = rawItems is List && rawItems.any((e) => e is Map);
    final List<Map<String, dynamic>> normalizedItemsFromItems = itemsAreObjects
        ? rawItems
            .whereType<Map>()
            .map((e) {
              final m = Map<String, dynamic>.from(e);
              final est = (m['est'] is Map) ? Map<String, dynamic>.from(m['est'] as Map) : const <String, dynamic>{};
              final nameAr = (m['name_ar'] ?? m['name'] ?? m['label'] ?? '').toString().trim();
              final nameEn = (m['name_en'] ?? '').toString().trim();
              return <String, dynamic>{
                'name_ar': nameAr,
                'name_en': nameEn,
                'name': nameAr.isNotEmpty ? nameAr : nameEn,
                'grams': _nullableNum(m['grams'] ?? m['estimated_weight_g'] ?? m['weight_g'] ?? m['quantity_g']),
                'ml': _nullableNum(m['ml'] ?? m['volume_ml']),
                'primary_query': (m['primary_query'] ?? '').toString(),
                'calories_kcal': _num(est['kcal']) > 0 ? _num(est['kcal']) : _num(m['calories_kcal'] ?? m['calories'] ?? m['kcal']),
                'protein_g': _num(est['protein_g']) > 0 ? _num(est['protein_g']) : _num(m['protein_g'] ?? m['protein']),
                'carbs_g': _num(est['carbs_g']) > 0 ? _num(est['carbs_g']) : _num(m['carbs_g'] ?? m['carbs'] ?? m['carb']),
                'fat_g': _num(est['fat_g']) > 0 ? _num(est['fat_g']) : _num(m['fat_g'] ?? m['fat']),
                'confidence': m['confidence'],
                'source': 'gemini_visual_estimate',
              };
            })
            .toList()
        : const <Map<String, dynamic>>[];

    final dynamic rawIngredients = src['ingredients'];
    final bool ingredientsAreObjects = rawIngredients is List && rawIngredients.any((e) => e is Map);
    final List<Map<String, dynamic>> normalizedItemsFromIngredients = ingredientsAreObjects
        ? rawIngredients
            .whereType<Map>()
            .map((e) {
              final m = Map<String, dynamic>.from(e);
              final name = (m['name'] ?? m['ingredient_name'] ?? m['label'] ?? '').toString().trim();
              return <String, dynamic>{
                'name_ar': name,
                'name': name,
                'grams': _nullableNum(m['estimated_weight_g'] ?? m['weight_g'] ?? m['grams'] ?? m['quantity_g']),
                'calories_kcal': _num(m['calories_kcal'] ?? m['calories'] ?? m['kcal']),
                'protein_g': _num(m['protein_g'] ?? m['protein']),
                'carbs_g': _num(m['carbs_g'] ?? m['carbs'] ?? m['carb']),
                'fat_g': _num(m['fat_g'] ?? m['fat']),
                'source': 'gemini_visual_estimate',
              };
            })
            .toList()
        : const <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> normalizedItems =
        normalizedItemsFromItems.isNotEmpty ? normalizedItemsFromItems : normalizedItemsFromIngredients;

    final List<String>? ingredientNames = normalizedItems.isNotEmpty
        ? normalizedItems
            .map((e) => (e['name_ar'] ?? e['name'] ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : null;

    final double inferredPortionGrams = normalizedItems.fold<double>(
      0,
      (sum, e) => sum + _num(e['grams']),
    );

    final double itemsKcalSum = normalizedItems.fold<double>(
      0,
      (sum, e) => sum + _num(e['calories_kcal']),
    );
    final double itemsProteinSum = normalizedItems.fold<double>(
      0,
      (sum, e) => sum + _num(e['protein_g']),
    );
    final double itemsCarbsSum = normalizedItems.fold<double>(
      0,
      (sum, e) => sum + _num(e['carbs_g']),
    );
    final double itemsFatSum = normalizedItems.fold<double>(
      0,
      (sum, e) => sum + _num(e['fat_g']),
    );
    final double avgItemConfidence = normalizedItems.isEmpty
        ? 0.0
        : normalizedItems.fold<double>(
              0,
              (sum, e) => sum + _num(e['confidence']),
            ) /
            normalizedItems.length;

    double cals =
        _num(totalsSrc['calories_kcal']) > 0 ? _num(totalsSrc['calories_kcal']) :
        _num(totalsSrc['kcal']) > 0 ? _num(totalsSrc['kcal']) :
        _num(src['calories']) > 0 ? _num(src['calories']) :
        _num(src['calories_kcal']) > 0 ? _num(src['calories_kcal']) :
        _num(src['kcal']) > 0 ? _num(src['kcal']) :
        _num(energy['kcal']) > 0 ? _num(energy['kcal']) :
        _num(nutrition['calories']) > 0 ? _num(nutrition['calories']) :
        _num(macros['energy_kcal']) > 0 ? _num(macros['energy_kcal']) :
        _num(macros['calories']) > 0 ? _num(macros['calories']) :
        0.0;

    final totalsMacros = (totalsSrc['macros'] is Map) ? Map<String, dynamic>.from(totalsSrc['macros'] as Map) : const <String, dynamic>{};

    double protein = _num(totalsSrc['protein_g']);
    if (protein == 0) protein = _num(totalsMacros['protein_g']);
    if (protein == 0) protein = _num(src['protein']);
    if (protein == 0) protein = _num(src['protein_g']);
    if (protein == 0) protein = _num(macros['protein_g']);

    double carbs = _num(totalsSrc['carbs_g']);
    if (carbs == 0) carbs = _num(totalsMacros['carbs_g']);
    if (carbs == 0) carbs = _num(src['carbs']);
    if (carbs == 0) carbs = _num(src['carbs_g']);
    if (carbs == 0) carbs = _num(macros['carbs_g']);

    double fat = _num(totalsSrc['fat_g']);
    if (fat == 0) fat = _num(totalsMacros['fat_g']);
    if (fat == 0) fat = _num(src['fat']);
    if (fat == 0) fat = _num(src['fat_g']);
    if (fat == 0) fat = _num(macros['fat_g']);

    if (cals == 0 && itemsKcalSum > 0) cals = itemsKcalSum;
    if (protein == 0 && itemsProteinSum > 0) protein = itemsProteinSum;
    if (carbs == 0 && itemsCarbsSum > 0) carbs = itemsCarbsSum;
    if (fat == 0 && itemsFatSum > 0) fat = itemsFatSum;

    final portion = (src['portion'] is Map) ? Map<String, dynamic>.from(src['portion']) : const <String, dynamic>{};
    final serving = src['serving'] ?? src['serving_text'] ?? src['serving_size'] ?? src['serving_size_g'];
    final dishName = (src['dish_name'] ?? meal['name_ar'] ?? src['name_ar'] ?? src['food_name_ar'] ?? src['ar_name'] ?? src['label'] ?? src['food_name'] ?? src['name'] ?? '').toString();
    final dishNameEn = (src['name_en'] ?? meal['name_en'] ?? src['food_name_en'] ?? src['food_name'] ?? '').toString();

    return {
      'label': dishName,
      'name_ar': dishName,
      'name_en': dishNameEn,
      'serving': serving,
      'portion_desc': src['portion_desc'] ?? portion['desc'],
      'portion_desc_ar': src['portion_desc_ar'] ?? portion['desc_ar'] ?? src['portion_desc'] ?? portion['desc'],
      'portion_grams': src['portion_grams'] ?? portion['grams'] ?? (inferredPortionGrams > 0 ? inferredPortionGrams : null),
      'items': normalizedItems.isNotEmpty ? normalizedItems : ((src['items'] is List) ? src['items'] : null),
      'totals': <String, dynamic>{
        'calories_kcal': cals,
        'macros': <String, dynamic>{
          'protein_g': protein,
          'carbs_g': carbs,
          'fat_g': fat,
        },
      },
      'calories': cals,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'ingredients': ingredientNames ?? src['ingredients'] ?? src['ingredients_ar'] ?? src['ingredientsAr'] ?? src['components'] ?? src['contents'],
      'ingredients_en': src['ingredients_en'] ?? src['ingredientsEn'] ?? src['ingredientsEnglish'],
      'confidence': _nullableNum(src['confidence']) ?? (avgItemConfidence > 0 ? avgItemConfidence : null),
      'decision': (src['decision'] ?? 'estimated_by_gemini').toString(),
      'reasons': (src['reasons'] is List) ? src['reasons'] : const [],
      'source': (src['source'] ?? 'gemini_visual_estimate').toString(),
      'wazin_analysis': (src['wazin_analysis'] ?? '').toString(),
      'description_ar': (src['wazin_analysis'] ?? '').toString(),
      'need_clarification': src['need_clarification'],
      'questions': src['questions'],
      'bbox': (src['bbox'] is Map) ? src['bbox'] : {'x': 0.3, 'y': 0.3, 'w': 0.4, 'h': 0.4}
    };
  }


  // ===== استخراج JSON من رد Gemini =====
  static Map<String, dynamic> _extractJsonFromGemini(dynamic payload) {
    // GenerateContent: { candidates:[{ content:{ parts:[{text:'{...}'}] } }] }
    try {
      final candidates = payload['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates.first['content'];
        final parts = content?['parts'] as List?;
        if (parts != null) {
          for (final p in parts) {
            final txt = (p is Map) ? p['text'] : null;
            if (txt is String && txt.trim().isNotEmpty) {
              final extracted = _extractFirstJsonObject(txt);
              if (extracted != null) return extracted;
            }
          }
        }
      }
    } catch (_) {}

    // أحيانًا يرجع مباشرة Map
    if (payload is Map<String, dynamic>) {
      // إذا كان الرد من API الكامل، نعيده كما هو (قد يُفك لاحقًا عبر _unwrap/_toCompat)
      return payload;
    }

    throw Exception('Unable to extract JSON from Gemini response.');
  }

  /// يحاول استخراج أول كائن JSON داخل نص (حتى لو كان داخل ``` أو معه نص زائد).
  static Map<String, dynamic>? _extractFirstJsonObject(String text) {
    final t = text.trim();
    // إذا كان JSON صريح
    if (t.startsWith('{') && t.endsWith('}')) {
      try {
        return Map<String, dynamic>.from(jsonDecode(t));
      } catch (_) {}
    }
    // ابحث عن أول { وآخر }
    final i = t.indexOf('{');
    final j = t.lastIndexOf('}');
    if (i >= 0 && j > i) {
      final slice = t.substring(i, j + 1);
      try {
        return Map<String, dynamic>.from(jsonDecode(slice));
      } catch (_) {}
    }
    return null;
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


  /// تفعيل/تعطيل القصّ المربّع المركزي قبل الإرسال.
  /// افتراضيًا: false (أدق في كثير من الحالات مثل الأطباق البيضاوية/الساندويتش الطويل).
  /// لتفعيله: ضع FOOD_CENTER_CROP=true في .env
  static bool _centerCropSquareEnabled() {
    final v = (dotenv.env['FOOD_CENTER_CROP'] ?? '').toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'yes';
  }

  static Future<Uint8List?> _shrinkToMaxEdge(
    Uint8List input,
    int maxEdge, {
    int quality = 90,
    bool centerCropSquare = false
  }) async {
    final args = <String, dynamic>{
      'bytes': input,
      'maxEdge': maxEdge,
      'quality': quality,
      'centerCropSquare': centerCropSquare,
    };

    try {
      // أهم إصلاح للسلاسة: فك/تصغير/ضغط الصورة يتم في isolate خارج UI thread.
      if (!kIsWeb) {
        return await compute(_resizeFoodImageWorker, args);
      }
      return _resizeFoodImageWorker(args);
    } catch (_) {
      return _resizeFoodImageWorker(args);
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

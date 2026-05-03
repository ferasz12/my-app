// lib/services/food_ai_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ML Kit (اختياري كـ Fallback محلي)
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

/// رابط الدالة السحابية (اقرأ من .env وإلا استخدم الافتراضي)
String get _endpoint =>
    dotenv.env['FOOD_PROXY_URL'] ??
    'https://europe-west1-wazenfapp.cloudfunctions.net/analyzeFood';

class FoodAnalysis {
  final String label;     // اسم الوجبة
  final double calories;  // kcal
  final double protein;   // g
  final double carbs;     // g
  final double fat;       // g
  final String serving;   // نص الحصّة (مثلاً "120 g")
  final Map<String, dynamic> raw; // الرد الكامل (للاحتياط/الديبغ)

  const FoodAnalysis({
    required this.label,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.serving,
    required this.raw,
  });

  static num _num(dynamic v) {
    if (v is num) return v;
    if (v == null) return 0;

    String normalizeDigits(String input) {
      const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
      const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
      const ascii = '0123456789';
      final sb = StringBuffer();
      for (final ch in input.split('')) {
        final i1 = arabicIndic.indexOf(ch);
        if (i1 != -1) { sb.write(ascii[i1]); continue; }
        final i2 = easternArabic.indexOf(ch);
        if (i2 != -1) { sb.write(ascii[i2]); continue; }
        sb.write(ch);
      }
      return sb.toString()
          .replaceAll('٬', '')
          .replaceAll('٫', '.')
          .replaceAll('،', '.');
    }

    final s = normalizeDigits(v.toString()).trim().replaceAll(',', '.');
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(s);
    if (m == null) return 0;
    return num.tryParse(m.group(0)!) ?? 0;
  }

  factory FoodAnalysis.fromResponse(Map<String, dynamic> m) {
    final label = (m['label'] ?? m['name'] ?? '').toString();
    final calories = _num(m['calories'] ?? m['calories_kcal']).toDouble();
    final protein  = _num(m['protein']  ?? m['protein_g']).toDouble();
    final carbs    = _num(m['carbs']    ?? m['carbs_g']).toDouble();
    final fat      = _num(m['fat']      ?? m['fat_g']).toDouble();

    String serving;
    if (m['serving'] is String && (m['serving'] as String).isNotEmpty) {
      serving = m['serving'] as String;
    } else if (m['serving_size_g'] != null) {
      serving = '${_num(m['serving_size_g']).round()} g';
    } else {
      serving = '1 serving';
    }

    return FoodAnalysis(
      label: label,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      serving: serving,
      raw: m,
    );
  }

  bool get isValid => label.isNotEmpty && calories > 0;
}

class FoodAiService {
  FoodAiService({String? endpoint}) : _url = endpoint ?? _endpoint;
  final String _url;

  /// المسار الأساسي الموصى به: رفع ملف كـ multipart إلى الدالة.
  Future<FoodAnalysis> analyzeFile(File imageFile, {String? clarifier}) async {
    final req = http.MultipartRequest('POST', Uri.parse(_url));
    req.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    if (clarifier != null && clarifier.trim().isNotEmpty) {
      req.fields['clarifier'] = clarifier.trim();
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    final map = _parseJsonOrThrow(resp);

    // لو رجع RAW فهذا يعني الموديل طلع نص غير JSON
    if (map.containsKey('raw')) {
      throw Exception('تعذر التحليل (RAW): ${map['raw']}');
    }

    final result = FoodAnalysis.fromResponse(map);
    if (!result.isValid) {
      throw Exception('لم يتم التعرف على الطعام أو القيم غير كافية.');
    }
    return result;
  }

  /// بديل: لو عندك downloadURL للصورة وتحب ترسله JSON بدل multipart.
  Future<FoodAnalysis> analyzeImageUrl(String imageUrl, {String? clarifier}) async {
    final payload = <String, dynamic>{'imageUrl': imageUrl};
    if (clarifier != null && clarifier.trim().isNotEmpty) {
      payload['clarifier'] = clarifier.trim();
    }

    final resp = await http.post(
      Uri.parse(_url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    final map = _parseJsonOrThrow(resp);
    if (map.containsKey('raw')) {
      throw Exception('تعذر التحليل (RAW): ${map['raw']}');
    }

    final result = FoodAnalysis.fromResponse(map);
    if (!result.isValid) {
      throw Exception('لم يتم التعرف على الطعام أو القيم غير كافية.');
    }
    return result;
  }

  // -------------------- اختياري: Fallback MLKit + Nutritionix --------------------

  /// يقرأ الصورة ويستخرج أعلى التسميات بثقة ≥ 0.6
  static Future<List<String>> detectLabels(String imagePath) async {
    if (!File(imagePath).existsSync()) return [];
    final options = ImageLabelerOptions(confidenceThreshold: 0.6);
    final imageLabeler = ImageLabeler(options: options);
    final input = InputImage.fromFilePath(imagePath);
    final labels = await imageLabeler.processImage(input);
    await imageLabeler.close();

    labels.sort((a, b) => b.confidence.compareTo(a.confidence));
    final names = <String>[];
    for (final l in labels) {
      final name = l.label.trim();
      if (name.isNotEmpty && !names.contains(name)) {
        names.add(name);
      }
      if (names.length == 3) break;
    }
    return names;
  }

  /// Fallback: استخدام Nutritionix (يتطلب مفاتيح .env)
  static Future<FoodAnalysis?> fetchNutritionix(
    String baseQuery, {
    String? clarifier,
  }) async {
    final appId = dotenv.env['NUTRITIONIX_APP_ID'];
    final apiKey = dotenv.env['NUTRITIONIX_API_KEY'];
    if ((appId == null || appId.isEmpty) || (apiKey == null || apiKey.isEmpty)) {
      return null; // لا مفاتيح
    }

    final query = (clarifier != null && clarifier.trim().isNotEmpty)
        ? "${_arabicDigitsToAscii(clarifier.trim())} $baseQuery"
        : baseQuery;

    final url = Uri.parse('https://trackapi.nutritionix.com/v2/natural/nutrients');
    http.Response resp;
    try {
      resp = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-app-id': appId,
              'x-app-key': apiKey,
            },
            body: jsonEncode({'query': query}),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      return null;
    }

    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body);
    if (data is! Map || data['foods'] == null || (data['foods'] as List).isEmpty) {
      return null;
    }

    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final f = (data['foods'] as List).first as Map;
    final foodName = (f['food_name'] ?? baseQuery).toString();

    final baseCalories = toDouble(f['nf_calories']);
    final baseProtein  = toDouble(f['nf_protein']);
    final baseCarbs    = toDouble(f['nf_total_carbohydrate']);
    final baseFat      = toDouble(f['nf_total_fat']);
    final servingQty   = toDouble(f['serving_qty']);
    final servingUnit  = (f['serving_unit'] ?? '').toString();
    final servingGrams = toDouble(f['serving_weight_grams']);

    final double? targetGrams = _gramsFromClarifier(clarifier);
    double scale = 1.0;
    String servingText;

    if (targetGrams != null && targetGrams > 0 && servingGrams > 0) {
      scale = targetGrams / servingGrams;
      servingText = "${targetGrams.toStringAsFixed(0)} g";
    } else {
      final isInt = servingQty == servingQty.roundToDouble();
      final qtyStr = isInt ? servingQty.toStringAsFixed(0) : servingQty.toStringAsFixed(1);
      servingText = "${servingQty > 0 ? qtyStr : '1'} $servingUnit".trim();
    }

    return FoodAnalysis(
      label: foodName,
      calories: baseCalories * scale,
      protein:  baseProtein  * scale,
      carbs:    baseCarbs    * scale,
      fat:      baseFat      * scale,
      serving:  servingText,
      raw: {'source': 'nutritionix', 'food': f},
    );
  }

  /// سلسلة fallback: MLKit → Nutritionix
  static Future<FoodAnalysis?> analyzeImageFallback(String imagePath, {String? clarifier}) async {
    final labels = await detectLabels(imagePath);
    for (final name in labels) {
      final r = await fetchNutritionix(name, clarifier: clarifier);
      if (r != null && r.isValid) return r;
    }
    if (labels.isNotEmpty) {
      return await fetchNutritionix(labels.first, clarifier: clarifier);
    }
    return null;
  }

  // --------------------------- Helpers ---------------------------

  Map<String, dynamic> _parseJsonOrThrow(http.Response resp) {
    // اطبع للديبغ (اختياري)
    // ignore: avoid_print
    print('analyzeFood status=${resp.statusCode} body=${resp.body}');
    if (resp.statusCode != 200) {
      throw Exception('Server ${resp.statusCode}: ${resp.body}');
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('رد غير مفهوم من السيرفر');
    } catch (e) {
      throw Exception('JSON parse error: $e');
    }
  }

  static double? _gramsFromClarifier(String? clarifier) {
    if (clarifier == null || clarifier.trim().isEmpty) return null;
    String s = _arabicDigitsToAscii(clarifier.trim());
    final reg = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:g|gram|grams|gm|gms|غ|جم|جرام|غرام)\b',
      caseSensitive: false,
    );
    final m = reg.firstMatch(s);
    if (m == null) return null;
    final numStr = m.group(1)!.replaceAll(',', '.');
    return double.tryParse(numStr);
    }

  static String _arabicDigitsToAscii(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const ascii  = '0123456789';
    final map = {for (int i = 0; i < arabic.length; i++) arabic[i]: ascii[i]};
    return s.split('').map((ch) => map[ch] ?? ch).join();
  }
}

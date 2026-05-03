// lib/features/meal_analysis/meal_analysis.dart
// تحليل الطعام (نصي) عبر أحد مسارين تلقائيًا:
// 1) Proxy HTTP قديم عبر FOOD_PROXY_URL.
// 2) Firebase Cloud Functions (analyzeMealText/europe-west1) إذا لم يوجد FOOD_PROXY_URL.
//
// - في وضع البروكسي: POST JSON إلى السيرفر، ويرسل Firebase ID Token في Authorization.
// - بعض السيرفرات تتطلب imageBase64 إلزاميًا؛ نرسل صورة شفافة 1x1 كافتراضي.
// - في وضع Cloud Functions: يستدعي callable function باسم analyzeMealText.
//
// المتطلبات (pubspec.yaml):
//   flutter_dotenv: ^5.1.0
//   http: ^1.2.0
//   firebase_auth: ^4.17.8
//   cloud_functions: ^5.1.0
//
// flutter:
//   uses-material-design: true
//   assets:
//     - .env
//
// وفي main.dart:
//   await dotenv.load(fileName: ".env");

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../shared/friendly_errors.dart';
import '../../shared/premium_feature.dart';
import '../../shared/premium_gate.dart';

/// صورة PNG شفافة 1×1 (Base64 خام بدون data: prefix)
const String _kTinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';

/// ==========================
/// Model
/// ==========================
class MealAnalysisResult {
  final bool ok;
  final String? foodName;
  final double? calories;
  final Map<String, double>? macros; // {protein_g, carbs_g, fat_g}
  final Map<String, dynamic>? portion; // {grams, desc}
  final String? decision; // ok / caution / avoid ...
  final double? confidence; // 0..1
  final List<String>? reasons;
  final Map<String, dynamic>? raw;
  final String? errorMessage;

  MealAnalysisResult({
    required this.ok,
    this.foodName,
    this.calories,
    this.macros,
    this.portion,
    this.decision,
    this.confidence,
    this.reasons,
    this.raw,
    this.errorMessage,
  });

  factory MealAnalysisResult.fromJson(Map<String, dynamic> json) {
    final normalized = _normalizeAnalysisJson(json);

    Map<String, double>? _macros;
    final m = normalized['macros'];
    if (m is Map) {
      _macros = {
        'protein_g': _toD(m['protein_g']) ?? 0.0,
        'carbs_g': _toD(m['carbs_g']) ?? 0.0,
        'fat_g': _toD(m['fat_g']) ?? 0.0,
      };
    } else {
      final p = _toD(normalized['protein_g']);
      final c = _toD(normalized['carbs_g']);
      final f = _toD(normalized['fat_g']);
      if (p != null || c != null || f != null) {
        _macros = {
          'protein_g': p ?? 0.0,
          'carbs_g': c ?? 0.0,
          'fat_g': f ?? 0.0,
        };
      }
    }

    Map<String, dynamic>? _portion;
    final p = normalized['portion'];
    if (p is Map) {
      _portion = {
        'grams': (p['grams'] is num)
            ? (p['grams'] as num).toDouble()
            : _toD(normalized['serving_size_g']),
        'desc': p['desc'] ?? normalized['serving_desc'],
      };
    } else {
      final grams = _toD(normalized['serving_size_g']);
      if (grams != null) {
        _portion = {'grams': grams, 'desc': normalized['serving_desc']};
      }
    }

    final calories =
        _toD(normalized['calories']) ?? _toD(normalized['calories_kcal']);

    final reasons = _toStringList(normalized['reasons']) ??
        _toStringList(normalized['notes']) ??
        _toStringList(normalized['messages']);

    return MealAnalysisResult(
      ok: (normalized['ok'] is bool) ? normalized['ok'] as bool : true,
      foodName: _toS(normalized['food_name']) ??
          _toS(normalized['name']) ??
          _toS(normalized['item']) ??
          _toS(normalized['title']) ??
          _toS(normalized['description']) ??
          _toS(normalized['text']),
      calories: calories,
      macros: _macros,
      portion: _portion,
      decision: _toS(normalized['decision']),
      confidence: _toD(normalized['confidence']),
      reasons: reasons,
      raw: normalized,
      errorMessage: _toS(normalized['error']) ?? _toS(normalized['message']),
    );
  }

  factory MealAnalysisResult.error(String message,
      {Map<String, dynamic>? raw}) {
    return MealAnalysisResult(ok: false, errorMessage: message, raw: raw);
  }

  static double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) {
      var s = v.trim();
      if (s.isEmpty) return null;

      // حوّل الأرقام العربية/الفارسية إلى إنجليزية
      const digits = <String, String>{
        '٠': '0',
        '١': '1',
        '٢': '2',
        '٣': '3',
        '٤': '4',
        '٥': '5',
        '٦': '6',
        '٧': '7',
        '٨': '8',
        '٩': '9',
        '۰': '0',
        '۱': '1',
        '۲': '2',
        '۳': '3',
        '۴': '4',
        '۵': '5',
        '۶': '6',
        '۷': '7',
        '۸': '8',
        '۹': '9',
      };
      final sb = StringBuffer();
      for (final ch in s.split('')) {
        sb.write(digits[ch] ?? ch);
      }
      s = sb.toString();

      // نظّف الفواصل/الوحدات (مثل: "230 kcal", "١٢٫٥")
      s = s.replaceAll('٬', '');
      s = s.replaceAll('،', '.');
      s = s.replaceAll(',', '.');

      final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
      if (match == null) return null;
      return double.tryParse(match.group(0)!);
    }
    return null;
  }

  static String? _toS(dynamic v) => v?.toString();

  static List<String>? _toStringList(dynamic v) {
    if (v == null) return null;
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String) return v.split(',').map((e) => e.trim()).toList();
    return null;
  }
}

/// ==========================
/// Service (Auto: Proxy or Functions)
/// ==========================
class MealAnalysisService {
  static const Duration _timeout = Duration(seconds: 25);
  static const int _maxRetries = 1;

  // نحدّد هل نستخدم البروكسي أم الفنكشن تلقائيًا
  bool get _useProxy {
    final envUrl = dotenv.env['FOOD_PROXY_URL']?.trim();
    final defineUrl =
        const String.fromEnvironment('FOOD_PROXY_URL', defaultValue: '').trim();
    final url = (envUrl != null && envUrl.isNotEmpty)
        ? envUrl
        : (defineUrl.isNotEmpty ? defineUrl : '');
    return url.isNotEmpty;
  }

  bool get _isWindowsDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  String? get _callableHttpEndpoint {
    final envUrl = dotenv.env['ANALYZE_MEAL_TEXT_URL']?.trim();
    final defineUrl = const String.fromEnvironment(
      'ANALYZE_MEAL_TEXT_URL',
      defaultValue: '',
    ).trim();

    final explicit = (envUrl != null && envUrl.isNotEmpty)
        ? envUrl
        : (defineUrl.isNotEmpty ? defineUrl : '');
    if (explicit.isNotEmpty) return explicit;

    try {
      final projectId = Firebase.app().options.projectId;
      if (projectId.isNotEmpty) {
        return 'https://europe-west1-$projectId.cloudfunctions.net/analyzeMealText';
      }
    } catch (_) {}
    return null;
  }

  String get _endpoint {
    final envUrl = dotenv.env['FOOD_PROXY_URL']?.trim();
    final defineUrl =
        const String.fromEnvironment('FOOD_PROXY_URL', defaultValue: '').trim();

    final url = (envUrl != null && envUrl.isNotEmpty)
        ? envUrl
        : (defineUrl.isNotEmpty ? defineUrl : '');

    if (url.isEmpty) {
      throw StateError(
        'FOOD_PROXY_URL غير مُعرّف.\n'
        'لو تبغى تستخدم البروكسي عرّفه في .env أو بـ --dart-define.\n'
        'ولو ما تبي بروكسي، ما يحتاج—راح نستخدم Cloud Functions تلقائيًا.',
      );
    }
    return url;
  }

  bool _isZeroDietDrinkOnly(String d) {
    final zeroHint = RegExp(
            r'(دايت|زيرو|صفر\s*سكر|بدون\s*سكر|خالي\s*من\s*السكر|sugar[-\s]*free|diet|zero)')
        .hasMatch(d);
    final drinkHint = RegExp(
            r'(كولا|كوكا|كوكاكولا|بيبسي|سبرايت|فانتا|مشروب\s*غازي|صودا|cola|coke|coca[-\s]*cola|pepsi|sprite|fanta|red\s*bull|monster|energy)')
        .hasMatch(d);

    if (!zeroHint || !drinkHint) return false;

    final hasConnector =
        RegExp(r'(^|\s)(و|مع|and|plus|with)(\s|$)').hasMatch(d) ||
            d.contains('+') ||
            d.contains(',') ||
            d.contains(' و ');
    final hasOtherFood = RegExp(
      r'(برجر|burger|ساندويتش|sandwich|بطاطس|fries|بيتزا|pizza|شاورما|shawarma|رز|rice|مكرونة|pasta|دجاج|chicken|لحم|beef|سلطة|salad|خبز|bread|حلى|dessert|كيك|cake|ايس|آيس|ice\s*cream)',
    ).hasMatch(d);

    return !(hasConnector || hasOtherFood);
  }

  bool _looksBad(MealAnalysisResult r, String description) {
    final raw = r.raw ?? const <String, dynamic>{};
    if (raw['needs_user_answers'] == true || raw['source'] == 'wazin_pre_clarification') {
      return false;
    }
    final d = description.toLowerCase();
    final looksLikeWater = d.contains('ماء') || d.contains('water');
    if (looksLikeWater) return false;

    // ✅ مشروبات دايت/زيرو: الصفر طبيعي، لكن لو رجعت أرقام عالية نعتبرها خطأ عشان نسوي fallback
    if (_isZeroDietDrinkOnly(d)) {
      final kcal = (r.calories ?? 0);
      return kcal > 30; // مثال المشكلة: كولا دايت تطلع 200
    }

    final kcal = (r.calories ?? 0);
    final p = (r.macros?['protein_g'] ?? 0);
    final c = (r.macros?['carbs_g'] ?? 0);
    final f = (r.macros?['fat_g'] ?? 0);

    if (kcal <= 0) return true;
    if (p <= 0 && c <= 0 && f <= 0) return true;
    return false;
  }

  Future<MealAnalysisResult> analyzeText({
    required String description,
    Map<String, dynamic>? profile,
    String? imageBase64, // احتفظنا فيها لدعم البروكسي القديم
    List<Map<String, dynamic>>? clarificationAnswers,
  }) async {
    final desc = description.trim();
    if (desc.isEmpty) {
      return MealAnalysisResult.error('يرجى كتابة وصف للوجبة أولًا.');
    }

    // ✅ لو البروكسي شغّال: نجربه أولًا (وبعدين fallback للفنكشن لو طلع 0/ناقصة)
    if (_useProxy) {
      final proxyRes = await _callProxy(
        description: desc,
        profile: profile,
        imageBase64: imageBase64,
      );

      final name = (proxyRes.foodName ?? '').trim();
      final nameNotArabic = name.isNotEmpty && !RegExp(r'[ء-ي]').hasMatch(name);

      final bool needFallback = !proxyRes.ok ||
          _looksBad(proxyRes, desc) ||
          nameNotArabic ||
          (name.isEmpty || name == 'وجبة');

      if (!needFallback) return proxyRes;

      final fnRes = await _callFunctions(
        description: desc,
        clarificationAnswers: clarificationAnswers,
      );

      if (fnRes.raw?['needs_user_answers'] == true) return fnRes;

      if (fnRes.ok && !_looksBad(fnRes, desc)) {
        return fnRes;
      }

      // لا نرجّع أصفار مضللة — نرجّع خطأ واضح
      return MealAnalysisResult.error(
        fnRes.errorMessage ??
            proxyRes.errorMessage ??
            'تعذّر استخراج سعرات/ماكروز من النص. اكتب وصفًا أوضح للوجبة أو مكوناتها.',
        raw: fnRes.raw ?? proxyRes.raw,
      );
    }

    // ✅ افتراضيًا: Cloud Functions
    final fnRes = await _callFunctions(
      description: desc,
      clarificationAnswers: clarificationAnswers,
    );
    if (fnRes.raw?['needs_user_answers'] == true) return fnRes;
    if (fnRes.ok && _looksBad(fnRes, desc)) {
      return MealAnalysisResult.error(
        'تعذّر استخراج سعرات/ماكروز من النص. اكتب وصفًا أوضح للوجبة أو مكوناتها.',
        raw: fnRes.raw,
      );
    }
    return fnRes;
  }

  // --------- 1) المسار القديم (Proxy HTTP) ----------
  Future<MealAnalysisResult> _callProxy({
    required String description,
    Map<String, dynamic>? profile,
    String? imageBase64,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final uri = Uri.parse(_endpoint);

        // بعض السيرفرات تتطلب imageBase64 إلزاميًا — نرسل صورة 1x1 شفافة كحل افتراضي
        final imageB64 = (imageBase64 != null && imageBase64.isNotEmpty)
            ? imageBase64
            : _kTinyPngBase64;

        final body = <String, dynamic>{
          'text': description.trim(),
          'imageBase64': imageB64,
          if (profile != null && profile.isNotEmpty) 'profile': profile,
        };

        final headers = <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        };

        // Firebase ID token
        try {
          final auth = FirebaseAuth.instance;
          User? user = auth.currentUser;

          if (user == null) {
            await auth.signInAnonymously();
            user = auth.currentUser;
          }

          final idToken = await user?.getIdToken(true);
          if (idToken != null && idToken.isNotEmpty) {
            headers['Authorization'] = 'Bearer $idToken';
          }
        } catch (e) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('WARN: unable to attach Firebase ID token: $e');
          }
        }

        final resp = await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);

        final contentType = resp.headers['content-type']?.toLowerCase() ?? '';
        final isJson = contentType.contains('application/json') ||
            contentType.contains('+json');

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          if (isJson) {
            final decoded =
                jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
            final core = (decoded['data'] is Map)
                ? decoded['data'] as Map<String, dynamic>
                : decoded;

            if (core['ok'] == false) {
              final msg =
                  core['error']?.toString() ?? 'فشل التحليل من السيرفر.';
              return MealAnalysisResult.error(msg, raw: decoded);
            }
            return MealAnalysisResult.fromJson(core);
          } else {
            try {
              final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
              return MealAnalysisResult.fromJson(decoded);
            } catch (_) {
              return MealAnalysisResult.error(
                'نجح الاتصال لكن صيغة الرد ليست JSON.\nرجاءً إرجاع application/json.',
                raw: {'body': resp.body},
              );
            }
          }
        }

        // أخطاء 4xx/5xx
        if (isJson) {
          try {
            final decoded =
                jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
            final msg = decoded['error']?.toString() ??
                decoded['message']?.toString() ??
                'فشل التحليل (HTTP ${resp.statusCode}).';
            return MealAnalysisResult.error(msg, raw: decoded);
          } catch (_) {
            return MealAnalysisResult.error(
              'فشل التحليل (HTTP ${resp.statusCode}).\nنص الرد: ${resp.body}',
            );
          }
        } else {
          return MealAnalysisResult.error(
            'فشل التحليل (HTTP ${resp.statusCode}).\nنص الرد: ${resp.body}',
          );
        }
      } on TimeoutException {
        if (attempt <= _maxRetries) continue;
        return MealAnalysisResult.error(
          'انتهى وقت الانتظار أثناء الاتصال بالسيرفر. حاول مرة أخرى.',
        );
      } catch (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('MealAnalysisService (proxy) error: $e\n$st');
        }
        return MealAnalysisResult.error(FriendlyErrors.message(e));
      }
    }
  }

  // --------- 2) المسار الجديد (Firebase Functions Callable) ----------
  Future<MealAnalysisResult> _callFunctions({
    required String description,
    List<Map<String, dynamic>>? clarificationAnswers,
  }) async {
    if (_isWindowsDesktop) {
      return _callFunctionsHttp(
        description: description,
        clarificationAnswers: clarificationAnswers,
      );
    }

    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      final fns = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = fns.httpsCallable('analyzeMealText');
      final payload = <String, dynamic>{
        'description': description.trim(),
        if (clarificationAnswers != null && clarificationAnswers.isNotEmpty)
          'clarificationAnswers': clarificationAnswers,
      };
      final res = await callable.call(payload);

      final data = (res.data is Map<String, dynamic>)
          ? res.data as Map<String, dynamic>
          : Map<String, dynamic>.from(res.data as Map);

      return MealAnalysisResult.fromJson(data);
    } on FirebaseFunctionsException catch (e) {
      return MealAnalysisResult.error(
        e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : FriendlyErrors.message(e),
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MealAnalysisService (functions) error: $e\n$st');
      }
      return MealAnalysisResult.error(FriendlyErrors.message(e));
    }
  }

  Future<MealAnalysisResult> _callFunctionsHttp({
    required String description,
    List<Map<String, dynamic>>? clarificationAnswers,
  }) async {
    try {
      final endpoint = _callableHttpEndpoint;
      if (endpoint == null || endpoint.isEmpty) {
        return MealAnalysisResult.error(
          'تعذر تحديد رابط analyzeMealText لويندوز. '
          'أضف ANALYZE_MEAL_TEXT_URL أو FOOD_PROXY_URL.',
        );
      }

      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      final idToken = await auth.currentUser?.getIdToken(true);

      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (idToken != null && idToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $idToken';
      }

      final resp = await http
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'description': description.trim(),
                if (clarificationAnswers != null && clarificationAnswers.isNotEmpty)
                  'clarificationAnswers': clarificationAnswers,
              },
            }),
          )
          .timeout(_timeout);

      final bodyText = utf8.decode(resp.bodyBytes);
      Map<String, dynamic>? decoded;
      try {
        final j = jsonDecode(bodyText);
        if (j is Map<String, dynamic>) {
          decoded = j;
        } else if (j is Map) {
          decoded = Map<String, dynamic>.from(j);
        }
      } catch (_) {}

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final map = decoded ?? <String, dynamic>{'raw': bodyText};
        if (map['result'] is Map) {
          return MealAnalysisResult.fromJson(
            Map<String, dynamic>.from(map['result'] as Map),
          );
        }
        if (map['data'] is Map) {
          return MealAnalysisResult.fromJson(
            Map<String, dynamic>.from(map['data'] as Map),
          );
        }
        if (map['error'] is Map) {
          final err = Map<String, dynamic>.from(map['error'] as Map);
          return MealAnalysisResult.error(
            _callableErrorMessage(err),
            raw: map,
          );
        }
        return MealAnalysisResult.fromJson(map);
      }

      if (decoded != null && decoded['error'] is Map) {
        final err = Map<String, dynamic>.from(decoded['error'] as Map);
        return MealAnalysisResult.error(
          _callableErrorMessage(err),
          raw: decoded,
        );
      }

      return MealAnalysisResult.error(
        'فشل تحليل النص (HTTP ${resp.statusCode}).',
        raw: decoded ?? <String, dynamic>{'body': bodyText},
      );
    } on TimeoutException {
      return MealAnalysisResult.error(
        'انتهى وقت الانتظار أثناء الاتصال بخدمة التحليل.',
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MealAnalysisService (functions-http) error: $e\n$st');
      }
      return MealAnalysisResult.error(FriendlyErrors.message(e));
    }
  }
}

/// ==========================
/// شاشة التحليل (نصي) + Bridge لـ home_screen
/// ==========================

// ==========================
// نماذج مساعدة لتفصيل المكونات (Text Analysis)
// ==========================
class _IngredientBreakdown {
  final String nameAr;
  final String nameEn;
  final String quantityLabel;
  double grams;
  double caloriesKcal;
  double proteinG;
  double carbsG;
  double fatG;
  final bool needsConfirmation;
  final bool gramsWasGuessed;
  final double matchScore;
  final double confidence;

  _IngredientBreakdown({
    required this.nameAr,
    required this.nameEn,
    required this.quantityLabel,
    required this.grams,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.needsConfirmation,
    required this.gramsWasGuessed,
    required this.matchScore,
    required this.confidence,
  });

  factory _IngredientBreakdown.fromJson(Map<String, dynamic> j) {
    final grams = _toD(j['grams']) ?? _toD(j['portion_g']) ?? 0;
    final ml = _toD(j['ml']) ?? 0;
    final quantityLabel =
        _toS(j['quantity_label']) ??
        _toS(j['portion_desc_ar']) ??
        (grams > 0
            ? '${grams.toStringAsFixed(0)} جم'
            : (ml > 0 ? '${ml.toStringAsFixed(0)} مل' : 'حصة تقديرية'));

    return _IngredientBreakdown(
      nameAr:
          _toS(j['name_ar']) ?? _toS(j['name']) ?? _toS(j['ingredient']) ?? '—',
      nameEn: _toS(j['name_en']) ?? '',
      quantityLabel: quantityLabel,
      grams: grams,
      caloriesKcal: _toD(j['calories_kcal']) ?? _toD(j['calories']) ?? 0,
      proteinG: _toD(j['protein_g']) ?? 0,
      carbsG: _toD(j['carbs_g']) ?? 0,
      fatG: _toD(j['fat_g']) ?? 0,
      needsConfirmation: (j['needs_confirmation'] is bool)
          ? j['needs_confirmation'] as bool
          : false,
      gramsWasGuessed: (j['grams_was_guessed'] is bool)
          ? j['grams_was_guessed'] as bool
          : false,
      matchScore: _toD(j['match_score']) ?? 0,
      confidence:
          (((_toD(j['ingredient_confidence']) ?? _toD(j['confidence']) ?? 0)
                  .clamp(0.0, 1.0)) as num)
              .toDouble(),
    );
  }

  void rescale(double newGrams) {
    if (grams <= 0) {
      grams = newGrams;
      return;
    }
    final factor = newGrams / grams;
    grams = newGrams;
    caloriesKcal *= factor;
    proteinG *= factor;
    carbsG *= factor;
    fatG *= factor;
  }
}

class _Clarification {
  final String ingredient;
  final String question;
  final double suggestedGrams;
  final String reason;

  _Clarification({
    required this.ingredient,
    required this.question,
    required this.suggestedGrams,
    required this.reason,
  });

  factory _Clarification.fromJson(Map<String, dynamic> j) {
    return _Clarification(
      ingredient: _toS(j['ingredient']) ?? '—',
      question: _toS(j['question']) ?? '—',
      suggestedGrams: _toD(j['suggested_grams']) ?? _toD(j['grams']) ?? 0,
      reason: _toS(j['reason']) ?? '',
    );
  }
}


class _PreAnalysisOption {
  final String label;
  final String value;
  final String append;

  const _PreAnalysisOption({
    required this.label,
    required this.value,
    required this.append,
  });

  factory _PreAnalysisOption.fromJson(Map<String, dynamic> j) {
    return _PreAnalysisOption(
      label: _toS(j['label']) ?? _toS(j['value']) ?? '',
      value: _toS(j['value']) ?? _toS(j['label']) ?? '',
      append: _toS(j['append']) ?? _toS(j['label']) ?? _toS(j['value']) ?? '',
    );
  }
}

class _PreAnalysisQuestion {
  final String id;
  final String title;
  final String question;
  final String ingredient;
  final String reason;
  final List<_PreAnalysisOption> options;

  const _PreAnalysisQuestion({
    required this.id,
    required this.title,
    required this.question,
    required this.ingredient,
    required this.reason,
    required this.options,
  });

  factory _PreAnalysisQuestion.fromJson(Map<String, dynamic> j) {
    final rawOptions = j['options'];
    final options = <_PreAnalysisOption>[];
    if (rawOptions is List) {
      for (final x in rawOptions) {
        if (x is Map) {
          options.add(_PreAnalysisOption.fromJson(Map<String, dynamic>.from(x)));
        }
      }
    }
    return _PreAnalysisQuestion(
      id: _toS(j['id']) ?? _toS(j['type']) ?? UniqueKey().toString(),
      title: _toS(j['title']) ?? 'تأكيد سريع',
      question: _toS(j['question']) ?? 'اختر الخيار الأقرب',
      ingredient: _toS(j['ingredient']) ?? '',
      reason: _toS(j['reason']) ?? '',
      options: options,
    );
  }
}

class AnalyzeMeal {
  /// تفتح شاشة التحليل النصي. عند الضغط على "إضافة للسجل" ترجع Map جاهز
  /// لنفس صيغة MealTextUI.sheetFromMap في الصفحة الرئيسية.
  static Future<Map<String, dynamic>?> launch(BuildContext context) async {
    return await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const MealTextAnalysisScreen()),
    );
  }
}

class MealTextAnalysisScreen extends StatefulWidget {
  final String? initialDescription;
  final bool autoAnalyze;

  const MealTextAnalysisScreen({
    super.key,
    this.initialDescription,
    this.autoAnalyze = false,
  });
  @override
  State<MealTextAnalysisScreen> createState() => _MealTextAnalysisScreenState();
}

class _MealTextAnalysisScreenState extends State<MealTextAnalysisScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDescription;
    if (init != null && init.trim().isNotEmpty) {
      _ctrl.text = init.trim();
      _inputName = init.trim();
      if (widget.autoAnalyze) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _analyze();
        });
      }
    }
  }

  Map<String, dynamic>? _result;
  MealAnalysisResult? _analysis;

  // اسم الوجبة كما كتبه المستخدم (نعرضه دائمًا بدل اسم عام مثل "وجبة")
  String _inputName = '';

  // تفصيل المكونات (سعرات/ماكروز لكل مكوّن) + أسئلة تأكيد
  List<_IngredientBreakdown> _breakdown = <_IngredientBreakdown>[];
  List<_Clarification> _clarifications = <_Clarification>[];
  final Map<String, TextEditingController> _gramsCtrls =
      <String, TextEditingController>{};

  // أسئلة قبل التحليل النهائي: تظهر فقط عندما تكون الوجبة ناقصة معلومات مؤثرة.
  List<_PreAnalysisQuestion> _preQuestions = <_PreAnalysisQuestion>[];
  final Map<String, String> _preAnswers = <String, String>{};

  // إجمالي محسوب (إما من التفصيل أو من نتيجة التحليل العامة)
  double _sumKcal = 0;
  double _sumP = 0;
  double _sumC = 0;
  double _sumF = 0;

  Map<String, dynamic> _toHomeSheetMap() {
    final name = _inputName.trim().isNotEmpty
        ? _inputName.trim()
        : ((_analysis?.foodName ?? 'وجبة').trim().isEmpty
            ? 'وجبة'
            : (_analysis?.foodName ?? 'وجبة'));

    return <String, dynamic>{
      'name': name,
      'calories_kcal': _sumKcal,
      'protein_g': _sumP,
      'carbs_g': _sumC,
      'fat_g': _sumF,
      'confidence': (_analysis?.confidence ?? 0).toDouble(),
      'notes': (_analysis?.reasons?.isNotEmpty ?? false)
          ? _analysis!.reasons!.join(' • ')
          : '',
      // (اختياري) إرسال التفصيل إن احتجته لاحقًا في السجل
      'ingredients_breakdown': _breakdown
          .map((b) => {
                'name_ar': b.nameAr,
                'name_en': b.nameEn,
                'grams': b.grams,
                'quantity_label': b.quantityLabel,
                'portion_desc_ar': b.quantityLabel,
                'calories_kcal': b.caloriesKcal,
                'protein_g': b.proteinG,
                'carbs_g': b.carbsG,
                'fat_g': b.fatG,
                'match_score': b.matchScore,
              })
          .toList(),
    };
  }

  Future<void> _analyze({bool withClarificationAnswers = false}) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'اكتب وصف الوجبة أولًا.');
      return;
    }

    final answers = withClarificationAnswers ? _selectedClarificationAnswers() : <Map<String, dynamic>>[];
    if (withClarificationAnswers && answers.length < _preQuestions.length) {
      setState(() => _error = 'جاوب على الأسئلة السريعة أولًا عشان نحسبها بدقة.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _analysis = null;

      if (!withClarificationAnswers) {
        _preQuestions = <_PreAnalysisQuestion>[];
        _preAnswers.clear();
      }

      _inputName = text;
      _breakdown = <_IngredientBreakdown>[];
      _clarifications = <_Clarification>[];
      _gramsCtrls.forEach((_, c) => c.dispose());
      _gramsCtrls.clear();

      _sumKcal = 0;
      _sumP = 0;
      _sumC = 0;
      _sumF = 0;
    });

    final svc = MealAnalysisService();
    final res = await svc.analyzeText(
      description: text,
      clarificationAnswers: answers,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;

      if (!res.ok) {
        _analysis = null;
        _error = res.errorMessage ??
            'تعذّر إجراء التحليل. تحقق من الاتصال ثم حاول مجددًا.';
        return;
      }

      final raw = (res.raw ?? <String, dynamic>{});
      if (raw['needs_user_answers'] == true) {
        _analysis = null;
        _result = null;
        _breakdown = <_IngredientBreakdown>[];
        _clarifications = <_Clarification>[];
        final qs = raw['clarification_questions'];
        if (qs is List) {
          _preQuestions = qs
              .where((e) => e is Map)
              .map((e) => _PreAnalysisQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
              .where((q) => q.options.isNotEmpty)
              .toList();
        }
        if (_preQuestions.isEmpty) {
          _error = 'احتجنا توضيح بسيط، لكن لم تصل الخيارات بشكل صحيح. حاول كتابة الوصف بتفصيل أكثر.';
        }
        return;
      }

      _preQuestions = <_PreAnalysisQuestion>[];
      _preAnswers.clear();
      _analysis = res;

      // ✅ نعرض اسم الوجبة كما كتبه المستخدم دائمًا
      _inputName = text;

      final List<_IngredientBreakdown> bd = <_IngredientBreakdown>[];
      final List<_Clarification> qs = <_Clarification>[];

      // تفصيل المكونات (إن توفر من السيرفر)
      final rawBd = raw['ingredients_breakdown'];
      if (rawBd is List) {
        for (final x in rawBd) {
          if (x is Map) {
            bd.add(_IngredientBreakdown.fromJson(Map<String, dynamic>.from(x)));
          }
        }
      }
      _breakdown = bd;

      // أسئلة التأكيد (إن توفرت)
      final rawQs = raw['clarifications'];
      if (rawQs is List) {
        for (final x in rawQs) {
          if (x is Map) {
            qs.add(_Clarification.fromJson(Map<String, dynamic>.from(x)));
          }
        }
      }
      _clarifications = qs;

      // إجمالي (يفضّل من تفصيل المكونات إذا موجود)
      if (_breakdown.isNotEmpty) {
        _sumKcal = _breakdown.fold(0.0, (a, b) => a + b.caloriesKcal);
        _sumP = _breakdown.fold(0.0, (a, b) => a + b.proteinG);
        _sumC = _breakdown.fold(0.0, (a, b) => a + b.carbsG);
        _sumF = _breakdown.fold(0.0, (a, b) => a + b.fatG);
      } else {
        _sumKcal = (res.calories ?? 0).toDouble();
        _sumP = (res.macros?['protein_g'] ?? 0).toDouble();
        _sumC = (res.macros?['carbs_g'] ?? 0).toDouble();
        _sumF = (res.macros?['fat_g'] ?? 0).toDouble();
      }

      // جهّز حقول تعديل الجرامات (للمكوّنات غير المؤكدة)
      for (final q in _clarifications) {
        final key = q.ingredient;
        _gramsCtrls[key] = TextEditingController(
          text:
              (q.suggestedGrams > 0 ? q.suggestedGrams : 0).toStringAsFixed(0),
        );
      }

      _result = {
        'الاسم': _inputName,
        'السعرات (ك.س)': _sumKcal.toStringAsFixed(0),
        'بروتين (غ)': _sumP.toStringAsFixed(0),
        'كارب (غ)': _sumC.toStringAsFixed(0),
        'دهون (غ)': _sumF.toStringAsFixed(0),
        'الثقة': res.confidence != null
            ? '${(res.confidence!.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%'
            : '—',
      };
    });
  }

  List<Map<String, dynamic>> _selectedClarificationAnswers() {
    return _preQuestions.map((q) {
      final selectedValue = _preAnswers[q.id];
      final selected = q.options.firstWhere(
        (o) => o.value == selectedValue,
        orElse: () => const _PreAnalysisOption(label: '', value: '', append: ''),
      );
      return <String, dynamic>{
        'id': q.id,
        'title': q.title,
        'question': q.question,
        'ingredient': q.ingredient,
        'answer': <String, dynamic>{
          'label': selected.label,
          'value': selected.value,
          'append': selected.append,
        },
      };
    }).where((m) {
      final a = m['answer'];
      return a is Map && (a['value'] ?? '').toString().trim().isNotEmpty;
    }).toList();
  }

  Widget _buildPreClarificationCard() {
    if (_preQuestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allAnswered = _preQuestions.every((q) => (_preAnswers[q.id] ?? '').trim().isNotEmpty);

    return Expanded(
      child: ListView(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.tips_and_updates_rounded, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تأكيد سريع قبل التحليل',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'جاوب على أكثر نقطة مؤثرة عشان وازن يحسب وجبتك بدقة أعلى.',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ..._preQuestions.map((q) {
                  final selected = _preAnswers[q.id];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            q.title,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            q.question,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (q.reason.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              q.reason,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: q.options.map((o) {
                              final isSelected = selected == o.value;
                              return ChoiceChip(
                                selected: isSelected,
                                label: Text(o.label),
                                onSelected: (_) {
                                  setState(() => _preAnswers[q.id] = o.value);
                                },
                                selectedColor: cs.primary.withOpacity(0.16),
                                side: BorderSide(
                                  color: isSelected ? cs.primary : cs.outlineVariant,
                                ),
                                labelStyle: TextStyle(
                                  color: isSelected ? cs.primary : cs.onSurface,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: allAnswered && !_loading
                      ? () => _analyze(withClarificationAnswers: true)
                      : null,
                  icon: const Icon(Icons.analytics_rounded),
                  label: const Text('ابدأ التحليل الدقيق'),
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _preQuestions = <_PreAnalysisQuestion>[];
                            _preAnswers.clear();
                          });
                          _analyze(withClarificationAnswers: true);
                        },
                  child: const Text('تخطي وسوِّ تحليل تقديري'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _emojiStyle(double size) {
    String? family;
    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          family = 'Apple Color Emoji';
          break;
        case TargetPlatform.android:
          family = 'Noto Color Emoji';
          break;
        case TargetPlatform.windows:
          family = 'Segoe UI Emoji';
          break;
        default:
          family = null;
      }
    }
    return TextStyle(
      fontSize: size,
      height: 1.0,
      fontFamily: family,
      fontFamilyFallback: const [
        'Apple Color Emoji',
        'Noto Color Emoji',
        'Segoe UI Emoji',
      ],
    );
  }

  Widget _macroLine({
    required String title,
    required String emoji,
    required String valueText,
    required String unit,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Text(emoji, style: _emojiStyle(18)),
          const Spacer(),
          Text(
            valueText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          Text(unit, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }

  Widget _buildInlineMacrosCard() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final cal = _sumKcal.round();
    final p = _sumP.round();
    final c = _sumC.round();
    final f = _sumF.round();

    final confRaw = _analysis?.confidence;
    final conf = confRaw == null ? null : confRaw.clamp(0.0, 1.0);
    final confText = conf == null ? '—' : '${(conf * 100).toStringAsFixed(0)}%';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _macroLine(
              title: 'السعرات', emoji: '🔥', valueText: '$cal', unit: 'kcal'),
          Divider(height: 1, color: cs.outlineVariant),
          _macroLine(
              title: 'البروتين', emoji: '🥩', valueText: '$p', unit: 'غ'),
          Divider(height: 1, color: cs.outlineVariant),
          _macroLine(
              title: 'الكربوهيدرات', emoji: '🍞', valueText: '$c', unit: 'غ'),
          Divider(height: 1, color: cs.outlineVariant),
          _macroLine(title: 'الدهون', emoji: '🥑', valueText: '$f', unit: 'غ'),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'نسبة الثقة',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Text('🎯', style: _emojiStyle(18)),
              const Spacer(),
              Text(
                confText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: conf ?? 0,
              minHeight: 10,
              backgroundColor: cs.surfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    final name = _inputName.trim().isNotEmpty
        ? _inputName.trim()
        : (((_analysis?.foodName ?? 'وجبة').trim().isEmpty)
            ? 'وجبة'
            : (_analysis?.foodName ?? 'وجبة'));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Text('🍽️', style: _emojiStyle(22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final decision = _analysis?.decision;
    final confidence = _analysis?.confidence;
    final reasons = _analysis?.reasons;

    String confText = '—';
    if (confidence != null) {
      confText = '${(confidence * 100).toStringAsFixed(0)}%';
    }

    final String reasonsText =
        (reasons?.isNotEmpty ?? false) ? reasons!.join(' • ') : '—';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تفاصيل التحليل',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text('القرار: ${decision ?? '—'}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('الثقة: $confText', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text('الأسباب:',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(reasonsText, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  List<String> _extractRawIngredients() {
    final raw = _analysis?.raw;
    if (raw == null) return const <String>[];
    final v = raw['ingredients'];
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (v is String) {
      return v
          .split(RegExp(r'[,،;\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  void _recomputeTotals() {
    if (_breakdown.isNotEmpty) {
      _sumKcal = _breakdown.fold(0.0, (a, b) => a + b.caloriesKcal);
      _sumP = _breakdown.fold(0.0, (a, b) => a + b.proteinG);
      _sumC = _breakdown.fold(0.0, (a, b) => a + b.carbsG);
      _sumF = _breakdown.fold(0.0, (a, b) => a + b.fatG);
    }
    _result = {
      'الاسم': _inputName,
      'السعرات (ك.س)': _sumKcal.toStringAsFixed(0),
      'بروتين (غ)': _sumP.toStringAsFixed(0),
      'كارب (غ)': _sumC.toStringAsFixed(0),
      'دهون (غ)': _sumF.toStringAsFixed(0),
      'الثقة': _analysis?.confidence != null
          ? '${((_analysis!.confidence!).clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%'
          : '—',
    };
  }

  void _applyQuickConfirm() {
    if (_breakdown.isEmpty || _clarifications.isEmpty) return;

    for (final q in _clarifications) {
      final ctrl = _gramsCtrls[q.ingredient];
      if (ctrl == null) continue;
      final newG = double.tryParse(ctrl.text.trim());
      if (newG == null || newG <= 0) continue;

      // أفضل تطابق: اسم عربي مساوي، وإلا يحتوي
      _IngredientBreakdown? hit;
      for (final b in _breakdown) {
        if (b.nameAr.trim() == q.ingredient.trim()) {
          hit = b;
          break;
        }
      }
      if (hit == null) {
        for (final b in _breakdown) {
          if (b.nameAr.contains(q.ingredient) ||
              q.ingredient.contains(b.nameAr)) {
            hit = b;
            break;
          }
        }
      }
      if (hit == null) continue;

      hit.rescale(newG);
    }

    _recomputeTotals();
  }

  Widget _buildClarificationsCard() {
    if (_breakdown.isEmpty || _clarifications.isEmpty)
      return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تأكيد سريع لرفع الدقة',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              'إذا لم يكن التطبيق متأكدًا من كمية بعض المكونات، عدّل الجرامات ثم حدّث الحساب.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            ..._clarifications.map((q) {
              final ctrl = _gramsCtrls[q.ingredient] ??
                  TextEditingController(
                      text: q.suggestedGrams.toStringAsFixed(0));
              _gramsCtrls[q.ingredient] = ctrl;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(q.question,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: false),
                            decoration: InputDecoration(
                              hintText: 'جرام',
                              prefixIcon: const Icon(Icons.scale_rounded),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('جم'),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: () {
                setState(_applyQuickConfirm);
              },
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('تحديث الحساب'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientsCard() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (_analysis == null) return const SizedBox.shrink();

    // 1) لو التفصيل موجود: اعرض سعرات لكل مكوّن
    if (_breakdown.isNotEmpty) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('المكونات',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              ..._breakdown.map((b) {
                final kcal = b.caloriesKcal.isFinite ? b.caloriesKcal : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.nameAr,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (b.confidence > 0)
                              Text(
                                'الثقة: ${(b.confidence * 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      Text('${kcal.toStringAsFixed(0)} kcal',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 10),
                      Text(b.quantityLabel,
                          style: theme.textTheme.labelLarge),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      );
    }

    // 2) لو ما عندنا تفصيل: اعرض أسماء المكونات (بدون سعرات لكل مكوّن)
    final ings = _extractRawIngredients();
    if (ings.isEmpty) return const SizedBox.shrink();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('المكونات',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ings
                  .map((x) => Chip(
                        label: Text(x),
                        side: BorderSide(color: cs.outlineVariant),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _gramsCtrls.forEach((_, c) => c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PremiumGate(
      feature: PremiumFeature.aiText,
      blurPreview: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('تحليل الطعام (نصي)')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                children: [
                  TextField(
                    controller: _ctrl,
                    maxLines: 5,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText:
                          'اكتب وصف الوجبة بالتفصيل (الكمية/المكونات/الصَلصات ...)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : () => _analyze(),
                      icon: const Icon(Icons.analytics_rounded),
                      label: const Text('حلّل الوصف'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.error.withOpacity(.25)),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  if (_preQuestions.isNotEmpty && _result == null)
                    _buildPreClarificationCard(),
                  if (_result != null)
                    Expanded(
                      child: ListView(
                        children: [
                          if (_analysis != null && _analysis!.ok) ...[
                            _buildHeaderCard(),
                            const SizedBox(height: 12),
                            _buildInlineMacrosCard(),
                            const SizedBox(height: 12),
                            _buildIngredientsCard(),
                            const SizedBox(height: 12),
                            _buildClarificationsCard(),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  final payload = _toHomeSheetMap();
                                  Navigator.of(context).pop(payload);
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('إضافة للسجل'),
                              ),
                            ),
                          ] else ...[
                            ..._result!.entries.map((e) {
                              return Card(
                                elevation: 0.6,
                                child: ListTile(
                                  title: Text(
                                    e.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(e.value.toString()),
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _normalizeAnalysisJson(Map<String, dynamic> input) {
  final meal = input['meal'];
  final itemsRaw = input['items'];
  final totalsRaw = input['total_macros'];

  if (meal is Map || itemsRaw is List || totalsRaw is Map) {
    final mealMap =
        meal is Map ? Map<String, dynamic>.from(meal) : <String, dynamic>{};
    final totals = totalsRaw is Map
        ? Map<String, dynamic>.from(totalsRaw)
        : <String, dynamic>{};

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is! Map) continue;
        final it = Map<String, dynamic>.from(item);
        final est = it['est'] is Map
            ? Map<String, dynamic>.from(it['est'] as Map)
            : <String, dynamic>{};

        final grams = _toD(it['grams']) ?? _toD(it['g']) ?? 0;
        final ml = _toD(it['ml']) ?? 0;
        items.add(<String, dynamic>{
          'name_ar': it['name_ar'] ?? it['name'] ?? 'عنصر',
          'name_en': it['name_en'] ?? '',
          'grams': grams,
          'ml': ml,
          'quantity_label': it['quantity_label'] ??
              it['portion_desc_ar'] ??
              (grams > 0
                  ? '${grams.toStringAsFixed(0)} جم'
                  : (ml > 0 ? '${ml.toStringAsFixed(0)} مل' : 'حصة تقديرية')),
          'calories_kcal': _toD(est['kcal']) ?? _toD(it['calories_kcal']) ?? 0,
          'protein_g': _toD(est['protein_g']) ?? _toD(it['protein_g']) ?? 0,
          'carbs_g': _toD(est['carbs_g']) ?? _toD(it['carbs_g']) ?? 0,
          'fat_g': _toD(est['fat_g']) ?? _toD(it['fat_g']) ?? 0,
          'ingredient_confidence': _toD(it['confidence']) ?? 0,
          'confidence': _toD(it['confidence']) ?? 0,
          'match_score': _toD(it['confidence']) ?? 0,
        });
      }
    }

    double avgConfidence = 0;
    if (items.isNotEmpty) {
      avgConfidence = items.fold<double>(
            0,
            (sum, item) => sum + (_toD(item['confidence']) ?? 0),
          ) /
          items.length;
    }

    final List<Map<String, dynamic>> clarifications = <Map<String, dynamic>>[];
    final questions = input['questions'];
    if (questions is List) {
      for (final q in questions) {
        final s = q.toString().trim();
        if (s.isEmpty) continue;
        clarifications.add(<String, dynamic>{
          'ingredient': 'عام',
          'question': s,
          'suggested_grams': 0,
          'reason': 'clarification',
        });
      }
    }

    final totalKcal =
        _toD(totals['kcal']) ?? _toD(totals['calories_kcal']) ?? 0;
    final totalProtein = _toD(totals['protein_g']) ?? 0;
    final totalCarbs = _toD(totals['carbs_g']) ?? 0;
    final totalFat = _toD(totals['fat_g']) ?? 0;

    final name = (_toS(mealMap['name_ar']) ??
            _toS(input['dish_name']) ??
            _toS(input['name_ar']) ??
            _toS(input['name']) ??
            'وجبة')
        .trim();

    final reasons = <String>[
      if ((_toS(input['wazin_analysis']) ?? '').trim().isNotEmpty)
        (_toS(input['wazin_analysis']) ?? '').trim(),
    ];

    return <String, dynamic>{
      'ok': true,
      'food_name': name,
      'name': name,
      'calories_kcal': totalKcal,
      'protein_g': totalProtein,
      'carbs_g': totalCarbs,
      'fat_g': totalFat,
      'macros': <String, dynamic>{
        'protein_g': totalProtein,
        'carbs_g': totalCarbs,
        'fat_g': totalFat,
      },
      'confidence': _toD(input['confidence']) ?? avgConfidence,
      'decision': (input['need_clarification'] == true) ? 'clarify' : 'ok',
      'reasons': reasons,
      'ingredients': items.map((e) => (e['name_ar'] ?? '').toString()).toList(),
      'ingredients_breakdown': items,
      'clarifications': clarifications,
      'serving_size_g': _toD(input['portion_grams']),
      'serving_desc': _toS(input['portion_desc_ar']),
      'portion': <String, dynamic>{
        'grams': _toD(input['portion_grams']),
        'desc': _toS(input['portion_desc_ar']),
      },
      'raw_original': input,
    };
  }

  return input;
}

String _callableErrorMessage(Map<String, dynamic> err) {
  final message = (_toS(err['message']) ?? '').trim();
  final status = (_toS(err['status']) ?? '').trim();
  final details = err['details'];

  if (details is Map) {
    final detailMsg =
        (_toS(details['message']) ?? _toS(details['error']) ?? '').trim();
    if (detailMsg.isNotEmpty) return detailMsg;
  }

  if (details is String && details.trim().isNotEmpty) {
    return details.trim();
  }

  if (message.isNotEmpty) return message;
  if (status.isNotEmpty) return status;
  return 'تعذر تنفيذ تحليل النص.';
}

// ---------- Helpers (library-level) ----------
// These helpers are used across multiple models/widgets in this file.
// Keep them top-level so they are visible everywhere in this library.

double? _toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1.0 : 0.0;
  if (v is String) {
    var s = v.trim();
    if (s.isEmpty) return null;

    // حوّل الأرقام العربية/الفارسية إلى إنجليزية
    const digits = <String, String>{
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
    };
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      sb.write(digits[ch] ?? ch);
    }
    s = sb.toString();

    // نظّف الفواصل/الوحدات (مثل: "230 kcal", "١٢٫٥")
    s = s.replaceAll('٬', '');
    s = s.replaceAll('،', '.');
    s = s.replaceAll(',', '.');

    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }
  return null;
}

String? _toS(dynamic v) => v?.toString();

List<String>? _toStringList(dynamic v) {
  if (v == null) return null;
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String) return v.split(',').map((e) => e.trim()).toList();
  return null;
}

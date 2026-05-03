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
import 'package:cloud_functions/cloud_functions.dart';

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
    // دعم شكلين للماكروز: داخل "macros" أو مفاتيح مسطحة
    Map<String, double>? _macros;
    final m = json['macros'];
    if (m is Map) {
      _macros = {
        'protein_g': _toD(m['protein_g']) ?? 0.0,
        'carbs_g': _toD(m['carbs_g']) ?? 0.0,
        'fat_g': _toD(m['fat_g']) ?? 0.0,
      };
    } else {
      // fallback من مفاتيح مسطّحة
      final p = _toD(json['protein_g']);
      final c = _toD(json['carbs_g']);
      final f = _toD(json['fat_g']);
      if (p != null || c != null || f != null) {
        _macros = {
          'protein_g': p ?? 0.0,
          'carbs_g': c ?? 0.0,
          'fat_g': f ?? 0.0,
        };
      }
    }

    // الحصّة (portion) إن وجدت
    Map<String, dynamic>? _portion;
    final p = json['portion'];
    if (p is Map) {
      _portion = {
        'grams': (p['grams'] is num) ? (p['grams'] as num).toDouble() : _toD(json['serving_size_g']),
        'desc': p['desc'] ?? json['serving_desc'],
      };
    } else {
      // fallback: لو عندنا serving_size_g بدون map
      final grams = _toD(json['serving_size_g']);
      if (grams != null) {
        _portion = {'grams': grams, 'desc': json['serving_desc']};
      }
    }

    // السعرات: دعم calories أو calories_kcal
    final calories = _toD(json['calories']) ?? _toD(json['calories_kcal']);

    final reasons = _toStringList(json['reasons']) ??
        _toStringList(json['notes']) ??
        _toStringList(json['messages']);

    return MealAnalysisResult(
      ok: (json['ok'] is bool) ? json['ok'] as bool : true,
      foodName: _toS(json['food_name']) ?? _toS(json['name']) ?? _toS(json['title']),
      calories: calories,
      macros: _macros,
      portion: _portion,
      decision: _toS(json['decision']),
      confidence: _toD(json['confidence']),
      reasons: reasons,
      raw: json,
    );
  }

  factory MealAnalysisResult.error(String message, {Map<String, dynamic>? raw}) {
    return MealAnalysisResult(ok: false, errorMessage: message, raw: raw);
  }

  static double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
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

  Future<MealAnalysisResult> analyzeText({
    required String description,
    Map<String, dynamic>? profile,
    String? imageBase64, // احتفظنا فيها لدعم البروكسي القديم
  }) async {
    if (description.trim().isEmpty) {
      return MealAnalysisResult.error('يرجى كتابة وصف للوجبة أولًا.');
    }

    if (_useProxy) {
      // === المسار القديم: HTTP Proxy يبقى كما هو ===
      return _callProxy(
        description: description,
        profile: profile,
        imageBase64: imageBase64,
      );
    } else {
      // === المسار الجديد: Firebase Functions (Callable) ===
      return _callFunctions(description: description);
    }
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
        final isJson =
            contentType.contains('application/json') || contentType.contains('+json');

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          if (isJson) {
            final decoded =
                jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
            final core =
                (decoded['data'] is Map) ? decoded['data'] as Map<String, dynamic> : decoded;

            if (core['ok'] == false) {
              final msg = core['error']?.toString() ?? 'فشل التحليل من السيرفر.';
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
        return MealAnalysisResult.error('خطأ غير متوقع أثناء التحليل: $e');
      }
    }
  }

  // --------- 2) المسار الجديد (Firebase Functions Callable) ----------
  Future<MealAnalysisResult> _callFunctions({required String description}) async {
    try {
      // تأكد من وجود مستخدم (لو عندك enforceAppCheck+auth على الفنكشن)
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      final fns = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = fns.httpsCallable('analyzeMealText');
      final res = await callable.call(<String, dynamic>{'description': description.trim()});

      // بعض نسخ SDK تُرجع Map مباشرة، نتعامل مع الحالتين
      final data = (res.data is Map<String, dynamic>)
          ? res.data as Map<String, dynamic>
          : Map<String, dynamic>.from(res.data as Map);

      // إن احتاجت الواجهة شكلًا معينًا، يحوّله الـ fromJson
      return MealAnalysisResult.fromJson(data);
    } on FirebaseFunctionsException catch (e) {
      return MealAnalysisResult.error(e.message ?? 'تعذّر استدعاء الوظيفة: ${e.code}');
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MealAnalysisService (functions) error: $e\n$st');
      }
      return MealAnalysisResult.error('تعذّر إجراء التحليل عبر Cloud Functions: $e');
    }
  }
}

/// ==========================
/// شاشة التحليل (نصي) + Bridge لـ home_screen
/// ==========================
class AnalyzeMeal {
  static Future<void> launch(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MealTextAnalysisScreen()),
    );
  }
}

class MealTextAnalysisScreen extends StatefulWidget {
  const MealTextAnalysisScreen({super.key});

  @override
  State<MealTextAnalysisScreen> createState() => _MealTextAnalysisScreenState();
}

class _MealTextAnalysisScreenState extends State<MealTextAnalysisScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _analyze() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'اكتب وصف الوجبة أولًا.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    final svc = MealAnalysisService();
    final res = await svc.analyzeText(description: text);

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _result = {
          'الاسم': res.foodName ?? '—',
          'السعرات (ك.س)': res.calories?.toStringAsFixed(0) ?? '—',
          'بروتين (غ)': res.macros?['protein_g']?.toStringAsFixed(0) ?? '0',
          'كارب (غ)': res.macros?['carbs_g']?.toStringAsFixed(0) ?? '0',
          'دهون (غ)': res.macros?['fat_g']?.toStringAsFixed(0) ?? '0',
          'القرار': res.decision ?? '—',
          'الثقة': res.confidence != null
              ? '${(res.confidence! * 100).toStringAsFixed(0)}%'
              : '—',
          'أسباب': (res.reasons?.isNotEmpty ?? false)
              ? res.reasons!.join(' • ')
              : '—',
        };
      } else {
        _error = res.errorMessage ??
            'تعذّر إجراء التحليل. تحقق من الاتصال ثم حاول مجددًا.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
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
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'اكتب وصف الوجبة بالتفصيل (الكمية/المكونات/الصَلصات ...)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _analyze,
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
                if (_result != null)
                  Expanded(
                    child: ListView(
                      children: _result!.entries.map((e) {
                        return Card(
                          elevation: 0.6,
                          child: ListTile(
                            title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(e.value.toString()),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

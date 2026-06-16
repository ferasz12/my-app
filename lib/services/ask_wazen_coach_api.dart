// lib/services/ask_wazen_coach_api.dart
// واجهة استدعاء Cloud Function الخاصة بميزة "مدرب وازن الذكي".

import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'ask_wazen_report.dart';

class CoachApiException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const CoachApiException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => message.isNotEmpty ? message : code;
}


class CoachAction {
  final String type;
  final String label;
  final String route;
  final Map<String, dynamic> payload;

  const CoachAction({
    required this.type,
    required this.label,
    this.route = '',
    this.payload = const <String, dynamic>{},
  });

  factory CoachAction.fromMap(Map<dynamic, dynamic> map) {
    return CoachAction(
      type: (map['type'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      route: (map['route'] ?? '').toString(),
      payload: (map['payload'] is Map)
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': type,
        'label': label,
        'route': route,
        'payload': payload,
      };
}

class CoachRecipeCard {
  final String id;
  final String title;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String goal;
  final String imageUrl;
  final String userName;
  final String userPhotoUrl;
  final List<String> ingredients;
  final String method;
  final String caption;
  final String route;

  const CoachRecipeCard({
    required this.id,
    required this.title,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.goal,
    this.imageUrl = '',
    this.userName = '',
    this.userPhotoUrl = '',
    this.ingredients = const <String>[],
    this.method = '',
    this.caption = '',
    this.route = '/recipes',
  });

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  static List<String> _toList(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((e) => e.trim().isNotEmpty).toList();
    }
    return const <String>[];
  }

  factory CoachRecipeCard.fromMap(Map<dynamic, dynamic> map) {
    final macros = map['macros'] is Map ? Map<dynamic, dynamic>.from(map['macros'] as Map) : const <dynamic, dynamic>{};
    final nutrition = map['nutrition'] is Map
        ? Map<dynamic, dynamic>.from(map['nutrition'] as Map)
        : const <dynamic, dynamic>{};
    final ingredients = _toList(map['ingredients']).isNotEmpty
        ? _toList(map['ingredients'])
        : _toList(map['items']);
    final methodRaw = map['method'] ?? map['instructions'] ?? map['steps'];
    final method = methodRaw is List ? methodRaw.map((e) => e.toString()).join('، ') : (methodRaw ?? '').toString();

    return CoachRecipeCard(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? map['name'] ?? '').toString(),
      calories: _toInt(map['calories'] ?? map['kcal'] ?? macros['calories'] ?? macros['kcal'] ?? nutrition['calories']),
      protein: _toInt(map['protein'] ?? map['proteinG'] ?? macros['protein'] ?? macros['proteinG'] ?? nutrition['protein']),
      carbs: _toInt(map['carbs'] ?? map['carb'] ?? map['carbsG'] ?? macros['carbs'] ?? macros['carb'] ?? nutrition['carbs']),
      fat: _toInt(map['fat'] ?? map['fatG'] ?? macros['fat'] ?? macros['fatG'] ?? nutrition['fat']),
      goal: (map['goal'] ?? map['targetGoal'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? map['photoUrl'] ?? map['image'] ?? '').toString(),
      userName: (map['userName'] ?? map['authorName'] ?? '').toString(),
      userPhotoUrl: (map['userPhotoUrl'] ?? map['authorPhotoUrl'] ?? '').toString(),
      ingredients: ingredients,
      method: method,
      caption: (map['caption'] ?? map['description'] ?? '').toString(),
      route: (map['route'] ?? '/recipes').toString(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'title': title,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'goal': goal,
        'imageUrl': imageUrl,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'ingredients': ingredients,
        'method': method,
        'caption': caption,
        'route': route,
      };
}


class CoachWorkoutExercise {
  final String name;
  final int sets;
  final int reps;
  final String note;

  const CoachWorkoutExercise({
    required this.name,
    required this.sets,
    required this.reps,
    this.note = '',
  });

  static int _toInt(dynamic v, {int def = 0}) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v') ?? def;
  }

  factory CoachWorkoutExercise.fromMap(Map<dynamic, dynamic> map) {
    return CoachWorkoutExercise(
      name: (map['name'] ?? map['exercise'] ?? map['title'] ?? '').toString(),
      sets: _toInt(map['sets'], def: 3),
      reps: _toInt(map['reps'], def: 10),
      note: (map['note'] ?? map['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'sets': sets,
        'reps': reps,
        if (note.trim().isNotEmpty) 'note': note,
      };
}

class CoachWorkoutDay {
  final String title;
  final List<CoachWorkoutExercise> items;

  const CoachWorkoutDay({required this.title, required this.items});

  factory CoachWorkoutDay.fromMap(Map<dynamic, dynamic> map) {
    final rawItems = map['items'] ?? map['exercises'] ?? map['workouts'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => CoachWorkoutExercise.fromMap(e))
            .where((e) => e.name.trim().isNotEmpty)
            .toList()
        : <CoachWorkoutExercise>[];
    return CoachWorkoutDay(
      title: (map['title'] ?? map['day'] ?? map['name'] ?? '').toString(),
      items: items,
    );
  }

  Map<String, dynamic> toLegacyMap() => <String, dynamic>{
        'title': title,
        'items': items.map((e) => e.toMap()).toList(),
      };

  Map<String, dynamic> toMap() => <String, dynamic>{
        'title': title,
        'items': items.map((e) => e.toMap()).toList(),
      };
}

class CoachWorkoutPlan {
  final String id;
  final String name;
  final String goal;
  final String summary;
  final List<CoachWorkoutDay> days;

  const CoachWorkoutPlan({
    required this.id,
    required this.name,
    required this.goal,
    required this.summary,
    required this.days,
  });

  factory CoachWorkoutPlan.fromMap(Map<dynamic, dynamic> map) {
    final rawDays = map['days'];
    final days = rawDays is List
        ? rawDays
            .whereType<Map>()
            .map((e) => CoachWorkoutDay.fromMap(e))
            .where((d) => d.title.trim().isNotEmpty && d.items.isNotEmpty)
            .toList()
        : <CoachWorkoutDay>[];
    return CoachWorkoutPlan(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? map['title'] ?? 'جدول مدرب وازن').toString(),
      goal: (map['goal'] ?? '').toString(),
      summary: (map['summary'] ?? map['description'] ?? '').toString(),
      days: days,
    );
  }

  Map<String, dynamic> toLegacyMap() => <String, dynamic>{
        'id': id.isNotEmpty ? id : 'coach_${DateTime.now().millisecondsSinceEpoch}',
        'name': name,
        'goal': goal,
        'summary': summary,
        'days': days.map((d) => d.toLegacyMap()).toList(),
        'createdByCoach': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

  Map<String, dynamic> toWorkoutDataMap() {
    final daysMap = <String, dynamic>{};
    for (final d in days) {
      daysMap[d.title] = d.items.map((e) => e.toMap()).toList();
    }
    return <String, dynamic>{
      'name': name,
      'goal': goal,
      'summary': summary,
      'days': daysMap,
      'isCustom': true,
      'createdByCoach': true,
    };
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'goal': goal,
        'summary': summary,
        'days': days.map((d) => d.toMap()).toList(),
      };
}


bool _isBlockedCoachProfileAction(CoachAction action) {
  final type = action.type.trim().toLowerCase();
  final route = action.route.trim().toLowerCase();
  final payloadText = jsonEncode(action.payload).toLowerCase();
  final joined = '$type $route $payloadText';
  return RegExp(
    r'(profile_update|update_profile|update_user_profile|edit_profile|set_weight|change_weight|set_height|change_height|change_goal|set_goal|weightkg|heightcm|targetweight)',
  ).hasMatch(joined);
}

class CoachResponse {
  final String reply;
  final List<CoachAction> actions;
  final List<CoachRecipeCard> recipes;
  final List<CoachWorkoutPlan> workoutPlans;

  const CoachResponse({
    required this.reply,
    this.actions = const <CoachAction>[],
    this.recipes = const <CoachRecipeCard>[],
    this.workoutPlans = const <CoachWorkoutPlan>[],
  });

  static List _firstList(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is List) return value;
    }
    return const [];
  }

  static List _recipeListFromData(Map<String, dynamic> data) => _firstList(data, const [
        'recipes',
        'recipeCards',
        'coachRecipes',
        'coachGeneratedRecipes',
        'generatedRecipes',
        'wazenRecipes',
        'recommendedRecipes',
        'suggestedRecipes',
      ]);

  static List _workoutPlanListFromData(Map<String, dynamic> data) => _firstList(data, const [
        'workoutPlans',
        'workoutPlanCards',
        'generatedWorkoutPlans',
        'plans',
      ]);

  factory CoachResponse.fromData(dynamic raw) {
    final data = (raw as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return CoachResponse(
      reply: AskWazenCoachApi.cleanReply(data['reply'] ?? data['text'] ?? data['message']),
      actions: (data['actions'] is List)
          ? (data['actions'] as List)
              .whereType<Map>()
              .map((e) => CoachAction.fromMap(e))
              .where((e) => e.label.trim().isNotEmpty)
              .where((e) => !_isBlockedCoachProfileAction(e))
              .toList()
          : const <CoachAction>[],
      recipes: _recipeListFromData(data)
          .whereType<Map>()
          .map((e) => CoachRecipeCard.fromMap(e))
          .where((e) => e.title.trim().isNotEmpty)
          .toList(),
      workoutPlans: _workoutPlanListFromData(data)
          .whereType<Map>()
          .map((e) => CoachWorkoutPlan.fromMap(e))
          .where((e) => e.name.trim().isNotEmpty && e.days.isNotEmpty)
          .toList(),
    );
  }
}

class AskWazenCoachApi {
  AskWazenCoachApi._();

  static const String _region = 'europe-west1';
  static const String _projectId = 'wazenfapp';
  static const String _functionName = 'askWazenCoach';

  static String _httpCodeToFunctionsCode(int statusCode, Map<String, dynamic> body) {
    final error = body['error'];
    final status = error is Map ? (error['status'] ?? '').toString().toLowerCase() : '';
    if (status.isNotEmpty) {
      return status.replaceAll('_', '-');
    }
    switch (statusCode) {
      case 401:
        return 'unauthenticated';
      case 403:
        return 'permission-denied';
      case 404:
        return 'not-found';
      case 429:
        return 'resource-exhausted';
      case 500:
        return 'internal';
      default:
        return 'unknown';
    }
  }

  static String _httpErrorMessage(Map<String, dynamic> body, int statusCode) {
    final error = body['error'];
    if (error is Map) {
      final message = (error['message'] ?? error['details'] ?? '').toString().trim();
      if (message.isNotEmpty) return message;
    }
    return 'تعذّر الاتصال بمدرب وازن الآن. رمز الخطأ: $statusCode';
  }

  static Future<dynamic> _callViaHttp(Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const CoachApiException(
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لاستخدام مدرب وازن الذكي.',
      );
    }

    final uri = Uri.parse(
      'https://$_region-$_projectId.cloudfunctions.net/$_functionName',
    );

    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken(false);
    } catch (_) {
      appCheckToken = null;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer $token',
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'X-Firebase-AppCheck': appCheckToken,
    };

    final res = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, dynamic>{'data': payload}),
        )
        .timeout(const Duration(seconds: 45));

    Map<String, dynamic> body;
    try {
      body = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      body = <String, dynamic>{};
    }

    if (res.statusCode < 200 || res.statusCode >= 300 || body.containsKey('error')) {
      throw CoachApiException(
        code: _httpCodeToFunctionsCode(res.statusCode, body),
        message: _httpErrorMessage(body, res.statusCode),
        details: body['error'],
      );
    }

    return body['result'] ?? body['data'] ?? body;
  }

  static Future<dynamic> _callRaw(Map<String, dynamic> payload) async {
    // الاتصال هنا HTTP مباشر فقط بدون قناة Flutter Functions.
    return _callViaHttp(payload);
  }

  // بعض الردود قد تصل كنص JSON أو string مشفّر أو Markdown.
  // هذا يضمن عرض نص خام ونظيف داخل واجهة الشات.
  static String cleanReply(dynamic raw) {
    if (raw == null) return '';
    if (raw is Map) {
      final v = raw['response'] ??
          raw['reply'] ??
          raw['text'] ??
          raw['message'] ??
          raw['content'];
      return cleanReply(v);
    }
    if (raw is List) {
      return raw.map((e) => cleanReply(e)).where((s) => s.isNotEmpty).join('\n').trim();
    }

    var s = raw.toString().trim();
    if (s.isEmpty) return '';

    for (var i = 0; i < 3; i++) {
      final before = s;
      if (s.startsWith('```')) {
        s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
        s = s.replaceFirst(RegExp(r'```\s*$'), '');
        s = s.trim();
      }
      try {
        if ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith('{') && s.endsWith('}')) ||
            (s.startsWith('[') && s.endsWith(']'))) {
          final decoded = jsonDecode(s);
          final cleaned = cleanReply(decoded);
          if (cleaned.isNotEmpty) s = cleaned;
        }
      } catch (_) {
        // ignore
      }
      if (before == s) break;
    }

    final m = RegExp(r'"(?:response|reply|text|message|content)"\s*:\s*"([\s\S]*)"\s*\}?\s*$')
        .firstMatch(s);
    if (m != null) s = m.group(1) ?? s;

    s = s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\"', '"')
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll(RegExp(r'^[\s>*-]+', multiLine: true), '• ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (s.startsWith('"') && s.endsWith('"') && s.length > 1) {
      s = s.substring(1, s.length - 1).trim();
    }

    return s;
  }


  static Future<Map<String, dynamic>> updateUserProfile({
    required Map<String, dynamic> fields,
  }) async {
    throw const CoachApiException(
      code: 'permission-denied',
      message: 'مدرب وازن يقرأ بياناتك فقط ولا يملك صلاحية تعديل الوزن أو الطول أو الهدف.',
    );
  }


  static Map<String, dynamic> _readOnlyCoachRules() => const <String, dynamic>{
        'profileAccess': 'read_only',
        'forbidProfileWrites': true,
        'blockedFields': [
          'weight',
          'currentWeightKg',
          'targetWeightKg',
          'height',
          'heightCm',
          'goal',
          'gender',
          'age',
          'activityFactor',
          'caloriesNeeded',
          'protein',
          'carbs',
          'fat',
        ],
        'allowedOutputs': [
          'advice',
          'recipe_recommendations',
          'wazen_recipe_recommendations',
          'coach_generated_recipes',
          'generated_recipe_cards',
          'workout_plans',
        ],
      };

  /// إرسال تقرير اليوم يدويًا، وما زال مقفل مرة واحدة يوميًا من السيرفر.
  static Future<CoachResponse> sendDailyReport({
    required Map<String, dynamic> report,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const CoachApiException(
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لاستخدام مدرب وازن الذكي.',
      );
    }

    final ymd = (report['ymd'] ?? '').toString();
    final data = await _callRaw({
      'mode': 'daily',
      'ymd': ymd,
      'report': report,
      'clientRules': _readOnlyCoachRules(),
    });

    return CoachResponse.fromData(data);
  }

  /// رسالة دردشة عادية.
  /// يرسل تقريرًا خفيفًا تلقائيًا مع كل رسالة عشان المدرب يعرف الوزن/الطول/الماكروز فورًا.
  static Future<CoachResponse> chat({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const CoachApiException(
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول لاستخدام مدرب وازن الذكي.',
      );
    }

    Map<String, dynamic>? report;
    try {
      report = await AskWazenReportBuilder.build(days: 7);
    } catch (_) {
      report = null;
    }

    final data = await _callRaw({
      'mode': 'chat',
      'message': message,
      'history': history,
      if (report != null) 'report': report,
      'clientRules': _readOnlyCoachRules(),
      'coachCapabilities': {
        'canReadUserProfile': true,
        'canModifyUserProfile': false,
        'canCreateWorkoutPlans': true,
        'canRecommendRecipes': true,
        'canRecommendWazenRecipes': true,
        'canGenerateOwnRecipes': true,
        'canGenerateRecipeCards': true,
        'recipeSources': ['wazen_existing_recipes', 'coach_generated_recipes'],
        'recipeSourceRule':
            'When the user asks for a recipe, support two sources: existing Wazen recipes and new coach-generated recipes. If the message asks for coach recipes, generate a new recipe card yourself instead of saying you can only use Wazen recipes.',
      },
    });

    return CoachResponse.fromData(data);
  }
}

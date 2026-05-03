// lib/data/legacy_user_repository.dart
//
// ✅ Legacy Source of Truth (Firestore root doc): users/{uid}
//
// المطلوب:
// - لا نعتمد على users/{uid}/meta/* ولا users/{uid}/profile/* كمصدر أساسي.
// - مسموح فقط كـ fallback مؤقت للمهاجرة: إذا البيانات ناقصة في الجذر، نقرأ من الجديد ثم ننسخها للجذر مرة واحدة.
// - نستخدم Timestamp.now() بدل FieldValue.serverTimestamp.

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/diagnostics/firestore_diag.dart';
import '../core/diagnostics/onb_log.dart';
import '../models/weight_goal.dart';

class LegacyOnboardingStatus {
  final bool onboardingDone;
  final int onboardingStep;
  final int? lifestyleScore;

  const LegacyOnboardingStatus({
    required this.onboardingDone,
    required this.onboardingStep,
    this.lifestyleScore,
  });

  bool get done => onboardingDone;
  int get step => onboardingStep;
}

class LegacyUserRepository {
  const LegacyUserRepository();

  void _log(String event, {Map<String, Object?>? ctx}) {
    OnbLog.i('LegacyUserRepository', event, ctx: ctx);
    if (!kDebugMode) return;
    debugPrint('📦 [LegacyUserRepository] ${DateTime.now().toIso8601String()} | $event${ctx == null ? '' : ' | $ctx'}');
  }

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _profileBasic(String uid) =>
      _db.doc('users/$uid/profile/basic');
  DocumentReference<Map<String, dynamic>> _profileSocial(String uid) =>
      _db.doc('users/$uid/profile/social');

  DocumentReference<Map<String, dynamic>> _metaOnboarding(String uid) =>
      _db.doc('users/$uid/meta/onboarding');
  DocumentReference<Map<String, dynamic>> _metaFlags(String uid) =>
      _db.doc('users/$uid/meta/flags');
  DocumentReference<Map<String, dynamic>> _metaMetrics(String uid) =>
      _db.doc('users/$uid/meta/metrics');
  DocumentReference<Map<String, dynamic>> _metaGoal(String uid) =>
      _db.doc('users/$uid/meta/goal');

  User _requireUser() {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');
    return u;
  }

  // ------------------------------------------------------------
  // (1) Ensure root doc exists
  // ------------------------------------------------------------

  /// يضمن وجود users/{uid} بأقل حقول لازمة.
  ///
  /// ملاحظة: لا نعتمد على البنية الجديدة كمصدر رئيسي.
  /// لكن إن كانت بيانات الجذر ناقصة، نحاول قراءة الجديد مرة واحدة وننسخها للجذر (migration).
  Future<void> ensureLegacyUserDocExists() async {
    final u = _requireUser();
    final uid = u.uid;
    final ref = _userDoc(uid);
    final now = Timestamp.now();

    _log('ENSURE_ROOT_START', ctx: {
      'uid': uid,
      'email': (u.email ?? ''),
      'emailVerified': u.emailVerified,
    });

    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      _log('ENSURE_ROOT_READ_SERVER_OK', ctx: {'exists': snap.exists});
    } catch (e) {
      // لا نوقف التطبيق إذا فشل server read (قد تكون Offline)
      _log('ENSURE_ROOT_READ_SERVER_FAILED', ctx: {'err': e.toString()});
      try {
        snap = await ref.get(const GetOptions(source: Source.cache));
        _log('ENSURE_ROOT_READ_CACHE_OK', ctx: {'exists': snap.exists});
      } catch (e2) {
        _log('ENSURE_ROOT_READ_CACHE_FAILED', ctx: {'err': e2.toString()});
      }
    }

    final exists = snap?.exists == true;
    final existing = snap?.data() ?? <String, dynamic>{};

    final createPayload = <String, dynamic>{
      'uid': uid,
      'email': (u.email ?? '').trim(),
      'username': (u.displayName ?? '').trim(),
      'username_lower': (u.displayName ?? '').trim().toLowerCase(),
      if ((u.photoURL ?? '').trim().isNotEmpty) 'photoUrl': u.photoURL!.trim(),
      'bio': existing['bio'] ?? '',
      'social': existing['social'] ?? <String, dynamic>{},
      'onboardingStep': existing['onboardingStep'] ?? 0,
      'onboardingDone': existing['onboardingDone'] ?? false,
      'flags': existing['flags'] ?? {
        'lifestyleAssessmentCompleted': false,
        'userDataEntered': false,
        'onboardingComplete': false,
        'updatedAt': now,
      },
      'metrics': existing['metrics'] ?? {'updatedAt': now},
      'createdAt': existing['createdAt'] ?? now,
      'updatedAt': now,
    };

    try {
      if (!exists) {
        _log('ENSURE_ROOT_CREATE_ATTEMPT');
        await ref.set(createPayload, SetOptions(merge: true));
        _log('ENSURE_ROOT_CREATED');
      } else {
        // Patch فقط (بدون Transaction) لتفادي internal invariant errors
        final patch = <String, dynamic>{'updatedAt': now};

        if (!(existing['uid'] is String) || (existing['uid'] as String).trim().isEmpty) {
          patch['uid'] = uid;
        }

        final email = (u.email ?? '').trim();
        if (email.isNotEmpty) {
          final cur = (existing['email'] ?? '').toString().trim();
          if (cur.isEmpty) patch['email'] = email;
        }

        final photo = (u.photoURL ?? '').trim();
        if (photo.isNotEmpty) {
          final cur = (existing['photoUrl'] ?? '').toString().trim();
          if (cur.isEmpty) patch['photoUrl'] = photo;
        }

        if (!existing.containsKey('onboardingStep')) patch['onboardingStep'] = 0;
        if (!existing.containsKey('onboardingDone')) patch['onboardingDone'] = false;
        if (!existing.containsKey('flags')) {
          patch['flags'] = {
            'lifestyleAssessmentCompleted': false,
            'userDataEntered': false,
            'onboardingComplete': false,
            'updatedAt': now,
          };
        }
        if (!existing.containsKey('metrics')) {
          patch['metrics'] = {'updatedAt': now};
        }
        if (!existing.containsKey('createdAt')) patch['createdAt'] = now;

        if (patch.keys.length > 1) {
          _log('ENSURE_ROOT_PATCH_ATTEMPT', ctx: {'fields': patch.keys.toList()});
          await ref.set(patch, SetOptions(merge: true));
          _log('ENSURE_ROOT_PATCH_OK');
        } else {
          _log('ENSURE_ROOT_PATCH_SKIP');
        }
      }
    } on FirebaseException catch (e, st) {
      _log('ENSURE_ROOT_FIREBASE_EXCEPTION', ctx: {'code': e.code, 'message': e.message});
      OnbLog.e('LegacyUserRepository', 'ENSURE_ROOT_FIREBASE_EXCEPTION', e, st);
      // تشخيص إضافي: هل أصلًا ممكن تكتب على users/{uid} ؟
      try {
        await FirestoreDiag.diagnoseWrite(
          tag: 'ensureLegacyUserDocExists',
          ref: ref,
          payload: {
            'diagPing': DateTime.now().toIso8601String(),
            'stage': 'LegacyUserRepository.ensureLegacyUserDocExists',
          },
          confirmField: 'diagEnsureWriteId',
        );
      } catch (e2) {
        _log('ENSURE_ROOT_DIAG_FAILED', ctx: {'err': e2.toString()});
      }
      rethrow;
    }

    // محاولة مهاجرة (Best-effort) إذا في نقص بالجذر
    try {
      final rootSnap = await ref.get(const GetOptions(source: Source.server));
      await _migrateFromNewSchemaIfNeeded(uid, rootSnap.data() ?? const <String, dynamic>{});
    } catch (_) {
      // تجاهل
    }

    _log('ENSURE_ROOT_DONE');
  }

  // ------------------------------------------------------------
  // (2) Load onboarding status (root source of truth)
  // ------------------------------------------------------------

  /// يقرأ onboardingDone/onboardingStep من الجذر users/{uid}.
  /// fallback:
  /// - استنتاج من flags / وجود weightGoal / etc
  /// - migration best-effort من المسارات الجديدة لو كانت القيم ناقصة في الجذر.
  Future<LegacyOnboardingStatus> loadOnboardingStatus({String? uid}) async {
    final u = _requireUser();
    final realUid = uid ?? u.uid;

    await ensureLegacyUserDocExists();

    // cache-first ثم server
    Map<String, dynamic>? data;
    try {
      final cacheSnap = await _userDoc(realUid).get(const GetOptions(source: Source.cache));
      if (cacheSnap.exists) data = cacheSnap.data();
    } catch (_) {}

    data ??= (await _userDoc(realUid).get(const GetOptions(source: Source.server))).data();
    data ??= <String, dynamic>{};

    // مهاجرة لو ناقص
    try {
      await _migrateFromNewSchemaIfNeeded(realUid, data!);
      final refreshed = await _userDoc(realUid).get(const GetOptions(source: Source.server));
      data = refreshed.data() ?? data;
    } catch (_) {}

    final flags = (data?['flags'] is Map)
        ? Map<String, dynamic>.from(data?['flags'] as Map)
        : <String, dynamic>{};
    final metrics = (data?['metrics'] is Map)
        ? Map<String, dynamic>.from(data?['metrics'] as Map)
        : <String, dynamic>{};

    bool done = (data?['onboardingDone'] == true);
    int step = (data?['onboardingStep'] is num)
        ? (data?['onboardingStep'] as num).toInt()
        : 0;

    // fallback من flags/metrics (بدون اعتماد على meta/profile)
    final lifestyleCompleted = flags['lifestyleAssessmentCompleted'] == true;
    final userDataEntered = flags['userDataEntered'] == true;
    final onboardingComplete = flags['onboardingComplete'] == true;

    if (lifestyleCompleted) step = math.max(step, 1);
    if (userDataEntered) step = math.max(step, 2);

    final hasGoal = (data?['weightGoal'] is Map) ||
        (data?['targetWeightKg'] is num) ||
        (data?['targetDate'] is Timestamp);
    if (hasGoal) step = math.max(step, 3);

    if (onboardingComplete) {
      step = math.max(step, 4);
      done = true;
    }

    // metrics قد يحمل lifestyleScore
    final ls = metrics['lifestyleScore'];
    final lifestyleScore = (ls is num) ? ls.toInt() : null;

    // إذا done=true نضمن step>=4
    if (done) step = math.max(step, 4);

    return LegacyOnboardingStatus(
      onboardingDone: done,
      onboardingStep: step,
      lifestyleScore: lifestyleScore,
    );
  }

  // ------------------------------------------------------------
  // (3) Save onboarding steps
  // ------------------------------------------------------------

  /// يحفظ lifestyle + metrics + flags + onboardingStep>=1 في الجذر.
  Future<void> saveLifestyleStep({
    required Map<String, dynamic> answers,
    required int score,
    required String activityLevel,
    required double activityFactor,
  }) async {
    final u = _requireUser();
    final uid = u.uid;
    final now = Timestamp.now();

    await ensureLegacyUserDocExists();

    await _updateRootWithStepAtLeast(
      uid,
      stepAtLeast: 1,
      patch: {
        'lifestyle': {
          'answers': answers,
          'score': score,
          'activityLevel': activityLevel,
          'activityFactor': activityFactor,
          'updatedAt': now,
        },
        'metrics.lifestyleScore': score,
        'metrics.activityFactor': activityFactor,
        'metrics.updatedAt': now,
        'flags.lifestyleAssessmentCompleted': true,
        'flags.updatedAt': now,
        'onboardingDone': false,
        'updatedAt': now,
      },
    );
  }

  /// يحفظ gender/age/heightCm/currentWeightKg/bio/social/goal + metrics + flags + onboardingStep>=2 في الجذر.
  Future<void> saveUserInputStep({
    required String gender,
    required int age,
    required double heightCm,
    required double currentWeightKg,
    required String bio,
    required Map<String, dynamic> social,
    String? goal,
    String? goalType,
    required double caloriesNeeded,
    required double maintenanceCalories,
    required double protein,
    required double carbs,
    required double fat,
    required int lifestyleScore,
    required double activityFactor,
  }) async {
    final u = _requireUser();
    final uid = u.uid;
    final now = Timestamp.now();

    await ensureLegacyUserDocExists();

    final patch = <String, dynamic>{
      'gender': gender,
      'age': age,
      'heightCm': heightCm,
      'currentWeightKg': currentWeightKg,
      'bio': bio,
      'social': social,
      if (goal != null) 'goal': goal,
      if (goalType != null) 'goalType': goalType,
      // metrics (dot-notation لتفادي استبدال كامل map)
      'metrics.caloriesNeeded': caloriesNeeded,
      'metrics.maintenanceCalories': maintenanceCalories,
      'metrics.protein': protein,
      'metrics.carbs': carbs,
      'metrics.fat': fat,
      'metrics.lifestyleScore': lifestyleScore,
      'metrics.activityFactor': activityFactor,
      if (goalType != null) 'metrics.goalType': goalType,
      'metrics.updatedAt': now,
      // flags
      'flags.lifestyleAssessmentCompleted': true,
      'flags.userDataEntered': true,
      'flags.updatedAt': now,
      'onboardingDone': false,
      'updatedAt': now,
    };

    await _updateRootWithStepAtLeast(uid, stepAtLeast: 2, patch: patch);
  }

  /// يحفظ weightGoal + mirror root fields (currentWeightKg/targetWeightKg/targetDate) + onboardingStep>=3 في الجذر.
  Future<void> saveGoalStep({required WeightGoal goal}) async {
    final u = _requireUser();
    final uid = u.uid;
    final now = Timestamp.now();

    await ensureLegacyUserDocExists();

    await _updateRootWithStepAtLeast(
      uid,
      stepAtLeast: 3,
      patch: {
        'weightGoal': goal.toMap(),
        // mirror
        'currentWeightKg': goal.currentWeight,
        'targetWeightKg': goal.targetWeight,
        'targetDate': Timestamp.fromDate(goal.targetDate),
        'onboardingDone': false,
        'updatedAt': now,
      },
    );
  }

  /// يحفظ onboardingDone=true + onboardingStep>=4 + flags.onboardingComplete=true في الجذر.
  Future<void> finishOnboarding() async {
    final u = _requireUser();
    final uid = u.uid;
    final now = Timestamp.now();

    await ensureLegacyUserDocExists();

    await _updateRootWithStepAtLeast(
      uid,
      stepAtLeast: 4,
      patch: {
        'onboardingDone': true,
        'flags.onboardingComplete': true,
        'flags.updatedAt': now,
        'completedAt': now,
        'updatedAt': now,
      },
    );
  }

  // ------------------------------------------------------------
  // Helpers used by non-onboarding pages
  // ------------------------------------------------------------

  /// تحديث عام للجذر (merge) بدون إنقاص onboardingStep.
  Future<void> updateLegacyUserRoot({
    required Map<String, dynamic> patch,
    int? stepAtLeast,
    bool? setOnboardingDone,
  }) async {
    final u = _requireUser();
    final uid = u.uid;
    await ensureLegacyUserDocExists();

    if (stepAtLeast != null) {
      await _updateRootWithStepAtLeast(uid, stepAtLeast: stepAtLeast, patch: {
        ...patch,
        if (setOnboardingDone != null) 'onboardingDone': setOnboardingDone,
      });
    } else {
      final now = Timestamp.now();
      await _userDoc(uid).set({
        ...patch,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }
  }

  // ------------------------------------------------------------
  // Internal: step-safe update (no regress)
  // ------------------------------------------------------------

  Future<void> _updateRootWithStepAtLeast(
    String uid, {
    required int stepAtLeast,
    required Map<String, dynamic> patch,
  }) async {
    final ref = _userDoc(uid);

    int curStep = 0;
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final data = snap.data() ?? <String, dynamic>{};
      curStep = (data['onboardingStep'] is num)
          ? (data['onboardingStep'] as num).toInt()
          : 0;
    } catch (e) {
      _log('UPDATE_ROOT_READ_STEP_FAILED', ctx: {'uid': uid, 'err': e.toString()});
    }

    final nextStep = math.max(curStep, stepAtLeast);
    final merged = <String, dynamic>{
      ...patch,
      'onboardingStep': nextStep,
    };

    _log('UPDATE_ROOT_ATTEMPT', ctx: {
      'uid': uid,
      'curStep': curStep,
      'stepAtLeast': stepAtLeast,
      'nextStep': nextStep,
      'keys': merged.keys.take(12).toList(),
    });

    final issues = FirestoreDiag.validateEncodable(merged);
    if (issues.isNotEmpty) {
      _log('UPDATE_ROOT_BLOCK_INVALID_PAYLOAD', ctx: {'issues': issues});
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: 'Invalid payload: ${issues.join(', ')}',
      );
    }

    try {
      await ref.update(merged);
      _log('UPDATE_ROOT_OK', ctx: {'uid': uid, 'nextStep': nextStep});
    } on FirebaseException catch (e, st) {
      _log('UPDATE_ROOT_FIREBASE_EXCEPTION', ctx: {'code': e.code, 'message': e.message});
      OnbLog.e('LegacyUserRepository', 'UPDATE_ROOT_FIREBASE_EXCEPTION', e, st);

      if (e.code == 'not-found') {
        // إنشاء الوثيقة ثم إعادة المحاولة
        await ref.set({'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now()}, SetOptions(merge: true));
        await ref.update(merged);
        _log('UPDATE_ROOT_OK_AFTER_CREATE', ctx: {'uid': uid});
        return;
      }

      // تشخيص إضافي عندما يظهر internal/unavailable
      try {
        await FirestoreDiag.diagnoseUpdate(
          tag: 'updateRootWithStepAtLeast',
          ref: ref,
          payload: {
            'diagPing': DateTime.now().toIso8601String(),
            'stage': '_updateRootWithStepAtLeast',
            'stepAtLeast': stepAtLeast,
          },
          confirmField: 'diagUpdateRootId',
        );
      } catch (e2) {
        _log('UPDATE_ROOT_DIAG_FAILED', ctx: {'err': e2.toString()});
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // Migration: copy missing fields from new structure to root (one-way)
  // ------------------------------------------------------------

  Future<void> _migrateFromNewSchemaIfNeeded(
    String uid,
    Map<String, dynamic> root,
  ) async {
    final patch = <String, dynamic>{};
    final now = Timestamp.now();

    bool _missingString(String key) {
      final v = root[key];
      return !(v is String) || v.trim().isEmpty;
    }

    bool _missingNum(String key) {
      final v = root[key];
      return !(v is num);
    }

    bool _missingMap(String key) {
      final v = root[key];
      return !(v is Map);
    }

    // --------------------------------------------------
    // profile/basic -> root fields
    // --------------------------------------------------
    bool needBasic = _missingString('bio') ||
        _missingString('gender') ||
        _missingNum('age') ||
        _missingNum('heightCm') ||
        _missingNum('currentWeightKg');

    Map<String, dynamic>? basic;
    if (needBasic) {
      try {
        final snap = await _profileBasic(uid).get();
        basic = snap.data();
      } catch (_) {}
    }

    if (basic != null) {
      if (_missingString('bio')) {
        final v = (basic['bio'] as String?)?.trim();
        if (v != null && v.isNotEmpty) patch['bio'] = v;
      }
      if (_missingString('gender')) {
        final v = (basic['gender'] as String?)?.trim();
        if (v != null && v.isNotEmpty) patch['gender'] = v;
      }
      if (_missingNum('age')) {
        final v = basic['age'];
        if (v is num) patch['age'] = v.toInt();
      }
      if (_missingNum('heightCm')) {
        final v = basic['heightCm'];
        if (v is num) patch['heightCm'] = v.toDouble();
      }
      if (_missingNum('currentWeightKg')) {
        // بعض البنى كانت تستخدم weightKg
        final v = basic['currentWeightKg'] ?? basic['weightKg'];
        if (v is num) patch['currentWeightKg'] = v.toDouble();
      }
    }

    // --------------------------------------------------
    // profile/social -> root.social
    // --------------------------------------------------
    if (_missingMap('social')) {
      try {
        final snap = await _profileSocial(uid).get();
        final s = snap.data();
        if (s != null && s.isNotEmpty) {
          final social = <String, dynamic>{};
          for (final k in ['instagram', 'snapchat', 'tiktok']) {
            final v = (s[k] as String?)?.trim();
            if (v != null && v.isNotEmpty) social[k] = v;
          }
          if (social.isNotEmpty) patch['social'] = social;
        }
      } catch (_) {}
    }

    // --------------------------------------------------
    // meta -> root (onboarding/flags/metrics/goal) — fallback migration only
    // --------------------------------------------------

    if (!root.containsKey('onboardingStep') || !root.containsKey('onboardingDone')) {
      try {
        final snap = await _metaOnboarding(uid).get();
        final m = snap.data();
        if (m != null) {
          if (!root.containsKey('onboardingStep') && m['onboardingStep'] is num) {
            patch['onboardingStep'] = (m['onboardingStep'] as num).toInt();
          }
          if (!root.containsKey('onboardingDone') && m['onboardingDone'] is bool) {
            patch['onboardingDone'] = m['onboardingDone'] as bool;
          }
        }
      } catch (_) {}
    }

    // flags
    if (_missingMap('flags')) {
      try {
        final snap = await _metaFlags(uid).get();
        final m = snap.data();
        if (m != null && m.isNotEmpty) {
          patch['flags'] = {
            if (m['lifestyleAssessmentCompleted'] is bool)
              'lifestyleAssessmentCompleted': m['lifestyleAssessmentCompleted'],
            if (m['userDataEntered'] is bool) 'userDataEntered': m['userDataEntered'],
            if (m['onboardingComplete'] is bool) 'onboardingComplete': m['onboardingComplete'],
            'updatedAt': now,
          };
        }
      } catch (_) {}
    }

    // metrics
    if (_missingMap('metrics')) {
      try {
        final snap = await _metaMetrics(uid).get();
        final m = snap.data();
        if (m != null && m.isNotEmpty) {
          final metrics = <String, dynamic>{};
          for (final k in [
            'caloriesNeeded',
            'maintenanceCalories',
            'protein',
            'carbs',
            'fat',
            'lifestyleScore',
            'activityFactor',
            'goalType',
          ]) {
            final v = m[k];
            if (v is num || v is String || v is bool) metrics[k] = v;
          }
          metrics['updatedAt'] = now;
          if (metrics.isNotEmpty) patch['metrics'] = metrics;
        }
      } catch (_) {}
    }

    // goal
    if (!(root['weightGoal'] is Map)) {
      try {
        final snap = await _metaGoal(uid).get();
        final m = snap.data();
        if (m != null && m.isNotEmpty) {
          patch['weightGoal'] = m;
          // mirror إن كانت موجودة
          final cw = m['currentWeight'];
          final tw = m['targetWeight'];
          final td = m['targetDate'];
          if (_missingNum('currentWeightKg') && cw is num) patch['currentWeightKg'] = cw.toDouble();
          if (!(root['targetWeightKg'] is num) && tw is num) patch['targetWeightKg'] = tw.toDouble();
          if (!(root['targetDate'] is Timestamp) && td is Timestamp) patch['targetDate'] = td;
        }
      } catch (_) {}
    }

    if (patch.isEmpty) return;

    patch['updatedAt'] = now;

    // لا ننقص step حتى لو جاء من meta
    if (patch.containsKey('onboardingStep') && root['onboardingStep'] is num) {
      final cur = (root['onboardingStep'] as num).toInt();
      final inc = (patch['onboardingStep'] as num?)?.toInt() ?? 0;
      patch['onboardingStep'] = math.max(cur, inc);
    }

    await _userDoc(uid).set(patch, SetOptions(merge: true));
  }
}

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/weight_goal.dart';

class LegacyOnboardingStatus {
  final bool onboardingDone;
  final int onboardingStep;
  final int? lifestyleScore;
  const LegacyOnboardingStatus({required this.onboardingDone, required this.onboardingStep, this.lifestyleScore});
  bool get done => onboardingDone;
  int get step => onboardingStep;
}

class LegacyUserRepository {
  const LegacyUserRepository();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => _db.collection('users').doc(uid);

  User _requireUser() {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');
    return u;
  }

  
Future<void> ensureLegacyUserDocExists() async {
  final u = _requireUser();
  final uid = u.uid;
  final ref = _userDoc(uid);
  final now = Timestamp.now();

  DocumentSnapshot<Map<String, dynamic>>? snap;
  try {
    snap = await ref
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    snap = null;
  }

  if (snap == null || !snap.exists) {
    // Create بأسلوب best-effort (لا نوقف تسجيل الدخول لو فشل)
    try {
      await ref
          .set({
            'uid': uid,
            'email': (u.email ?? '').trim(),
            'username': (u.displayName ?? '').trim(),
            'username_lower': (u.displayName ?? '').trim().toLowerCase(),
            'onboardingStep': 0,
            'onboardingDone': false,
            'flags': {
              'lifestyleAssessmentCompleted': false,
              'userDataEntered': false,
              'onboardingComplete': false,
              'updatedAt': now,
            },
            'createdAt': now,
            'updatedAt': now,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}


Future<LegacyOnboardingStatus> loadOnboardingStatus({String? uid}) async {
  final u = _requireUser();
  final realUid = uid ?? u.uid;

  // 1) جرّب الكاش بسرعة (لتفادي تعليق أول مرة/شبكة ضعيفة)
  try {
    final cacheSnap = await _userDoc(realUid)
        .get(const GetOptions(source: Source.cache))
        .timeout(const Duration(seconds: 3));
    if (cacheSnap.exists) {
      final data = cacheSnap.data() ?? {};
      final done = (data['onboardingDone'] == true);
      final step = (data['onboardingStep'] is num) ? (data['onboardingStep'] as num).toInt() : 0;
      final lifestyleScore = (data['metrics']?['lifestyleScore'] is num)
          ? (data['metrics']['lifestyleScore'] as num).toInt()
          : null;

      return LegacyOnboardingStatus(
        onboardingDone: done,
        onboardingStep: step,
        lifestyleScore: lifestyleScore,
      );
    }
  } catch (_) {}

  // 2) ضمان وجود الوثيقة (Best-effort + Timeout)
  try {
    await ensureLegacyUserDocExists().timeout(const Duration(seconds: 15));
  } catch (_) {}

  // 3) قراءة serverAndCache بمهلة، ثم fallback افتراضي
  try {
    final snap = await _userDoc(realUid)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(const Duration(seconds: 15));
    final data = snap.data() ?? {};

    final done = (data['onboardingDone'] == true);
    final step = (data['onboardingStep'] is num) ? (data['onboardingStep'] as num).toInt() : 0;

    return LegacyOnboardingStatus(
      onboardingDone: done,
      onboardingStep: step,
      lifestyleScore: (data['metrics']?['lifestyleScore'] is num)
          ? (data['metrics']['lifestyleScore'] as num).toInt()
          : null,
    );
  } catch (_) {
    // لو Firestore علق/فشل: نرجع default ونكمل التطبيق
    return const LegacyOnboardingStatus(onboardingDone: false, onboardingStep: 0);
  }
}

// --- دوال الأونبوردنق ---

  Future<void> saveLifestyleStep({required Map<String, dynamic> answers, required int score, required String activityLevel, required double activityFactor}) async {
    await _updateRootWithStepAtLeast(_requireUser().uid, stepAtLeast: 1, patch: {
      'lifestyle': {'answers': answers, 'score': score, 'activityLevel': activityLevel, 'activityFactor': activityFactor, 'updatedAt': Timestamp.now()},
      'metrics.lifestyleScore': score,
      'metrics.activityFactor': activityFactor,
      'flags.lifestyleAssessmentCompleted': true,
      'onboardingDone': false,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> saveUserInputStep({required String gender, required int age, required double heightCm, required double currentWeightKg, required String bio, required Map<String, dynamic> social, String? goal, String? goalType, required double caloriesNeeded, required double maintenanceCalories, required double protein, required double carbs, required double fat, required int lifestyleScore, required double activityFactor}) async {
    await _updateRootWithStepAtLeast(_requireUser().uid, stepAtLeast: 2, patch: {
      'gender': gender, 'age': age, 'heightCm': heightCm, 'currentWeightKg': currentWeightKg, 'bio': bio, 'social': social,
      if (goal != null) 'goal': goal,
      'metrics.caloriesNeeded': caloriesNeeded, 'metrics.maintenanceCalories': maintenanceCalories,
      'metrics.protein': protein, 'metrics.carbs': carbs, 'metrics.fat': fat, 'metrics.lifestyleScore': lifestyleScore, 'metrics.activityFactor': activityFactor,
      'flags.userDataEntered': true, 'updatedAt': Timestamp.now(),
    });
  }

  Future<void> saveGoalStep({required WeightGoal goal}) async {
    await _updateRootWithStepAtLeast(_requireUser().uid, stepAtLeast: 3, patch: {
      'weightGoal': goal.toMap(),
      'targetWeightKg': goal.targetWeight,
      'onboardingDone': false,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> finishOnboarding() async {
    // ✅ بعد إضافة خطوة (GoalProgressOnboardingPage) أصبح إكمال الأونبوردنغ = الخطوة 5
    await _updateRootWithStepAtLeast(_requireUser().uid, stepAtLeast: 5, patch: {
      'onboardingDone': true,
      'flags.onboardingComplete': true,
      'updatedAt': Timestamp.now(),
    });
  }

  // --- الدالة المطلوبة لصفحة MyDataPage ---

  Future<void> updateLegacyUserRoot({required Map<String, dynamic> patch, int? stepAtLeast, bool? setOnboardingDone}) async {
    final uid = _requireUser().uid;
    await _userDoc(uid).set({
      ...patch,
      if (stepAtLeast != null) 'onboardingStep': stepAtLeast,
      if (setOnboardingDone != null) 'onboardingDone': setOnboardingDone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // المساعد الداخلي
  Future<void> _updateRootWithStepAtLeast(String uid, {required int stepAtLeast, required Map<String, dynamic> patch}) async {
    await _userDoc(uid).set({
      ...patch,
      'onboardingStep': stepAtLeast,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
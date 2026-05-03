// lib/data/user_repository.dart
//
// ✅ Repository موحّد على الجذر users/{uid} كمصدر بيانات وحيد (Source of Truth).
// ❗️لا يعتمد على users/{uid}/meta/* أو users/{uid}/profile/* كمصدر أساسي.
// ✅ مسموح استخدامها فقط كـ fallback مؤقت للمهاجرة: إذا كانت البيانات ناقصة في الجذر
//   نقرأ من البنية الجديدة ثم ننسخ للجذر مرة واحدة.
//
// ملاحظات:
// - يستخدم Timestamp.now() بدل FieldValue.serverTimestamp() لتفادي مشاكل Rules.
// - يحتفظ بنفس واجهة الدوال (API) قدر الإمكان حتى لا يكسر بقية التطبيق.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // User, ActionCodeSettings
import 'package:firebase_storage/firebase_storage.dart';

class UserRepository {
  const UserRepository();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;

  // ----------------------------
  // مراجع Firestore (الجذر)
  // ----------------------------

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _usernameDoc(String handle) =>
      _db.collection('usernames').doc(handle);

  // ----------------------------
  // مراجع Firestore (Fallback فقط للمهاجرة)
  // ----------------------------

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
  DocumentReference<Map<String, dynamic>> _metaPrefs(String uid) =>
      _db.doc('users/$uid/meta/prefs');
  DocumentReference<Map<String, dynamic>> _metaGoal(String uid) =>
      _db.doc('users/$uid/meta/goal');

  // ----------------------------
  // أدوات مساعدة
  // ----------------------------

  String _normalizeHandle(String raw) => raw.trim().toLowerCase();

  void _validateHandle(String handle) {
    if (handle.isEmpty) throw Exception('اسم المستخدم غير صالح');
    if (handle.length < 3) throw Exception('اسم المستخدم قصير جدًا');
    if (handle.length > 20) throw Exception('اسم المستخدم طويل جدًا');
    final ok = RegExp(r'^[a-z0-9_]+$').hasMatch(handle);
    if (!ok) throw Exception('اسم المستخدم يجب أن يكون أحرف/أرقام/شرطة سفلية فقط');
  }

  bool _isMissingValue(dynamic v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is Map) return v.isEmpty;
    if (v is Iterable) return v.isEmpty;
    return false;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  Timestamp _now() => Timestamp.now();

  /// يحاول مهاجرة بيانات من البنية الجديدة (meta/profile) إلى الجذر users/{uid} إذا كانت ناقصة.
  /// - يكتب إلى الجذر مرة واحدة فقط للحقول المفقودة.
  Future<void> _migrateFromNewStructureIfNeeded({
    required String uid,
    required Map<String, dynamic> rootData,
  }) async {
    final patch = <String, dynamic>{};
    final now = _now();

    // ----------------------------
    // basic/profile -> root fields
    // ----------------------------
    final needsBasic = _isMissingValue(rootData['firstName']) ||
        _isMissingValue(rootData['lastName']) ||
        _isMissingValue(rootData['gender']) ||
        rootData['age'] == null ||
        rootData['heightCm'] == null ||
        rootData['currentWeightKg'] == null ||
        _isMissingValue(rootData['bio']) ||
        _isMissingValue(rootData['photoUrl']);

    if (needsBasic) {
      final basicSnap = await _profileBasic(uid).get();
      final basic = basicSnap.data();

      if (basic != null) {
        void copyIfMissing(String key, dynamic value) {
          if (_isMissingValue(rootData[key]) && !_isMissingValue(value)) {
            patch[key] = value;
          }
        }

        copyIfMissing('firstName', basic['firstName']);
        copyIfMissing('lastName', basic['lastName']);
        copyIfMissing('gender', basic['gender']);

        if (rootData['age'] == null && basic['age'] is num) {
          patch['age'] = (basic['age'] as num).toInt();
        }
        if (rootData['heightCm'] == null && basic['heightCm'] is num) {
          patch['heightCm'] = (basic['heightCm'] as num).toDouble();
        }
        if (rootData['currentWeightKg'] == null &&
            basic['currentWeightKg'] is num) {
          patch['currentWeightKg'] = (basic['currentWeightKg'] as num).toDouble();
        }

        copyIfMissing('bio', basic['bio']);
        copyIfMissing('photoUrl', basic['photoUrl']);

        if (_isMissingValue(rootData['phone']) &&
            !_isMissingValue(basic['phone'])) {
          patch['phone'] = basic['phone'];
        }
        if (_isMissingValue(rootData['birthDate']) &&
            basic['birthDate'] is Timestamp) {
          patch['birthDate'] = basic['birthDate'];
        }
      }
    }

    // ----------------------------
    // social/profile -> root.social
    // ----------------------------
    final needsSocial = _isMissingValue(rootData['social']);
    if (needsSocial) {
      final socialSnap = await _profileSocial(uid).get();
      final social = socialSnap.data();
      if (social != null && social.isNotEmpty) {
        final nested = _asMap(social['social']);
        final socialMap = nested ?? social;
        if (socialMap.isNotEmpty) {
          patch['social'] = {
            if (!_isMissingValue(socialMap['instagram']))
              'instagram': socialMap['instagram'],
            if (!_isMissingValue(socialMap['snapchat']))
              'snapchat': socialMap['snapchat'],
            if (!_isMissingValue(socialMap['tiktok']))
              'tiktok': socialMap['tiktok'],
          };
        }
      }
    }

    // ----------------------------
    // flags/meta -> root.flags
    // ----------------------------
    final needsFlags = _isMissingValue(rootData['flags']);
    if (needsFlags) {
      final flagsSnap = await _metaFlags(uid).get();
      final flags = flagsSnap.data();
      if (flags != null && flags.isNotEmpty) {
        patch['flags'] = {
          if (flags['lifestyleAssessmentCompleted'] is bool)
            'lifestyleAssessmentCompleted': flags['lifestyleAssessmentCompleted'],
          if (flags['userDataEntered'] is bool)
            'userDataEntered': flags['userDataEntered'],
          if (flags['onboardingComplete'] is bool)
            'onboardingComplete': flags['onboardingComplete'],
        };
      }
    }

    // ----------------------------
    // metrics/meta -> root.metrics
    // ----------------------------
    final needsMetrics = _isMissingValue(rootData['metrics']);
    if (needsMetrics) {
      final metricsSnap = await _metaMetrics(uid).get();
      final metrics = metricsSnap.data();
      if (metrics != null && metrics.isNotEmpty) {
        final m = <String, dynamic>{};

        void putNum(String k) {
          final v = metrics[k];
          if (v is num) m[k] = v.toDouble();
        }

        putNum('caloriesNeeded');
        putNum('maintenanceCalories');
        putNum('protein');
        putNum('carbs');
        putNum('fat');
        putNum('lifestyleScore');
        putNum('activityFactor');

        if (metrics['goalType'] is String) m['goalType'] = metrics['goalType'];

        if (metrics['userPoints'] is num) {
          m['userPoints'] = (metrics['userPoints'] as num).toInt();
        }

        m['updatedAt'] = now;
        if (m.isNotEmpty) patch['metrics'] = m;
      }
    }

    // ----------------------------
    // onboarding/meta -> root onboarding fields + goal
    // ----------------------------
    final needsOnboarding =
        rootData['onboardingDone'] == null || rootData['onboardingStep'] == null;
    final needsWeightGoal = _isMissingValue(rootData['weightGoal']);

    if (needsOnboarding || needsWeightGoal) {
      final obSnap = await _metaOnboarding(uid).get();
      final ob = obSnap.data();

      if (ob != null) {
        if (needsOnboarding) {
          if (rootData['onboardingDone'] == null && ob['onboardingDone'] is bool) {
            patch['onboardingDone'] = ob['onboardingDone'];
          }
          if (rootData['onboardingStep'] == null && ob['onboardingStep'] is num) {
            patch['onboardingStep'] = (ob['onboardingStep'] as num).toInt();
          }
        }

        if (needsWeightGoal) {
          final setGoal = _asMap(ob['setGoal']);
          if (setGoal != null && setGoal.isNotEmpty) {
            final current = setGoal['currentWeight'];
            final target = setGoal['targetWeight'];
            final targetDate = setGoal['targetDate'];

            final wg = <String, dynamic>{};
            if (current is num) wg['currentWeightKg'] = current.toDouble();
            if (target is num) wg['targetWeightKg'] = target.toDouble();
            if (setGoal['unit'] is String) wg['unit'] = setGoal['unit'];
            if (targetDate is Timestamp) wg['targetDate'] = targetDate;
            wg['updatedAt'] = now;

            if (wg.isNotEmpty) {
              patch['weightGoal'] = wg;

              if (rootData['currentWeightKg'] == null &&
                  wg['currentWeightKg'] is num) {
                patch['currentWeightKg'] =
                    (wg['currentWeightKg'] as num).toDouble();
              }
              if (rootData['targetWeightKg'] == null &&
                  wg['targetWeightKg'] is num) {
                patch['targetWeightKg'] =
                    (wg['targetWeightKg'] as num).toDouble();
              }
              if (_isMissingValue(rootData['targetDate']) &&
                  wg['targetDate'] is Timestamp) {
                patch['targetDate'] = wg['targetDate'];
              }
            }
          }
        }
      }
    }

    // goal/meta -> root.weightGoal (fallback إضافي)
    if (_isMissingValue(rootData['weightGoal'])) {
      final gSnap = await _metaGoal(uid).get();
      final g = gSnap.data();
      if (g != null && g.isNotEmpty) {
        patch['weightGoal'] = Map<String, dynamic>.from(g)..['updatedAt'] = now;

        if (rootData['currentWeightKg'] == null && g['currentWeightKg'] is num) {
          patch['currentWeightKg'] = (g['currentWeightKg'] as num).toDouble();
        }
        if (rootData['targetWeightKg'] == null && g['targetWeightKg'] is num) {
          patch['targetWeightKg'] = (g['targetWeightKg'] as num).toDouble();
        }
        if (_isMissingValue(rootData['targetDate']) && g['targetDate'] is Timestamp) {
          patch['targetDate'] = g['targetDate'];
        }
      }
    }

    // prefs/meta -> root.prefs
    final needsPrefs = _isMissingValue(rootData['prefs']);
    if (needsPrefs) {
      final pSnap = await _metaPrefs(uid).get();
      final p = pSnap.data();
      if (p != null && p.isNotEmpty) {
        patch['prefs'] = Map<String, dynamic>.from(p);
      }
    }

    if (patch.isEmpty) return;

    patch['updatedAt'] = now;
    await _userDoc(uid).set(patch, SetOptions(merge: true));
  }

  // ----------------------------
  // أساسيات وثيقة المستخدم (الجذر)
  // ----------------------------

  /// يضمن وجود users/{uid}؛ ينشئها لو مفقودة، ويضيف أقل حقول لازمة.
  Future<void> ensureUserDocExists() async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    final ref = _userDoc(u.uid);
    final now = _now();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.data() ?? <String, dynamic>{};

      if (!snap.exists) {
        tx.set(ref, {
          'uid': u.uid,
          'email': (u.email ?? '').trim(),
          if ((u.displayName ?? '').trim().isNotEmpty)
            'displayName': u.displayName!.trim(),
          if ((u.photoURL ?? '').trim().isNotEmpty)
            'photoUrl': u.photoURL!.trim(),
          'onboardingDone': false,
          'onboardingStep': 0,
          'flags': {
            'lifestyleAssessmentCompleted': false,
            'userDataEntered': false,
            'onboardingComplete': false,
          },
          'createdAt': now,
          'updatedAt': now,
          'role': 'user', // مسموح فقط عند الإنشاء
        });
      } else {
        final patch = <String, dynamic>{'updatedAt': now};

        final email = u.email;
        if (email != null && email.trim().isNotEmpty) patch['email'] = email.trim();

        final dn = u.displayName;
        if (dn != null && dn.trim().isNotEmpty) patch['displayName'] = dn.trim();

        final photo = u.photoURL;
        if (photo != null && photo.trim().isNotEmpty) patch['photoUrl'] = photo.trim();

        if (_isMissingValue(existing['uid'])) {
          patch['uid'] = u.uid;
        }

        if (!existing.containsKey('createdAt')) {
          patch['createdAt'] = now;
        }
        if (!existing.containsKey('onboardingDone')) {
          patch['onboardingDone'] = false;
        }
        if (!existing.containsKey('onboardingStep')) {
          patch['onboardingStep'] = 0;
        }

        if (!existing.containsKey('flags') || _asMap(existing['flags']) == null) {
          patch['flags'] = {
            'lifestyleAssessmentCompleted': false,
            'userDataEntered': false,
            'onboardingComplete': false,
          };
        }

        tx.set(ref, patch, SetOptions(merge: true));
      }
    });

    try {
      final snap = await ref.get();
      final data = snap.data() ?? <String, dynamic>{};
      await _migrateFromNewStructureIfNeeded(uid: u.uid, rootData: data);
    } catch (_) {}
  }

  /// يضمن وجود حقول الأونبوردنق داخل users/{uid} (الجذر) دون إرجاع الخطوات للخلف.
  Future<void> ensureOnboardingDocExists({int initialStep = 0}) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    await ensureUserDocExists();

    final ref = _userDoc(u.uid);
    final now = _now();
    final snap = await ref.get();
    final data = snap.data() ?? <String, dynamic>{};

    final patch = <String, dynamic>{'updatedAt': now};

    if (!data.containsKey('onboardingStep')) {
      patch['onboardingStep'] = initialStep;
    }
    if (!data.containsKey('onboardingDone')) {
      patch['onboardingDone'] = false;
    }
    if (!data.containsKey('createdAt')) {
      patch['createdAt'] = now;
    }

    await ref.set(patch, SetOptions(merge: true));

    try {
      final after = (await ref.get()).data() ?? <String, dynamic>{};
      await _migrateFromNewStructureIfNeeded(uid: u.uid, rootData: after);
    } catch (_) {}
  }

  /// يرجّع وثيقة المستخدم من الجذر. (مع مهاجرة تلقائية للحقول الناقصة عند الحاجة)
  Future<Map<String, dynamic>> getUser() async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    await ensureUserDocExists();

    final ref = _userDoc(u.uid);
    final snap = await ref.get();
    final root = snap.data() ?? <String, dynamic>{};

    try {
      await _migrateFromNewStructureIfNeeded(uid: u.uid, rootData: root);
      final fresh = (await ref.get()).data();
      if (fresh != null) return fresh;
    } catch (_) {}

    return root;
  }

  /// ستريم حي لوثيقة المستخدم في الجذر.
  Stream<DocumentSnapshot<Map<String, dynamic>>> userStream() {
    final u = _auth.currentUser;
    if (u == null) return const Stream.empty();
    return _userDoc(u.uid).snapshots();
  }

  // ----------------------------
  // تحديث بيانات البروفايل (الجذر)
  // ----------------------------

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? gender,
    DateTime? birthDate,
  }) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    await ensureUserDocExists();

    final now = _now();
    final patch = <String, dynamic>{
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (phone != null) 'phone': phone,
      if (gender != null) 'gender': gender,
      if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate),
      'updatedAt': now,
    };

    await _userDoc(u.uid).set(patch, SetOptions(merge: true));
  }

  // ----------------------------
  // اسم المستخدم (مع فحص التفرّد)
  // ----------------------------

  Future<bool> isUsernameTaken(String username) async {
    final handle = _normalizeHandle(username);
    if (handle.isEmpty) return true;

    final doc = await _usernameDoc(handle).get();
    return doc.exists;
  }

  Future<void> updateUsername({required String username}) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    await ensureUserDocExists();

    final handle = _normalizeHandle(username);
    _validateHandle(handle);

    final now = _now();
    final userRef = _userDoc(u.uid);
    final newHandleRef = _usernameDoc(handle);

    await _db.runTransaction((tx) async {
      final newSnap = await tx.get(newHandleRef);
      if (newSnap.exists) {
        final ownerUid = newSnap.data()?['ownerUid'];
        if (ownerUid != u.uid) {
          throw Exception('اسم المستخدم مستخدم بالفعل');
        }
      }

      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? <String, dynamic>{};
      final oldHandle = (userData['username'] as String?)?.trim();
      final oldDisplayName = (userData['displayName'] as String?)?.trim();

      tx.set(newHandleRef, {
        'ownerUid': u.uid,
        'createdAt': now,
      }, SetOptions(merge: true));

      final patch = <String, dynamic>{
        'username': handle,
        'username_lower': handle,
        'updatedAt': now,
      };

      final shouldUpdateDisplayName = (oldDisplayName == null ||
          oldDisplayName.isEmpty ||
          (oldHandle != null &&
              oldHandle.isNotEmpty &&
              oldDisplayName == oldHandle));

      if (shouldUpdateDisplayName) {
        patch['displayName'] = handle;
      }

      tx.set(userRef, patch, SetOptions(merge: true));

      if (oldHandle != null && oldHandle.isNotEmpty && oldHandle != handle) {
        final oldRef = _usernameDoc(_normalizeHandle(oldHandle));
        final oldSnap = await tx.get(oldRef);
        if (oldSnap.exists && oldSnap.data()?['ownerUid'] == u.uid) {
          tx.delete(oldRef);
        }
      }
    });

    try {
      final current = _auth.currentUser;
      if (current != null) {
        final dn = current.displayName?.trim();
        if (dn == null || dn.isEmpty) {
          await current.updateDisplayName(handle);
        }
      }
    } catch (_) {}
  }

  // ----------------------------
  // الصورة الشخصية
  // ----------------------------

  Future<String> _uploadProfileBytes(String uid, Uint8List bytes) async {
    final ref = _storage.ref().child('users/$uid/profile.jpg');
    final meta = SettableMetadata(contentType: 'image/jpeg');
    await ref.putData(bytes, meta);
    return ref.getDownloadURL();
  }

  Future<void> updatePhotoFromBytes(Uint8List bytes) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final url = await _uploadProfileBytes(u.uid, bytes);
    await _userDoc(u.uid).set({
      'photoUrl': url,
      'updatedAt': _now(),
    }, SetOptions(merge: true));

    try {
      await u.updatePhotoURL(url);
    } catch (_) {}
  }

  Future<void> updatePhotoFromFile(File file) async {
    final bytes = await file.readAsBytes();
    return updatePhotoFromBytes(bytes);
  }

  // ----------------------------
  // إعادة التوثيق (Email/Password)
  // ----------------------------

  Future<void> _reauthWithPassword(String currentPassword) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');
    final email = u.email;
    if (email == null) throw Exception('لا يوجد بريد مرتبط بالحساب الحالي');
    final cred =
        EmailAuthProvider.credential(email: email, password: currentPassword);
    await u.reauthenticateWithCredential(cred);
  }

  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    await _reauthWithPassword(currentPassword);

    if (actionCodeSettings != null) {
      await u.verifyBeforeUpdateEmail(newEmail, actionCodeSettings);
    } else {
      await u.verifyBeforeUpdateEmail(newEmail);
    }
  }

  // ----------------------------
  // تغيير كلمة المرور
  // ----------------------------

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');

    await _reauthWithPassword(currentPassword);
    await u.updatePassword(newPassword);
  }

  // ----------------------------
  // أعلام الأونبوردنغ + سكور  (داخل root.flags + root.metrics)
  // ----------------------------

  Future<void> setLifestyleCompleted(bool v) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final now = _now();
    await _userDoc(u.uid).update({
      'flags.lifestyleAssessmentCompleted': v,
      'updatedAt': now,
    });
  }

  Future<void> setUserDataEntered(bool v) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final now = _now();
    await _userDoc(u.uid).update({
      'flags.userDataEntered': v,
      'updatedAt': now,
    });
  }

  Future<void> setLifestyleScore(int score) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final now = _now();
    await _userDoc(u.uid).update({
      'metrics.lifestyleScore': score,
      'metrics.updatedAt': now,
      'updatedAt': now,
    });
  }

  // ----------------------------
  // المقاييس (الماكروز / السعرات) داخل root.metrics
  // ----------------------------

  Future<void> setNutritionTargets({
    required double caloriesNeeded,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final now = _now();
    await _userDoc(u.uid).update({
      'metrics.caloriesNeeded': caloriesNeeded,
      'metrics.protein': protein,
      'metrics.carbs': carbs,
      'metrics.fat': fat,
      'metrics.updatedAt': now,
      'updatedAt': now,
    });
  }

  Future<Map<String, double>?> getNutritionTargets() async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final ref = _userDoc(u.uid);
    final snap = await ref.get();
    final root = snap.data() ?? <String, dynamic>{};

    try {
      await _migrateFromNewStructureIfNeeded(uid: u.uid, rootData: root);
    } catch (_) {}

    final fresh = (await ref.get()).data() ?? root;
    final metrics = _asMap(fresh['metrics']);
    if (metrics == null) return null;

    final k = metrics['caloriesNeeded'];
    final p = metrics['protein'];
    final c = metrics['carbs'];
    final f = metrics['fat'];

    if (k is num && p is num && c is num && f is num) {
      return {
        'k': k.toDouble(),
        'p': p.toDouble(),
        'c': c.toDouble(),
        'f': f.toDouble(),
      };
    }
    return null;
  }

  // ----------------------------
  // هدف الوزن  داخل root.weightGoal + mirror root fields
  // ----------------------------

  Future<void> setWeightGoal({
    required double currentWeight,
    required double targetWeight,
    required DateTime targetDate,
    String unit = 'kg',
  }) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final now = _now();
    final wg = <String, dynamic>{
      'currentWeightKg': currentWeight,
      'targetWeightKg': targetWeight,
      'unit': unit,
      'targetDate': Timestamp.fromDate(targetDate),
      'updatedAt': now,
    };

    await _userDoc(u.uid).set({
      'weightGoal': wg,
      'currentWeightKg': currentWeight,
      'targetWeightKg': targetWeight,
      'targetDate': Timestamp.fromDate(targetDate),
      'onboardingStep': 3,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getWeightGoal() async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final ref = _userDoc(u.uid);
    final snap = await ref.get();
    final root = snap.data() ?? <String, dynamic>{};

    try {
      await _migrateFromNewStructureIfNeeded(uid: u.uid, rootData: root);
    } catch (_) {}

    final fresh = (await ref.get()).data() ?? root;
    final wg = _asMap(fresh['weightGoal']);
    if (wg == null || wg.isEmpty) return null;
    return Map<String, dynamic>.from(wg);
  }

  // ----------------------------
  // التفضيلات العامة  داخل root.prefs
  // ----------------------------

  Future<void> setPrefs(Map<String, dynamic> prefs) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');
    await ensureUserDocExists();

    await _userDoc(u.uid).set({
      'prefs': prefs,
      'updatedAt': _now(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getPrefs() async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم مسجّل الدخول');
    await ensureUserDocExists();

    final ref = _userDoc(u.uid);
    final snap = await ref.get();
    final root = snap.data() ?? <String, dynamic>{};

    try {
      await _migrateFromNewStructureIfNeeded(uid: u.uid, rootData: root);
    } catch (_) {}

    final fresh = (await ref.get()).data() ?? root;
    final prefs = _asMap(fresh['prefs']);
    if (prefs == null || prefs.isEmpty) return null;
    return Map<String, dynamic>.from(prefs);
  }

  // ----------------------------
  // نقاط المستخدم  داخل root.metrics
  // ----------------------------

  Future<void> incrementUserPoints(int by) async {
    final u = _auth.currentUser;
    if (u == null) throw Exception('لا يوجد مستخدم');
    await ensureUserDocExists();

    final now = _now();
    await _userDoc(u.uid).update({
      'metrics.userPoints': FieldValue.increment(by),
      'metrics.updatedAt': now,
      'updatedAt': now,
    });
  }
}

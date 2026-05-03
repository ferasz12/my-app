import 'package:cloud_firestore/cloud_firestore.dart';

/// تمثيل وثيقة المستخدم users/{uid}
class UserProfile {
  final String uid;
  final String email;

  final String? firstName;
  final String? lastName;
  final String? username;
  final String? photoUrl;

  /// مقاييس تغذوية / صحية عامة
  /// مثال:
  /// {
  ///   'caloriesNeeded': 2200,
  ///   'protein': 130,
  ///   'carbs': 250,
  ///   'fat': 70,
  ///   'lifestyleScore': 12,
  /// }
  final Map<String, dynamic> metrics;

  /// أعلام التقدّم في الأونبوردنغ الخ…
  /// {
  ///   'lifestyleAssessmentCompleted': true/false,
  ///   'userDataEntered': true/false,
  ///   'onboardingComplete': true/false,
  /// }
  final Map<String, dynamic> flags;

  /// خطة الوزن
  /// الوزن الحالي/الهدف/تاريخ الهدف (اختياري)
  final double? heightCm;
  final double? currentWeightKg;
  final double? targetWeightKg;
  final DateTime? targetDate;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.uid,
    required this.email,
    this.firstName,
    this.lastName,
    this.username,
    this.photoUrl,
    this.metrics = const {},
    this.flags = const {},
    this.heightCm,
    this.currentWeightKg,
    this.targetWeightKg,
    this.targetDate,
    this.createdAt,
    this.updatedAt,
  });

  UserProfile copyWith({
    String? uid,
    String? email,
    String? firstName,
    String? lastName,
    String? username,
    String? photoUrl,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? flags,
    double? heightCm,
    double? currentWeightKg,
    double? targetWeightKg,
    DateTime? targetDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      metrics: metrics ?? this.metrics,
      flags: flags ?? this.flags,
      heightCm: heightCm ?? this.heightCm,
      currentWeightKg: currentWeightKg ?? this.currentWeightKg,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      targetDate: targetDate ?? this.targetDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      if (firstName != null) 'firstName': firstName,
      if (lastName  != null) 'lastName' : lastName,
      if (username  != null) 'username' : username,
      if (username  != null) 'username_lower': username!.toLowerCase(),
      if (photoUrl  != null) 'photoUrl' : photoUrl,
      if (metrics.isNotEmpty) 'metrics': metrics,
      if (flags.isNotEmpty)   'flags'  : flags,
      if (heightCm != null) 'heightCm': heightCm,
      if (currentWeightKg != null) 'currentWeightKg': currentWeightKg,
      if (targetWeightKg  != null) 'targetWeightKg' : targetWeightKg,
      if (targetDate      != null) 'targetDate'     : Timestamp.fromDate(targetDate!),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  static UserProfile fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime? _dt(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    double? _dn(dynamic v) {
      if (v is num) return v.toDouble();
      return null;
    }

    return UserProfile(
      uid: d['uid']?.toString() ?? doc.id,
      email: (d['email'] ?? '').toString(),
      firstName: d['firstName']?.toString(),
      lastName : d['lastName'] ?.toString(),
      username : d['username'] ?.toString(),
      photoUrl : d['photoUrl'] ?.toString(),
      metrics  : (d['metrics'] is Map) ? Map<String, dynamic>.from(d['metrics']) : const {},
      flags    : (d['flags']   is Map) ? Map<String, dynamic>.from(d['flags'])   : const {},
      heightCm: _dn(d['heightCm']),
      currentWeightKg: _dn(d['currentWeightKg']),
      targetWeightKg : _dn(d['targetWeightKg']),
      targetDate: _dt(d['targetDate']),
      createdAt: _dt(d['createdAt']),
      updatedAt: _dt(d['updatedAt']),
    );
  }

  /// مُنشئ افتراضي عند إنشاء الوثيقة لأول مرة
  factory UserProfile.initial({
    required String uid,
    required String email,
    String? firstName,
    String? lastName,
    String? username,
    String? photoUrl,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      firstName: firstName,
      lastName: lastName,
      username: username,
      photoUrl: photoUrl,
      metrics: const {
        'lifestyleScore': 10, // قيمة افتراضية معقولة كبداية
      },
      flags: const {
        'lifestyleAssessmentCompleted': false,
        'userDataEntered': false,
        'onboardingComplete': false,
      },
    );
  }
}

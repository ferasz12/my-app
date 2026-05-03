class UserPublic {
  final String uid;
  final String email;       // غير nullable لراحة الاستخدام
  final String username;    // غير nullable
  final String displayName; // غير nullable
  final String? photoUrl;
  final String? bio;
  final String? gender;
  final DateTime? createdAt;

  UserPublic({
    required this.uid,
    this.email = '',
    this.username = '',
    this.displayName = '',
    this.photoUrl,
    this.bio,
    this.gender,
    this.createdAt,
  });

  factory UserPublic.fromMap(String uid, Map<String, dynamic>? data) {
    data ??= const {};
    DateTime? _parse(dynamic v) {
      if (v == null) return null;
      try { return DateTime.tryParse(v.toString()); } catch (_) { return null; }
    }
    return UserPublic(
      uid: uid,
      email: (data['email'] ?? '') as String,
      username: (data['username'] ?? '') as String,
      displayName: (data['displayName'] ?? '') as String,
      photoUrl: data['photoUrl'] as String?,
      bio: data['bio'] as String?,
      gender: data['gender'] as String?,
      createdAt: _parse(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'email': email,
    'username': username,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'bio': bio,
    'gender': gender,
    'createdAt': createdAt?.toIso8601String(),
  };
}

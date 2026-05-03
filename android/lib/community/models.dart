// lib/community/models.dart
// ستبس موسّعة لتغطية التواقيع المستخدمة في المشروع بدون تفعيل المجتمع

class AppUser {
  final String uid;
  final String email;             // non-nullable لتفادي أخطاء String? -> String
  final String username;          // non-nullable
  final String displayName;       // non-nullable
  final String? photoUrl;
  final String? bio;
  final String? gender;           // تُستخدم في verify_email_page/auth_service
  final String? profileImagePath; // تُقرأ في بعض الشاشات كـ Asset path
  final DateTime? createdAt;

  // حقول مجتمع قديمة — نخليها اختيارية للتوافق فقط
  final List<String> followers;
  final List<String> following;

  AppUser({
    required this.uid,
    this.email = '',
    this.username = '',
    this.displayName = '',
    this.photoUrl,
    this.bio,
    this.gender,
    this.profileImagePath,
    this.createdAt,
    List<String>? followers,
    List<String>? following,
  })  : followers = followers ?? const <String>[],
        following = following ?? const <String>[];

  factory AppUser.fromJson(Map<String, dynamic> json, {required String uid}) {
    DateTime? _parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.tryParse(v.toString());
      } catch (_) {
        return null;
      }
    }

    List<String> _list(dynamic v) {
      if (v is List) {
        return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).cast<String>().toList();
      }
      return const <String>[];
    }

    return AppUser(
      uid: uid,
      email: (json['email'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      displayName: (json['displayName'] ?? '') as String,
      photoUrl: json['photoUrl'] as String?,
      bio: json['bio'] as String?,
      gender: json['gender'] as String?,
      profileImagePath: json['profileImagePath'] as String?,
      createdAt: _parse(json['createdAt']),
      followers: _list(json['followers']),
      following: _list(json['following']),
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'username': username,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'bio': bio,
        'gender': gender,
        'profileImagePath': profileImagePath,
        'createdAt': createdAt?.toIso8601String(),
        'followers': followers,
        'following': following,
      };
}

// ستب لمنشور مجتمع قديم — نعرّف الحقول المطلوبة في الشاشات
class Post {
  final String id;
  final String authorId;              // كانت الصفحات تقرأها
  final String caption;               // كانت الصفحات تقرأها
  final List<String> imagePaths;      // كانت الصفحات تقرأها
  final DateTime createdAt;

  Post({
    required this.id,
    required this.authorId,
    required this.caption,
    required this.imagePaths,
    required this.createdAt,
  });

  // بعض الاستدعاءات كانت بدون id مسمّى — نخلي id اختياري ونعوّض
  factory Post.fromJson(Map<String, dynamic> m, {String? id}) {
    DateTime _parse(dynamic v) {
      try {
        return DateTime.tryParse(v.toString()) ?? DateTime.now();
      } catch (_) {
        return DateTime.now();
      }
    }

    return Post(
      id: id ?? (m['id']?.toString() ?? ''),
      authorId: (m['authorId'] ?? m['authorUid'] ?? '').toString(),
      caption: (m['caption'] ?? m['content'] ?? '').toString(),
      imagePaths: List<String>.from(m['imagePaths'] ?? const <String>[]),
      createdAt: _parse(m['createdAt']),
    );
  }
}

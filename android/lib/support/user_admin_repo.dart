// lib/support/user_admin_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../community/models.dart';

/// محوّل تاريخ آمن لأي نوع (Timestamp/int/String/ISO)
DateTime _coerceDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

/// يقرأ جميع المستخدمين من مجموعة `users/`
/// ويحوّلهم إلى AppUser بشكل متسامح مع الحقول.
class UserAdminRepo {
  final _col = FirebaseFirestore.instance.collection('users');

  Future<List<AppUser>> listAllUsers({int limit = 1000}) async {
    final qs = await _col.limit(limit).get();

    return qs.docs.map((d) {
      final data = d.data() as Map<String, dynamic>? ?? const {};

      // حقول أساسية
      final email = (data['email'] ?? '').toString().trim();

      // محاولة استخراج اسم معروض من الحقول الشائعة
      final displayFromDoc = (data['displayName'] ?? '').toString().trim();
      final first = (data['firstName'] ?? '').toString().trim();
      final last  = (data['lastName'] ?? '').toString().trim();
      final nameFromParts =
          [first, last].where((e) => e.isNotEmpty).join(' ').trim();

      // أفضل اسم مستخدم/معروض متاح
      String username = (data['username'] ?? '').toString().trim();
      if (username.isEmpty) {
        if (nameFromParts.isNotEmpty) {
          username = nameFromParts; // fallback أول
        } else if (email.contains('@')) {
          username = email.split('@').first; // fallback ثاني
        } else {
          username = d.id; // fallback أخير
        }
      }

      // displayName النهائي
      final displayName = displayFromDoc.isNotEmpty
          ? displayFromDoc
          : (nameFromParts.isNotEmpty ? nameFromParts : username);

      // صورة (لو موجودة)
      final photoUrl = (data['photoUrl'] as String?)?.trim();
      final profileImagePath = (data['profileImagePath'] as String?)?.trim();

      // بايو وجندر
      final bio = (data['bio'] as String?);
      final gender = (data['gender'] ?? 'unknown').toString();

      // تاريخ الإنشاء
      final createdAt = _coerceDate(data['createdAt']);

      // تحويل إلى AppUser حسب نموذج stub الحالي
      return AppUser(
        uid: d.id,
        email: email,
        username: username,
        displayName: displayName,
        photoUrl: photoUrl,
        bio: bio,
        gender: gender,
        profileImagePath: profileImagePath,
        createdAt: createdAt,
      );
    }).toList();
  }
}

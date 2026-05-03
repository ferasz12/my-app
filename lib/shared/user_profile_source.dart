// lib/shared/user_profile_source.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../community/local_repos.dart';
import '../community/models.dart';

class UserView {
  final String uid;
  final String handle;        // @handle (username الموحّد)
  final String displayName;   // الاسم الظاهر (first/last/name)
  final String bio;
  final String? imagePath;
  final int followers;
  final int following;
  final DateTime createdAt;   // من AppUser للحساب "عضو منذ"

  UserView({
    required this.uid,
    required this.handle,
    required this.displayName,
    required this.bio,
    required this.imagePath,
    required this.followers,
    required this.following,
    required this.createdAt,
  });
}

String _sanitizeHandle(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9_.]'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

Future<UserView> getUserViewFor(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  final currentEmail = prefs.getString('currentEmail') ?? uid;

  String readString(String base) {
    final v1 = prefs.getString('${base}_$uid');
    if (v1 != null && v1.isNotEmpty) return v1;
    final v2 = prefs.getString('${base}_$currentEmail');
    return v2 ?? '';
  }

  List<String> readList(String base) {
    final v1 = prefs.getStringList('${base}_$uid');
    if (v1 != null && v1.isNotEmpty) return v1;
    final v2 = prefs.getStringList('${base}_$currentEmail');
    return v2 ?? const [];
  }

  // الاسم الظاهر
  final first = readString('firstName');
  final last  = readString('lastName');
  final namePref = readString('name');
  final displayName = (namePref.isNotEmpty
          ? namePref
          : [first, last].where((s) => s.trim().isNotEmpty).join(' '))
      .trim();

  // الهاندل الموحّد (@handle)
  var handle = readString('username').trim();
  if (handle.isEmpty) {
    // fallback من AppUser أو من الإيميل
    final me = await LocalAuthRepo().getUserById(uid) ?? await LocalAuthRepo().currentUser();
    final email = me.email;
    final guess = _sanitizeHandle(
      displayName.isNotEmpty ? displayName : (email.contains('@') ? email.split('@').first : email),
    );
    handle = guess;
    await prefs.setString('username_$uid', handle); // توحيد المصدر
  } else {
    handle = _sanitizeHandle(handle);
    await prefs.setString('username_$uid', handle); // تأكيد التوحيد
  }

  final bio = readString('bio');
  final imagePath = readString('profile_image_path').isNotEmpty
      ? readString('profile_image_path')
      : null;

  final followers = readList('followers').length;
  final following = readList('following').length;

  // createdAt من AppUser (علشان "عضو منذ")
  final me = await LocalAuthRepo().getUserById(uid) ?? await LocalAuthRepo().currentUser();

  return UserView(
    uid: uid,
    handle: handle,
    displayName: displayName,
    bio: bio,
    imagePath: imagePath,
    followers: followers,
    following: following,
    createdAt: (me.createdAt ?? DateTime.now()),
  );
}

Future<UserView> getCurrentUserView() async {
  final me = await LocalAuthRepo().currentUser();
  return getUserViewFor(me.uid);
}

bool fileExists(String? p) => p != null && p.isNotEmpty && File(p).existsSync();

import 'package:flutter/material.dart';
import '../features/users/ui/user_profile_page.dart' as newui;

class UserProfileScreen extends StatelessWidget {
  final dynamic user;
  const UserProfileScreen({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    final uid = (user?.uid ?? user?['uid'] ?? '') as String;
    if (uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('لا يوجد مستخدم')));
    }
    return newui.UserProfilePage(uid: uid);
  }
}

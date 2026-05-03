import 'package:flutter/material.dart';

class SocialAuth {
  static Future<void> signInWithGoogle(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تسجيل Google غير متاح على هذه المنصة')),
    );
  }

  static Future<void> signInWithApple(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تسجيل Apple غير متاح على هذه المنصة')),
    );
  }
}

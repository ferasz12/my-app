import 'package:flutter/material.dart';

class PublicProfileScreen extends StatelessWidget {
  final String userKey;
  const PublicProfileScreen({super.key, required this.userKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('عرض الملف يتطلب UID مباشر (المجتمع محذوف).'),
            const SizedBox(height: 12),
            Text('المُعرّف الحالي: $userKey'),
          ],
        ),
      ),
    );
  }
}

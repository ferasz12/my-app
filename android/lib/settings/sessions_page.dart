import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('الجلسات والأجهزة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('المستخدم الحالي'),
            subtitle: Text(u?.email ?? 'غير معروف'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () async {
              setState(() => _busy = true);
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              setState(() => _busy = false);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.logout),
            label: _busy ? const Text('جاري تسجيل الخروج...') : const Text('تسجيل الخروج من هذا الجهاز'),
          ),
          const SizedBox(height: 8),
          const Text(
            'ملاحظة: “تسجيل الخروج من جميع الأجهزة” يتطلب منطق إضافي (إبطال الجلسات عبر Cloud Functions أو فحص حقل revoke في Firestore). حالياً الزر أعلاه يخرجك من هذا الجهاز فقط.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

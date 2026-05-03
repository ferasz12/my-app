import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/session_manager.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await SessionManager.fullSignOut();
      if (!mounted) return;
      // ✅ تنظيف الستاك بالكامل لتفادي أي مشاكل (خصوصاً في iOS)
      Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (r) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تسجيل الخروج: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final providers = (u?.providerData ?? [])
        .map((p) => p.providerId)
        .toSet()
        .join('، ');

    return Scaffold(
      appBar: AppBar(title: const Text('الجلسات والأجهزة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (u == null) ...[
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('لا يوجد مستخدم مسجّل دخول حالياً'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('رجوع'),
            ),
            const SizedBox(height: 8),
            const Text(
              'إذا كنت تتوقع وجود جلسة، أعد فتح التطبيق أو سجّل الدخول مرة أخرى.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ] else ...[
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('المستخدم الحالي'),
            subtitle: Text(
              [
                if ((u.displayName ?? '').trim().isNotEmpty) u.displayName!.trim(),
                if ((u.email ?? '').trim().isNotEmpty) u.email!.trim(),
              ].join(' • ').isEmpty
                  ? 'غير معروف'
                  : [
                      if ((u.displayName ?? '').trim().isNotEmpty) u.displayName!.trim(),
                      if ((u.email ?? '').trim().isNotEmpty) u.email!.trim(),
                    ].join(' • '),
            ),
          ),
          if ((u.uid).trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('المعرّف (UID)'),
              subtitle: Text(u.uid),
            ),
          if (providers.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('طرق تسجيل الدخول'),
              subtitle: Text(providers),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: _busy ? const Text('جاري تسجيل الخروج...') : const Text('تسجيل الخروج من هذا الجهاز'),
          ),
          const SizedBox(height: 8),
          const Text(
            'ملاحظة:هذه الميزة تعمل فقط على جهازك قريبا سيتم تحديثها بشكل كامل',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          ],
        ],
      ),
    );
  }
}

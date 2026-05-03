import 'package:flutter/material.dart';
import '../data/user_repository.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final repo = const UserRepository();
  bool _busy = false;

  bool pushEnabled = true;
  bool tipsEnabled = true;
  bool remindersEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  // محوّل آمن لأي قيمة إلى bool
  bool _toBool(dynamic v, {bool def = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;                // يدعم 0/1 و0.0/1.0
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return def;
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await repo.getPrefs() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        pushEnabled      = _toBool(p['push'],      def: true);
        tipsEnabled      = _toBool(p['dailyTips'], def: true);
        remindersEnabled = _toBool(p['reminders'], def: true);
      });
    } catch (_) {
      // ممكن تضيف لوق هنا لو حبيت
    }
  }

  Future<void> _save() async {
    try {
      setState(() => _busy = true);
      await repo.setPrefs({
        'push': pushEnabled,
        'dailyTips': tipsEnabled,
        'reminders': remindersEnabled,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الحفظ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: pushEnabled,
            onChanged: (v) => setState(() => pushEnabled = v),
            title: const Text('تفعيل الإشعارات العامة'),
            subtitle: const Text('تمكين/تعطيل جميع إشعارات التطبيق'),
          ),
          const Divider(),
          SwitchListTile(
            value: tipsEnabled,
            onChanged: (v) => setState(() => tipsEnabled = v),
            title: const Text('نصيحة صحية يومية'),
          ),
          SwitchListTile(
            value: remindersEnabled,
            onChanged: (v) => setState(() => remindersEnabled = v),
            title: const Text('تذكيرات الأهداف (ماء/وزن/سعرات)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save),
            label: _busy ? const Text('جاري الحفظ...') : const Text('حفظ'),
          ),
          const SizedBox(height: 8),
          const Text(
            'لتفعيل الإشعارات Push فعليًا ستحتاج إعداد FCM + أذون النظام. هذي الصفحة تحفظ تفضيلاتك في Firestore فقط.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        ],
      ),
    );
  }
}

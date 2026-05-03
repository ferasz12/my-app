// lib/features/admin_support/admin_support_dashboard_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/auth/roles_service.dart'; // AppRole, RolesService
import '../announcement/announcement_editor_page.dart';

/// لوحة موحّدة للمالك/الأدمن/الدعم
/// - تبويب واحد: إدارة المستخدمين
/// - تعرض الاسم/اليوزر/الإيميل/الصورة/النقاط/الدور/الحظر
/// - أوامر: تغيير الدور، حظر/فكّ الحظر، تعليق/إلغاء تعليق نشر الوصفات،
 ///          زيادة/إنقاص/تعيين النقاط، إرسال إشعار
class AdminSupportDashboardPage extends StatelessWidget {
  const AdminSupportDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRole>(
      future: RolesService().currentUserRoleOnce(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data!;
        final allowed =
            role == AppRole.owner || role == AppRole.admin || role == AppRole.support;
        if (!allowed) {
          return const Scaffold(
            body: Center(child: Text('هذه الصفحة متاحة للمالك/الأدمن/الدعم فقط')),
          );
        }

        return DefaultTabController(
          length: 1,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                role == AppRole.owner
                    ? 'لوحة المالك'
                    : (role == AppRole.admin ? 'لوحة الأدمن' : 'لوحة الدعم'),
              ),
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.people_alt_rounded), text: 'المستخدمون'),
                ],
              ),
            ),
            body: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _UsersTab(role: role),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ============================
/// تبويب (المستخدمون)
/// ============================
class _UsersTab extends StatefulWidget {
  const _UsersTab({super.key, required this.role});
  final AppRole role;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _qCtrl = TextEditingController();
  String _q = '';
  final _db = FirebaseFirestore.instance;
  final _roles = RolesService();

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        // ===== الإعلان العام (بانر التطبيق) =====
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.doc('appConfig/announcement').snapshots(),
          builder: (context, snap) {
            final allowAdmin = (snap.data?.data()?['allowAdminEdit'] == true);
            final canEdit = (widget.role == AppRole.owner) || (widget.role == AppRole.admin && allowAdmin);
            if (!canEdit && widget.role != AppRole.owner) return const SizedBox.shrink();
            return Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded),
                    const SizedBox(width: 8),
                    Expanded(child: Text('الإعلان العام (بانر التطبيق)', style: Theme.of(context).textTheme.titleMedium)),
                    FilledButton.icon(
                      onPressed: canEdit ? () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementEditorPage()));
                      } : null,
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل الإعلان'),
                    ),
                    if (widget.role == AppRole.owner) ...[
                      const SizedBox(width: 12),
                      Row(
                        children: [
                          const Text('السماح للإدمن:'),
                          Switch(
                            value: allowAdmin,
                            onChanged: (v) async {
                              await _db.doc('appConfig/announcement').set({'allowAdminEdit': v}, SetOptions(merge: true));
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),

        // شريط البحث
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _qCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ابحث بالاسم / اليوزر / الإيميل / UID',
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _q = '';
                        _qCtrl.clear();
                      }),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),

        // قائمة المستخدمين
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('users').limit(400).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? const [];
              final filtered = docs.where((d) {
                if (_q.isEmpty) return true;
                final m = d.data();
                final uid = d.id.toLowerCase();
                final name = (_nameFrom(m) ?? '').toLowerCase();
                final handle = (_handleFrom(m) ?? '').toLowerCase();
                final email = (_emailFrom(m) ?? '').toLowerCase();
                return uid.contains(_q) ||
                    name.contains(_q) ||
                    handle.contains(_q) ||
                    email.contains(_q);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('لا يوجد نتائج'));
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final doc = filtered[i];
                  final data = doc.data();
                  final uid = doc.id;

                  final name = _nameFrom(data) ?? 'بدون اسم';
                  final handle = _handleFrom(data) ?? '';
                  final email = _emailFrom(data) ?? '';
                  final role = (data['role'] ?? 'user').toString();
                  final banned = (data['isBanned'] ?? false) == true;
                  final points = _readUserPoints(data);
                  final photo = _photoFrom(data);

                  return ListTile(
                    leading: _Avatar(photoUrl: photo, fallbackText: name),
                    title: Text(name),
                    subtitle: Text(_subtitle(handle: handle, email: email, uid: uid)),
                    isThreeLine: true,
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('الدور: $role'),
                        const SizedBox(height: 2),
                        Text('النقاط: $points',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        if (banned)
                          const Text('محظور',
                              style: TextStyle(color: Colors.red)),
                      ],
                    ),
                    onTap: () => _openUserActions(
                      context,
                      uid: uid,
                      name: name,
                      handle: handle,
                      email: email,
                      photoUrl: photo,
                      currentPoints: points,
                      role: role,
                      banned: banned,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _openUserActions(
    BuildContext context, {
    required String uid,
    required String name,
    required String handle,
    required String email,
    required String? photoUrl,
    required int currentPoints,
    required String role,
    required bool banned,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _UserActionsSheet(
        uid: uid,
        displayName: name,
        handle: handle,
        email: email,
        photoUrl: photoUrl,
        initialRole: role,
        initialBanned: banned,
        initialPoints: currentPoints,
      ),
    );
  }

  // ===== Helpers لقراءة الحقول المتنوعة للأسماء/الصور/اليوزر =====
  String? _nameFrom(Map<String, dynamic> x) {
    return (x['name'] ??
            x['displayName'] ??
            x['fullName'] ??
            x['userName'])?.toString();
  }

  String? _handleFrom(Map<String, dynamic> x) {
    return (x['handle'] ?? x['username'] ?? x['userHandle'])?.toString();
  }

  String? _emailFrom(Map<String, dynamic> x) {
    return (x['email'] ?? x['mail'])?.toString();
  }

  String? _photoFrom(Map<String, dynamic> x) {
    return (x['photoUrl'] ?? x['userPhotoUrl'] ?? x['avatarUrl'])?.toString();
  }

  String _subtitle(
      {required String handle, required String email, required String uid}) {
    final parts = <String>[];
    if (handle.isNotEmpty) parts.add('@$handle');
    if (email.isNotEmpty) parts.add(email);
    parts.add('UID: $uid');
    return parts.join(' • ');
  }

  /// نفس منطق صفحة الإنجازات (يتحمّل صيغ متعددة)
  int _readUserPoints(Map<String, dynamic> data) {
    // points_total (جديد)
    final pt = data['points_total'];
    if (pt is num) return pt.toInt();
    if (pt is String) return int.tryParse(pt) ?? 0;

    // stats.points (قديم)
    final stats = data['stats'];
    if (stats is Map) {
      final sp = stats['points'];
      if (sp is num) return sp.toInt();
      if (sp is String) return int.tryParse(sp) ?? 0;
    }

    // توافق قديم
    final p = data['points'];
    if (p is num) return p.toInt();
    if (p is String) return int.tryParse(p) ?? 0;

    final pt2 = data['pointsTotal'];
    if (pt2 is num) return pt2.toInt();
    if (pt2 is String) return int.tryParse(pt2) ?? 0;

    return 0;
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String fallbackText;
  const _Avatar({required this.photoUrl, required this.fallbackText});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(photoUrl!));
    }
    final t = fallbackText.trim();
    final letter = t.isNotEmpty ? t.characters.first.toUpperCase() : '?';
    return CircleAvatar(child: Text(letter));
  }
}

class _UserActionsSheet extends StatefulWidget {
  final String uid;
  final String displayName;
  final String handle;
  final String email;
  final String? photoUrl;
  final String initialRole;
  final bool initialBanned;
  final int initialPoints;

  const _UserActionsSheet({
    required this.uid,
    required this.displayName,
    required this.handle,
    required this.email,
    required this.photoUrl,
    required this.initialRole,
    required this.initialBanned,
    required this.initialPoints,
  });

  @override
  State<_UserActionsSheet> createState() => _UserActionsSheetState();
}

class _UserActionsSheetState extends State<_UserActionsSheet> {
  final _roles = RolesService();
  final _db = FirebaseFirestore.instance;

  late String _role;
  late bool _banned;
  late int _points;

  final _notifyTitle = TextEditingController();
  final _notifyBody = TextEditingController();
  final _pointsCtrl = TextEditingController();

  // تعليق النشر حتى تاريخ/ساعة
  DateTime? _suspendUntil;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _banned = widget.initialBanned;
    _points = widget.initialPoints;
    _pointsCtrl.text = _points.toString();

    // جلب قيمة recipesSuspendedUntil الحالية (اختياري للعرض)
    _db.doc('users/${widget.uid}').get().then((snap) {
      final ts = snap.data()?['recipesSuspendedUntil'];
      if (ts is Timestamp) {
        setState(() => _suspendUntil = ts.toDate());
      } else {
        setState(() => _suspendUntil = null);
      }
    });
  }

  @override
  void dispose() {
    _notifyTitle.dispose();
    _notifyBody.dispose();
    _pointsCtrl.dispose();
    super.dispose();
  }

  AppRole _toAppRole(String r) {
    switch (r) {
      case 'owner':
        return AppRole.owner;
      case 'admin':
        return AppRole.admin;
      case 'support':
        return AppRole.support;
      default:
        return AppRole.user;
    }
  }

  // ===== الأوامر =====

  Future<void> _saveRole() async {
    try {
      await _roles.setUserRole(widget.uid, _toAppRole(_role));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تحديث الدور')));
    } catch (e) {
      _err('خطأ تغيير الدور', e);
    }
  }

  Future<void> _toggleBan() async {
    try {
      await _roles.setBanned(widget.uid, !_banned);
      if (!mounted) return;
      setState(() => _banned = !_banned);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_banned ? 'تم الحظر' : 'تم إلغاء الحظر')),
      );
    } catch (e) {
      _err('خطأ الحظر', e);
    }
  }

  Future<void> _pickSuspendUntil() async {
    final now = DateTime.now();
    final initDate = _suspendUntil ?? now.add(const Duration(days: 7));

    final pickedDate = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: initDate,
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(_suspendUntil ?? now.add(const Duration(hours: 12))),
    );
    if (pickedTime == null) return;

    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    try {
      await _roles.setRecipesSuspendedUntil(widget.uid, dt);
      if (!mounted) return;
      setState(() => _suspendUntil = dt);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفعيل تعليق نشر الوصفات حتى التاريخ المحدد')),
      );
    } catch (e) {
      _err('خطأ تعليق النشر', e);
    }
  }

  Future<void> _clearSuspend() async {
    try {
      await _roles.setRecipesSuspendedUntil(widget.uid, null);
      if (!mounted) return;
      setState(() => _suspendUntil = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء تعليق النشر')),
      );
    } catch (e) {
      _err('خطأ إلغاء التعليق', e);
    }
  }

  Future<void> _incrementPoints(int delta) async {
    try {
      await _roles.incrementUserPoints(widget.uid, delta);
      if (!mounted) return;
      setState(() {
        _points += delta;
        _pointsCtrl.text = _points.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(delta >= 0
                ? 'زِيدت ${delta} نقطة'
                : 'نُقصت ${-delta} نقطة')),
      );
    } catch (e) {
      _err('خطأ تعديل النقاط', e);
    }
  }

  Future<void> _savePoints() async {
    final p = int.tryParse(_pointsCtrl.text.trim());
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل رقم صحيح للنقاط')));
      return;
    }
    try {
      await _roles.setUserPoints(widget.uid, p);
      if (!mounted) return;
      setState(() => _points = p);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تحديث النقاط')));
    } catch (e) {
      _err('خطأ حفظ النقاط', e);
    }
  }

  Future<void> _sendNotification() async {
    final title = _notifyTitle.text.trim();
    final body = _notifyBody.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتب عنوان ونص الإشعار')));
      return;
    }
    try {
      await _roles.sendInboxNotification(toUid: widget.uid, title: title, body: body);
      if (!mounted) return;
      _notifyTitle.clear();
      _notifyBody.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم إرسال الإشعار')));
    } catch (e) {
      _err('خطأ الإشعار', e);
    }
  }

  void _err(String msg, Object e) {
    // يعرض الخطأ للمستخدم وللـ debug
    // تأكد من نشر القواعد وتعديل دالة myRole() كما شرحنا (قراءة role من وثيقة المستخدم أولاً)
    // وأن الحساب الحالي owner/admin/support حسب ما تريد.
    // ولو الخطأ Permission denied اطبع stacktrace كامل لتحديد الشرط الرافض.
    debugPrint('$msg: $e');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg: $e')));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          // مقبض السفلية
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // رأس بروفايل مختصر
          ListTile(
            leading: _Avatar(photoUrl: widget.photoUrl, fallbackText: widget.displayName),
            title: Text(widget.displayName),
            subtitle: Text([
              if (widget.handle.isNotEmpty) '@${widget.handle}',
              if (widget.email.isNotEmpty) widget.email,
              'UID: ${widget.uid}',
            ].join(' • ')),
          ),

          const Divider(height: 24),

          // ===== الدور =====
          Text('الدور', style: tt.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _role,
            items: const [
              DropdownMenuItem(value: 'owner', child: Text('Owner')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
              DropdownMenuItem(value: 'support', child: Text('Support')),
              DropdownMenuItem(value: 'user', child: Text('User')),
            ],
            onChanged: (v) => setState(() => _role = v ?? 'user'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saveRole,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الدور'),
          ),

          const Divider(height: 24),

          // ===== الحظر =====
          SwitchListTile(
            value: _banned,
            onChanged: (_) => _toggleBan(),
            title: const Text('حظر المستخدم'),
            subtitle: const Text('يمنع دخول المستخدم للتطبيق (حسب منطقك)'),
          ),

          const Divider(height: 24),

          // ===== تعليق نشر الوصفات =====
          Text('تعليق نشر الوصفات', style: tt.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _suspendUntil == null
                      ? 'غير معلّق'
                      : 'معلّق حتى: ${_suspendUntil!.toLocal()}',
                ),
              ),
              OutlinedButton(
                onPressed: _pickSuspendUntil,
                child: const Text('تحديد موعد'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _clearSuspend,
                child: const Text('إلغاء التعليق'),
              ),
            ],
          ),

          const Divider(height: 24),

          // ===== النقاط =====
          Text('النقاط الحالية: $_points',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _incrementPoints(-1),
                icon: const Icon(Icons.exposure_minus_1),
                label: const Text('-1'),
              ),
              OutlinedButton.icon(
                onPressed: () => _incrementPoints(1),
                icon: const Icon(Icons.exposure_plus_1),
                label: const Text('+1'),
              ),
              OutlinedButton(onPressed: () => _incrementPoints(-10), child: const Text('-10')),
              OutlinedButton(onPressed: () => _incrementPoints(10), child: const Text('+10')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pointsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'تعيين عدد النقاط يدويًا'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _savePoints, child: const Text('حفظ')),
            ],
          ),

          const Divider(height: 24),

          // ===== الإشعار =====
          Text('إرسال إشعار', style: tt.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _notifyTitle,
            decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notifyBody,
            decoration: const InputDecoration(labelText: 'نص الإشعار'),
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _sendNotification,
            icon: const Icon(Icons.send),
            label: const Text('إرسال إشعار'),
          ),
          const SizedBox(height: 16),

          // تلميح صغير
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'ملاحظة: لو واجهت رفض صلاحيات، تأكد من نشر Firestore rules الأخيرة '
              'وأن دالة myRole() تقرأ الدور من وثيقة المستخدم أولاً، '
              'وأن الحساب الحالي يملك الدور المناسب (owner/admin/support).',
              style: tt.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
import 'dart:io';
// lib/support/support_dashboard_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app/shared/badges_api.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/auth/roles_service.dart';

import '../shared/badges.dart';
import '../community/local_repos.dart' show LocalPostsRepo, LocalAuthRepo;
import '../shared/user_badges_store.dart'; // ✅ القراءة/الحفظ ديناميكيًا (بالـ UID فقط)
import 'firestore_posts_repo_adapter.dart';
import '../community/models.dart';
import '../support/moderation_repo.dart';
import '../foods/admin_food_submissions_screen.dart'; // شاشة مراجعة طلبات العناصر
import '../support/user_admin_repo.dart';
import '../trainers/admin_trainer_approvals_screen.dart';

class SupportDashboardScreen extends StatefulWidget {
  const SupportDashboardScreen({super.key});

  @override
  State<SupportDashboardScreen> createState() => _SupportDashboardScreenState();
}

class _SupportDashboardScreenState extends State<SupportDashboardScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tab;
  BadgeType _myBadge = BadgeType.none;
  bool _loading = true;
  bool _isOwner = false;

  // ==== تشخيص ====
  String? _diag;
  bool _diagRunning = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final meUid = FirebaseAuth.instance.currentUser?.uid;
    if (meUid == null) {
      setState(() => _loading = false);
      return;
    }

    // ✅ وحّدنا المفتاح على UID فقط
    _myBadge = await getBadge(meUid);
    // ✅ تحديد المالك بشكل صحيح (بدل _isOwner = _isOwner)
    try {
      final r = await RolesService().currentUserRoleOnce();
      _isOwner = r == AppRole.owner;
    } catch (_) {
      _isOwner = false;
    }

    // إذا Owner → 3 تبويبات، غير كذا → 2
    _tab = TabController(length: _isOwner ? 4 : 3, vsync: this);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tab?.dispose(); // ✅ مهم
    super.dispose();
  }

  // ===== دوال تشخيص سريعة =====
  void _appendDiag(String s) {
    debugPrint(s);
    _diag = (_diag == null || _diag!.isEmpty) ? s : '${_diag!}\n$s';
  }

  Future<void> _seedAndDebug() async {
    if (_diagRunning) return;
    setState(() {
      _diagRunning = true;
      _diag = 'تشخيص جارٍ...';
    });

    // 1) عمل seed لوثيقة المستخدم الحالي في users/{uid}
    try {
      await LocalAuthRepo().currentUser(); // ينشئ/يحدّث users/{uid}
      _appendDiag('✅ Seed: currentUser() تم بنجاح');
    } catch (e) {
      _appendDiag('❌ seed error: $e');
    }

    // 2) اطبع الـ claims
    try {
      final u = FirebaseAuth.instance.currentUser;
      final t = await u?.getIdTokenResult(true); // refresh claims
      _appendDiag('UID=${u?.uid}');
      _appendDiag('claims=${t?.claims}');
    } catch (e) {
      _appendDiag('❌ claims error: $e');
    }

    // 3) جرّب قراءة users/ مباشرةً
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('username')
          .limit(3)
          .get();
      _appendDiag('users docs = ${snap.docs.length}');
      for (final d in snap.docs) {
        _appendDiag('doc ${d.id} => ${d.data()}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Debug: users=${snap.docs.length}')),
        );
      }
    } on FirebaseException catch (e) {
      _appendDiag('❌ FIRESTORE ERROR: code=${e.code} message=${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firestore error: ${e.code}')),
        );
      }
    } catch (e) {
      _appendDiag('❌ GENERIC ERROR: $e');
    }

    if (mounted) setState(() => _diagRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final allowed =
        _myBadge == BadgeType.support || _isOwner;
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('الدعم الفني')),
        body: const Center(child: Text('غير مصرح بالوصول')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الدعم الفني'),
        actions: [
          IconButton(
            tooltip: 'تشخيص users/ والـ claims',
            icon: const Icon(Icons.bug_report),
            onPressed: _seedAndDebug,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            const Tab(text: 'المجتمع', icon: Icon(Icons.forum)),
            const Tab(text: 'موافقات المدربين', icon: Icon(Icons.verified_user)),
            const Tab(text: 'طلبات العناصر', icon: Icon(Icons.restaurant)),
            if (_isOwner)
              const Tab(text: 'المستخدمون', icon: Icon(Icons.people_alt)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_diag != null && _diag!.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _diag!,
                          style: const TextStyle(height: 1.3),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _diag = null),
                      tooltip: 'إخفاء التشخيص',
                    )
                  ],
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const _CommunityModerationTab(),
                const AdminTrainerApprovalsScreen(),
                AdminFoodSubmissionsScreen(),
                if (_isOwner) const _UsersAdminTab(), // 👈 يظهر للمالك فقط
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===== تبويب المجتمع =====
class _CommunityModerationTab extends StatelessWidget {
  const _CommunityModerationTab();

  bool _isHttp(String p) =>
      p.startsWith('http://') || p.startsWith('https://');

  Widget _imageWidget(String path) {
    final placeholder = Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
    if (_isHttp(path)) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return Image.file(
      File(path),

      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final postsRepo = LocalPostsRepo();
    final mod = ModerationRepo();

    return StreamBuilder<List<Post>>(
      stream: postsRepo.watchFeed(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'خطأ: ${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final posts = snap.data ?? const <Post>[];
        if (posts.isEmpty) {
          return const Center(child: Text('لا توجد منشورات'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final p = posts[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الكاتب: ${p.authorId}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(p.caption),
                    const SizedBox(height: 8),
                    if (p.imagePaths.isNotEmpty)
                      SizedBox(
                        height: 160,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: p.imagePaths.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final path = p.imagePaths[idx];
                            return AspectRatio(
                              aspectRatio: 1,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _imageWidget(path),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            await postsRepo.deletePost(p.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم حذف البوست')),
                            );
                          },
                          icon: const Icon(Icons.delete),
                          label: const Text('حذف البوست'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final days = await _pickBanDays(context);
                            if (days == null) return;
                            await mod.banUser(p.authorId, days: days);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('تم إيقاف المستخدم $days يوم')),
                            );
                          },
                          icon: const Icon(Icons.gavel),
                          label: const Text('إيقاف أيام'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await mod.unbanUser(p.authorId);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم إلغاء الإيقاف')),
                            );
                          },
                          icon: const Icon(Icons.lock_open),
                          label: const Text('إلغاء الإيقاف'),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final ok = await _confirm(
                              context,
                              'حذف الحساب سيحذف جميع منشوراته. هل أنت متأكد؟',
                            );
                            if (ok != true) return;
                            await mod.deleteUser(p.authorId); // ← توقيع موحّد (positional)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم حذف الحساب ومحتواه')),
                            );
                          },
                          icon: const Icon(Icons.person_remove),
                          label: const Text('حذف الحساب'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<int?> _pickBanDays(BuildContext context) async {
    final ctrl = TextEditingController(text: '7');
    return showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('مدّة الإيقاف (أيام)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0 = دائم'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              Navigator.pop(c, v ?? 0);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(BuildContext context, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }
}

/// ===== تبويب المستخدمين (للـ Owner فقط) =====
class _UsersAdminTab extends StatefulWidget {
  const _UsersAdminTab();

  @override
  State<_UsersAdminTab> createState() => _UsersAdminTabState();
}

class _UsersAdminTabState extends State<_UsersAdminTab> {
  final _repo = UserAdminRepo();
  List<AppUser> _all = [];
  List<AppUser> _filtered = [];
  String _q = '';

  // تشخيص
  bool _loading = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final users = await _repo.listAllUsers();
      setState(() {
        _all = users;
        _apply();
      });
    } on FirebaseException catch (e) {
      setState(() => _err = 'Firestore: ${e.code}');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply() {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = _all;
    } else {
      _filtered = _all
          .where((u) =>
              u.username.toLowerCase().contains(q) ||
              (u.email).toLowerCase().contains(q) ||
              u.uid.toLowerCase().contains(q))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return Center(
        child: Text(_err!, style: const TextStyle(color: Colors.red)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'بحث باسم/إيميل/UID',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              setState(() {
                _q = v;
                _apply();
              });
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _filtered.isEmpty
                ? const Center(child: Text('لا يوجد مستخدمون'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final u = _filtered[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(u.username),
                        subtitle: Text(u.email),
                        trailing: Icon(Icons.chevron_right, color: cs.outline),
                        onTap: () => _openUser(context, u),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openUser(BuildContext context, AppUser u) async {
    // ✅ القراءة بالـ UID فقط
    final badge = await getBadge(u.uid);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) {
        BadgeType current = badge;
        return StatefulBuilder(builder: (c, setSt) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.person)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${u.username}\n${u.email}')),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BadgeType>(
                  initialValue: current,
                  decoration: const InputDecoration(labelText: 'الرتبة'),
                  items: const [
                    DropdownMenuItem(value: BadgeType.none, child: Text('بدون')),
                    DropdownMenuItem(value: BadgeType.verified, child: Text('موثّق')),
                    DropdownMenuItem(value: BadgeType.coach, child: Text('مدرب')),
                    DropdownMenuItem(value: BadgeType.support, child: Text('دعم فني')),
                    DropdownMenuItem(value: BadgeType.owner, child: Text('مالك')),
                  ],
                  onChanged: (v) => setSt(() => current = v ?? BadgeType.none),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('حفظ الرتبة'),
                      onPressed: () async {
                        // ✅ الحفظ بالـ UID فقط
                        await setBadge(u.uid, current);

                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم تحديث الرتبة')),
                        );

                        // تحديث القائمة
                        await _load();
                      },
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('إلغاء'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.gavel),
                      label: const Text('إيقاف 7 أيام'),
                      onPressed: () async {
                        await ModerationRepo().banUser(u.uid, days: 7);
                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم الإيقاف 7 أيام')),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lock_open),
                      label: const Text('إلغاء الإيقاف'),
                      onPressed: () async {
                        await ModerationRepo().unbanUser(u.uid);
                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم إلغاء الإيقاف')),
                        );
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.person_remove),
                      label: const Text('حذف الحساب'),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('تأكيد حذف الحساب'),
                            content: const Text('سيتم حذف الحساب وجميع منشوراته.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('رجوع'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ModerationRepo().deleteUser(u.uid); // ← positional
                          if (mounted) Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم حذف الحساب')),
                          );
                          await _load();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        });
      },
    );
  }
}

// lib/features/admin_support/admin_support_dashboard_page.dart
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/roles_service.dart'; // AppRole, RolesService
import '../announcement/announcement_editor_page.dart';
import '../../settings/contact_page.dart';

/// لوحة موحّدة للمالك/الأدمن/الدعم
/// - تبويب واحد: إدارة المستخدمين
/// - تعرض الاسم/اليوزر/الإيميل/الصورة/النقاط/الدور/الحظر
/// - أوامر: تغيير الدور، حظر/فكّ الحظر، تعليق/إلغاء تعليق نشر الوصفات،
 ///          زيادة/إنقاص/تعيين النقاط، إرسال إشعار
class AdminSupportDashboardPage extends StatefulWidget {
  const AdminSupportDashboardPage({super.key});

  @override
  State<AdminSupportDashboardPage> createState() => _AdminSupportDashboardPageState();
}

class _AdminSupportDashboardPageState extends State<AdminSupportDashboardPage> {
  late final Future<AppRole> _roleFuture = RolesService().currentUserRoleOnce();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRole>(
      future: _roleFuture,
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
          child: Stack(
            children: [
              _HealthBackground(),
              Scaffold(
                backgroundColor: Colors.transparent,
                extendBodyBehindAppBar: false,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  titleSpacing: 16,
                  title: _AdminHeaderTitle(role: role),
                  flexibleSpace: _GlassAppBarBackground(),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(58),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: _GlassTabBar(),
                    ),
                  ),
                ),
                body: TabBarView(
                  physics: NeverScrollableScrollPhysics(),
                  children: [
                    _UsersTab(role: role),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// خلفية صحية فخمة (UI فقط)
class _HealthBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.20),
            cs.secondary.withOpacity(0.14),
            cs.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _BlurBlob(color: cs.primary.withOpacity(0.28), size: 220),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: _BlurBlob(color: cs.secondary.withOpacity(0.22), size: 260),
          ),
          Positioned(
            top: 140,
            left: -40,
            child: _BlurBlob(color: cs.tertiary.withOpacity(0.18), size: 160),
          ),
        ],
      ),
    );
  }
}

class _BlurBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _BlurBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
          ),
        ),
      ),
    );
  }
}

class _GlassAppBarBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surface.withOpacity(0.75),
                cs.surface.withOpacity(0.25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.45),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            indicator: BoxDecoration(
              color: cs.primary.withOpacity(0.20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.35)),
            ),
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'المستخدمون'),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminHeaderTitle extends StatelessWidget {
  final AppRole role;
  const _AdminHeaderTitle({required this.role});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final title = role == AppRole.owner
        ? 'لوحة المالك'
        : (role == AppRole.admin ? 'لوحة الأدمن' : 'لوحة الدعم');

    final badgeText = role == AppRole.owner
        ? 'Owner'
        : (role == AppRole.admin ? 'Admin' : 'Support');

    final badgeIcon = role == AppRole.owner
        ? Icons.verified_rounded
        : (role == AppRole.admin ? Icons.admin_panel_settings_rounded : Icons.support_agent_rounded);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('إدارة المستخدمين والإعلان العام', style: tt.bodySmall),
            ],
          ),
        ),
        _Pill(
          icon: badgeIcon,
          label: badgeText,
          tone: role == AppRole.owner
              ? _PillTone.primary
              : (role == AppRole.admin ? _PillTone.secondary : _PillTone.neutral),
        ),
      ],
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
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        // ===== الإعلان العام (بانر التطبيق) =====
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.doc('appConfig/announcement').snapshots(),
          builder: (context, snap) {
            final allowAdmin = (snap.data?.data()?['allowAdminEdit'] == true);
            final canEdit = (widget.role == AppRole.owner) ||
                (widget.role == AppRole.admin && allowAdmin);

            // نفس منطقك: إخفاء القسم إن ما عنده صلاحية (والمالك يشوفه دائمًا)
            if (!canEdit && widget.role != AppRole.owner) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: _GlassCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الإعلان العام (بانر التطبيق)',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'إدارة إعلان التطبيق من مكان واحد بدون إظهار إحصائيات المستخدمين للأدمن.',
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: canEdit
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AnnouncementEditorPage(),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل'),
                    ),
                    if (widget.role == AppRole.owner) ...[
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('السماح للإدمن'),
                          Switch(
                            value: allowAdmin,
                            onChanged: (v) async {
                              await _db
                                  .doc('appConfig/announcement')
                                  .set({'allowAdminEdit': v}, SetOptions(merge: true));
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

        // ===== شريط البحث =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: _GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
        ),

        // ===== قائمة المستخدمين =====
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('users').limit(120).snapshots(),
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

              final isOwner = widget.role == AppRole.owner;

              // الخصوصية: أعداد المستخدمين والنتائج والإحصائيات تظهر للمالك فقط.
              // الأدمن/الدعم يقدرون يديرون المستخدمين بدون معرفة إجمالي التحميلات أو عدد النتائج.
              final totalUsers = isOwner ? docs.length : null;
              int bannedCount = 0;
              int staffCount = 0;
              int adminsCount = 0;

              if (isOwner) {
                for (final d in docs) {
                  final data = d.data();
                  final role = (data['role'] ?? 'user').toString();
                  final banned = (data['isBanned'] ?? false) == true;
                  if (banned) bannedCount++;
                  if (role == 'owner' || role == 'admin' || role == 'support') staffCount++;
                  if (role == 'admin') adminsCount++;
                }
              }

              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Center(
                    child: _GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.search_off_rounded),
                          SizedBox(height: 10),
                          Text('لا يوجد نتائج'),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Scrollbar(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: filtered.length + 2,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: _StatsGrid(
                          showTotalUsers: isOwner,
                          totalUsers: totalUsers ?? 0,
                          results: filtered.length,
                          bannedCount: bannedCount,
                          staffCount: staffCount,
                          adminsCount: adminsCount,
                        ),
                      );
                    }

                    if (index == 1) {
                      return _GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.people_alt_rounded),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'المستخدمون',
                                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            _Pill(
                              icon: Icons.filter_alt_rounded,
                              label: isOwner
                                  ? '${filtered.length} / ${totalUsers ?? filtered.length}'
                                  : 'العدد مخفي',
                              tone: _PillTone.neutral,
                            ),
                          ],
                        ),
                      );
                    }

                    final doc = filtered[index - 2];
                    final data = doc.data();
                    final uid = doc.id;

                    final name = _nameFrom(data) ?? 'بدون اسم';
                    final handle = _handleFrom(data) ?? '';
                    final email = _emailFrom(data) ?? '';
                    final role = (data['role'] ?? 'user').toString();
                    final banned = (data['isBanned'] ?? false) == true;
                    final points = _readUserPoints(data);
                    final photo = _photoFrom(data);
                    final banReason =
                        (data['banReason'] ?? data['bannedReason'] ?? data['ban_reason'])
                            ?.toString();
                    final bannedUntil = _readDateTime(
                      data['bannedUntil'] ?? data['banUntil'] ?? data['banned_until'],
                    );


                    return _UserCard(
                      uid: uid,
                      name: name,
                      handle: handle,
                      email: email,
                      role: role,
                      points: points,
                      banned: banned,
                      photoUrl: photo,
                      onOpen: () => _openUserActions(
                        context,
                        uid: uid,
                        name: name,
                        handle: handle,
                        email: email,
                        photoUrl: photo,
                        currentPoints: points,
                        role: role,
                        banned: banned,
                        banReason: banReason,
                        bannedUntil: bannedUntil,
                      ),
                    );
                  },
                ),
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
    String? banReason,
    DateTime? bannedUntil,
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
        viewerRole: widget.role,
        initialBanReason: banReason,
        initialBannedUntil: bannedUntil,
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
  /// قراءة تاريخ من أنواع متعددة (Timestamp/DateTime/String/int) — للعرض فقط
  DateTime? _readDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) {
      // غالبًا millisecondsSinceEpoch
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {
        return null;
      }
    }
    if (v is Map) {
      final s = v['seconds'];
      if (s is int) {
        return DateTime.fromMillisecondsSinceEpoch(s * 1000);
      }
    }
    return null;
  }

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

/// كرت زجاجي (UI فقط) — لا يغيّر المنطق
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const _GlassCard({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // BackdropFilter داخل كل كرت في قائمة طويلة يستهلك GPU/RAM كثير،
    // وكان ممكن يسبب تهنيق أو كراش في لوحة الإدارة.
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.82),
        borderRadius: borderRadius,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
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

/// شارة صغيرة (Chip) بشكل أنيق لعرض الدور/الحالة/الإحصاءات
enum _PillTone { primary, secondary, danger, neutral }

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final _PillTone tone;

  const _Pill({
    required this.icon,
    required this.label,
    required this.tone,
  });

  Color _base(ColorScheme cs) {
    switch (tone) {
      case _PillTone.primary:
        return cs.primary;
      case _PillTone.secondary:
        return cs.secondary;
      case _PillTone.danger:
        return cs.error;
      case _PillTone.neutral:
      default:
        return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = _base(cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: base.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: base.withOpacity(0.95)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: base.withOpacity(0.95))),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? caption;
  final _PillTone tone;

  const _MetricTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Color base;
    switch (tone) {
      case _PillTone.primary:
        base = cs.primary;
        break;
      case _PillTone.secondary:
        base = cs.secondary;
        break;
      case _PillTone.danger:
        base = cs.error;
        break;
      case _PillTone.neutral:
      default:
        base = cs.outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: base.withOpacity(0.25)),
        color: base.withOpacity(0.06),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: base.withOpacity(0.14),
            ),
            child: Icon(icon, size: 18, color: base.withOpacity(0.95)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(value, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final bool showTotalUsers;
  final int totalUsers;
  final int results;
  final int bannedCount;
  final int staffCount;
  final int adminsCount;

  const _StatsGrid({
    required this.showTotalUsers,
    required this.totalUsers,
    required this.results,
    required this.bannedCount,
    required this.staffCount,
    required this.adminsCount,
  });

  @override
  Widget build(BuildContext context) {
    // الأدمن/الدعم: لا نعرض أي رقم يوضح عدد مستخدمي التطبيق أو نتائج البحث.
    if (!showTotalUsers) {
      return _MetricTile(
        icon: Icons.lock_outline_rounded,
        title: 'النتائج',
        value: 'للاونر فقط',
        caption: 'تم إخفاء أعداد المستخدمين والإحصائيات عن الأدمن والدعم.',
        tone: _PillTone.primary,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 720;

        final totalTile = _MetricTile(
          icon: Icons.people_alt_rounded,
          title: 'الإجمالي',
          value: '$totalUsers',
          caption: 'كل المستخدمين',
          tone: _PillTone.neutral,
        );

        final resultsTile = _MetricTile(
          icon: Icons.filter_alt_rounded,
          title: 'نتائج البحث',
          value: '$results',
          caption: 'حسب الفلتر الحالي',
          tone: _PillTone.primary,
        );

        final staffTile = _MetricTile(
          icon: Icons.shield_rounded,
          title: 'الطاقم',
          value: '$staffCount',
          caption: 'Admins: $adminsCount',
          tone: _PillTone.secondary,
        );

        final bannedTile = _MetricTile(
          icon: Icons.block_rounded,
          title: 'محظور',
          value: '$bannedCount',
          caption: 'الحسابات المحظورة',
          tone: _PillTone.danger,
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: totalTile),
              const SizedBox(width: 10),
              Expanded(child: resultsTile),
              const SizedBox(width: 10),
              Expanded(child: staffTile),
              const SizedBox(width: 10),
              Expanded(child: bannedTile),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: totalTile),
                const SizedBox(width: 10),
                Expanded(child: resultsTile),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: staffTile),
                const SizedBox(width: 10),
                Expanded(child: bannedTile),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  final String uid;
  final String name;
  final String handle;
  final String email;
  final String role;
  final int points;
  final bool banned;
  final String? photoUrl;
  final VoidCallback onOpen;

  const _UserCard({
    required this.uid,
    required this.name,
    required this.handle,
    required this.email,
    required this.role,
    required this.points,
    required this.banned,
    required this.photoUrl,
    required this.onOpen,
  });

  static _PillTone roleTone(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return _PillTone.primary;
      case 'admin':
        return _PillTone.secondary;
      case 'support':
        return _PillTone.neutral;
      default:
        return _PillTone.neutral;
    }
  }

  static String roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'مالك';
      case 'admin':
        return 'أدمن';
      case 'support':
        return 'دعم';
      default:
        return 'مستخدم';
    }
  }

  String _subtitle() {
    final parts = <String>[];
    if (handle.isNotEmpty) parts.add('@$handle');
    if (email.isNotEmpty) parts.add(email);
    parts.add('UID: $uid');
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return _GlassCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(photoUrl: photoUrl, fallbackText: name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (banned) ...[
                        const SizedBox(width: 8),
                        const _Pill(
                          icon: Icons.block_rounded,
                          label: 'محظور',
                          tone: _PillTone.danger,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle(),
                    style: tt.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(
                        icon: Icons.badge_rounded,
                        label: roleLabel(role),
                        tone: roleTone(role),
                      ),
                      _Pill(
                        icon: Icons.stars_rounded,
                        label: 'النقاط: $points',
                        tone: _PillTone.neutral,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onOpen,
              tooltip: 'إدارة',
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: cs.outlineVariant.withOpacity(0.75),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SheetSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return _GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withOpacity(0.12),
                ),
                child: Icon(icon, size: 18, color: cs.primary.withOpacity(0.95)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
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
  final AppRole viewerRole;
  final String? initialBanReason;
  final DateTime? initialBannedUntil;

  const _UserActionsSheet({
    required this.uid,
    required this.displayName,
    required this.handle,
    required this.email,
    required this.photoUrl,
    required this.initialRole,
    required this.initialBanned,
    required this.initialPoints,
    required this.viewerRole,
    this.initialBanReason,
    this.initialBannedUntil,
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
  final _banReasonCtrl = TextEditingController();
  DateTime? _bannedUntil;
  String _banPreset = 'دائم';

  // تعليق النشر حتى تاريخ/ساعة
  DateTime? _suspendUntil;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _banned = widget.initialBanned;
    _points = widget.initialPoints;
    _pointsCtrl.text = _points.toString();

    _banReasonCtrl.text = (widget.initialBanReason ?? '').trim();
    _bannedUntil = widget.initialBannedUntil;
    _banPreset = _bannedUntil == null ? 'دائم' : 'مخصص';

    // جلب قيم recipesSuspendedUntil + بيانات الحظر (اختياري للعرض)
    _db.doc('users/${widget.uid}').get().then((snap) {
      final data = snap.data();

      // تعليق نشر الوصفات
      DateTime? suspend;
      final ts = data?['recipesSuspendedUntil'];
      if (ts is Timestamp) suspend = ts.toDate();

      // بيانات الحظر
      final br = data?['banReason'] ?? data?['bannedReason'] ?? data?['ban_reason'];
      final until = data?['bannedUntil'] ?? data?['banUntil'] ?? data?['banned_until'];
      DateTime? bu;
      if (until is Timestamp) bu = until.toDate();
      if (until is DateTime) bu = until;
      if (until is String) bu = DateTime.tryParse(until);
      if (until is int) {
        try { bu = DateTime.fromMillisecondsSinceEpoch(until); } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _suspendUntil = suspend;
        if (br != null && br.toString().trim().isNotEmpty) {
          _banReasonCtrl.text = br.toString().trim();
        }
        _bannedUntil = bu ?? _bannedUntil;
        _banPreset = _bannedUntil == null ? 'دائم' : 'مخصص';
      });
    });
  }

  @override
  void dispose() {
    _notifyTitle.dispose();
    _notifyBody.dispose();
    _pointsCtrl.dispose();
    _banReasonCtrl.dispose();
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
    final next = !_banned;
    try {
      await _roles.setBanned(widget.uid, next);
      await _persistBanMeta(banned: next);
      if (!mounted) return;
      setState(() => _banned = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_banned ? 'تم الحظر' : 'تم إلغاء الحظر')),
      );
    } catch (e) {
      _err('خطأ الحظر', e);
    }
  }

  Future<void> _persistBanMeta({required bool banned}) async {
    // حفظ/مسح سبب ومدة الحظر في وثيقة المستخدم (اختياري للعرض في شاشة الحظر)
    final ref = _db.doc('users/${widget.uid}');
    if (banned) {
      await ref.set({
        'banReason': _banReasonCtrl.text.trim(),
        'bannedUntil': _bannedUntil == null ? null : Timestamp.fromDate(_bannedUntil!),
        'bannedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await ref.set({
        'banReason': null,
        'bannedUntil': null,
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _banReasonCtrl.text = '';
          _bannedUntil = null;
          _banPreset = 'دائم';
        });
      }
    }
  }

  void _applyBanPreset(String preset) {
    final now = DateTime.now();
    DateTime? until;
    switch (preset) {
      case 'دائم':
        until = null;
        break;
      case '24 ساعة':
        until = now.add(const Duration(hours: 24));
        break;
      case '3 أيام':
        until = now.add(const Duration(days: 3));
        break;
      case '7 أيام':
        until = now.add(const Duration(days: 7));
        break;
      case '30 يوم':
        until = now.add(const Duration(days: 30));
        break;
      default:
        until = _bannedUntil;
    }
    setState(() {
      _banPreset = preset;
      _bannedUntil = until;
    });
  }

  Future<void> _pickBannedUntil() async {
    final now = DateTime.now();
    final initDate = _bannedUntil ?? now.add(const Duration(days: 7));

    final pickedDate = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: initDate,
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initDate),
    );
    if (pickedTime == null) return;

    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (!mounted) return;
    setState(() {
      _banPreset = 'مخصص';
      _bannedUntil = dt;
    });
  }

  String _formatDt(DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final d = loc.formatFullDate(dt);
    final t = loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt), alwaysUse24HourFormat: true);
    return '$d • $t';
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
      // مهم: الإرسال القديم كان يكتب فقط داخل Firestore Inbox، لذلك ما كان يوصل Push فعلي.
      // الآن نستدعي Cloud Function التي ترسل FCM وتحفظ نسخة داخل صندوق المستخدم.
      final current = FirebaseAuth.instance.currentUser;
      final idToken = await current?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        throw Exception('سجّل دخولك مرة أخرى حتى نقدر نرسل الإشعار.');
      }

      final uri = Uri.parse(
        'https://europe-west1-wazenfapp.cloudfunctions.net/adminSendUserPushNotification',
      );
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'uid': widget.uid,
          'title': title,
          'body': body,
          'deeplink': '/notifications',
        }),
      );

      final raw = response.body.trim();
      Map<String, dynamic> data = const <String, dynamic>{};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final msg = (data['message'] ?? data['error'] ?? raw).toString();
        throw Exception(msg.isEmpty ? 'فشل إرسال الإشعار' : msg);
      }

      if (!mounted) return;
      _notifyTitle.clear();
      _notifyBody.clear();

      final tokenCount = data['tokenCount'] ?? 0;
      final successCount = data['successCount'] ?? 0;
      final message = (data['message'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isNotEmpty
                ? '$message التوكنات: $tokenCount — الناجحة: $successCount'
                : 'تم إرسال الإشعار الفعلي. التوكنات: $tokenCount — الناجحة: $successCount',
          ),
        ),
      );
    } catch (e) {
      _err('خطأ الإشعار الفعلي', e);
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const _SheetHandle(),
              const SizedBox(height: 12),

              // ===== بطاقة هوية المستخدم =====
              _GlassCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(photoUrl: widget.photoUrl, fallbackText: widget.displayName),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.displayName,
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (widget.handle.isNotEmpty) '@${widget.handle}',
                              if (widget.email.isNotEmpty) widget.email,
                              'UID: ${widget.uid}',
                            ].join(' • '),
                            style: tt.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Pill(
                                icon: Icons.badge_rounded,
                                label: 'Role: $_role',
                                tone: _UserCard.roleTone(_role),
                              ),
                              _Pill(
                                icon: Icons.stars_rounded,
                                label: 'النقاط: $_points',
                                tone: _PillTone.neutral,
                              ),
                              if (_banned)
                                const _Pill(
                                  icon: Icons.block_rounded,
                                  label: 'محظور',
                                  tone: _PillTone.danger,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ===== الدور =====
              if (widget.viewerRole == AppRole.owner) ...[
                _SheetSection(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'الصلاحيات والدور',
                  child: Column(
                    children: [
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
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saveRole,
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ الدور'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ===== الحظر وتعليق النشر =====
              _SheetSection(
                icon: Icons.security_rounded,
                title: 'الحظر والنشر',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _banned,
                      onChanged: (_) => _toggleBan(),
                      title: const Text('حظر المستخدم'),
                      subtitle: Text(_banned ? 'الحظر مفعل' : 'الحظر غير مفعل'),
                    ),
                    TextField(
                      controller: _banReasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'سبب الحظر (اختياري)',
                        prefixIcon: Icon(Icons.report_gmailerrorred_rounded),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _banPreset,
                      decoration: const InputDecoration(
                        labelText: 'مدة الحظر',
                        prefixIcon: Icon(Icons.timer_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'دائم',
                          child: Text('دائم (حتى فك الحظر)'),
                        ),
                        DropdownMenuItem(value: '24 ساعة', child: Text('24 ساعة')),
                        DropdownMenuItem(value: '3 أيام', child: Text('3 أيام')),
                        DropdownMenuItem(value: '7 أيام', child: Text('7 أيام')),
                        DropdownMenuItem(value: '30 يوم', child: Text('30 يوم')),
                        DropdownMenuItem(
                          value: 'مخصص',
                          child: Text('تحديد تاريخ/وقت'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        if (v == 'مخصص') {
                          _pickBannedUntil();
                        } else {
                          _applyBanPreset(v);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _bannedUntil == null
                                  ? 'مدة الحظر: دائم (حتى يتم فكّه من الإدارة)'
                                  : 'ينتهي الحظر: ${_formatDt(_bannedUntil!)}',
                              style: tt.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _banned ? () => _persistBanMeta(banned: true) : null,
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('حفظ بيانات الحظر'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ContactPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.support_agent_rounded),
                            label: const Text('تواصل مع الدعم'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickSuspendUntil,
                            icon: const Icon(Icons.schedule_rounded),
                            label: Text(
                              _suspendUntil == null
                                  ? 'تعليق نشر الوصفات'
                                  : 'تغيير موعد التعليق',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearSuspend,
                            icon: const Icon(Icons.undo_rounded),
                            label: const Text('إلغاء التعليق'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _GlassCard(
                      padding: const EdgeInsets.all(12),
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: cs.primary.withOpacity(0.9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _suspendUntil == null
                                  ? 'النشر غير معلّق حاليًا.'
                                  : 'النشر معلّق حتى: ${_suspendUntil!.toString()}',
                              style: tt.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ===== النقاط =====
              _SheetSection(
                icon: Icons.stars_rounded,
                title: 'النقاط والمكافآت',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الرصيد الحالي', style: tt.labelLarge),
                    const SizedBox(height: 6),
                    Text('$_points',
                        style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pointsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'تعيين نقاط محددة',
                        prefixIcon: Icon(Icons.edit_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _savePoints,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('حفظ النقاط'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('تعديلات سريعة', style: tt.labelLarge),
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
                        OutlinedButton(
                          onPressed: () => _incrementPoints(-10),
                          child: const Text('-10'),
                        ),
                        OutlinedButton(
                          onPressed: () => _incrementPoints(10),
                          child: const Text('+10'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ===== الإشعارات =====
              _SheetSection(
                icon: Icons.notifications_active_rounded,
                title: 'إشعار فعلي للتطبيق',
                child: Column(
                  children: [
                    TextField(
                      controller: _notifyTitle,
                      decoration: const InputDecoration(
                        labelText: 'عنوان الإشعار',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notifyBody,
                      decoration: const InputDecoration(
                        labelText: 'نص الإشعار',
                        prefixIcon: Icon(Icons.message_rounded),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _sendNotification,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('إرسال Push فعلي'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // تلميح صغير (نفس منطقك)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
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
          );
        },
      ),
    );
  }
}
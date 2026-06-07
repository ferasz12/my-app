// lib/features/admin_support/admin_support_dashboard_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/roles_service.dart'; // AppRole, RolesService
import '../announcement/announcement_editor_page.dart';
import '../../settings/contact_page.dart';
import '../../models/community_models.dart';

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
          return const Scaffold(body: Center(child: Text('يتم تجهيز اللوحة...')));
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
          length: 2,
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
                    _ReportsTab(role: role),
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withOpacity(0.55)),
      ),
    );
  }
}

class _GlassAppBarBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.94),
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.35))),
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surface,
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
          Tab(icon: Icon(Icons.flag_rounded), text: 'البلاغات'),
          Tab(icon: Icon(Icons.people_alt_rounded), text: 'المستخدمون'),
        ],
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
              Text('بلاغات المجتمع، إدارة المستخدمين والإعلان العام', style: tt.bodySmall),
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
/// تبويب (بلاغات المجتمع)
/// ============================
class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.role});
  final AppRole role;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  final _db = FirebaseFirestore.instance;
  String _filter = 'open';

  Stream<List<CommunityReport>> _reportsStream() {
    return _db
        .collection('communityReports')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(CommunityReport.fromDoc).toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityReport>>(
      stream: _reportsStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Text('يتم تجهيز البيانات...'));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text('تعذر تحميل البلاغات: ${snap.error}'),
            ),
          );
        }

        final all = snap.data ?? const <CommunityReport>[];
        final openCount = all.where((r) => r.status == 'open').length;
        final hiddenCount = all.where((r) => r.status == 'post_hidden').length;
        final bannedCount = all.where((r) => r.status == 'author_banned').length;
        final resolvedCount = all.where((r) => r.status == 'resolved' || r.status == 'rejected').length;

        final filtered = _filter == 'all'
            ? all
            : all.where((r) {
                if (_filter == 'resolved') return r.status == 'resolved' || r.status == 'rejected';
                return r.status == _filter;
              }).toList(growable: false);

        return RefreshIndicator(
          onRefresh: () async {
            await _db.collection('communityReports').limit(1).get();
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            itemCount: filtered.isEmpty ? 3 : filtered.length + 2,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.health_and_safety_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'مركز بلاغات مجتمع وازن',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          _Pill(icon: Icons.flag_rounded, label: '$openCount جديد', tone: _PillTone.danger),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ReportStatsRow(
                        total: all.length,
                        open: openCount,
                        hidden: hiddenCount,
                        banned: bannedCount,
                        resolved: resolvedCount,
                      ),
                    ],
                  ),
                );
              }

              if (index == 1) {
                return _GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ReportFilterChip(label: 'الجديدة', value: 'open', selected: _filter, onSelected: _setFilter),
                        _ReportFilterChip(label: 'الكل', value: 'all', selected: _filter, onSelected: _setFilter),
                        _ReportFilterChip(label: 'مخفية', value: 'post_hidden', selected: _filter, onSelected: _setFilter),
                        _ReportFilterChip(label: 'محظور', value: 'author_banned', selected: _filter, onSelected: _setFilter),
                        _ReportFilterChip(label: 'معالجة/مرفوضة', value: 'resolved', selected: _filter, onSelected: _setFilter),
                      ],
                    ),
                  ),
                );
              }

              if (filtered.isEmpty) {
                return const _GlassCard(
                  padding: EdgeInsets.all(18),
                  child: Center(child: Text('لا توجد بلاغات في هذا القسم')),
                );
              }

              final report = filtered[index - 2];
              return _ReportCard(report: report, onOpen: () => _openReportSheet(report));
            },
          ),
        );
      },
    );
  }

  void _setFilter(String value) => setState(() => _filter = value);

  Future<void> _openReportSheet(CommunityReport report) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (context, controller) {
            final tt = Theme.of(context).textTheme;
            final cs = Theme.of(context).colorScheme;
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              children: [
                Text('تفاصيل البلاغ', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Pill(icon: Icons.flag_rounded, label: report.reasonLabelAr, tone: _PillTone.danger),
                          _Pill(icon: Icons.pending_actions_rounded, label: report.statusLabelAr, tone: report.isOpen ? _PillTone.danger : _PillTone.primary),
                          _Pill(icon: Icons.category_rounded, label: report.postCategory.labelAr, tone: _PillTone.neutral),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ReportInfoLine(icon: Icons.person_search_rounded, label: 'المبلّغ', value: '${report.reporterName} • ${report.reporterUid}'),
                      _ReportInfoLine(icon: Icons.person_rounded, label: 'صاحب المنشور', value: '${report.postAuthorName} • ${report.postAuthorUid}'),
                      _ReportInfoLine(icon: Icons.schedule_rounded, label: 'وقت البلاغ', value: _formatDate(context, report.createdAt)),
                      if (report.reviewedAt != null)
                        _ReportInfoLine(icon: Icons.done_all_rounded, label: 'آخر معالجة', value: _formatDate(context, report.reviewedAt!)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('محتوى المنشور', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      SelectableText(report.postContent.isEmpty ? 'لا يوجد نص محفوظ للمنشور' : report.postContent),
                      if (report.details.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Divider(color: cs.outlineVariant.withOpacity(0.7)),
                        const SizedBox(height: 8),
                        Text('تفاصيل المبلّغ', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        SelectableText(report.details),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إجراءات الدعم', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _hidePost(report, closeContext: sheetContext),
                            icon: const Icon(Icons.visibility_off_rounded),
                            label: const Text('إخفاء المنشور'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _suspendCommunity(report, days: 7, closeContext: sheetContext),
                            icon: const Icon(Icons.pause_circle_outline_rounded),
                            label: const Text('تعليق المجتمع 7 أيام'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _suspendCommunity(report, days: 30, closeContext: sheetContext),
                            icon: const Icon(Icons.event_busy_rounded),
                            label: const Text('تعليق المجتمع 30 يوم'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _banAuthor(report, closeContext: sheetContext),
                            icon: Icon(Icons.block_rounded, color: cs.error),
                            label: const Text('حظر دائم'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _markReport(report, 'resolved', closeContext: sheetContext),
                            icon: const Icon(Icons.task_alt_rounded),
                            label: const Text('معالجة بدون إجراء'),
                          ),
                          TextButton.icon(
                            onPressed: () => _markReport(report, 'rejected', closeContext: sheetContext),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('رفض البلاغ'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'الإخفاء لا يحذف الداتا نهائيًا؛ فقط يضع isDeleted=true حتى يختفي من المجتمع وتبقى نسخة البلاغ للدعم.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _hidePost(CommunityReport report, {required BuildContext closeContext}) async {
    final moderatorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final batch = _db.batch();
    batch.set(_db.collection('communityPosts').doc(report.postId), {
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': moderatorUid,
      'deleteReason': 'community_report:${report.id}',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('communityReports').doc(report.id), {
      'status': 'post_hidden',
      'reviewedBy': moderatorUid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await _notifyReportHandled(
      report,
      type: 'community_report_post_hidden',
      authorTitle: 'تم إخفاء منشورك في مجتمع وازن',
      authorBody: 'تمت مراجعة منشورك وإخفاؤه بسبب بلاغ وصل إلى الدعم.',
      reporterTitle: 'تمت معالجة بلاغك',
      reporterBody: 'راجع الدعم البلاغ وتم إخفاء المنشور المخالف.',
    );
    if (!mounted) return;
    Navigator.pop(closeContext);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إخفاء المنشور ومعالجة البلاغ')));
  }

  Future<void> _suspendCommunity(CommunityReport report, {required int days, required BuildContext closeContext}) async {
    if (report.postAuthorUid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد UID لصاحب المنشور')));
      return;
    }
    final moderatorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final until = DateTime.now().add(Duration(days: days));
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(report.postAuthorUid), {
      'communitySuspendedUntil': Timestamp.fromDate(until),
      'communitySuspendedReason': 'بلاغ مجتمع: ${report.reasonLabelAr}',
      'communitySuspendedBy': moderatorUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('communityReports').doc(report.id), {
      'status': 'author_suspended',
      'reviewedBy': moderatorUid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'resolutionNote': 'تم تعليق المجتمع $days يوم',
    }, SetOptions(merge: true));
    await batch.commit();
    await _notifyReportHandled(
      report,
      type: 'community_report_author_suspended',
      authorTitle: 'تم تعليق النشر في مجتمع وازن',
      authorBody: 'تم تعليق النشر في المجتمع لمدة $days يوم بسبب مخالفة قواعد المجتمع.',
      reporterTitle: 'تمت معالجة بلاغك',
      reporterBody: 'راجع الدعم البلاغ وتم اتخاذ إجراء على صاحب المنشور.',
    );
    if (!mounted) return;
    Navigator.pop(closeContext);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تعليق نشره في المجتمع $days يوم')));
  }

  Future<void> _banAuthor(CommunityReport report, {required BuildContext closeContext}) async {
    if (report.postAuthorUid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد UID لصاحب المنشور')));
      return;
    }
    final moderatorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(report.postAuthorUid), {
      'isBanned': true,
      'banReason': 'بلاغ مجتمع: ${report.reasonLabelAr}',
      'bannedAt': FieldValue.serverTimestamp(),
      'bannedBy': moderatorUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('communityReports').doc(report.id), {
      'status': 'author_banned',
      'reviewedBy': moderatorUid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await _notifyReportHandled(
      report,
      type: 'community_report_author_banned',
      authorTitle: 'تم حظر حسابك من وازن',
      authorBody: 'تم حظر الحساب بعد مراجعة بلاغ مجتمع وازن.',
      reporterTitle: 'تمت معالجة بلاغك',
      reporterBody: 'راجع الدعم البلاغ وتم اتخاذ إجراء حظر على صاحب المنشور.',
    );
    if (!mounted) return;
    Navigator.pop(closeContext);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حظر صاحب المنشور')));
  }

  Future<void> _markReport(CommunityReport report, String status, {required BuildContext closeContext}) async {
    final moderatorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _db.collection('communityReports').doc(report.id).set({
      'status': status,
      'reviewedBy': moderatorUid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _sendCommunityInboxNotification(
      toUid: report.reporterUid,
      type: status == 'rejected'
          ? 'community_report_rejected'
          : 'community_report_resolved',
      title: status == 'rejected' ? 'تمت مراجعة بلاغك' : 'تمت معالجة بلاغك',
      body: status == 'rejected'
          ? 'راجع الدعم البلاغ ولم يتم اتخاذ إجراء إضافي.'
          : 'راجع الدعم البلاغ وتمت معالجته.',
      postId: report.postId,
      reportId: report.id,
    );
    if (!mounted) return;
    Navigator.pop(closeContext);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث حالة البلاغ')));
  }

  Future<void> _notifyReportHandled(
    CommunityReport report, {
    required String type,
    required String authorTitle,
    required String authorBody,
    required String reporterTitle,
    required String reporterBody,
  }) async {
    await _sendCommunityInboxNotification(
      toUid: report.postAuthorUid,
      type: type,
      title: authorTitle,
      body: authorBody,
      postId: report.postId,
      reportId: report.id,
      priority: 'high',
    );
    await _sendCommunityInboxNotification(
      toUid: report.reporterUid,
      type: '${type}_reporter',
      title: reporterTitle,
      body: reporterBody,
      postId: report.postId,
      reportId: report.id,
    );
  }

  Future<void> _sendCommunityInboxNotification({
    required String toUid,
    required String type,
    required String title,
    required String body,
    required String postId,
    required String reportId,
    String priority = 'normal',
  }) async {
    try {
      final target = toUid.trim();
      if (target.isEmpty) return;
      final moderatorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (moderatorUid.isNotEmpty && moderatorUid == target) return;
      await _db
          .collection('notifications')
          .doc(target)
          .collection('inbox')
          .add({
        'title': title,
        'body': body,
        'notificationType': type,
        'type': type,
        'source': 'community_support',
        'active': true,
        'read': false,
        'priority': priority,
        'senderUid': moderatorUid,
        'senderName': 'دعم وازن',
        'targetUid': target,
        'postId': postId,
        'reportId': reportId,
        'createdAt': FieldValue.serverTimestamp(),
        'scheduledAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // لا نخلي تعطل الإشعار يمنع إجراء الدعم.
    }
  }

  String _formatDate(BuildContext context, DateTime date) {
    final loc = MaterialLocalizations.of(context);
    final d = loc.formatShortDate(date);
    final t = loc.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true);
    return '$d • $t';
  }
}

class _ReportFilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelected;

  const _ReportFilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        selected: selected == value,
        label: Text(label),
        onSelected: (_) => onSelected(value),
      ),
    );
  }
}

class _ReportStatsRow extends StatelessWidget {
  final int total;
  final int open;
  final int hidden;
  final int banned;
  final int resolved;

  const _ReportStatsRow({
    required this.total,
    required this.open,
    required this.hidden,
    required this.banned,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 720;
        final children = [
          _MetricTile(icon: Icons.all_inbox_rounded, title: 'الإجمالي', value: '$total', tone: _PillTone.neutral),
          _MetricTile(icon: Icons.flag_rounded, title: 'جديدة', value: '$open', tone: _PillTone.danger),
          _MetricTile(icon: Icons.visibility_off_rounded, title: 'مخفية', value: '$hidden', tone: _PillTone.primary),
          _MetricTile(icon: Icons.block_rounded, title: 'حظر', value: '$banned', tone: _PillTone.secondary),
          _MetricTile(icon: Icons.done_all_rounded, title: 'منتهية', value: '$resolved', tone: _PillTone.neutral),
        ];
        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: children[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(children: [Expanded(child: children[0]), const SizedBox(width: 8), Expanded(child: children[1])]),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: children[2]), const SizedBox(width: 8), Expanded(child: children[3])]),
            const SizedBox(height: 8),
            children[4],
          ],
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final CommunityReport report;
  final VoidCallback onOpen;

  const _ReportCard({required this.report, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isOpen = report.status == 'open';
    return _GlassCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(photoUrl: report.postAuthorPhotoUrl, fallbackText: report.postAuthorName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.postAuthorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text('بواسطة: ${report.reporterName}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _Pill(icon: isOpen ? Icons.flag_rounded : Icons.task_alt_rounded, label: report.statusLabelAr, tone: isOpen ? _PillTone.danger : _PillTone.primary),
              ],
            ),
            const SizedBox(height: 10),
            Text(report.postContent.isEmpty ? 'لا يوجد نص محفوظ للمنشور' : report.postContent, maxLines: 3, overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(height: 1.35)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(icon: Icons.report_problem_rounded, label: report.reasonLabelAr, tone: _PillTone.danger),
                _Pill(icon: Icons.category_rounded, label: report.postCategory.labelAr, tone: _PillTone.neutral),
                _Pill(icon: Icons.open_in_new_rounded, label: 'استعراض', tone: _PillTone.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportInfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReportInfoLine({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: Text(label, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w900))),
          Expanded(child: SelectableText(value, style: tt.bodySmall)),
        ],
      ),
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
                return const Center(child: Text('يتم تجهيز البيانات...'));
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
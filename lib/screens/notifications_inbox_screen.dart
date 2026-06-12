import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../notifications/wazen_inbox_service.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() => _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  static const _tabs = <_InboxTab>[
    _InboxTab(key: 'all', label: 'الكل', icon: Icons.notifications_rounded),
    _InboxTab(key: 'general', label: 'عامة', icon: Icons.campaign_rounded),
    _InboxTab(key: 'community', label: 'المجتمع', icon: Icons.forum_rounded),
    _InboxTab(key: 'recipes', label: 'الوصفات', icon: Icons.restaurant_menu_rounded),
    _InboxTab(key: 'support', label: 'الدعم', icon: Icons.support_agent_rounded),
  ];

  @override
  void initState() {
    super.initState();
    // أول ما يدخل المستخدم صفحة الإشعارات تعتبر مقروءة.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 450), () async {
      await WazenInboxService.instance.markAllRead();
    }));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إشعارات وازن'),
          actions: [
            IconButton(
              tooltip: 'تحديد الكل كمقروء',
              onPressed: () async {
                await WazenInboxService.instance.markAllRead();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديد الإشعارات كمقروءة')),
                );
              },
              icon: const Icon(Icons.done_all_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final tab in _tabs)
                Tab(
                  icon: Icon(tab.icon, size: 20),
                  text: tab.label,
                ),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: WazenInboxService.instance.inboxStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'تعذر تحميل الإشعارات',
                body: 'تأكد من الاتصال أو صلاحيات Firestore ثم حاول مرة أخرى.',
              );
            }

            final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
              ...?snapshot.data?.docs,
            ].where((doc) => doc.data()['active'] != false).toList();

            if (docs.isEmpty) {
              return const _EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'لا توجد إشعارات',
                body: 'أي رسالة عامة، تفاعل في المجتمع، وصفة، أو رسالة دعم ستظهر هنا.',
              );
            }

            return TabBarView(
              children: [
                for (final tab in _tabs)
                  _NotificationsList(
                    docs: docs.where((doc) {
                      if (tab.key == 'all') return true;
                      return _categoryOf(doc.data()) == tab.key;
                    }).toList(),
                    emptyCategoryLabel: tab.label,
                    colorScheme: cs,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationsList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String emptyCategoryLabel;
  final ColorScheme colorScheme;

  const _NotificationsList({
    required this.docs,
    required this.emptyCategoryLabel,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox_rounded,
        title: 'لا توجد إشعارات في $emptyCategoryLabel',
        body: 'إذا وصل تحديث من هذا النوع سيظهر هنا مباشرة.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data();
        final title = (data['title'] ?? _fallbackTitle(data)).toString().trim();
        final body = (data['body'] ?? '').toString().trim();
        final read = data['read'] == true;
        final category = _categoryOf(data);
        final sender = (data['senderName'] ?? '').toString().trim();

        return Dismissible(
          key: ValueKey(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.delete_rounded, color: colorScheme.onErrorContainer),
          ),
          confirmDismiss: (_) async {
            await WazenInboxService.instance.deleteNotification(doc.id);
            return false;
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => WazenInboxService.instance.markRead(doc.id),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: read
                    ? colorScheme.surface
                    : colorScheme.primaryContainer.withOpacity(0.34),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: read
                      ? colorScheme.outlineVariant.withOpacity(0.55)
                      : colorScheme.primary.withOpacity(0.22),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.65),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_iconOf(category), color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title.isEmpty ? _fallbackTitle(data) : title,
                                style: TextStyle(
                                  fontWeight: read ? FontWeight.w800 : FontWeight.w900,
                                  fontSize: 15.5,
                                ),
                              ),
                            ),
                            if (!read) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (sender.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            sender,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            body,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MiniChip(
                              icon: _iconOf(category),
                              label: _labelOf(category),
                            ),
                            _MiniChip(
                              icon: Icons.schedule_rounded,
                              label: _formatTime(data['createdAt']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: cs.primary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxTab {
  final String key;
  final String label;
  final IconData icon;

  const _InboxTab({required this.key, required this.label, required this.icon});
}

String _categoryOf(Map<String, dynamic> data) {
  final source = (data['source'] ?? '').toString().toLowerCase();
  final type = (data['notificationType'] ?? data['type'] ?? '').toString().toLowerCase();
  final category = (data['category'] ?? '').toString().toLowerCase();

  if (category == 'support' || source.contains('support') || type.contains('support')) {
    return 'support';
  }
  if (category == 'recipes' || category == 'recipe' || source.contains('recipe') || type.contains('recipe')) {
    return 'recipes';
  }
  if (category == 'community' || source.contains('community') || type.contains('comment') || type.contains('like') || type.contains('reply')) {
    return 'community';
  }
  return 'general';
}

String _labelOf(String category) {
  switch (category) {
    case 'support':
      return 'دعم وازن';
    case 'recipes':
      return 'الوصفات';
    case 'community':
      return 'المجتمع';
    default:
      return 'رسالة عامة';
  }
}

IconData _iconOf(String category) {
  switch (category) {
    case 'support':
      return Icons.support_agent_rounded;
    case 'recipes':
      return Icons.restaurant_menu_rounded;
    case 'community':
      return Icons.forum_rounded;
    default:
      return Icons.campaign_rounded;
  }
}

String _fallbackTitle(Map<String, dynamic> data) {
  final category = _categoryOf(data);
  switch (category) {
    case 'support':
      return 'رسالة من دعم وازن';
    case 'recipes':
      return 'تحديث في الوصفات';
    case 'community':
      return 'تفاعل جديد في المجتمع';
    default:
      return 'رسالة عامة من وازن';
  }
}

String _formatTime(dynamic value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (date == null) return 'الآن';

  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';

  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

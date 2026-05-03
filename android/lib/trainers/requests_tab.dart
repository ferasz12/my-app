import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../community/local_repos.dart'; // LocalAuthRepo, LocalChatRepo
import '../community/messages_repo.dart'; // MessagesRepo, MessageRequest
import '../community/public_profile_screen.dart'; // PublicProfileScreen
import '../trainers/payments_gateway.dart'; // لو بتفعل فحص الاشتراك
import '../trainers/payments_router.dart'; // resolveGateway()

class TrainerRequestsTab extends StatefulWidget {
  final String trainerId; // uid المدرّب (الحالي)
  const TrainerRequestsTab({super.key, required this.trainerId});

  @override
  State<TrainerRequestsTab> createState() => _TrainerRequestsTabState();
}

class _TrainerRequestsTabState extends State<TrainerRequestsTab> {
  final _msgRepo = MessagesRepo();
  final _auth = LocalAuthRepo();
  final _chat = LocalChatRepo();
  late final PaymentsGateway _gateway;

  // كاش بسيط لحالة الاشتراك لكل مستخدم
  final Map<String, bool> _subCache = {};
  final _fmt = DateFormat.yMMMd("ar").add_Hm();

  @override
  void initState() {
    super.initState();
    _gateway = resolveGateway();
  }

  // TODO: اربطها بباكندك – الآن ترجع false افتراضيًا
  Future<bool> _isSubscriber(String userId) async {
    if (_subCache.containsKey(userId)) return _subCache[userId]!;
    // مثال: استعلم من باكندك: GET /subscriptions/is-active?userId&trainerId
    // final ok = await YourApi.isActive(userId, widget.trainerId);
    final ok = false;
    _subCache[userId] = ok;
    return ok;
  }

  Future<void> _accept(MessageRequest req) async {
    // 1) حدّث حالة الطلب إلى accepted
    await _msgRepo.updateRequestStatus(req.id, 'accepted');

    // 2) أنشئ أو افتح محادثة مع المرسل
    final chatId =
        await _chat.openOrCreateChatWith(widget.trainerId, req.fromUserId);

    if (!mounted) return;

    // 3) انتقل لصفحة الشات
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        chatId: chatId,
        myUid: widget.trainerId,
        otherUid: req.fromUserId,
      ),
    ));
  }

  Future<void> _reject(MessageRequest req) async {
    await _msgRepo.updateRequestStatus(req.id, 'rejected');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم رفض الطلب')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MessageRequest>>(
      stream: _msgRepo.watchRequestsForTrainer(widget.trainerId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = (snap.data ?? const <MessageRequest>[])
            .where((r) =>
                r.status == 'open' ||
                r.status == 'accepted') // أعرض المفتوح والمقبول
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (items.isEmpty) {
          return const Center(child: Text('لا توجد طلبات حاليًا'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _RequestCard(
            req: items[i],
            fmt: _fmt,
            isSubscriber: _isSubscriber,
            loadUser: _auth.getUserById,
            onOpenProfile: (uid) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PublicProfileScreen(userId: uid),
              ));
            },
            onAccept: _accept,
            onReject: _reject,
          ),
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  final MessageRequest req;
  final DateFormat fmt;
  final Future<bool> Function(String userId) isSubscriber;
  final Future<AppUser?> Function(String uid) loadUser;
  final void Function(String uid) onOpenProfile;
  final Future<void> Function(MessageRequest) onAccept;
  final Future<void> Function(MessageRequest) onReject;

  const _RequestCard({
    required this.req,
    required this.fmt,
    required this.isSubscriber,
    required this.loadUser,
    required this.onOpenProfile,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<AppUser?>(
      future: loadUser(req.fromUserId),
      builder: (context, snap) {
        final user = snap.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                    radius: 22,
                    backgroundImage: (user?.profileImagePath != null)
                        ? AssetImage(user!.profileImagePath!)
                        : null,
                    child: (user?.profileImagePath == null)
                        ? const Icon(Icons.person)
                        : null),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            user?.username ?? 'مستخدم',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        FutureBuilder<bool>(
                          future: isSubscriber(req.fromUserId),
                          builder: (context, s) {
                            final sub = s.data == true;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: sub
                                    ? Colors.green.withOpacity(.1)
                                    : cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(sub ? 'مشترك' : 'غير مشترك',
                                  style: TextStyle(
                                      color: sub
                                          ? Colors.green.shade700
                                          : cs.onSecondaryContainer,
                                      fontSize: 12)),
                            );
                          },
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(req.text,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text(fmt.format(req.createdAt.toLocal()),
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => onOpenProfile(req.fromUserId),
                            icon: const Icon(Icons.account_circle_outlined),
                            label: const Text('الملف الشخصي'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => onAccept(req),
                            icon: const Icon(Icons.check),
                            label: const Text('قبول'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => onReject(req),
                            icon: const Icon(Icons.close),
                            label: const Text('رفض'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ملاحظة: ChatScreen هنا نفترض تواقيعها بالشكل التالي:
/// class ChatScreen extends StatelessWidget {
///   final String chatId, myUid, otherUid;
///   const ChatScreen({super.key, required this.chatId, required this.myUid, required this.otherUid});
///   ...
/// }
/// لو التوقيع مختلف عندك، عدّل الاستدعاء في _accept.

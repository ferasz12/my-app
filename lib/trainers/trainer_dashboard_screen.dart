import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../shared/badges.dart';

import '../community/local_repos.dart'; // LocalAuthRepo, LocalChatRepo
import '../community/models.dart'; // AppUser, ...
import '../community/public_profile_screen.dart'; // PublicProfileScreen(userKey: ...)
import '../community/chat_screen.dart'; // ChatScreen(chatId, me)
import '../shared/user_badges_store.dart';
import 'local_repos.dart'; // LocalTrainersRepo
import 'messages_repo.dart'; // MessagesRepo, MessageRequest

class TrainerDashboardScreen extends StatefulWidget {
  const TrainerDashboardScreen({super.key});

  @override
  State<TrainerDashboardScreen> createState() => _TrainerDashboardScreenState();
}

class _TrainerDashboardScreenState extends State<TrainerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;

  String _trainerId = '';
  BadgeType _myBadge = BadgeType.none;

  final _trainersRepo = LocalTrainersRepo();
  final _msgRepo = MessagesRepo();

  // مشتركون + طلبات
  List<Map<String, dynamic>> _subs = [];
  List<MessageRequest> _requests = [];

  // لتحسين إظهار شارة الاشتراك بسرعة
  final Set<String> _subscriberUids = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final me = await LocalAuthRepo().currentUser();
    _myBadge = await getBadge(me.uid); // إذا مفاتيحك UID بدّلها لـ me.uid
    if (_myBadge != BadgeType.coach && _myBadge != BadgeType.owner) {
      setState(() => _loading = false);
      return;
    }
    _trainerId = me.uid;

    await _loadData();
    setState(() => _loading = false);
  }

  Future<void> _loadData() async {
    final subs = await _trainersRepo.listSubscribersForTrainer(_trainerId);
    final reqs = await _msgRepo.listForTrainer(_trainerId, status: 'open');

    // ابنِ مجموعة الـ UIDs للمشتركين الحاليين
    final uids = <String>{};
    for (final m in subs) {
      final user = m['user'] as Map<String, dynamic>?;
      final uid = user?['uid'] as String?;
      if (uid != null && uid.isNotEmpty) uids.add(uid);
    }

    setState(() {
      _subs = subs;
      _requests = reqs;
      _subscriberUids
        ..clear()
        ..addAll(uids);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!(_myBadge == BadgeType.coach || _myBadge == BadgeType.owner)) {
      return Scaffold(
        appBar: AppBar(title: const Text('لوحة المدرب')),
        body: const Center(child: Text('هذه الصفحة للمدربين فقط')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة المدرب'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'مشتركون', icon: Icon(Icons.people)),
            Tab(text: 'طلبات تواصل', icon: Icon(Icons.mail_outline)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _SubscribersTab(items: _subs),
          _RequestsTab(
            trainerId: _trainerId,
            requests: _requests,
            isSubscriber: (uid) => _subscriberUids.contains(uid),
            onChanged: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showHowToGetRequests(context),
        icon: const Icon(Icons.info_outline),
        label: const Text('كيف يستفسر العميل؟'),
      ),
    );
  }

  void _showHowToGetRequests(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('طريقة وصول الطلبات'),
        content: const Text(
          'العميل يفتح صفحة المدرب ويضغط "استفسر قبل الاشتراك" ويكتب سؤاله.\n'
          'الطلب يظهر لك هنا، وتقدر تقبله أو ترفضه. عند القبول تنفتح محادثة مباشرة.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('حسناً')),
        ],
      ),
    );
  }
}

class _SubscribersTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _SubscribersTab({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('لا يوجد مشتركون حالياً'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final userJson = items[i]['user'] as Map<String, dynamic>;
        final username = (userJson['username'] ?? 'مستخدم') as String;
        final email = (userJson['email'] ?? '') as String;
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(username),
          subtitle: Text(email),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final keyOrEmail = userJson['uid']
                as String?; // المفتاح الذي تخزن به بيانات المستخدم
            if (keyOrEmail != null && keyOrEmail.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(userKey: keyOrEmail),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final String trainerId;
  final List<MessageRequest> requests;
  final bool Function(String uid) isSubscriber;
  final Future<void> Function() onChanged;

  const _RequestsTab({
    required this.trainerId,
    required this.requests,
    required this.isSubscriber,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(child: Text('لا توجد طلبات حالياً'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final r = requests[i];
        return _RequestCard(
          trainerId: trainerId,
          req: r,
          isSubscriber: isSubscriber(r.fromUserId),
          onChanged: onChanged,
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String trainerId;
  final MessageRequest req;
  final bool isSubscriber;
  final Future<void> Function() onChanged;

  const _RequestCard({
    required this.trainerId,
    required this.req,
    required this.isSubscriber,
    required this.onChanged,
  });

  Future<void> _accept(BuildContext context) async {
    // 1) حدّث حالة الطلب إلى accepted
    await MessagesRepo().updateStatus(req.id, 'accepted');

    // 2) أنشئ/افتح محادثة
    final chatId =
        await LocalChatRepo().openOrCreateChatWith(trainerId, req.fromUserId);

    // 3) جهّز كائن المستخدم (المدرب) لتمريره إلى ChatScreen.me (اختياري)
    final me = await LocalAuthRepo().getUserById(trainerId);

    // 4) انتقل إلى صفحة الشات
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم قبول الطلب — تم فتح المحادثة')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            me: me, // ✅ حسب توقيع ChatScreen عندك
          ),
        ),
      );
      await onChanged();
    }
  }

  Future<void> _reject(BuildContext context) async {
    await MessagesRepo().updateStatus(req.id, 'rejected');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب')),
      );
      await onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.yMMMd("ar").add_Hm();

    return FutureBuilder<AppUser?>(
      future: LocalAuthRepo().getUserById(req.fromUserId),
      builder: (context, snap) {
        final user = snap.data;

        // مفتاح الملف الشخصي (عندك تستخدم email كمفتاح غالبًا)
        final profileKey = user?.email ?? req.fromUserId;

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
                      : null,
                ),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSubscriber
                                ? Colors.green.withOpacity(.1)
                                : cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isSubscriber ? 'مشترك' : 'غير مشترك',
                            style: TextStyle(
                              color: isSubscriber
                                  ? Colors.green.shade700
                                  : cs.onSecondaryContainer,
                              fontSize: 12,
                            ),
                          ),
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
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PublicProfileScreen(userKey: profileKey),
                                ),
                              );
                            },
                            icon: const Icon(Icons.account_circle_outlined),
                            label: const Text('الملف الشخصي'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => _accept(context),
                            icon: const Icon(Icons.check),
                            label: const Text('قبول'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _reject(context),
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

import 'package:flutter/material.dart';
import '../community/local_repos.dart';
import '../community/chat_screen.dart';
import 'local_repos.dart';
import 'models.dart';
import 'trainers_market_screen.dart';
import 'become_trainer_screen.dart';

class MyTrainerScreen extends StatefulWidget {
  const MyTrainerScreen({super.key});
  @override
  State<MyTrainerScreen> createState() => _MyTrainerScreenState();
}

class _MyTrainerScreenState extends State<MyTrainerScreen> {
  final repo = LocalTrainersRepo();
  Trainer? trainer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await LocalAuthRepo().currentUser();
    await repo.seedDefaultsIfEmpty();
    final tid = await repo.activeTrainerId(me.uid);
    if (tid == null) {
      setState(() => trainer = null);
      return;
    }
    final list = await repo.listTrainers();
    setState(() => trainer =
        list.firstWhere((t) => t.id == tid, orElse: () => list.first));
  }

  @override
  Widget build(BuildContext context) {
    final t = trainer;
    return Scaffold(
      appBar: AppBar(title: const Text('مدربي')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: t == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ما عندك مدرب حالياً'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TrainersMarketScreen()),
                        );
                      },
                      child: const Text('استكشاف المدرّبين'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BecomeTrainerScreen()),
                        );
                      },
                      child: const Text('أصبح مدربًا'),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(t.name),
                    subtitle: Text(t.bio),
                    trailing: Text(
                        '${(t.priceMonthlyCents / 100).toStringAsFixed(2)} ر.س/شهر'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.chat),
                    label: const Text('محادثة مع المدرب'),
                    onPressed: () async {
                      final me = await LocalAuthRepo().currentUser();
                      final chatId = await LocalChatRepo()
                          .openChatWith(me.uid, 'trainer_${t.id}');
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(chatId: chatId, me: me)),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TrainersMarketScreen()),
                      );
                    },
                    child: const Text('تبديل المدرب'),
                  ),
                ],
              ),
      ),
    );
  }
}

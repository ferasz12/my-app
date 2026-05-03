// lib/trainers/trainers_market_screen.dart
import 'package:flutter/material.dart';

import '../community/local_repos.dart'; // LocalAuthRepo().currentUser()
// يستورد BadgeType + getBadge/setBadge من مكان واحد
import '../shared/badges.dart';
import 'package:my_app/shared/badges_api.dart';

import 'local_repos.dart';
import 'models.dart';
import 'my_trainer_screen.dart';
import 'become_trainer_screen.dart';
import 'trainer_public_screen.dart';

class TrainersMarketScreen extends StatefulWidget {
  const TrainersMarketScreen({super.key});

  @override
  State<TrainersMarketScreen> createState() => _TrainersMarketScreenState();
}

class _TrainersMarketScreenState extends State<TrainersMarketScreen> {
  final repo = LocalTrainersRepo();
  List<Trainer> trainers = [];
  bool loading = true;

  // رتبة المستخدم الحالي
  BadgeType _myBadge = BadgeType.none;

  // مالك المتجر (اختياري) — إن كان إيميلك المالك مختلف غيّره هنا
  static const String _ownerEmail = 'frasalyamy99@gmail.com';

  bool get _canDelete =>
      _myBadge == BadgeType.owner || _myBadge == BadgeType.support;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final me = await LocalAuthRepo().currentUser();

      // إذا إيميله هو المالك اعتبره Owner
      if (me.email == _ownerEmail) {
        _myBadge = BadgeType.owner;
      } else {
        // تقدر تغيّرها إلى getBadge(me.uid) إذا مفاتيحك UID
        _myBadge = await getBadge(me.email);
      }
    } catch (_) {
      _myBadge = BadgeType.none;
    }

    await _load();
  }

  Future<void> _load() async {
    await repo.seedDefaultsIfEmpty();
    final list = await repo.listTrainers();
    if (!mounted) return;
    setState(() {
      trainers = list;
      loading = false;
    });
  }

  String priceText(int cents) => '${(cents / 100).toStringAsFixed(2)} ر.س / شهر';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سوق المدرّبين'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BecomeTrainerScreen()),
              );
            },
            child: const Text('أصبح مدربًا'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: trainers.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 160),
                        Center(child: Text('لا يوجد مدرّبون حالياً')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: trainers.length,
                      itemBuilder: (_, i) {
                        final t = trainers[i];

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TrainerPublicScreen(
                                    trainerId: t.id,
                                    trainer: t,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const CircleAvatar(
                                      radius: 22, child: Icon(Icons.person)),
                                  const SizedBox(width: 12),

                                  // النصوص تتمدد
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // الاسم + السعر يمين
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                t.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              priceText(t.priceMonthlyCents),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          t.bio,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'التقييم: ${t.rating.toStringAsFixed(1)} ★',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                          ),
                                        ),
                                        const SizedBox(height: 10),

                                        // أزرار الإجراءات في صف واحد
                                        Row(
                                          children: [
                                            OutlinedButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        TrainerPublicScreen(
                                                      trainerId: t.id,
                                                      trainer: t,
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: const Text('استفسر'),
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton(
                                              onPressed: () async {
                                                final me = await LocalAuthRepo()
                                                    .currentUser();
                                                await repo.subscribeMonthly(
                                                  uid: me.uid,
                                                  trainer: t,
                                                );
                                                if (!mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'تم الاشتراك مع ${t.name}'),
                                                ));
                                                Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const MyTrainerScreen(),
                                                  ),
                                                );
                                              },
                                              child: const Text('اشترك'),
                                            ),
                                            const Spacer(),
                                            if (_canDelete)
                                              IconButton.filledTonal(
                                                tooltip: 'حذف المدرب',
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                onPressed: () async {
                                                  final ok =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (c) => AlertDialog(
                                                      title: const Text(
                                                          'تأكيد حذف المدرب'),
                                                      content: Text(
                                                          'سيتم حذف (${t.name}) وإلغاء اشتراكات المتابعين بالكامل.'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  c, false),
                                                          child: const Text(
                                                              'رجوع'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  c, true),
                                                          child:
                                                              const Text('حذف'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (ok == true) {
                                                    try {
                                                      await repo
                                                          .deleteTrainer(t.id);
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'تم حذف المدرب ${t.name}'),
                                                        ),
                                                      );
                                                      await _load();
                                                    } catch (e) {
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'فشل الحذف: $e'),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                },
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
                    ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'local_repos.dart';
import 'models.dart';

class TrainersAdminScreen extends StatefulWidget {
  const TrainersAdminScreen({super.key});

  @override
  State<TrainersAdminScreen> createState() => _TrainersAdminScreenState();
}

class _TrainersAdminScreenState extends State<TrainersAdminScreen> {
  final _repo = LocalTrainersRepo();
  List<Trainer> _trainers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.listTrainers();
    if (!mounted) return;
    setState(() {
      _trainers = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المدربين')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _trainers.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 160),
                        Center(child: Text('لا يوجد مدربون')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemCount: _trainers.length,
                      itemBuilder: (_, i) {
                        final t = _trainers[i];
                        return Card(
                          child: ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(t.name),
                            subtitle: Text(
                              'سعر شهري: ${(t.priceMonthlyCents / 100).toStringAsFixed(2)} ر.س',
                            ),
                            trailing: IconButton.filledTonal(
                              icon: const Icon(Icons.delete),
                              tooltip: 'حذف المدرب',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('تأكيد حذف المدرب'),
                                    content: Text(
                                      'سيتم إلغاء اشتراكات المتابعين وحذف المدرب (${t.name}).',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('رجوع'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await _repo.deleteTrainer(t.id);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'تم حذف المدرب ${t.name} وإلغاء الاشتراكات المرتبطة',
                                      ),
                                    ),
                                  );
                                  await _load();
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

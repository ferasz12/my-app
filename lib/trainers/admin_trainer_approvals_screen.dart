import 'dart:io';
import 'package:flutter/material.dart';
import 'local_repos.dart';
import 'models.dart';

class AdminTrainerApprovalsScreen extends StatefulWidget {
  const AdminTrainerApprovalsScreen({super.key});
  @override
  State<AdminTrainerApprovalsScreen> createState() =>
      _AdminTrainerApprovalsScreenState();
}

class _AdminTrainerApprovalsScreenState
    extends State<AdminTrainerApprovalsScreen> {
  final repo = LocalTrainersRepo();
  List<TrainerApplication> apps = [];
  bool loading = true;

  Future<void> _load() async {
    setState(() => loading = true);
    final list = await repo.listApplications(status: 'pending');
    if (mounted) setState(() => apps = list);
    if (mounted) setState(() => loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الانضمام كمدرب')),
      body: loading
          ? Center(child: CircularProgressIndicator()) // ← شيلنا const
          : RefreshIndicator(
              onRefresh: _load,
              child: apps.isEmpty
                  ? ListView(
                      // ← شيلنا const
                      children: const [
                        SizedBox(height: 200),
                        Center(child: Text('لا توجد طلبات حالياً')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: apps.length,
                      itemBuilder: (_, i) {
                        final a = apps[i];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: cs.surfaceContainerHighest,
                                      child: a.personalImagePath.isEmpty
                                          ? const Icon(Icons.person)
                                          : ClipOval(
                                              child: Image.file(
                                                File(a.personalImagePath),
                                                width: 52,
                                                height: 52,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                        Icons.person_off),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(a.name,
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text('UID: ${a.userId}',
                                              style: TextStyle(
                                                  color: cs.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                        '${(a.priceMonthlyCents / 100).toStringAsFixed(2)} ر.س/شهر',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (a.bio.trim().isNotEmpty) Text(a.bio),
                                const SizedBox(height: 8),
                                if (a.specialties.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: -6,
                                    children: a.specialties
                                        .map((e) => Chip(label: Text(e)))
                                        .toList(),
                                  ),
                                const SizedBox(height: 12),
                                const Text('صور التحقق',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ImagePreviewBox(
                                        title: 'صورة شخصية',
                                        path: a.personalImagePath,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _ImagePreviewBox(
                                        title: 'صورة الهوية',
                                        path: a.idImagePath,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: () async {
                                        await repo.setApplicationStatus(
                                            a.id, 'rejected');
                                        await _load();
                                      },
                                      child: const Text('رفض'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: () async {
                                        await repo
                                            .approveApplicationAndCreateTrainer(
                                                a.id);
                                        await _load();
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'تمت الموافقة وتحويل ${a.name} إلى مدرب')),
                                        );
                                      },
                                      child: const Text('موافقة'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _ImagePreviewBox extends StatelessWidget {
  final String title;
  final String path;
  const _ImagePreviewBox({required this.title, required this.path});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: path.isEmpty
          ? Center(child: Text('$title: لا يوجد'))
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) =>
                    Center(child: Text('$title: تعذّر عرض الصورة')),
              ),
            ),
    );
  }
}

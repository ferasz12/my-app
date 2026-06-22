import 'package:flutter/material.dart';

import 'app_poll_model.dart';
import 'app_poll_service.dart';

class AppPollEditorPage extends StatefulWidget {
  const AppPollEditorPage({super.key});

  @override
  State<AppPollEditorPage> createState() => _AppPollEditorPageState();
}

class _AppPollEditorPageState extends State<AppPollEditorPage> {
  final _service = AppPollService();
  final _titleCtrl = TextEditingController(text: 'ساعدنا نطور وازن');
  final _questionCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _linkTextCtrl = TextEditingController(text: 'فتح الرابط');
  final _linkUrlCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  String? _loadedPollId;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _questionCtrl.dispose();
    _descriptionCtrl.dispose();
    _linkTextCtrl.dispose();
    _linkUrlCtrl.dispose();
    for (final ctrl in _optionCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _applyPoll(AppPollConfig poll) {
    if (_loadedPollId == poll.pollId) return;
    _loadedPollId = poll.pollId;
    _titleCtrl.text = poll.title.isEmpty ? 'ساعدنا نطور وازن' : poll.title;
    _questionCtrl.text = poll.question;
    _descriptionCtrl.text = poll.description;
    _linkTextCtrl.text = poll.linkText.isEmpty ? 'فتح الرابط' : poll.linkText;
    _linkUrlCtrl.text = poll.linkUrl;

    while (_optionCtrls.length < poll.options.length) {
      _optionCtrls.add(TextEditingController());
    }
    for (var i = 0; i < _optionCtrls.length; i++) {
      _optionCtrls[i].text = i < poll.options.length ? poll.options[i] : '';
    }
  }

  List<String> _options() => _optionCtrls
      .map((ctrl) => ctrl.text.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  Future<void> _publish() async {
    final options = _options();
    if (_questionCtrl.text.trim().isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب سؤال التصويت وأضف خيارين على الأقل')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.publishPoll(
        title: _titleCtrl.text,
        question: _questionCtrl.text,
        description: _descriptionCtrl.text,
        options: options,
        linkText: _linkTextCtrl.text,
        linkUrl: _linkUrlCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر التصويت وسيظهر للمستخدمين عند دخول التطبيق')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر نشر التصويت: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _saving = true);
    try {
      await _service.setEnabled(false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إيقاف التصويت')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    final removed = _optionCtrls.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppPollConfig?>(
      stream: _service.watchPoll(),
      builder: (context, snap) {
        final poll = snap.data;
        if (poll != null && _loadedPollId != poll.pollId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _applyPoll(poll));
          });
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(poll: poll),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إنشاء تصويت يظهر للجميع',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'عند نشر تصويت جديد، سيظهر للمستخدم عند دخول التطبيق بشكل إجباري حتى يختار إجابة. التصويت يُستخدم لتطوير وازن ومعرفة رأي المستخدمين.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'عنوان النافذة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _questionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'سؤال التصويت',
                        hintText: 'مثال: وش أكثر ميزة تبغى نطورها في وازن؟',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descriptionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'وصف اختياري',
                        hintText: 'اكتب توضيح بسيط للمستخدم',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'الخيارات',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_optionCtrls.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _optionCtrls[index],
                                decoration: InputDecoration(
                                  labelText: 'الخيار ${index + 1}',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              tooltip: 'حذف الخيار',
                              onPressed: _optionCtrls.length <= 2 ? null : () => _removeOption(index),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _addOption,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة خيار'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'رابط اختياري',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _linkTextCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نص زر الرابط',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _linkUrlCtrl,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'الرابط',
                        hintText: 'https://wazensapp.com/...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _publish,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.publish_rounded),
                            label: Text(_saving ? 'جاري الحفظ...' : 'نشر التصويت'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _disable,
                          icon: const Icon(Icons.pause_circle_outline),
                          label: const Text('إيقاف'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ResultsCard(service: _service, poll: poll),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppPollConfig? poll;

  const _StatusCard({required this.poll});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = poll?.isActive == true;
    return Card(
      color: active ? cs.primary.withOpacity(0.08) : null,
      child: ListTile(
        leading: Icon(active ? Icons.how_to_vote_rounded : Icons.pause_circle_outline, color: active ? cs.primary : null),
        title: Text(active ? 'التصويت مفعل الآن' : 'لا يوجد تصويت مفعل'),
        subtitle: Text(poll == null
            ? 'أنشئ تصويت جديد من النموذج بالأسفل.'
            : 'ID: ${poll!.pollId}\n${poll!.question.isEmpty ? 'لم يتم كتابة سؤال بعد' : poll!.question}'),
        isThreeLine: poll != null,
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  final AppPollService service;
  final AppPollConfig? poll;

  const _ResultsCard({required this.service, required this.poll});

  @override
  Widget build(BuildContext context) {
    final p = poll;
    if (p == null || p.pollId.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('نتائج التصويت ستظهر هنا بعد النشر.'),
        ),
      );
    }

    return StreamBuilder<List<AppPollVote>>(
      stream: service.watchVotes(p.pollId),
      builder: (context, snap) {
        final votes = snap.data ?? const <AppPollVote>[];
        final counts = <String, int>{for (final option in p.options) option: 0};
        for (final vote in votes) {
          if (counts.containsKey(vote.optionText)) {
            counts[vote.optionText] = (counts[vote.optionText] ?? 0) + 1;
          }
        }
        final total = votes.length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نتائج التصويت',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text('إجمالي الأصوات: $total'),
                const SizedBox(height: 12),
                if (p.options.isEmpty)
                  const Text('لا توجد خيارات')
                else
                  ...p.options.map((option) {
                    final count = counts[option] ?? 0;
                    final percent = total == 0 ? 0.0 : count / total;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(option, style: const TextStyle(fontWeight: FontWeight.w800))),
                              Text('$count صوت'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: percent.clamp(0.0, 1.0).toDouble()),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

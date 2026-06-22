import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_poll_model.dart';
import 'app_poll_service.dart';

class AppPollPrompt {
  AppPollPrompt._();

  static bool _isShowing = false;
  static String? _lastCheckedPollId;

  static Future<void> showIfNeeded(BuildContext context) async {
    if (_isShowing) return;
    final service = AppPollService();
    final poll = await service.getPoll();
    if (poll == null || !poll.isActive) return;

    if (_lastCheckedPollId == poll.pollId) {
      final voted = await service.currentUserHasVoted(poll.pollId);
      if (voted) return;
    }

    final hasVoted = await service.currentUserHasVoted(poll.pollId);
    _lastCheckedPollId = poll.pollId;
    if (hasVoted) return;
    if (!context.mounted) return;

    _isShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RequiredPollDialog(poll: poll, service: service),
      );
    } finally {
      _isShowing = false;
    }
  }
}

class _RequiredPollDialog extends StatefulWidget {
  final AppPollConfig poll;
  final AppPollService service;

  const _RequiredPollDialog({required this.poll, required this.service});

  @override
  State<_RequiredPollDialog> createState() => _RequiredPollDialogState();
}

class _RequiredPollDialogState extends State<_RequiredPollDialog> {
  int? _selected;
  bool _saving = false;
  String? _error;

  Future<void> _openLink() async {
    final url = widget.poll.linkUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    final choice = _selected;
    if (choice == null) {
      setState(() => _error = 'اختر إجابة أولًا');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.submitVote(poll: widget.poll, optionIndex: choice);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شكرًا لك، تم تسجيل تصويتك ✅')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'تعذر تسجيل التصويت، تأكد من الاتصال وحاول مرة ثانية.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final poll = widget.poll;

    return WillPopScope(
      onWillPop: () async => false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.how_to_vote_rounded, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  poll.title.isEmpty ? 'تصويت وازن' : poll.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  poll.question,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.35,
                      ),
                ),
                if (poll.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    poll.description,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
                  ),
                ],
                if (poll.hasLink) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openLink,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(poll.linkText.isEmpty ? 'فتح الرابط' : poll.linkText),
                  ),
                ],
                const SizedBox(height: 14),
                ...List.generate(poll.options.length, (index) {
                  final option = poll.options[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selected == index ? cs.primary : cs.outlineVariant,
                        width: _selected == index ? 1.4 : 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: _selected == index ? cs.primary.withOpacity(0.08) : null,
                    ),
                    child: RadioListTile<int>(
                      value: index,
                      groupValue: _selected,
                      onChanged: _saving ? null : (v) => setState(() => _selected = v),
                      title: Text(option, style: const TextStyle(fontWeight: FontWeight.w800)),
                      activeColor: cs.primary,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  );
                }),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 4),
                Text(
                  'هذا التصويت يساعدنا نطور وازن حسب رأيك. لازم تختار إجابة للمتابعة.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_saving ? 'جاري التسجيل...' : 'تسجيل التصويت'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

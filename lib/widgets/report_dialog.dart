import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/report_store.dart';

/// استدعِ هذا: showReportDialog(context, postId: id, postAuthor: name, postText: content);
Future<void> showReportDialog(
  BuildContext context, {
  required String postId,
  required String postAuthor,
  required String postText,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  final reasons = <String>[
    'محتوى مزعج/سبام',
    'تحرّش/تنمّر',
    'خطاب كراهية',
    'معلومات مضلّلة',
    'خطر إيذاء النفس',
    'عري/محتوى حساس',
    'نشاط غير قانوني',
    'أخرى',
  ];

  int selected = 0;
  final detailsCtl = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final tt = theme.textTheme;
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text('الإبلاغ عن منشور',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'سيصل بلاغك إلى فريق الدعم ليتخذ الإجراء المناسب.',
                style: tt.bodySmall?.copyWith(color: cs.outline),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(reasons.length, (i) {
                  final sel = i == selected;
                  return ChoiceChip(
                    label: Text(reasons[i]),
                    selected: sel,
                    onSelected: (_) => setState(() => selected = i),
                    selectedColor: cs.primaryContainer,
                    backgroundColor: cs.surface,
                    side:
                        BorderSide(color: sel ? cs.primary : cs.outlineVariant),
                    labelStyle: TextStyle(
                      color: sel ? cs.onPrimaryContainer : cs.onSurface,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  );
                }),
              ),
              const SizedBox(height: 12),
              if (reasons[selected] == 'أخرى')
                TextField(
                  controller: detailsCtl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'اذكر تفاصيل إضافية',
                    border: const OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.flag),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final email = prefs.getString('currentEmail');

                    final report = PostReport(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      postId: postId,
                      postAuthor: postAuthor,
                      postSnippet: postText.length > 120
                          ? '${postText.substring(0, 120)}…'
                          : postText,
                      reason: reasons[selected],
                      details: reasons[selected] == 'أخرى' &&
                              detailsCtl.text.trim().isNotEmpty
                          ? detailsCtl.text.trim()
                          : null,
                      reporterEmail: email,
                      createdAt: DateTime.now(),
                    );

                    await ReportStore.addReport(report);

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم إرسال البلاغ إلى الدعم 👌')),
                      );
                    }
                  },
                  label: const Text('إرسال البلاغ'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

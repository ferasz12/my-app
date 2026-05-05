import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/report_store.dart';

/// استدعِ هذا:
/// showReportDialog(context, postId: id, postAuthor: name, postText: content);
Future<void> showReportDialog(
  BuildContext context, {
  required String postId,
  required String postAuthor,
  required String postText,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  const reasons = <String>[
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

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final tt = theme.textTheme;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (innerContext, setModalState) {
                final selectedReason = reasons[selected];
                final needsDetails = selectedReason == 'أخرى';

                return SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withOpacity(0.50),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.flag_rounded,
                                color: cs.error,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'الإبلاغ عن منشور',
                                    style: tt.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'سيصل بلاغك إلى فريق الدعم ليتخذ الإجراء المناسب.',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                            postText.trim().isEmpty
                                ? 'لا يوجد نص للمنشور.'
                                : postText.trim().length > 120
                                    ? '${postText.trim().substring(0, 120)}…'
                                    : postText.trim(),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'اختر سبب البلاغ',
                          style: tt.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(reasons.length, (i) {
                            final isSelected = i == selected;

                            return ChoiceChip(
                              label: Text(reasons[i]),
                              selected: isSelected,
                              onSelected: (_) => setModalState(() => selected = i),
                              selectedColor: cs.primaryContainer,
                              backgroundColor: cs.surface,
                              side: BorderSide(
                                color: isSelected ? cs.primary : cs.outlineVariant,
                              ),
                              labelStyle: TextStyle(
                                color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            );
                          }),
                        ),
                        if (needsDetails) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: detailsCtl,
                            minLines: 2,
                            maxLines: 4,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              labelText: 'اذكر تفاصيل إضافية',
                              hintText: 'اكتب سبب البلاغ بشكل مختصر...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.flag_rounded),
                            onPressed: () async {
                              final details = detailsCtl.text.trim();

                              if (needsDetails && details.isEmpty) {
                                ScaffoldMessenger.of(innerContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('اكتب تفاصيل البلاغ أولًا.'),
                                  ),
                                );
                                return;
                              }

                              final prefs = await SharedPreferences.getInstance();
                              final email =
                                  (prefs.getString('currentEmail') ?? '').trim();

                              final report = PostReport(
                                id: DateTime.now().microsecondsSinceEpoch.toString(),
                                postId: postId,
                                postAuthor: postAuthor,
                                postSnippet: postText.length > 120
                                    ? '${postText.substring(0, 120)}…'
                                    : postText,
                                reason: selectedReason,
                                details: needsDetails && details.isNotEmpty
                                    ? details
                                    : '',
                                // الإصلاح الأساسي: PostReport يتوقع String وليس String?
                                reporterEmail: email.isNotEmpty ? email : 'unknown_user',
                                createdAt: DateTime.now(),
                              );

                              await ReportStore.addReport(report);

                              if (Navigator.of(sheetContext).canPop()) {
                                Navigator.of(sheetContext).pop();
                              }

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم إرسال البلاغ إلى الدعم 👌'),
                                  ),
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
            ),
          ),
        );
      },
    );
  } finally {
    detailsCtl.dispose();
  }
}

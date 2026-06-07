// lib/settings/sync_page.dart
// صفحة توافق فقط: المزامنة السحابية متوقفة حتى لا تسبب بطء أو تعليق.

import 'package:flutter/material.dart';

class SettingsCloudSyncPage extends StatelessWidget {
  const SettingsCloudSyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المزامنة السحابية')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 56, color: cs.primary),
                      const SizedBox(height: 14),
                      Text(
                        'المزامنة السحابية متوقفة حاليًا',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تم إيقافها لتحسين سرعة التطبيق ومنع التعليق. بيانات السعرات والتتبع والماء تبقى محفوظة محليًا على الجهاز.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// lib/settings/sync_page.dart
// صفحة المزامنة السحابية.

import 'package:flutter/material.dart';

import '../services/cloud_sync_service.dart';
import 'subscription_page.dart';

class SettingsCloudSyncPage extends StatefulWidget {
  const SettingsCloudSyncPage({super.key});

  @override
  State<SettingsCloudSyncPage> createState() => _SettingsCloudSyncPageState();
}

class _SettingsCloudSyncPageState extends State<SettingsCloudSyncPage> {
  final Set<String> _selected = CloudSyncService.categories.map((c) => c.id).toSet();

  bool _checking = true;
  bool _isSubscriber = false;
  bool _busy = false;
  String? _status;
  String? _error;
  Map<String, DateTime?> _lastSync = <String, DateTime?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    final ok = await CloudSyncService.hasActiveSubscription();
    final times = ok ? await CloudSyncService.readLastSyncTimes() : <String, DateTime?>{};

    if (!mounted) return;
    setState(() {
      _isSubscriber = ok;
      _lastSync = times;
      _checking = false;
    });
  }

  Future<void> _uploadSelected({bool all = false}) async {
    final ids = all ? <String>[CloudSyncService.allCategoryId] : _selected.toList(growable: false);
    if (ids.isEmpty) {
      _showSnack('اختر قسم واحد على الأقل.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'جاري مزامنة بياناتك في السحابة...';
    });

    try {
      final result = await CloudSyncService.upload(categoryIds: ids);
      final times = await CloudSyncService.readLastSyncTimes();
      if (!mounted) return;
      setState(() {
        _status = result.summary;
        _lastSync = times;
      });
      _showSnack('تمت المزامنة بنجاح');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreSelected() async {
    if (_selected.isEmpty) {
      _showSnack('اختر قسم واحد على الأقل.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع من السحابة؟'),
        content: const Text(
          'سيتم استبدال البيانات المحلية للأقسام المحددة بآخر نسخة محفوظة في السحابة. يفضل استخدامه عند تغيير الجهاز أو حذف التطبيق.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استرجاع')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _busy = true;
      _error = null;
      _status = 'جاري استرجاع بياناتك من السحابة...';
    });

    try {
      final result = await CloudSyncService.restore(categoryIds: _selected);
      if (!mounted) return;
      setState(() => _status = result.summary);
      _showSnack('تم الاسترجاع بنجاح. قد تحتاج بعض الصفحات إلى إعادة الفتح لعرض البيانات المحدثة.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('permission-denied')) {
      return 'تعذر الوصول إلى المزامنة. تحقق من تسجيل الدخول وصلاحيات الحساب ثم حاول مرة أخرى.';
    }
    if (text.contains('network')) return 'تأكد من اتصال الإنترنت ثم حاول مرة ثانية.';
    if (text.contains('المشتركين فقط')) return 'المزامنة السحابية متاحة للمشتركين فقط.';
    return text.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المزامنة السحابية'),
          actions: [
            IconButton(
              tooltip: 'تحديث الحالة',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _checking
            ? const Center(child: CircularProgressIndicator())
            : !_isSubscriber
                ? _LockedView(onSubscribe: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionPage()));
                  })
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _HeroCard(
                        busy: _busy,
                        selectedCount: _selected.length,
                        onSyncAll: _busy ? null : () => _uploadSelected(all: true),
                        onSyncSelected: _busy ? null : () => _uploadSelected(),
                        onRestore: _busy ? null : _restoreSelected,
                      ),
                      const SizedBox(height: 12),
                      if (_busy) ...[
                        _SyncProgressCard(message: _status ?? 'جاري مزامنة بياناتك في السحابة...'),
                        const SizedBox(height: 12),
                      ],
                      if (_status != null) _InfoBox(icon: Icons.check_circle_rounded, text: _status!, color: cs.primary),
                      if (_error != null) _InfoBox(icon: Icons.error_rounded, text: _error!, color: cs.error),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'اختر البيانات التي تريد مزامنتها',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      if (_selected.length == CloudSyncService.categories.length) {
                                        _selected.clear();
                                      } else {
                                        _selected
                                          ..clear()
                                          ..addAll(CloudSyncService.categories.map((c) => c.id));
                                      }
                                    });
                                  },
                            child: Text(_selected.length == CloudSyncService.categories.length ? 'إلغاء الكل' : 'تحديد الكل'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...CloudSyncService.categories.map((category) {
                        final selected = _selected.contains(category.id);
                        return _CategoryTile(
                          category: category,
                          selected: selected,
                          lastSync: _lastSync[category.id],
                          enabled: !_busy,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(category.id);
                              } else {
                                _selected.remove(category.id);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
      ),
    );
  }
}

class _LockedView extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _LockedView({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded, color: cs.primary, size: 38),
              ),
              const SizedBox(height: 16),
              Text('المزامنة للمشتركين فقط', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                'اشترك في وازن لحفظ بياناتك في السحابة واسترجاعها عند تغيير الجهاز أو إعادة تثبيت التطبيق.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onSubscribe,
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('عرض الاشتراك'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final bool busy;
  final int selectedCount;
  final VoidCallback? onSyncAll;
  final VoidCallback? onSyncSelected;
  final VoidCallback? onRestore;

  const _HeroCard({
    required this.busy,
    required this.selectedCount,
    required this.onSyncAll,
    required this.onSyncSelected,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [cs.primaryContainer, cs.surface],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: cs.primary.withOpacity(0.14), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.cloud_sync_rounded, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('حفظ واسترجاع بيانات وازن', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      'الأقسام المحددة: $selectedCount',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onSyncAll,
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('مزامنة الكل'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onSyncSelected,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('مزامنة المحدد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: busy ? null : onRestore,
              icon: const Icon(Icons.cloud_download_rounded),
              label: const Text('استرجاع المحدد من السحابة'),
            ),
          ),
        ],
      ),
    );
  }
}


class _SyncProgressCard extends StatelessWidget {
  final String message;
  const _SyncProgressCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.8, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CloudSyncCategory category;
  final bool selected;
  final DateTime? lastSync;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.lastSync,
    required this.enabled,
    required this.onChanged,
  });

  IconData get _icon {
    switch (category.id) {
      case 'profile':
        return Icons.badge_rounded;
      case 'calories':
        return Icons.restaurant_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'tracking':
        return Icons.monitor_heart_rounded;
      case 'settings':
        return Icons.tune_rounded;
      case 'plans':
        return Icons.fitness_center_rounded;
    }
    return Icons.cloud_done_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? cs.primary.withOpacity(0.08) : cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? cs.primary.withOpacity(0.45) : cs.outlineVariant),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: enabled ? onChanged : null,
        controlAffinity: ListTileControlAffinity.leading,
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(_icon, color: cs.primary),
        ),
        title: Text(category.title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${category.description}${lastSync == null ? '' : '\nآخر مزامنة: ${_formatDate(lastSync!)}'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoBox({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4))),
        ],
      ),
    );
  }
}

// lib/settings/cloud_sync_page.dart
import 'package:flutter/material.dart';

import '../services/smart_cloud_sync_service.dart';
import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';

class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  SmartCloudSyncStatus? _status;
  SmartCloudSyncProgress? _progress;
  SmartCloudSyncResult? _lastResult;
  bool _checkingAccess = true;
  bool _hasAccess = false;
  bool _loadingStatus = true;
  bool _busy = false;
  bool _enabled = false;
  bool _overwriteOnRestore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyAccessAndLoad());
  }

  Future<bool> _checkPremiumAccess({bool showSheet = false}) async {
    var allowed = await PremiumAccess.ensureSubscribed(
      context,
      feature: PremiumFeature.cloudSync,
      showSheet: false,
    );

    // في iPhone قد يكون كاش الاشتراك فاضي بعد التحديث، لذلك نحدّثه مرة
    // ثم نعيد التحقق قبل إظهار صفحة الاشتراك أو قفل المزامنة.
    if (!allowed) {
      await PremiumAccess.refreshLocalFromRemoteQuietly();
      allowed = await PremiumAccess.ensureSubscribed(
        context,
        feature: PremiumFeature.cloudSync,
        showSheet: false,
      );
    }

    if (!allowed && showSheet && mounted) {
      allowed = await PremiumAccess.ensureSubscribed(
        context,
        feature: PremiumFeature.cloudSync,
        showSheet: true,
      );
    }

    return allowed;
  }

  Future<void> _verifyAccessAndLoad() async {
    final allowed = await _checkPremiumAccess(showSheet: false);
    if (!mounted) return;
    setState(() {
      _hasAccess = allowed;
      _checkingAccess = false;
    });
    if (allowed) {
      await _loadStatus();
    } else {
      setState(() => _loadingStatus = false);
    }
  }

  Future<bool> _requireAccess({bool showSheet = true}) async {
    final allowed = await _checkPremiumAccess(showSheet: showSheet);
    if (!mounted) return false;
    setState(() => _hasAccess = allowed);
    return allowed;
  }

  Future<void> _loadStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final s = await SmartCloudSyncService.instance.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _enabled = s.enabled;
        _loadingStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _loadingStatus = false;
      });
      _showSnack('تعذر قراءة حالة المزامنة حاليًا.');
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (!await _requireAccess()) return;
    await SmartCloudSyncService.instance.setEnabled(value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _upload() async {
    if (_busy) return;
    if (!await _requireAccess()) return;
    setState(() {
      _busy = true;
      _progress = null;
      _lastResult = null;
    });

    try {
      final result = await SmartCloudSyncService.instance.uploadLocalData(
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _lastResult = result);
      await _loadStatus();
    } on SmartCloudSyncException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('تعذرت المزامنة حاليًا. تحقق من الاتصال وحاول مجددًا.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    if (!await _requireAccess()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع البيانات'),
        content: Text(
          _overwriteOnRestore
              ? 'سيتم استبدال البيانات المحلية بالنسخة السحابية للأيام المتوفرة. يفضّل استخدام هذا الخيار عند نقل الحساب إلى جهاز جديد.'
              : 'سيتم تنزيل البيانات غير الموجودة محليًا فقط، مع الحفاظ على بيانات الجهاز الحالية.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استرجاع')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _progress = null;
      _lastResult = null;
    });

    try {
      final result = await SmartCloudSyncService.instance.restoreCloudData(
        overwriteLocal: _overwriteOnRestore,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _lastResult = result);
      await _loadStatus();
    } on SmartCloudSyncException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('تعذر الاسترجاع حاليًا. تحقق من الاتصال وحاول مجددًا.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'لم تتم';
    final local = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}  ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المزامنة السحابية')),
        body: SafeArea(
          child: _checkingAccess
              ? const Center(child: CircularProgressIndicator())
              : !_hasAccess
                  ? _CloudSyncLocked(
                      onSubscribe: () async {
                        await PremiumAccess.openPaywall(context, force: true);
                        if (!mounted) return;
                        setState(() => _checkingAccess = true);
                        await _verifyAccessAndLoad();
                      },
                    )
                  : _loadingStatus
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _card(
                                context,
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: cs.primary.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.cloud_sync_rounded, color: cs.primary),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'النسخ الاحتياطي السحابي',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'احفظ بياناتك واسترجعها عند الحاجة من حسابك الحالي.',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _card(
                                context,
                                padding: const EdgeInsetsDirectional.fromSTEB(12, 2, 6, 2),
                                child: SwitchListTile.adaptive(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: _enabled,
                                  onChanged: _busy ? null : _setEnabled,
                                  title: Text('تفعيل المزامنة اليدوية', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  subtitle: Text(
                                    'يتم الرفع أو الاسترجاع عند اختيارك فقط.',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.bodySmall,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _card(
                                context,
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(child: _MetricItem(label: 'الأيام', value: '${_status?.localDaysCount ?? 0}')),
                                    _divider(context),
                                    Expanded(child: _MetricItem(label: 'آخر رفع', value: _fmt(_status?.lastUploadAt))),
                                    _divider(context),
                                    Expanded(child: _MetricItem(label: 'آخر استرجاع', value: _fmt(_status?.lastRestoreAt))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _statusPanel(context),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _restoreOption(context),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _busy ? null : _upload,
                                      icon: _busy
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.cloud_upload_rounded),
                                      label: const Text('رفع البيانات'),
                                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _busy ? null : _restore,
                                      icon: const Icon(Icons.cloud_download_rounded),
                                      label: const Text('استرجاع'),
                                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
        ),
      ),
    );
  }

  Widget _statusPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_progress != null) {
      final ratio = _progress!.ratio;
      return _card(
        context,
        key: const ValueKey('progress'),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_progress!.message, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: ratio == 0 ? null : ratio),
            const SizedBox(height: 8),
            Text('${(ratio * 100).round()}%', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    if (_lastResult != null) {
      return _card(
        context,
        key: const ValueKey('result'),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _lastResult!.success ? Icons.check_circle_rounded : Icons.error_rounded,
              color: _lastResult!.success ? Colors.green : cs.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _lastResult!.message,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      context,
      key: const ValueKey('info'),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('البيانات المشمولة', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const _Bullet(text: 'بيانات الحساب والهدف الصحي'),
          const SizedBox(height: 6),
          const _Bullet(text: 'سجل الوجبات والسعرات اليومية'),
          const SizedBox(height: 6),
          const _Bullet(text: 'الماء، الوزن، النشاط، والخطوات'),
          const SizedBox(height: 10),
          Text(
            'لا يتم تشغيل أي عملية مزامنة تلقائية عند فتح التطبيق.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _restoreOption(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return _card(
      context,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 6, 0),
      child: CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: _overwriteOnRestore,
        onChanged: _busy ? null : (v) => setState(() => _overwriteOnRestore = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('استبدال بيانات الجهاز عند الاسترجاع', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
        subtitle: const Text('اتركه غير محدد للاسترجاع الآمن.'),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(width: 1, height: 42, color: cs.outlineVariant.withOpacity(0.8));
  }

  Widget _card(BuildContext context, {Key? key, required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(16)}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.035), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}

class _CloudSyncLocked extends StatelessWidget {
  const _CloudSyncLocked({required this.onSubscribe});

  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.workspace_premium_rounded, size: 38, color: cs.primary),
              ),
              const SizedBox(height: 14),
              Text(
                'المزامنة السحابية ضمن الباقة',
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'اشترك لتفعيل النسخ الاحتياطي واسترجاع بياناتك من السحابة عند الحاجة.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onSubscribe,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('الاشتراك الآن'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('رجوع'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: tt.bodyMedium)),
      ],
    );
  }
}

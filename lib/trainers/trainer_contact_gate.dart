// lib/trainers/trainer_contact_gate.dart
import 'package:flutter/material.dart';

import '../community/local_repos.dart';         // LocalAuthRepo().currentUser()
import '../models/badge.dart';                  // BadgeType
import '../shared/user_badges_store.dart';      // UserBadgesStore

/// غلاف عام لأي صفحة "تواصل مع مدرب":
/// - يعرض الصفحة الأصلية للمالك والدعم الفني فقط.
/// - يعرض شاشة "تحت التحديث" لبقية المستخدمين.
/// الاستخدام:
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => TrainerContactGate(child: ContactTrainerScreen()),
/// ));
class TrainerContactGate extends StatefulWidget {
  final Widget child;

  /// تقدر تغيّر الأدوار المسموح لها تشوف الصفحة الأصلية (افتراضي: owner + support)
  final Set<BadgeType> allowedRoles;

  const TrainerContactGate({
    super.key,
    required this.child,
    this.allowedRoles = const {BadgeType.owner, BadgeType.support},
  });

  @override
  State<TrainerContactGate> createState() => _TrainerContactGateState();
}

class _TrainerContactGateState extends State<TrainerContactGate> {
  static const UserBadgesStore _badges = UserBadgesStore();

  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    try {
      // نجيب المستخدم الحالي (يربط Firebase إن وُجد)
      final me = await LocalAuthRepo().currentUser();
      final badge = await _badges.getBadge(me.uid);
      _allowed = widget.allowedRoles.contains(badge);
    } catch (_) {
      // أي خطأ = نعتبره غير مسموح (عشان ما نخرب الصفحة)
      _allowed = false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // لو المالك/الدعم → يشوف الصفحة الأصلية بدون أي تغيير
    if (_allowed) return widget.child;

    // غير ذلك → شاشة "تحت التحديث"
    return const _MaintenanceScreen();
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.construction, size: 88, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'الصفحة تحت التحديث ✨',
                    textAlign: TextAlign.center,
                    style: tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'نعمل حالياً على تحسين صفحة "تواصل مع مدرب".'
                    '\nترقّبوا تجربة أفضل قريبًا!',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(minHeight: 6),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('رجوع'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

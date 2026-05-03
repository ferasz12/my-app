// lib/core/auth/banned_screen.dart
//
// شاشة الحظر: تمنع الرجوع وتعرض سبب/مدة الحظر + زر تواصل مع الدعم.
// ملاحظة: السبب/المدة تُقرأ من users/{uid}.banReason و users/{uid}.bannedUntil (اختياري).

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  // ✅ عدّلها حسب قنوات دعمك
  static const String _supportEmail = 'support@wazen.app';

  DateTime? _readDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {
        return null;
      }
    }
    if (v is Map) {
      final s = v['seconds'];
      if (s is int) {
        return DateTime.fromMillisecondsSinceEpoch(s * 1000);
      }
    }
    return null;
  }

  String _formatDt(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final d = loc.formatFullDate(dt);
    final t = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: true,
    );
    return '$d • $t';
  }

  String _remainingText(Duration d) {
    if (d.isNegative) return 'انتهت المدة (بانتظار فك الحظر)';
    final hours = d.inHours;
    final days = d.inDays;
    if (days >= 1) {
      final remH = hours - (days * 24);
      return 'متبقي: $days يوم${days == 1 ? '' : ''}${remH > 0 ? ' و $remH ساعة' : ''}';
    }
    if (hours >= 1) return 'متبقي: $hours ساعة';
    final mins = d.inMinutes;
    if (mins >= 1) return 'متبقي: $mins دقيقة';
    return 'متبقي: أقل من دقيقة';
  }

  Future<void> _contactSupport(BuildContext context,
      {required String uid, String? reason}) async {
    final subj = Uri.encodeComponent('طلب مراجعة حظر - تطبيق وازن');
    final body = Uri.encodeComponent('السلام عليكم\n\n'
        'تم حظري من استخدام تطبيق وازن.\n'
        'UID: $uid\n'
        '${(reason ?? '').trim().isEmpty ? '' : 'سبب الحظر: ${reason!.trim()}\n'}'
        '\nأرجو مراجعة الحظر. شكراً.');
    final uri = Uri.parse('mailto:$_supportEmail?subject=$subj&body=$body');

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح البريد. تواصل معنا على: $_supportEmail')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // يمنع الرجوع
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _BannedBody(
                  readDateTime: _readDateTime,
                  formatDt: _formatDt,
                  remainingText: _remainingText,
                  contactSupport: _contactSupport,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannedBody extends StatelessWidget {
  final DateTime? Function(dynamic) readDateTime;
  final String Function(BuildContext, DateTime) formatDt;
  final String Function(Duration) remainingText;
  final Future<void> Function(BuildContext, {required String uid, String? reason})
      contactSupport;

  const _BannedBody({
    required this.readDateTime,
    required this.formatDt,
    required this.remainingText,
    required this.contactSupport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return _card(
        context,
        title: 'تم حظرك من استخدام تطبيق وازن',
        subtitle:
            'لا يمكننا قراءة بيانات حسابك الآن. سجّل الدخول مرة أخرى ثم حاول.',
        reason: null,
        until: null,
        uid: 'غير معروف',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('users/$uid').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};

        final reasonRaw =
            data['banReason'] ?? data['bannedReason'] ?? data['ban_reason'];
        final reason = reasonRaw?.toString();

        final untilRaw =
            data['bannedUntil'] ?? data['banUntil'] ?? data['banned_until'];
        final until = readDateTime(untilRaw);

        final subtitle = 'تم تقييد حسابك مؤقتًا أو دائمًا. '
            'إذا تعتقد أن هذا خطأ، تواصل مع الدعم.';

        return _card(
          context,
          title: 'تم حظرك من استخدام تطبيق وازن',
          subtitle: subtitle,
          reason: reason,
          until: until,
          uid: uid,
          cs: cs,
          tt: tt,
        );
      },
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String uid,
    String? reason,
    DateTime? until,
    ColorScheme? cs,
    TextTheme? tt,
  }) {
    cs ??= Theme.of(context).colorScheme;
    tt ??= Theme.of(context).textTheme;

    final hasReason = (reason ?? '').trim().isNotEmpty;
    final isPermanent = until == null;

    final untilLine = isPermanent
        ? 'مدة الحظر: دائم (حتى يتم فكّه)'
        : 'ينتهي الحظر: ${formatDt(context, until)}';

    final remainingLine =
        isPermanent ? null : remainingText(until.difference(DateTime.now()));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHighest.withOpacity(0.9),
            cs.surface.withOpacity(0.95),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.block_rounded, color: cs.onErrorContainer, size: 36),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // UID
          _line(
            context,
            icon: Icons.badge_rounded,
            label: 'معرّف الحساب (UID)',
            value: uid,
          ),

          const SizedBox(height: 10),

          // Duration
          _line(
            context,
            icon: Icons.timer_rounded,
            label: 'مدة الحظر',
            value: untilLine,
          ),

          if (remainingLine != null) ...[
            const SizedBox(height: 10),
            _line(
              context,
              icon: Icons.hourglass_bottom_rounded,
              label: 'المتبقي',
              value: remainingLine!,
            ),
          ],

          const SizedBox(height: 10),

          // Reason
          _line(
            context,
            icon: Icons.report_gmailerrorred_rounded,
            label: 'سبب الحظر',
            value: hasReason ? reason!.trim() : 'لم يتم تحديد سبب.',
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => contactSupport(context, uid: uid, reason: reason),
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('تواصل مع الدعم'),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'لن تتمكن من استخدام التطبيق حتى يتم فك الحظر.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(value, style: tt.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// lib/widgets/auto_claim_launcher.dart
// Widget جاهز: يراقب وثيقة يوم المستخدم ويعرض BottomSheet التجميع تلقائياً.
// المتطلبات: cloud_firestore, firebase_auth
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Helper: YYYY-MM-DD
String ymd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class AutoClaimLauncher extends StatefulWidget {
  const AutoClaimLauncher({super.key});

  @override
  State<AutoClaimLauncher> createState() => _AutoClaimLauncherState();
}

class _AutoClaimLauncherState extends State<AutoClaimLauncher> {
  final List<StreamSubscription> _subs = [];
  bool _sheetOpen = false;
  int _lastPending = 0;
  bool _lastClaimed = true;

  @override
  void initState() {
    super.initState();
    _attachWatchers();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _attachWatchers() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final users = FirebaseFirestore.instance.collection('users');
    final now = DateTime.now();

    final ids = <String>{
      ymd(now),
      ymd(DateTime.now().toUtc()),
      ymd(now.subtract(const Duration(days: 1))),
      ymd(DateTime.now().toUtc().subtract(const Duration(days: 1))),
    }.toList();

    for (final id in ids) {
      final sub = users.doc(uid).collection('days').doc(id).snapshots().listen((snap) {
        final data = snap.data();
        final rewards = (data?['rewards'] as Map?)?.cast<String, dynamic>();
        if (rewards == null) return;

        bool claimed = rewards['claimed'] == true;
        int pending = _asInt(rewards['pendingPoints']);
        // fallback: بعض المشاريع تخزن 'pending' بدل pendingPoints
        final p = rewards['pending'];
        if (pending == 0) {
          if (p is num) pending = p.toInt();
          else if (p is String) pending = int.tryParse(p) ?? 0;
          else if (p is bool && p == true) {
            // Flag فقط: نفتح الورقة لكن زر التجميع يُعطّل لأن ما فيه رقم
            pending = 0;
          }
        }
        _maybeOpenSheet(pending: pending, claimed: claimed, now: now);
      });
      _subs.add(sub);
    }
  }

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  void _maybeOpenSheet({required int pending, required bool claimed, required DateTime now}) {
    final shouldOpen = (!claimed) && (pending > 0) && ((pending != _lastPending) || _lastClaimed);
    if (shouldOpen && !_sheetOpen && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSheet(pending: pending, now: now);
      });
    }
    _lastPending = pending;
    _lastClaimed = claimed;
  }

  Future<void> _showSheet({required int pending, required DateTime now}) async {
    _sheetOpen = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24, left: 16, right: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.redeem),
                    const SizedBox(width: 8),
                    Text('مبروك! عندك نقاط بانتظار التجميع', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text('العدد المتاح: $pending نقطة'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: pending > 0 ? () async {
                          Navigator.of(context).pop();
                          await _performClaim(awarded: pending, now: now);
                        } : null,
                        icon: const Icon(Icons.check_circle),
                        label: const Text('تجميع الآن'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _performClaim({required int awarded, required DateTime now}) async {
    if (awarded <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد نقاط متاحة للتجميع حالياً')),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final users = FirebaseFirestore.instance.collection('users');
    final userDoc = users.doc(uid);
    final dayDoc = userDoc.collection('days').doc(ymd(now));

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        txn.update(userDoc, {'points_total': FieldValue.increment(awarded)});

        final daySnap = await txn.get(dayDoc);
        final existing = daySnap.data() ?? {};
        final rewards = Map<String, dynamic>.from(
          (existing['rewards'] as Map?) ?? <String, dynamic>{},
        );
        rewards['awardedPoints'] = awarded;
        rewards['claimed'] = true;
        rewards['ts'] = Timestamp.now();

        txn.set(dayDoc, {'rewards': rewards}, SetOptions(merge: true));
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تجميع $awarded نقطة 🎉')),
      );
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر التجميع: ${e.message ?? e.code}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ غير متوقع أثناء التجميع')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // الودجت لا يعرض UI؛ فقط يراقب ويظهر BottomSheet عند الحاجة.
    return const SizedBox.shrink();
  }
}

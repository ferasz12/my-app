
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// شاشة الأدمن: مراجعة العناصر المرسلة من المستخدمين
/// - إن كان المستخدم أدمن (users/{uid}.role == 'admin') يعرض كل pending.
/// - غير الأدمن: يعرض pending الخاصة به فقط (لتجنّب permission-denied بسبب الاستعلام).
class AdminFoodSubmissionsScreen extends StatelessWidget {
  const AdminFoodSubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: db.collection('users').doc(uid).get(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(title: const Text('مراجعة العناصر')),
            body: Center(child: Text('خطأ في تحميل الدور: ${snap.error}')));
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data!.data()?['role'];
        final isAdmin = role == 'admin';

        Query<Map<String, dynamic>> q = db.collection('food_submissions')
          .where('status', isEqualTo: 'pending')
          .orderBy('submittedAt', descending: true);

        if (!isAdmin) {
          // مهم: لو مهو أدمن لازم نفلتر على submittedBy = uid
          // عشان الاستعلام ما يرجّع مستندات غير مسموح بها → ما يطيح permission-denied.
          q = db.collection('food_submissions')
            .where('status', isEqualTo: 'pending')
            .where('submittedBy', isEqualTo: uid)
            .orderBy('submittedAt', descending: true);
        }

        return Scaffold(
          appBar: AppBar(title: const Text('مراجعة العناصر')),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (ctx, s) {
              if (s.hasError) return Center(child: Text('خطأ: ${s.error}'));
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final docs = s.data!.docs;
              if (docs.isEmpty) {
                return Center(child: Text(isAdmin ? 'لا توجد عناصر قيد الانتظار' : 'لا توجد طلبات بانتظارك'));
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final ref = docs[i].reference;
                  final d = docs[i].data();
                  return ListTile(
                    title: Text(d['name'] ?? ''),
                    subtitle: Text(
                      '${d['caloriesKcal']} kcal • P ${d['proteinG']} • C ${d['carbsG']} • F ${d['fatG']}  '
                      '(${d['unitType']} / ${d['perAmount']})  —  by: ${d['submittedBy']}',
                    ),
                    trailing: isAdmin ? Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => _reject(ref),
                          tooltip: 'رفض',
                        ),
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _approve(ref, d),
                          tooltip: 'موافقة',
                        ),
                      ],
                    ) : null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _reject(DocumentReference ref) async {
    await ref.update({
      'status': 'rejected',
      'reviewedAt': Timestamp.now(),
      'approvedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Future<void> _approve(DocumentReference subRef, Map<String, dynamic> d) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final foodRef = db.collection('foods').doc();
    batch.set(foodRef, {
      'name': d['name'],
      'unitType': d['unitType'],
      'perAmount': d['perAmount'],
      'caloriesKcal': d['caloriesKcal'],
      'proteinG': d['proteinG'],
      'carbsG': d['carbsG'],
      'fatG': d['fatG'],
      'notes': d['notes'],
      'createdAt': Timestamp.now(),
      'createdBy': d['submittedBy'],
    });
    batch.update(subRef, {
      'status': 'approved',
      'approvedAt': Timestamp.now(),
      'approvedBy': FirebaseAuth.instance.currentUser?.uid,
    });
    await batch.commit();
  }
}

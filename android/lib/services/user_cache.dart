// lib/services/user_cache.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserCache {
  /// يضمن وجود currentEmail و isLoggedIn في SharedPreferences
  static Future<void> ensurePrefsEmail() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    final email = u.email ?? 'unknown_user';
    await prefs.setString('currentEmail', email);
    await prefs.setBool('isLoggedIn', true);
  }

  /// يعبّي بعض الحقول من Firestore → SharedPreferences (توافق مع الشاشات القديمة)
  static Future<void> seedProfileFromFirestore() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final email = u.email ?? 'unknown_user';
    final prefs = await SharedPreferences.getInstance();

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      final data = snap.data();
      if (data == null) return;

      final firstName = (data['firstName'] ?? '').toString();
      final lastName  = (data['lastName']  ?? '').toString();
      final username  = (data['username']  ?? (u.displayName ?? '')).toString();

      await prefs.setString('firstName_$email', firstName);
      await prefs.setString('lastName_$email',  lastName);
      await prefs.setString('username_$email',  username);
      await prefs.setString('name_$email',      username); // legacy توافق

      // لو عندنا ماكروز محفوظة في users.metrics ننسخها للشيرد
      final metrics = data['metrics'];
      if (metrics is Map) {
        final k = (metrics['caloriesNeeded'] ?? metrics['kcal']) as num?;
        final p = (metrics['protein'])       as num?;
        final c = (metrics['carbs'])         as num?;
        final f = (metrics['fat'])           as num?;

        if (k != null) await prefs.setDouble('caloriesNeeded_$email', k.toDouble());
        if (p != null) await prefs.setDouble('protein_$email',        p.toDouble());
        if (c != null) await prefs.setDouble('carbs_$email',          c.toDouble());
        if (f != null) await prefs.setDouble('fat_$email',            f.toDouble());
      }
    } catch (_) {
      // نتجاهل أي خطأ شبكة – الشاشات تشتغل ديـفولت
    }
  }
}

// lib/services/auth/recent_accounts_store.dart
// تخزين وعرض الحسابات السابقة على شاشة الترحيب لتسهيل التبديل.
// يعتمد على SharedPreferences (بدون تخزين كلمات مرور أو بيانات حساسة).

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentAccount {
  final String uid;
  final String email;
  final String displayName;
  final String photoUrl;
  final String providerId; // password / google.com / apple.com ...
  final int lastSeenAtMs;

  const RecentAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.providerId,
    required this.lastSeenAtMs,
  });

  String get title {
    final dn = displayName.trim();
    if (dn.isNotEmpty) return dn;
    final em = email.trim();
    if (em.isNotEmpty) return em;
    return uid.length >= 8 ? 'حساب ${uid.substring(0, 8)}' : 'حساب';
  }

  String get subtitle {
    final em = email.trim();
    if (em.isNotEmpty && title != em) return em;
    return '';
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'providerId': providerId,
        'lastSeenAtMs': lastSeenAtMs,
      };

  static RecentAccount? tryFromJson(dynamic raw) {
    try {
      if (raw is! Map) return null;
      final m = raw.cast<String, dynamic>();
      final uid = (m['uid'] ?? '').toString().trim();
      if (uid.isEmpty) return null;
      return RecentAccount(
        uid: uid,
        email: (m['email'] ?? '').toString(),
        displayName: (m['displayName'] ?? '').toString(),
        photoUrl: (m['photoUrl'] ?? '').toString(),
        providerId: (m['providerId'] ?? '').toString(),
        lastSeenAtMs: int.tryParse((m['lastSeenAtMs'] ?? '').toString()) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class RecentAccountsStore {
  static const String _kKey = 'recent_accounts_v1';
  static const int _kMax = 8; // كفاية لمعظم المستخدمين

  static Future<List<RecentAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return <RecentAccount>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <RecentAccount>[];

      final out = <RecentAccount>[];
      for (final item in decoded) {
        final a = RecentAccount.tryFromJson(item);
        if (a != null) out.add(a);
      }
      // الأحدث أولاً
      out.sort((a, b) => b.lastSeenAtMs.compareTo(a.lastSeenAtMs));
      return out;
    } catch (_) {
      return <RecentAccount>[];
    }
  }

  static Future<void> rememberUser(User user) async {
    final uid = user.uid.trim();
    if (uid.isEmpty) return;

    final providerId = _bestProviderId(user);
    final now = DateTime.now().millisecondsSinceEpoch;

    final entry = RecentAccount(
      uid: uid,
      email: (user.email ?? '').trim(),
      displayName: (user.displayName ?? '').trim(),
      photoUrl: (user.photoURL ?? '').trim(),
      providerId: providerId,
      lastSeenAtMs: now,
    );

    final list = await load();
    // upsert حسب uid (مفتاح ثابت)
    final next = <RecentAccount>[entry];
    for (final a in list) {
      if (a.uid == uid) continue;
      next.add(a);
      if (next.length >= _kMax) break;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  static Future<void> removeByUid(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final list = await load();
    final next = list.where((a) => a.uid != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  static String _bestProviderId(User user) {
    try {
      final providers = user.providerData;
      if (providers.isEmpty) return 'password';

      // إذا فيه password نعتبره بريد/كلمة مرور
      if (providers.any((p) => p.providerId == 'password')) return 'password';

      // خذ أول مزود معروف
      final known = providers
          .map((p) => (p.providerId).trim())
          .where((p) => p.isNotEmpty && p != 'firebase')
          .toList();
      return known.isNotEmpty ? known.first : 'password';
    } catch (_) {
      return 'password';
    }
  }
}

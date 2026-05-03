import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AdminTotals {
  final int downloadsIos;
  final int downloadsAndroid;
  final int downloadsOther;
  final int subscribers;
  final int revenueCents; // بالهللة/الـ cents
  final DateTime updatedAt;

  const AdminTotals({
    required this.downloadsIos,
    required this.downloadsAndroid,
    required this.downloadsOther,
    required this.subscribers,
    required this.revenueCents,
    required this.updatedAt,
  });

  int get downloadsTotal => downloadsIos + downloadsAndroid + downloadsOther;

  Map<String, dynamic> toJson() => {
        'downloadsIos': downloadsIos,
        'downloadsAndroid': downloadsAndroid,
        'downloadsOther': downloadsOther,
        'subscribers': subscribers,
        'revenueCents': revenueCents,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory AdminTotals.fromJson(Map<String, dynamic> m) => AdminTotals(
        downloadsIos: m['downloadsIos'] ?? 0,
        downloadsAndroid: m['downloadsAndroid'] ?? 0,
        downloadsOther: m['downloadsOther'] ?? 0,
        subscribers: m['subscribers'] ?? 0,
        revenueCents: m['revenueCents'] ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] ?? 0),
      );

  AdminTotals copyWith({
    int? downloadsIos,
    int? downloadsAndroid,
    int? downloadsOther,
    int? subscribers,
    int? revenueCents,
    DateTime? updatedAt,
  }) {
    return AdminTotals(
      downloadsIos: downloadsIos ?? this.downloadsIos,
      downloadsAndroid: downloadsAndroid ?? this.downloadsAndroid,
      downloadsOther: downloadsOther ?? this.downloadsOther,
      subscribers: subscribers ?? this.subscribers,
      revenueCents: revenueCents ?? this.revenueCents,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AdminAnalyticsRepo {
  static const _key = 'admin_analytics_totals';
  static final AdminAnalyticsRepo _i = AdminAnalyticsRepo._();
  factory AdminAnalyticsRepo() => _i;
  AdminAnalyticsRepo._();

  final _ctrl = StreamController<AdminTotals>.broadcast();

  Stream<AdminTotals> watchTotals() {
    _emitOnce();
    return _ctrl.stream;
  }

  Future<AdminTotals> loadTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final zero = AdminTotals(
        downloadsIos: 0,
        downloadsAndroid: 0,
        downloadsOther: 0,
        subscribers: 0,
        revenueCents: 0,
        updatedAt: DateTime.now(),
      );
      await saveTotals(zero);
      return zero;
    }
    return AdminTotals.fromJson(jsonDecode(raw));
  }

  Future<void> saveTotals(AdminTotals t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(t.toJson()));
    _ctrl.add(t);
  }

  Future<void> setDownloads({int? ios, int? android, int? other}) async {
    final cur = await loadTotals();
    await saveTotals(cur.copyWith(
      downloadsIos: ios ?? cur.downloadsIos,
      downloadsAndroid: android ?? cur.downloadsAndroid,
      downloadsOther: other ?? cur.downloadsOther,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> setSubscribers(int v) async {
    final cur = await loadTotals();
    await saveTotals(cur.copyWith(subscribers: v, updatedAt: DateTime.now()));
  }

  Future<void> setRevenueCents(int v) async {
    final cur = await loadTotals();
    await saveTotals(cur.copyWith(revenueCents: v, updatedAt: DateTime.now()));
  }

  Future<void> _emitOnce() async {
    final t = await loadTotals();
    _ctrl.add(t);
  }
}

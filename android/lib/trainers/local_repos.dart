import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
// لو تحتاج currentUser
import 'models.dart';

const _uuid = Uuid();

class LocalTrainersRepo {
  static const _kTrainers = 'trainers';
  static const _kSubs = 'subscriptions';
  static const _kApps = 'trainer_applications';

  static String _activeKey(String uid) => 'activeTrainer:$uid';

  // بذور افتراضية للمدربين (للتجربة)
  Future<void> seedDefaultsIfEmpty() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString(_kTrainers) ?? '').isNotEmpty) return;

    final defaults = [
      Trainer(
        id: _uuid.v4(),
        name: 'كابتن أحمد',
        bio: 'متخصص تخسيس وبرامج مقاومة للمبتدئين.',
        priceMonthlyCents: 9900,
        rating: 4.7,
        specialties: ['تخسيس', 'مقاومة'],
        photoUrl: null,
      ),
      Trainer(
        id: _uuid.v4(),
        name: 'كابتن سارة',
        bio: 'تغذية رياضية وجدولة تمارين للسيدات.',
        priceMonthlyCents: 14900,
        rating: 4.9,
        specialties: ['تغذية', 'لياقة عامة'],
        photoUrl: null,
      ),
    ];

    await prefs.setString(
      _kTrainers,
      jsonEncode(defaults.map((t) => t.toJson()).toList()),
    );
  }

  // ======== المدربين ========
  Future<List<Trainer>> listTrainers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTrainers);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Trainer.fromJson).where((t) => t.isActive).toList();
  }

  Future<Trainer?> getTrainer(String id) async {
    final list = await listTrainers();
    try {
      return list.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  // ======== الاشتراكات ========
  Future<Subscription?> currentSubscription(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSubs);
    if (raw == null) return null;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final now = DateTime.now();
    for (final m in list) {
      final s = Subscription.fromJson(m);
      if (s.userId == uid && s.status == 'active' && s.renewAt.isAfter(now)) {
        return s;
      }
    }
    return null;
  }

  Future<String?> activeTrainerId(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey(uid));
  }

  Future<Subscription> subscribeMonthly({
    required String uid,
    required Trainer trainer,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSubs);
    final list = raw != null
        ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
        : [];

    final start = DateTime.now();
    final renew = DateTime(start.year, start.month + 1, start.day);

    final s = Subscription(
      id: _uuid.v4(),
      userId: uid,
      trainerId: trainer.id,
      status: 'active',
      period: 'monthly',
      priceCents: trainer.priceMonthlyCents,
      currency: 'SAR',
      startAt: start,
      renewAt: renew,
    );
    list.add(s.toJson());
    await prefs.setString(_kSubs, jsonEncode(list));
    await prefs.setString(_activeKey(uid), trainer.id);
    return s;
  }

  Future<void> cancelSubscription(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSubs);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < list.length; i++) {
      final s = Subscription.fromJson(list[i]);
      if (s.userId == uid && s.status == 'active') {
        list[i]['status'] = 'canceled';
      }
    }
    await prefs.setString(_kSubs, jsonEncode(list));
    await prefs.remove(_activeKey(uid));
  }

  /// يرجّع قائمة المستخدمين المشتركين مع مدرب محدد.
  /// الناتج: [{ 'user': AppUserJson, 'subscription': Subscription }, ...]
  Future<List<Map<String, dynamic>>> listSubscribersForTrainer(
      String trainerId) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) الاشتراكات
    final rawSubs = prefs.getString(_kSubs);
    if (rawSubs == null) return [];
    final subs = (jsonDecode(rawSubs) as List).cast<Map<String, dynamic>>();

    final active = subs
        .map(Subscription.fromJson)
        .where((s) => s.trainerId == trainerId && s.status == 'active')
        .toList();

    // 2) المستخدمون
    final users = <Map<String, dynamic>>[];
    final rawAll = prefs.getString('mock_all_users');
    if (rawAll != null) {
      users.addAll((jsonDecode(rawAll) as List).cast<Map<String, dynamic>>());
    }
    final rawMe = prefs.getString('mock_user');
    if (rawMe != null) {
      final me = jsonDecode(rawMe) as Map<String, dynamic>;
      if (!users.any((u) => u['uid'] == me['uid'])) users.add(me);
    }

    // 3) الربط
    final result = <Map<String, dynamic>>[];
    for (final s in active) {
      final user = users.firstWhere(
        (u) => u['uid'] == s.userId,
        orElse: () => {},
      );
      if (user.isNotEmpty) {
        result.add({'user': user, 'subscription': s});
      }
    }
    return result;
  }

  // ======== طلبات الانضمام كمدرب ========
  Future<List<TrainerApplication>> listApplications(
      {String status = 'pending'}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kApps);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final apps = list.map(TrainerApplication.fromJson).toList();
    return status.isEmpty
        ? apps
        : apps.where((a) => a.status == status).toList();
  }

  Future<void> _saveApplications(List<TrainerApplication> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kApps, jsonEncode(apps.map((e) => e.toJson()).toList()));
  }

  Future<TrainerApplication> submitApplication({
    required String userId,
    required String name,
    required String bio,
    required int priceMonthlyCents,
    required List<String> specialties,
    required String personalImagePath, // صورة شخصية
    required String idImagePath, // صورة الهوية
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kApps);
    final list = raw != null
        ? (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(TrainerApplication.fromJson)
            .toList()
        : <TrainerApplication>[];

    final app = TrainerApplication(
      id: _uuid.v4(),
      userId: userId,
      name: name,
      bio: bio,
      priceMonthlyCents: priceMonthlyCents,
      specialties: specialties,
      status: 'pending',
      createdAt: DateTime.now(),
      personalImagePath: personalImagePath,
      idImagePath: idImagePath,
    );

    list.add(app);
    await _saveApplications(list);
    return app;
  }

  Future<void> setApplicationStatus(String appId, String newStatus) async {
    final apps = await listApplications(status: '');
    final i = apps.indexWhere((a) => a.id == appId);
    if (i == -1) return;
    apps[i] = TrainerApplication(
      id: apps[i].id,
      userId: apps[i].userId,
      name: apps[i].name,
      bio: apps[i].bio,
      priceMonthlyCents: apps[i].priceMonthlyCents,
      specialties: apps[i].specialties,
      status: newStatus,
      createdAt: apps[i].createdAt,
      personalImagePath: apps[i].personalImagePath,
      idImagePath: apps[i].idImagePath,
    );
    await _saveApplications(apps);
  }

  Future<void> approveApplicationAndCreateTrainer(String appId) async {
    final apps = await listApplications(status: '');
    final i = apps.indexWhere((a) => a.id == appId);
    if (i == -1) return;
    final app = apps[i];

    final prefs = await SharedPreferences.getInstance();
    final rawT = prefs.getString(_kTrainers);
    final trainers = rawT != null
        ? (jsonDecode(rawT) as List)
            .cast<Map<String, dynamic>>()
            .map(Trainer.fromJson)
            .toList()
        : <Trainer>[];

    final exists = trainers.any((t) => t.id == app.userId);
    if (!exists) {
      trainers.add(Trainer(
        id: app.userId,
        name: app.name,
        bio: app.bio,
        priceMonthlyCents: app.priceMonthlyCents,
        rating: 0,
        specialties: app.specialties,
        photoUrl: null,
        isActive: true,
      ));
      await prefs.setString(
          _kTrainers, jsonEncode(trainers.map((t) => t.toJson()).toList()));
    }

    await setApplicationStatus(appId, 'approved');
  }

  /// ======== جديد: حذف مدرّب نهائيًا ========
  Future<void> deleteTrainer(String trainerId) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) احذف من قائمة المدربين
    final rawT = prefs.getString(_kTrainers);
    if (rawT != null) {
      final trainers = (jsonDecode(rawT) as List).cast<Map<String, dynamic>>();
      trainers.removeWhere((t) => t['id'] == trainerId);
      await prefs.setString(_kTrainers, jsonEncode(trainers));
    }

    // 2) ألغِ كل اشتراكات هذا المدرب وامسح activeTrainer للمشتركين
    final rawS = prefs.getString(_kSubs);
    if (rawS != null) {
      final subs = (jsonDecode(rawS) as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < subs.length; i++) {
        final s = Subscription.fromJson(subs[i]);
        if (s.trainerId == trainerId && s.status == 'active') {
          subs[i]['status'] = 'canceled';
          await prefs.remove(_activeKey(s.userId));
        }
      }
      await prefs.setString(_kSubs, jsonEncode(subs));
    }

    // 3) علّم الطلبات السابقة لهذا المدرب بالرفض (اختياري)
    final rawA = prefs.getString(_kApps);
    if (rawA != null) {
      final apps = (jsonDecode(rawA) as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < apps.length; i++) {
        if (apps[i]['userId'] == trainerId) {
          apps[i]['status'] = 'rejected';
        }
      }
      await prefs.setString(_kApps, jsonEncode(apps));
    }
  }
}

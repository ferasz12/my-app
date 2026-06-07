import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'premium_feature.dart';

class OwnerFeatureFlagsService {
  OwnerFeatureFlagsService._();
  static final OwnerFeatureFlagsService _instance = OwnerFeatureFlagsService._();
  factory OwnerFeatureFlagsService() => _instance;

  static const String _collection = 'appConfig';
  static const String _docId = 'owner_controls';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection(_collection).doc(_docId);

  static const Map<PremiumFeature, bool> defaults = <PremiumFeature, bool>{
    PremiumFeature.aiPhoto: true,
    PremiumFeature.aiText: true,
    PremiumFeature.restaurants: true,
    PremiumFeature.coach: true,
    PremiumFeature.trackingPdf: true,
    PremiumFeature.guide: true,
    PremiumFeature.virtualGym: true,
    PremiumFeature.virtualClubGuide: true,
    PremiumFeature.recipes: true,
    PremiumFeature.regimens: true,
    PremiumFeature.regimen: true,
    PremiumFeature.theme: true,
    PremiumFeature.notifications: true,
  };

  Map<PremiumFeature, bool> _memoryFlags = defaults;
  bool _refreshing = false;

  Map<PremiumFeature, bool> get cachedFlags => _memoryFlags;

  Stream<Map<PremiumFeature, bool>> watchFlags() async* {
    yield _memoryFlags;
    try {
      await for (final snap in _doc.snapshots(includeMetadataChanges: true)) {
        final flags = _decode(snap.data());
        _memoryFlags = flags;
        yield flags;
      }
    } catch (_) {
      yield _memoryFlags;
    }
  }

  Future<Map<PremiumFeature, bool>> loadFlags() async {
    // Cache-first: لا نعلّق فتح الصفحة على Firestore.
    unawaited(_refreshFromServer());
    try {
      final snap = await _doc
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 250));
      _memoryFlags = _decode(snap.data());
    } catch (_) {
      // إذا ما فيه كاش، نستخدم الافتراضي/آخر قيمة في الذاكرة.
    }
    return _memoryFlags;
  }

  Future<bool> isEnabled(PremiumFeature feature) async {
    // يرجع فورًا من الذاكرة، ويحدّث بالخلفية بدون تعطيل التنقل.
    unawaited(_refreshFromServer());
    return _memoryFlags[feature] ?? true;
  }

  Future<void> _refreshFromServer() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snap = await _doc
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));
      _memoryFlags = _decode(snap.data());
    } catch (_) {
      // تجاهل مشاكل الشبكة حتى لا تؤثر على سرعة التطبيق.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> setFlag(PremiumFeature feature, bool enabled) async {
    final updates = <String, dynamic>{
      'featureFlags.${feature.name}': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (feature == PremiumFeature.regimen) {
      updates['featureFlags.${PremiumFeature.regimens.name}'] = enabled;
    }
    if (feature == PremiumFeature.regimens) {
      updates['featureFlags.${PremiumFeature.regimen.name}'] = enabled;
    }

    await _doc.set(updates, SetOptions(merge: true));
    _memoryFlags = Map<PremiumFeature, bool>.from(_memoryFlags)..[feature] = enabled;
  }

  Map<PremiumFeature, bool> _decode(Map<String, dynamic>? data) {
    final raw = (data?['featureFlags'] is Map)
        ? Map<String, dynamic>.from(data!['featureFlags'] as Map)
        : const <String, dynamic>{};

    final out = <PremiumFeature, bool>{};
    for (final entry in defaults.entries) {
      final value = raw[entry.key.name];
      if (value is bool) {
        out[entry.key] = value;
      } else {
        out[entry.key] = entry.value;
      }
    }

    final regimen = out[PremiumFeature.regimen] ?? true;
    final regimens = out[PremiumFeature.regimens] ?? regimen;
    final mergedRegimen = regimen && regimens;
    out[PremiumFeature.regimen] = mergedRegimen;
    out[PremiumFeature.regimens] = mergedRegimen;

    return out;
  }
}

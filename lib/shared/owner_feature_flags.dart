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
    PremiumFeature.restaurantsAdd: true,
    PremiumFeature.coach: true,
    PremiumFeature.smartCoach: true,
    PremiumFeature.trackingPdf: true,
    PremiumFeature.pdfTracking: true,
    PremiumFeature.guide: true,
    PremiumFeature.virtualGym: true,
    PremiumFeature.virtualClubGuide: true,
    PremiumFeature.recipes: true,
    PremiumFeature.regimens: true,
    PremiumFeature.regimen: true,
    PremiumFeature.theme: true,
    PremiumFeature.appearance: true,
    PremiumFeature.notifications: true,
    PremiumFeature.cloudSync: true,
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

    void mirror(PremiumFeature other) {
      updates['featureFlags.${other.name}'] = enabled;
    }

    if (feature == PremiumFeature.regimen) mirror(PremiumFeature.regimens);
    if (feature == PremiumFeature.regimens) mirror(PremiumFeature.regimen);
    if (feature == PremiumFeature.restaurants) mirror(PremiumFeature.restaurantsAdd);
    if (feature == PremiumFeature.restaurantsAdd) mirror(PremiumFeature.restaurants);
    if (feature == PremiumFeature.coach) mirror(PremiumFeature.smartCoach);
    if (feature == PremiumFeature.smartCoach) mirror(PremiumFeature.coach);
    if (feature == PremiumFeature.trackingPdf) mirror(PremiumFeature.pdfTracking);
    if (feature == PremiumFeature.pdfTracking) mirror(PremiumFeature.trackingPdf);
    if (feature == PremiumFeature.theme) mirror(PremiumFeature.appearance);
    if (feature == PremiumFeature.appearance) mirror(PremiumFeature.theme);

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

    bool merged(PremiumFeature a, PremiumFeature b) {
      return (out[a] ?? true) && (out[b] ?? true);
    }

    final mergedRegimen = merged(PremiumFeature.regimen, PremiumFeature.regimens);
    out[PremiumFeature.regimen] = mergedRegimen;
    out[PremiumFeature.regimens] = mergedRegimen;

    final mergedRestaurants = merged(PremiumFeature.restaurants, PremiumFeature.restaurantsAdd);
    out[PremiumFeature.restaurants] = mergedRestaurants;
    out[PremiumFeature.restaurantsAdd] = mergedRestaurants;

    final mergedCoach = merged(PremiumFeature.coach, PremiumFeature.smartCoach);
    out[PremiumFeature.coach] = mergedCoach;
    out[PremiumFeature.smartCoach] = mergedCoach;

    final mergedPdf = merged(PremiumFeature.trackingPdf, PremiumFeature.pdfTracking);
    out[PremiumFeature.trackingPdf] = mergedPdf;
    out[PremiumFeature.pdfTracking] = mergedPdf;

    final mergedTheme = merged(PremiumFeature.theme, PremiumFeature.appearance);
    out[PremiumFeature.theme] = mergedTheme;
    out[PremiumFeature.appearance] = mergedTheme;

    return out;
  }
}

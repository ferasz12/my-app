import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'premium_feature.dart';

class OwnerFeatureFlagsService {
  OwnerFeatureFlagsService._();
  static final OwnerFeatureFlagsService _instance = OwnerFeatureFlagsService._();
  factory OwnerFeatureFlagsService() => _instance;

  Map<PremiumFeature, bool>? _cachedFlags;
  DateTime? _cachedAt;

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
    PremiumFeature.cloudSync: false,
  };

  Stream<Map<PremiumFeature, bool>> watchFlags() {
    return _doc.snapshots().map((snap) {
      final decoded = _decode(snap.data());
      _cachedFlags = decoded;
      _cachedAt = DateTime.now();
      return decoded;
    });
  }

  Future<Map<PremiumFeature, bool>> loadFlags({bool allowCached = true}) async {
    final now = DateTime.now();
    final cached = _cachedFlags;
    final cachedAt = _cachedAt;
    if (allowCached && cached != null && cachedAt != null && now.difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }

    try {
      final snap = await _doc.get(const GetOptions(source: Source.serverAndCache)).timeout(const Duration(milliseconds: 450));
      final decoded = _decode(snap.data());
      _cachedFlags = decoded;
      _cachedAt = now;
      return decoded;
    } catch (_) {
      return cached ?? defaults;
    }
  }

  Future<bool> isEnabled(PremiumFeature feature) async {
    if (feature == PremiumFeature.cloudSync) return false;
    final now = DateTime.now();
    final cached = _cachedFlags;
    final cachedAt = _cachedAt;
    if (cached != null && cachedAt != null && now.difference(cachedAt) < const Duration(minutes: 10)) {
      return cached[feature] ?? true;
    }

    // مهم للأداء: لا نوقف فتح الصفحات على قراءة إعدادات المالك.
    // نرجع الافتراضي فورًا، ونحدّث الكاش بالخلفية للاستخدامات التالية.
    unawaited(loadFlags(allowCached: false).catchError((_) => defaults));
    return defaults[feature] ?? true;
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

// lib/data/restaurants_firestore_repository.dart
//
// Repository لإدارة المطاعم/المقاهي ووجباتها في Firestore + Storage.
// تحسينات هذه النسخة:
// - كاش داخل الذاكرة لعرض آخر نتيجة فور الرجوع للصفحة.
// - snapshots(includeMetadataChanges: true) للاستفادة من كاش Firestore بسرعة.
// - لا يوجد أي fallback ثابت للمقاهي من هنا؛ صفحة العرض هي التي تقرر استخدام fallback المطاعم فقط.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../models/meal.dart';
import '../models/venue.dart';

class RestaurantsFirestoreRepository {
  RestaurantsFirestoreRepository();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('restaurants');

  static final Map<String, List<Venue>> _venuesCache = <String, List<Venue>>{};
  static final Map<String, List<Meal>> _mealsCache = <String, List<Meal>>{};

  String _typeToString(VenueType t) =>
      t == VenueType.restaurant ? 'restaurant' : 'cafe';

  VenueType _stringToType(String? t) =>
      (t ?? '').toLowerCase() == 'cafe' ? VenueType.cafe : VenueType.restaurant;

  List<Venue> cachedVenuesByType(VenueType type) {
    return List<Venue>.unmodifiable(_venuesCache[_typeToString(type)] ?? const <Venue>[]);
  }

  List<Meal> cachedMeals(String restaurantId) {
    return List<Meal>.unmodifiable(_mealsCache[restaurantId] ?? const <Meal>[]);
  }

  /// بثّ حي للمطاعم/المقاهي حسب النوع.
  /// ملاحظة: الترتيب يتم محليًا حتى لا تحتاج index إضافي في Firestore.
  Stream<List<Venue>> streamVenuesByType(VenueType type) {
    final typeKey = _typeToString(type);
    return _col
        .where('type', isEqualTo: typeKey)
        .snapshots(includeMetadataChanges: true)
        .map((q) {
      final list = q.docs.map((d) {
        final data = d.data();
        return Venue(
          id: d.id,
          name: (data['name'] ?? '').toString().trim(),
          type: _stringToType(data['type']?.toString()),
          meals: const <Meal>[],
          imageUrl: data['imageUrl']?.toString(),
        );
      }).where((v) => v.name.isNotEmpty).toList();

      list.sort((a, b) => a.name.compareTo(b.name));
      _venuesCache[typeKey] = List<Venue>.unmodifiable(list);
      return list;
    });
  }

  /// بثّ حي لوجبات مطعم/مقهى واحد.
  Stream<List<Meal>> streamMeals(String restaurantId, {String? restaurantName}) {
    return _col
        .doc(restaurantId)
        .collection('meals')
        .snapshots(includeMetadataChanges: true)
        .map((q) {
      final list = q.docs.map((d) {
        final data = d.data();
        return Meal(
          id: d.id,
          restaurant: (restaurantName ?? data['restaurant'] ?? '').toString(),
          name: (data['name'] ?? '').toString().trim(),
          category: (data['category'] ?? '').toString(),
          serving: (data['serving'] ?? '').toString(),
          calories: _asInt(data['calories']),
          protein: _asDouble(data['protein']),
          carbs: _asDouble(data['carbs']),
          fat: _asDouble(data['fat']),
          imageUrl: data['imageUrl']?.toString(),
          description: data['description']?.toString(),
        );
      }).where((m) => m.name.isNotEmpty).toList();

      list.sort((a, b) => a.name.compareTo(b.name));
      _mealsCache[restaurantId] = List<Meal>.unmodifiable(list);
      return list;
    });
  }

  /// إنشاء أو تحديث مطعم/مقهى.
  Future<void> upsertVenue({
    required String id,
    required VenueType type,
    required String name,
    String? imageUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    final now = Timestamp.now();
    await _col.doc(id).set({
      'name': name.trim(),
      'type': _typeToString(type),
      if (imageUrl != null) 'imageUrl': imageUrl,
      'updatedAt': now,
      'createdAt': now,
      if (uid != null) 'createdBy': uid,
    }, SetOptions(merge: true));
  }

  /// حذف مطعم/مقهى (لا يحذف الصور تلقائياً).
  Future<void> deleteVenue(String id) async {
    await _col.doc(id).delete();
  }

  /// إنشاء أو تحديث وجبة.
  Future<void> upsertMeal({
    required String restaurantId,
    required String mealId,
    required String restaurantName,
    required String name,
    String? description,
    String? category,
    String? serving,
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
    String? imageUrl,
  }) async {
    final now = Timestamp.now();
    await _col.doc(restaurantId).collection('meals').doc(mealId).set({
      'restaurant': restaurantName,
      'name': name.trim(),
      'description': description,
      'category': category ?? '',
      'serving': serving ?? '',
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
  }

  Future<void> deleteMeal({
    required String restaurantId,
    required String mealId,
  }) async {
    await _col.doc(restaurantId).collection('meals').doc(mealId).delete();
  }

  /// يجهّز id جديد لمطعم/مقهى قبل الحفظ.
  String newVenueId() => _col.doc().id;

  /// يجهّز id جديد لوجبة قبل الحفظ.
  String newMealId(String restaurantId) =>
      _col.doc(restaurantId).collection('meals').doc().id;

  /// رفع صورة من المعرض وإرجاع رابطها.
  Future<String?> pickAndUploadImage({
    required String storagePath,
    int imageQuality = 85,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;

    final ref = _storage.ref().child(storagePath);

    if (kIsWeb) {
      final Uint8List bytes = await picked.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } else {
      await ref.putFile(File(picked.path));
    }

    return await ref.getDownloadURL();
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

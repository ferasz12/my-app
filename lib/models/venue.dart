// lib/models/venue.dart
import 'meal.dart';

enum VenueType { restaurant, cafe }

class Venue {
  final String id;
  final String name;
  final VenueType type;

  /// صورة ثابتة من assets (البيانات القديمة).
  final String? imageAsset;

  /// صورة من الشبكة (Firestore/Storage) للبيانات الجديدة.
  final String? imageUrl;

  /// للبيانات الثابتة: تكون القائمة ممتلئة.
  /// للبيانات من Firestore: غالباً تكون فارغة ونقرأ الوجبات من subcollection.
  final List<Meal> meals;

  const Venue({
    required this.id,
    required this.name,
    required this.type,
    required this.meals,
    this.imageAsset,
    this.imageUrl,
  });

  Venue copyWith({
    String? id,
    String? name,
    VenueType? type,
    String? imageAsset,
    String? imageUrl,
    List<Meal>? meals,
  }) {
    return Venue(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      meals: meals ?? this.meals,
      imageAsset: imageAsset ?? this.imageAsset,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

// lib/models/venue.dart
import 'meal.dart';

enum VenueType { restaurant, cafe }

class Venue {
  final String id;
  final String name;
  final VenueType type;
  final String? imageAsset; // مسار صورة المنشأة (Asset)
  final List<Meal> meals;

  const Venue({
    required this.id,
    required this.name,
    required this.type,
    required this.meals,
    this.imageAsset,
  });
}

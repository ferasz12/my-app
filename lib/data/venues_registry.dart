// lib/data/venues_registry.dart
import '../models/meal.dart';
import '../models/venue.dart';

// المطاعم
import 'restaurants/kfc.dart' as kfc;

// المقاهي
import 'cafes/starbucks.dart' as sbx;

final List<Venue> _allVenues = [
  kfc.venueKfc,
  sbx.venueStarbucks,
];

List<Venue> venuesByType(VenueType type) =>
    _allVenues.where((v) => v.type == type).toList();

// لو احتجت كل الوجبات المجموعة باسم المنشأة (مثل طريقتك القديمة):
Map<String, List<Meal>> buildVenuesRegistryAsMealsMap(VenueType type) {
  final Map<String, List<Meal>> map = {};
  for (final v in venuesByType(type)) {
    map[v.name] = v.meals;
  }
  return map;
}

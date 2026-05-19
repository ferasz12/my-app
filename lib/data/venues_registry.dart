// lib/data/venues_registry.dart
import '../models/meal.dart';
import '../models/venue.dart';

// المطاعم الثابتة القديمة تستخدم كـ fallback للمطاعم فقط عند عدم توفر Firestore.
import 'restaurants/kfc.dart' as kfc;

final List<Venue> _restaurantFallbackVenues = [
  kfc.venueKfc,
];

/// يعيد البيانات الثابتة القديمة للمطاعم فقط.
/// المقاهي لا ترجع أي بيانات ثابتة حتى لا يظهر ستاربكس/مقاهي وهمية للمستخدم.
List<Venue> venuesByType(VenueType type) {
  if (type == VenueType.restaurant) {
    return List<Venue>.unmodifiable(_restaurantFallbackVenues);
  }
  return const <Venue>[];
}

// لو احتجت كل الوجبات المجموعة باسم المنشأة (مثل طريقتك القديمة):
Map<String, List<Meal>> buildVenuesRegistryAsMealsMap(VenueType type) {
  final Map<String, List<Meal>> map = {};
  for (final v in venuesByType(type)) {
    map[v.name] = v.meals;
  }
  return map;
}

// lib/data/restaurants/kfc.dart
import '../../models/venue.dart';
import '../../models/meal.dart';

const String kfcName = 'KFC';

final Venue venueKfc = Venue(
  id: 'kfc',
  name: kfcName,
  type: VenueType.restaurant,
  imageAsset: 'assets/images/venues/kfc.jpg', // غيّرها إذا حبيت
  meals: const [
    Meal(
      id: 'kfc-001',
      restaurant: kfcName,
      name: 'زنجر برجر',
      category: 'سندويتش',
      serving: '1 قطعة',
      calories: 430,
      protein: 24,
      carbs: 45,
      fat: 18,
    ),
    Meal(
      id: 'kfc-002',
      restaurant: kfcName,
      name: 'ستريبس 3 قطع',
      category: 'قطع دجاج',
      serving: '3 قطع',
      calories: 360,
      protein: 27,
      carbs: 15,
      fat: 20,
    ),
  ],
);

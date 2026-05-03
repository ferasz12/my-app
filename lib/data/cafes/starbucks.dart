// lib/data/cafes/starbucks.dart
import '../../models/venue.dart';
import '../../models/meal.dart';

const String starbucksName = 'ستاربكس';

final Venue venueStarbucks = Venue(
  id: 'starbucks',
  name: starbucksName,
  type: VenueType.cafe,
  imageAsset: 'assets/images/venues/starbucks.jpg',
  meals: const [
    Meal(
      id: 'sbx-001',
      restaurant: starbucksName,
      name: 'كابتشينو وسط',
      category: 'مشروب ساخن',
      serving: '12 أونصة',
      calories: 120,
      protein: 6,
      carbs: 10,
      fat: 5,
    ),
    Meal(
      id: 'sbx-002',
      restaurant: starbucksName,
      name: 'لاتيه مثلج صغير',
      category: 'مشروب بارد',
      serving: '12 أونصة',
      calories: 140,
      protein: 7,
      carbs: 12,
      fat: 6,
    ),
  ],
);

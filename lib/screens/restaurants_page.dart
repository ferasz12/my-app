// lib/screens/restaurants_page.dart
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';

import '../models/meal.dart';
import '../models/venue.dart';
import 'venues_list_page.dart';

class RestaurantsPage extends StatelessWidget {
  /// إذا كانت true: الصفحة تعمل كـ "اختيار وجبة" وتُرجع Meal عند الاختيار.
  final bool pickMealMode;

  const RestaurantsPage({super.key, this.pickMealMode = false});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        title: 'المطاعم',
        type: VenueType.restaurant,
        asset: 'assets/images/categories/restaurants.png'
      ),
      (
        title: 'المقاهي',
        type: VenueType.cafe,
        asset: 'assets/images/categories/cafes.png'
      ),
    ];

    return PremiumGate(
      feature: PremiumFeature.restaurants,
      child: Scaffold(
      appBar: AppBar(
        title: Text(pickMealMode ? 'اختر من المطاعم' : 'المطاعم والمقاهي'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, i) {
          final it = items[i];
          return InkWell(
            onTap: () async {
              final Meal? picked = await Navigator.push<Meal?>(
                context,
                MaterialPageRoute(
                  builder: (_) => VenuesListPage(
                    type: it.type,
                    title: it.title,
                    pickMealMode: pickMealMode,
                  ),
                ),
              );

              if (pickMealMode && picked != null && context.mounted) {
                Navigator.pop(context, picked);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 8,
                    color: Colors.black.withOpacity(0.06),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: Image.asset(
                        it.asset,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.image, size: 48)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      it.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
    );
  }
}

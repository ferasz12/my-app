// lib/screens/restaurants_page.dart
import 'package:flutter/material.dart';

import '../models/meal.dart';
import '../models/venue.dart';
import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'venues_list_page.dart';

class RestaurantsPage extends StatelessWidget {
  /// إذا كانت true: الصفحة تعمل كـ "اختيار وجبة" وتُرجع Meal عند الاختيار.
  final bool pickMealMode;

  const RestaurantsPage({super.key, this.pickMealMode = false});

  @override
  Widget build(BuildContext context) {
    final items = [
      const _VenueCategoryItem(
        title: 'المطاعم',
        type: VenueType.restaurant,
        asset: 'assets/images/categories/restaurants.png',
      ),
      const _VenueCategoryItem(
        title: 'المقاهي',
        type: VenueType.cafe,
        asset: 'assets/images/categories/cafes.png',
      ),
    ];

    return PremiumGate(
      feature: PremiumFeature.restaurants,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(pickMealMode ? 'اختر من المطاعم والمقاهي' : 'المطاعم والمقاهي'),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: wide ? 2 : 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: wide ? 1.65 : 0.92,
                  ),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return _VenueCategoryCard(
                      item: it,
                      onTap: () => _openCategory(context, it),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCategory(BuildContext context, _VenueCategoryItem it) async {
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
  }
}

class _VenueCategoryItem {
  final String title;
  final VenueType type;
  final String asset;

  const _VenueCategoryItem({
    required this.title,
    required this.type,
    required this.asset,
  });
}

class _VenueCategoryCard extends StatelessWidget {
  final _VenueCategoryItem item;
  final VoidCallback onTap;

  const _VenueCategoryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: cs.surface,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  item.asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _CategoryPlaceholder(type: item.type),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.04),
                        Colors.black.withOpacity(0.18),
                        Colors.black.withOpacity(0.58),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 16,
                  end: 16,
                  bottom: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.30),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: cs.primary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPlaceholder extends StatelessWidget {
  final VenueType type;
  const _CategoryPlaceholder({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.primary.withOpacity(0.08),
      child: Center(
        child: Icon(
          type == VenueType.cafe ? Icons.local_cafe_rounded : Icons.restaurant_menu_rounded,
          color: cs.primary,
          size: 44,
        ),
      ),
    );
  }
}

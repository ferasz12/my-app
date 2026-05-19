// lib/screens/meal_from_restaurant_picker_page.dart
//
// اختيار وجبة جاهزة من المطاعم/المقاهي ثم إرجاعها للشاشة المستدعية.

import 'package:flutter/material.dart';

import '../data/restaurants_firestore_repository.dart';
import '../data/venues_registry.dart';
import '../models/meal.dart';
import '../models/venue.dart';

/// صفحة اختيار وجبة من مطعم/مقهى.
/// ترجع [Meal] عند الاختيار، أو null عند الإلغاء.
class MealFromRestaurantPickerPage extends StatefulWidget {
  final VenueType type;
  final String title;

  const MealFromRestaurantPickerPage({
    super.key,
    this.type = VenueType.restaurant,
    this.title = 'اختر وجبة من مطعم',
  });

  @override
  State<MealFromRestaurantPickerPage> createState() => _MealFromRestaurantPickerPageState();
}

class _MealFromRestaurantPickerPageState extends State<MealFromRestaurantPickerPage> {
  final _repo = RestaurantsFirestoreRepository();
  final _search = TextEditingController();

  bool get _isCafe => widget.type == VenueType.cafe;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Venue> _applyFilter(List<Venue> list) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((v) => v.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _openVenue(Venue v) async {
    final Meal? picked = await Navigator.push<Meal?>(
      context,
      MaterialPageRoute(builder: (_) => _VenueMealsPickerPage(venue: v)),
    );
    if (!mounted) return;
    if (picked != null) Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final isRestaurant = widget.type == VenueType.restaurant;
    final pageTitle = widget.title.isNotEmpty
        ? widget.title
        : (isRestaurant ? 'اختر وجبة من مطعم' : 'اختر وجبة من مقهى');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(pageTitle)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: _isCafe ? 'ابحث عن مقهى...' : 'ابحث عن مطعم...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Venue>>(
                stream: _repo.streamVenuesByType(widget.type),
                initialData: _repo.cachedVenuesByType(widget.type),
                builder: (context, snap) {
                  final cloud = snap.data ?? const <Venue>[];
                  final fallback = cloud.isEmpty && !_isCafe ? venuesByType(widget.type) : const <Venue>[];
                  final source = cloud.isNotEmpty ? cloud : fallback;
                  final filtered = _applyFilter(source);
                  final waitingFirst = snap.connectionState == ConnectionState.waiting && filtered.isEmpty;

                  if (snap.hasError && filtered.isEmpty) {
                    return const _CenterState(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذر تحميل القائمة',
                      message: 'حاول مرة أخرى بعد قليل.',
                    );
                  }

                  if (waitingFirst) {
                    return const _SoftLoadingList();
                  }

                  if (filtered.isEmpty) {
                    return _CenterState(
                      icon: _isCafe ? Icons.local_cafe_rounded : Icons.restaurant_menu_rounded,
                      title: _isCafe ? 'لا توجد مقاهٍ حاليًا' : 'لا توجد مطاعم حاليًا',
                      message: '',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final v = filtered[i];
                      return _VenuePickCard(
                        venue: v,
                        onTap: () => _openVenue(v),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VenueMealsPickerPage extends StatelessWidget {
  final Venue venue;

  const _VenueMealsPickerPage({required this.venue});

  bool get _isLocal => venue.meals.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final repo = RestaurantsFirestoreRepository();

    Widget buildList(List<Meal> meals) {
      if (meals.isEmpty) {
        return const _CenterState(
          icon: Icons.fastfood_rounded,
          title: 'لا توجد وجبات بعد',
          message: '',
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: meals.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final m = meals[i];
          return _MealPickCard(
            meal: m,
            onTap: () => Navigator.pop(context, m),
          );
        },
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(venue.name)),
        body: _isLocal
            ? buildList(venue.meals)
            : StreamBuilder<List<Meal>>(
                stream: repo.streamMeals(venue.id, restaurantName: venue.name),
                initialData: repo.cachedMeals(venue.id),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const _CenterState(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذر قراءة الوجبات',
                      message: 'حاول مرة أخرى بعد قليل.',
                    );
                  }
                  final meals = snap.data ?? const <Meal>[];
                  if (snap.connectionState == ConnectionState.waiting && meals.isEmpty) {
                    return const _SoftLoadingList();
                  }
                  return buildList(meals);
                },
              ),
      ),
    );
  }
}

class _VenuePickCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback onTap;

  const _VenuePickCard({required this.venue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(22)),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: _VenueImage(v: venue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  venue.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 14, start: 6),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: cs.primary, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VenueImage extends StatelessWidget {
  final Venue v;
  const _VenueImage({required this.v});

  @override
  Widget build(BuildContext context) {
    if (v.imageUrl != null && v.imageUrl!.trim().isNotEmpty) {
      return Image.network(
        v.imageUrl!,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _ImagePlaceholder(type: v.type);
        },
        errorBuilder: (_, __, ___) => _ImagePlaceholder(type: v.type),
      );
    }
    if (v.imageAsset != null && v.imageAsset!.trim().isNotEmpty) {
      return Image.asset(
        v.imageAsset!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _ImagePlaceholder(type: v.type),
      );
    }
    return _ImagePlaceholder(type: v.type);
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final VenueType type;
  const _ImagePlaceholder({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.primary.withOpacity(0.08),
      child: Center(
        child: Icon(
          type == VenueType.cafe ? Icons.local_cafe_rounded : Icons.restaurant_menu_rounded,
          color: cs.primary.withOpacity(0.72),
          size: 28,
        ),
      ),
    );
  }
}

class _MealPickCard extends StatelessWidget {
  final Meal meal;
  final VoidCallback onTap;

  const _MealPickCard({required this.meal, required this.onTap});

  String _fmtG(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final desc = (meal.description ?? '').trim();
    final metaBits = <String>[];
    if (meal.category.trim().isNotEmpty) metaBits.add(meal.category.trim());
    if (meal.serving.trim().isNotEmpty) metaBits.add(meal.serving.trim());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meal.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Icon(Icons.add_circle_outline_rounded, color: cs.primary),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MacroPill(emoji: '🔥', text: '${meal.calories} كال'),
                  _MacroPill(emoji: '🥩', text: '${_fmtG(meal.protein)}غ'),
                  _MacroPill(emoji: '🍞', text: '${_fmtG(meal.carbs)}غ'),
                  _MacroPill(emoji: '🥑', text: '${_fmtG(meal.fat)}غ'),
                ],
              ),
              if (metaBits.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  metaBits.join(' • '),
                  style: text.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.60),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(desc, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String emoji;
  final String text;

  const _MacroPill({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CenterState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _CenterState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: cs.primary, size: 32),
            ),
            const SizedBox(height: 12),
            Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
            if (message.trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                message,
                style: text.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65), height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoftLoadingList extends StatelessWidget {
  const _SoftLoadingList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 94,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 150, height: 12, color: cs.outlineVariant.withOpacity(0.45)),
            const SizedBox(height: 12),
            Container(width: 90, height: 10, color: cs.outlineVariant.withOpacity(0.35)),
          ],
        ),
      ),
    );
  }
}

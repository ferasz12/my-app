// lib/screens/meal_from_restaurant_picker_page.dart
//
// اختيار وجبة جاهزة من المطاعم/المقاهي ثم إرجاعها للشاشة المستدعية.
// الهدف: من الهوم (إضافة وجبة) يختار المستخدم مطعم ثم وجبة، وتُنضاف فورًا كأنه أكلها.

import 'package:flutter/material.dart';

import '../data/restaurants_firestore_repository.dart';
import '../data/venues_registry.dart';
import '../models/meal.dart';
import '../models/venue.dart';

/// صفحة اختيار وجبة من المطاعم.
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Venue> _applyFilter(List<Venue> list) {
    final q = _search.text.trim();
    if (q.isEmpty) return list;
    final qq = q.toLowerCase();
    return list.where((v) => v.name.toLowerCase().contains(qq)).toList();
  }

  Future<void> _openVenue(Venue v) async {
    final Meal? picked = await Navigator.push<Meal?>(
      context,
      MaterialPageRoute(
        builder: (_) => _VenueMealsPickerPage(venue: v),
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      Navigator.pop(context, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRestaurant = widget.type == VenueType.restaurant;
    final pageTitle = widget.title.isNotEmpty
        ? widget.title
        : (isRestaurant ? 'اختر وجبة من مطعم' : 'اختر وجبة من مقهى');

    return Scaffold(
      appBar: AppBar(title: Text(pageTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Venue>>(
              stream: _repo.streamVenuesByType(widget.type),
              builder: (context, snap) {
                // ✅ fallback للبيانات الثابتة لو الكلاود فاضي/غير متاح.
                final cloud = snap.data ?? const <Venue>[];
                final useCloud = cloud.isNotEmpty && !snap.hasError;
                final list = useCloud ? cloud : venuesByType(widget.type);
                final filtered = _applyFilter(list);

                if (filtered.isEmpty) {
                  return const Center(child: Text('لا توجد نتائج'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final v = filtered[i];
                              final m = meals[i];
          final desc = (m.description ?? '').trim();
          final metaBits = <String>[];
          if (m.category.trim().isNotEmpty) metaBits.add(m.category.trim());
          if (m.serving.trim().isNotEmpty) metaBits.add(m.serving.trim());

          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              onTap: () => Navigator.pop(context, m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (m.imageUrl != null && m.imageUrl!.trim().isNotEmpty)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        m.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image, size: 44)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const Icon(Icons.add_circle_outline),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MacroPill(emoji: '🔥', text: '${m.calories} كال'),
                            _MacroPill(emoji: '🥩', text: '${_fmtG(m.protein)}غ'),
                            _MacroPill(emoji: '🍞', text: '${_fmtG(m.carbs)}غ'),
                            _MacroPill(emoji: '🥑', text: '${_fmtG(m.fat)}غ'),
                          ],
                        ),
                        if (metaBits.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            metaBits.join(' • '),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            desc,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(venue.name)),
      body: _isLocal
          ? buildList(venue.meals)
          : StreamBuilder<List<Meal>>(
              stream: repo.streamMeals(venue.id, restaurantName: venue.name),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('تعذر قراءة الوجبات: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return buildList(snap.data!);
              },
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
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 48)),
      );
    }
    if (v.imageAsset != null && v.imageAsset!.trim().isNotEmpty) {
      return Image.asset(
        v.imageAsset!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image, size: 48)),
      );
    }
    return const Center(child: Icon(Icons.image, size: 48));
  }
}


class _MacroPill extends StatelessWidget {
  final String emoji;
  final String text;

  const _MacroPill({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceVariant.withOpacity(0.55);
    final border = theme.dividerColor.withOpacity(0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

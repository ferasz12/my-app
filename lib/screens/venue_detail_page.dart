// lib/screens/venue_detail_page.dart
import 'package:flutter/material.dart';

import '../core/auth/roles_service.dart';
import '../data/restaurants_firestore_repository.dart';
import '../models/meal.dart';
import '../models/venue.dart';
import 'meal_editor_page.dart';
import 'venue_editor_page.dart';

class VenueDetailPage extends StatelessWidget {
  final Venue venue;

  /// إذا كانت true: الصفحة تعمل كـ "اختيار وجبة" وتُرجع Meal عند الاختيار.
  final bool pickMealMode;

  const VenueDetailPage({
    super.key,
    required this.venue,
    this.pickMealMode = false,
  });

  bool get _isLocal => venue.meals.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final repo = RestaurantsFirestoreRepository();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<AppRole>(
        stream: RolesService().currentUserRoleStream(),
        initialData: AppRole.user,
        builder: (context, snap) {
          final role = snap.data ?? AppRole.user;
          final canManage = canManageRestaurants(role) && !pickMealMode;

          return Scaffold(
            appBar: AppBar(
              title: Text(venue.name),
              actions: [
                if (canManage)
                  IconButton(
                    tooltip: 'تعديل',
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: _isLocal
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('لا يمكن تعديل هذا العنصر.'),
                              ),
                            );
                          }
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VenueEditorPage(type: venue.type, existing: venue),
                              ),
                            );
                          },
                  ),
              ],
            ),
            floatingActionButton: canManage && !_isLocal
                ? FloatingActionButton.extended(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MealEditorPage(
                            restaurantId: venue.id,
                            restaurantName: venue.name,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة وجبة'),
                  )
                : null,
            body: _isLocal
                ? _MealsListView(
                    meals: venue.meals,
                    canManage: false,
                    pickMealMode: pickMealMode,
                    onPick: (m) => Navigator.pop(context, m),
                  )
                : StreamBuilder<List<Meal>>(
                    stream: repo.streamMeals(venue.id, restaurantName: venue.name),
                    initialData: repo.cachedMeals(venue.id),
                    builder: (context, mealSnap) {
                      if (mealSnap.hasError) {
                        return _CenterMessage(
                          icon: Icons.wifi_off_rounded,
                          title: 'تعذر قراءة الوجبات',
                          text: 'حاول مرة أخرى بعد قليل.',
                        );
                      }

                      final meals = mealSnap.data ?? const <Meal>[];
                      final waitingFirst = mealSnap.connectionState == ConnectionState.waiting && meals.isEmpty;

                      if (waitingFirst) {
                        return const _MealsLoadingList();
                      }

                      if (meals.isEmpty) {
                        return _CenterMessage(
                          icon: venue.type == VenueType.cafe
                              ? Icons.local_cafe_rounded
                              : Icons.restaurant_menu_rounded,
                          title: 'لا توجد وجبات بعد',
                          text: 'لا توجد وجبات حاليًا.',
                        );
                      }

                      return _MealsListView(
                        meals: meals,
                        canManage: canManage,
                        pickMealMode: pickMealMode,
                        onPick: (m) => Navigator.pop(context, m),
                        onEdit: (m) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MealEditorPage(
                                restaurantId: venue.id,
                                restaurantName: venue.name,
                                existing: m,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _MealsListView extends StatelessWidget {
  final List<Meal> meals;
  final bool canManage;
  final bool pickMealMode;
  final ValueChanged<Meal>? onPick;
  final ValueChanged<Meal>? onEdit;

  const _MealsListView({
    required this.meals,
    required this.canManage,
    required this.pickMealMode,
    this.onPick,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (pickMealMode)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: _PickHint(),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: meals.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final meal = meals[i];
              return _MealCard(
                meal: meal,
                canEdit: canManage,
                onTap: pickMealMode ? () => onPick?.call(meal) : null,
                onEdit: canManage ? () => onEdit?.call(meal) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PickHint extends StatelessWidget {
  const _PickHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.primary.withOpacity(0.08),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Text(
        'اختر الوجبة لإضافتها مباشرة لليوم',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final Meal meal;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;

  const _MealCard({
    required this.meal,
    required this.canEdit,
    this.onEdit,
    this.onTap,
  });

  String _fmtG(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final cs = theme.colorScheme;

    final metaBits = <String>[];
    if (meal.category.trim().isNotEmpty) metaBits.add(meal.category.trim());
    if (meal.serving.trim().isNotEmpty) metaBits.add(meal.serving.trim());

    final desc = (meal.description ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (meal.imageUrl != null && meal.imageUrl!.trim().isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      meal.imageUrl!,
                      fit: BoxFit.cover,
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) return child;
                        return const _MealImagePlaceholder();
                      },
                      errorBuilder: (_, __, ___) => const _MealImagePlaceholder(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
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
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (canEdit)
                          IconButton(
                            tooltip: 'تعديل',
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: onEdit,
                          )
                        else if (onTap != null)
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
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.58),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        desc,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealImagePlaceholder extends StatelessWidget {
  const _MealImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.primary.withOpacity(0.08),
      child: Center(child: Icon(Icons.fastfood_rounded, color: cs.primary.withOpacity(0.7), size: 34)),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String emoji;
  final String text;

  const _MacroPill({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.primary.withOpacity(0.06);
    final border = theme.colorScheme.primary.withOpacity(0.10);

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
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _CenterMessage({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 34, color: cs.primary),
            ),
            const SizedBox(height: 12),
            Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
            const SizedBox(height: 7),
            Text(
              text,
              textAlign: TextAlign.center,
              style: txt.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealsLoadingList extends StatelessWidget {
  const _MealsLoadingList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 128,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 160, height: 13, color: cs.outlineVariant.withOpacity(0.45)),
            const SizedBox(height: 14),
            Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Container(
                    margin: EdgeInsetsDirectional.only(end: i == 3 ? 0 : 8),
                    height: 28,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

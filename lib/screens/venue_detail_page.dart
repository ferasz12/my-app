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

    return StreamBuilder<AppRole>(
      stream: RolesService().currentUserRoleStream(),
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
                  icon: const Icon(Icons.edit),
                  onPressed: _isLocal
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('هذا مطعم ثابت (assets). أنشئ مطعمًا جديدًا من زر الإضافة لتعديله عبر Firestore.'),
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
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة وجبة'),
                )
              : null,
          body: _isLocal
              ? _LocalMealsView(
                  meals: venue.meals,
                  canManage: canManage,
                  pickMealMode: pickMealMode,
                  onPick: (m) => Navigator.pop(context, m),
                )
              : StreamBuilder<List<Meal>>(
                  stream: repo.streamMeals(venue.id, restaurantName: venue.name),
                  builder: (context, mealSnap) {
                    if (mealSnap.hasError) {
                      return _CenterMessage(
                        icon: Icons.error_outline,
                        text: 'تعذر قراءة الوجبات: ${mealSnap.error}',
                      );
                    }
                    if (!mealSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final meals = mealSnap.data!;
                    if (meals.isEmpty) {
                      return const _CenterMessage(
                        icon: Icons.fastfood,
                        text: 'لا توجد وجبات لهذا المطعم بعد.',
                      );
                    }
                    return Column(
                      children: [
                        if (pickMealMode)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                            child: Text(
                              'اختر الوجبة لإضافتها مباشرة لليوم',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                      itemCount: meals.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final m = meals[i];
                        return _MealCard(
                          meal: m,
                          canEdit: canManage,
                          onTap: pickMealMode ? () => Navigator.pop(context, m) : null,
                          onEdit: () async {
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
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

class _LocalMealsView extends StatelessWidget {
  final List<Meal> meals;
  final bool canManage;
  final bool pickMealMode;
  final ValueChanged<Meal>? onPick;

  const _LocalMealsView({
    required this.meals,
    required this.canManage,
    required this.pickMealMode,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (pickMealMode)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'اختر الوجبة لإضافتها مباشرة لليوم',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        if (canManage)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'ملاحظة: هذا المحتوى ثابت (assets). لإضافة/تعديل وجبات بشكل ديناميكي أنشئ مطعمًا جديدًا من صفحة المطاعم.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: meals.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _MealCard(
              meal: meals[i],
              canEdit: false,
              onTap: pickMealMode ? () => onPick?.call(meals[i]) : null,
            ),
          ),
        ),
      ],
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
    // نعرض بدون كسور إذا كانت قيمة صحيحة، وإلا رقم واحد بعد الفاصلة.
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final metaBits = <String>[];
    if (meal.category.trim().isNotEmpty) metaBits.add(meal.category.trim());
    if (meal.serving.trim().isNotEmpty) metaBits.add(meal.serving.trim());

    final desc = (meal.description ?? '').trim();
    final hasDesc = desc.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (meal.imageUrl != null && meal.imageUrl!.trim().isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  meal.imageUrl!,
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
                          meal.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (canEdit)
                        IconButton(
                          tooltip: 'تعديل',
                          icon: const Icon(Icons.edit),
                          onPressed: onEdit,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ===== ماكروز بشكل إيموجي مثل صفحة الهوم =====
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MacroPill(
                        emoji: '🔥',
                        text: '${meal.calories} كال',
                      ),
                      _MacroPill(
                        emoji: '🥩',
                        text: '${_fmtG(meal.protein)}غ',
                      ),
                      _MacroPill(
                        emoji: '🍞',
                        text: '${_fmtG(meal.carbs)}غ',
                      ),
                      _MacroPill(
                        emoji: '🥑',
                        text: '${_fmtG(meal.fat)}غ',
                      ),
                    ],
                  ),

                  if (metaBits.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      metaBits.join(' • '),
                      style: textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  if (hasDesc) ...[
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

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CenterMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

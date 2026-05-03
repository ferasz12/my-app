// lib/screens/venues_list_page.dart
import 'package:flutter/material.dart';

import '../core/auth/roles_service.dart';
import '../data/restaurants_firestore_repository.dart';
import '../data/venues_registry.dart';
import '../models/venue.dart';
import '../models/meal.dart';
import 'venue_detail_page.dart';
import 'venue_editor_page.dart';

class VenuesListPage extends StatefulWidget {
  final VenueType type;
  final String title;
  /// إذا كانت true: هذه الصفحة تعمل كـ "اختيار وجبة" وتُرجع Meal عند الاختيار.
  final bool pickMealMode;

  const VenuesListPage({
    super.key,
    required this.type,
    required this.title,
    this.pickMealMode = false,
  });

  @override
  State<VenuesListPage> createState() => _VenuesListPageState();
}

class _VenuesListPageState extends State<VenuesListPage> {
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
    return list.where((v) => v.name.toLowerCase().contains(q.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppRole>(
      stream: RolesService().currentUserRoleStream(),
      builder: (context, roleSnap) {
        final role = roleSnap.data ?? AppRole.user;
        final canManage = canManageRestaurants(role) && !widget.pickMealMode;

        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VenueEditorPage(type: widget.type),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: Text(widget.type == VenueType.cafe ? 'إضافة مقهى' : 'إضافة مطعم'),
                )
              : null,
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
                    // ✅ لو Firestore فاضي/غير متاح، نرجع للبيانات الثابتة كـ fallback.
                    final cloud = snap.data ?? const <Venue>[];
                    final useCloud = cloud.isNotEmpty && !snap.hasError;

                    final list = useCloud ? cloud : venuesByType(widget.type);
                    final filtered = _applyFilter(list);

                    if (filtered.isEmpty) {
                      return const Center(child: Text('لا توجد نتائج'));
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: filtered.length + (useCloud ? 0 : 1),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (!useCloud && i == filtered.length) {
                          return _FallbackHint(canManage: canManage);
                        }

                        final v = filtered[i];
                        final isLocal = v.meals.isNotEmpty;

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          child: InkWell(
                            onTap: () async {
                              final Meal? picked = await Navigator.push<Meal?>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VenueDetailPage(
                                    venue: v,
                                    pickMealMode: widget.pickMealMode,
                                  ),
                                ),
                              );

                              if (widget.pickMealMode && picked != null && context.mounted) {
                                Navigator.pop(context, picked);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: _VenueImage(v: v),
                                ),
                                ListTile(
                                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(widget.type == VenueType.restaurant ? 'مطعم' : 'مقهى'),
                                  trailing: (canManage && !isLocal)
                                      ? IconButton(
                                          tooltip: 'تعديل',
                                          icon: const Icon(Icons.edit),
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => VenueEditorPage(type: widget.type, existing: v),
                                              ),
                                            );
                                          },
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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

class _FallbackHint extends StatelessWidget {
  final bool canManage;
  const _FallbackHint({required this.canManage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surfaceContainerHighest.withOpacity(0.25),
      ),
      child: Text(
        canManage
            ? 'ملاحظة: الظاهر حالياً بيانات ثابتة (assets). اضغط "إضافة" لإنشاء مطعم/مقهى جديد يظهر للجميع من Firestore.'
            : 'ملاحظة: هذا القسم يعرض بيانات ثابتة حالياً. قريباً سيتم تحديثه ليعرض بيانات مضافة من الإدارة.',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontSize: 12),
      ),
    );
  }
}

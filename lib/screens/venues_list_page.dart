// lib/screens/venues_list_page.dart
import 'package:flutter/material.dart';

import '../core/auth/roles_service.dart';
import '../data/restaurants_firestore_repository.dart';
import '../data/venues_registry.dart';
import '../models/meal.dart';
import '../models/venue.dart';
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<AppRole>(
        stream: RolesService().currentUserRoleStream(),
        initialData: AppRole.user,
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
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_isCafe ? 'إضافة مقهى' : 'إضافة مطعم'),
                  )
                : null,
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: _SearchBox(
                    controller: _search,
                    hint: _isCafe ? 'ابحث عن مقهى...' : 'ابحث عن مطعم...',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Venue>>(
                    stream: _repo.streamVenuesByType(widget.type),
                    initialData: _repo.cachedVenuesByType(widget.type),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        final fallback = _localFallback();
                        if (fallback.isNotEmpty) {
                          return _VenuesList(
                            venues: _applyFilter(fallback),
                            canManage: canManage,
                            pickMealMode: widget.pickMealMode,
                            usingFallback: true,
                            onOpen: _openVenue,
                          );
                        }
                        return _StateMessage(
                          icon: Icons.wifi_off_rounded,
                          title: 'تعذر تحميل القائمة',
                          message: 'حاول مرة أخرى بعد قليل.',
                        );
                      }

                      final cloud = snap.data ?? const <Venue>[];
                      final fallback = cloud.isEmpty ? _localFallback() : const <Venue>[];
                      final usingFallback = cloud.isEmpty && fallback.isNotEmpty;
                      final source = cloud.isNotEmpty ? cloud : fallback;
                      final filtered = _applyFilter(source);

                      final waitingForFirstCloud =
                          snap.connectionState == ConnectionState.waiting && cloud.isEmpty && fallback.isEmpty;

                      if (waitingForFirstCloud) {
                        return const _SoftLoadingList();
                      }

                      if (filtered.isEmpty) {
                        return _StateMessage(
                          icon: _isCafe ? Icons.local_cafe_rounded : Icons.restaurant_menu_rounded,
                          title: _search.text.trim().isEmpty
                              ? (_isCafe ? 'لا توجد مقاهٍ حاليًا' : 'لا توجد مطاعم حاليًا')
                              : 'لا توجد نتائج مطابقة',
message: '',
                        );
                      }

                      return _VenuesList(
                        venues: filtered,
                        canManage: canManage,
                        pickMealMode: widget.pickMealMode,
                        usingFallback: usingFallback,
                        onOpen: _openVenue,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Venue> _localFallback() {
    // المقاهي لا تستخدم أي بيانات ثابتة نهائيًا.
    if (_isCafe) return const <Venue>[];
    return venuesByType(widget.type);
  }

  Future<void> _openVenue(Venue v) async {
    final Meal? picked = await Navigator.push<Meal?>(
      context,
      MaterialPageRoute(
        builder: (_) => VenueDetailPage(
          venue: v,
          pickMealMode: widget.pickMealMode,
        ),
      ),
    );

    if (widget.pickMealMode && picked != null && mounted) {
      Navigator.pop(context, picked);
    }
  }
}

class _ListHeader extends StatelessWidget {
  final bool isCafe;
  final bool pickMealMode;
  final bool canManage;

  const _ListHeader({
    required this.isCafe,
    required this.pickMealMode,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                isCafe ? Icons.local_cafe_rounded : Icons.restaurant_menu_rounded,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCafe ? 'قائمة المقاهي' : 'قائمة المطاعم',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCafe
                        ? 'اختر من القائمة'
                        : 'اختر من القائمة',
                    style: text.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.62),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (canManage)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'إدارة',
                  style: text.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _SearchBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: cs.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _VenuesList extends StatelessWidget {
  final List<Venue> venues;
  final bool canManage;
  final bool pickMealMode;
  final bool usingFallback;
  final ValueChanged<Venue> onOpen;

  const _VenuesList({
    required this.venues,
    required this.canManage,
    required this.pickMealMode,
    required this.usingFallback,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: venues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final v = venues[i];
        final isLocal = v.meals.isNotEmpty;
        return _VenueCard(
          venue: v,
          canEdit: canManage && !isLocal,
          pickMealMode: pickMealMode,
          onTap: () => onOpen(v),
          onEdit: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VenueEditorPage(type: v.type, existing: v),
              ),
            );
          },
        );
      },
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final bool canEdit;
  final bool pickMealMode;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _VenueCard({
    required this.venue,
    required this.canEdit,
    required this.pickMealMode,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isCafe = venue.type == VenueType.cafe;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: cs.surface,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(22)),
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: _VenueImage(v: venue),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      isCafe ? 'مقهى' : 'مطعم',
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.60),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (pickMealMode) ...[
                      const SizedBox(height: 8),
                      Text(
                        'اضغط لاختيار وجبة',
                        style: text.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: onEdit,
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 14),
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: cs.primary),
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
    final cs = Theme.of(context).colorScheme;

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

    return ColoredBox(
      color: cs.primary.withOpacity(0.08),
      child: _ImagePlaceholder(type: v.type),
    );
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
          size: 30,
        ),
      ),
    );
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        color: cs.primary.withOpacity(0.06),
      ),
      child: Text(
        '',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _StateMessage({
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
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 104,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.07),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(22)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 145, height: 13, color: cs.outlineVariant.withOpacity(0.45)),
                  const SizedBox(height: 10),
                  Container(width: 85, height: 10, color: cs.outlineVariant.withOpacity(0.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../../users/ui/user_profile_page.dart';

/// بطاقة وصفة أخف وأوضح:
/// - شكل أكثر ترتيبًا وارتفاع أقل
/// - ماكروز بنفس أسلوب الإيموجي الموجود في الصفحة الرئيسية
/// - توضيح واضح للبروتين/الكارب/الدهون
class RecipeCard extends StatefulWidget {
  final Recipe recipe;
  final bool isLiked;
  final bool canDelete;
  final VoidCallback? onDelete;
  final Future<void> Function() onToggleLike;
  final Widget? topRight;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.isLiked,
    required this.canDelete,
    required this.onDelete,
    required this.onToggleLike,
    this.topRight,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  bool _expanded = false;

  String _relativeAr(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'قبل لحظات';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return 'قبل $weeks أسبوع';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return 'قبل $months شهر';
    final years = (diff.inDays / 365).floor();
    return 'قبل $years سنة';
  }

  void _openUserProfile(BuildContext context) {
    final uid = widget.recipe.userId.trim();
    if (uid.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)),
    );
  }

  String _safeTitle(Recipe r) {
    final t = r.title.trim();
    return t.isEmpty ? 'وصفة بدون عنوان' : t;
  }

  String _bestCaption(Recipe r) {
    final c = (r.caption ?? '').trim();
    if (c.isNotEmpty) return c;

    final m = r.method.trim();
    if (m.isEmpty) return '';
    return m.split('\n').first.trim();
  }

  Future<void> _openImageViewer(String url) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'تعذر عرض الصورة',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      loadingBuilder: (c, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }

  ({Color color, Color bg, String emoji, String label, String unit}) _macroMeta(
    String kind,
    BuildContext context,
  ) {
    final primary = Theme.of(context).colorScheme.primary;

    switch (kind) {
      case 'protein':
        return (
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFEAF1FF),
          emoji: '🥩',
          label: 'البروتين',
          unit: 'غ',
        );
      case 'carbs':
        return (
          color: const Color(0xFFF97316),
          bg: const Color(0xFFFFF3E8),
          emoji: '🍞',
          label: 'الكارب',
          unit: 'غ',
        );
      case 'fat':
        return (
          color: const Color(0xFF22C55E),
          bg: const Color(0xFFEAFBF1),
          emoji: '🥑',
          label: 'الدهون',
          unit: 'غ',
        );
      default:
        return (
          color: primary,
          bg: primary.withOpacity(0.10),
          emoji: '🔥',
          label: 'السعرات',
          unit: 'kcal',
        );
    }
  }

  Widget _emojiPill(String emoji, Color tint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _macroTile({
    required BuildContext context,
    required String kind,
    required String value,
  }) {
    final meta = _macroMeta(kind, context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: meta.color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          _emojiPill(meta.emoji, meta.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meta.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withOpacity(0.66),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$value ${meta.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: meta.color,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _macrosGrid(
    BuildContext context, {
    required String kcal,
    required String protein,
    required String carbs,
    required String fat,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: width,
              child: _macroTile(context: context, kind: 'calories', value: kcal),
            ),
            SizedBox(
              width: width,
              child: _macroTile(context: context, kind: 'protein', value: protein),
            ),
            SizedBox(
              width: width,
              child: _macroTile(context: context, kind: 'carbs', value: carbs),
            ),
            SizedBox(
              width: width,
              child: _macroTile(context: context, kind: 'fat', value: fat),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.recipe;

    final title = _safeTitle(r);
    final caption = _bestCaption(r);

    final kcal = r.calories.isFinite ? r.calories.round().toString() : '-';
    final p = r.protein.isFinite ? r.protein.round().toString() : '-';
    final c = r.carbs.isFinite ? r.carbs.round().toString() : '-';
    final f = r.fat.isFinite ? r.fat.round().toString() : '-';

    final hasUserPhoto = (r.userPhotoUrl ?? '').trim().isNotEmpty;
    final imageUrl = (r.imageUrl ?? '').trim();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openUserProfile(context),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.black.withOpacity(0.06),
                          backgroundImage: hasUserPhoto
                              ? NetworkImage(r.userPhotoUrl!.trim())
                              : null,
                          child: hasUserPhoto
                              ? null
                              : Text(
                                  (r.userName.isNotEmpty ? r.userName[0] : 'و'),
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      r.userName.isNotEmpty ? r.userName : 'مستخدم',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (r.isVerified)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'موثوق',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _relativeAr(r.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _pill(
                          context: context,
                          icon: Icons.flag_outlined,
                          label: r.goal.labelAr,
                        ),
                        if (widget.canDelete && widget.onDelete != null) ...[
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: 'حذف',
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _openImageViewer(imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: AspectRatio(
                          aspectRatio: 16 / 8.3,
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black.withOpacity(0.05),
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined, size: 32),
                              ),
                            ),
                            loadingBuilder: (c, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: Colors.black.withOpacity(0.04),
                                child: const Center(child: CircularProgressIndicator()),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: _expanded ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.8,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      caption,
                      maxLines: _expanded ? 5 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.82),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  _macrosGrid(
                    context,
                    kcal: kcal,
                    protein: p,
                    carbs: c,
                    fat: f,
                  ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () async => widget.onToggleLike(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 24,
                                color: widget.isLiked
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${r.likeCount}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                        label: Text(_expanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل'),
                      ),
                    ],
                  ),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, anim) => SizeTransition(
                      sizeFactor: anim,
                      axisAlignment: -1,
                      child: child,
                    ),
                    child: _expanded
                        ? Padding(
                            key: const ValueKey('expanded'),
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Divider(color: Colors.black.withOpacity(0.08)),
                                const SizedBox(height: 8),
                                _sectionTitle(context, 'المكونات'),
                                const SizedBox(height: 8),
                                if (r.ingredients.isEmpty)
                                  Text(
                                    '—',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.75),
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: r.ingredients.map((ing) {
                                      final s = ing.trim();
                                      if (s.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 5),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '• ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                s,
                                                style: const TextStyle(
                                                  fontSize: 13.2,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                const SizedBox(height: 12),
                                _sectionTitle(context, 'الطريقة'),
                                const SizedBox(height: 8),
                                Text(
                                  r.method.trim().isEmpty ? '—' : r.method.trim(),
                                  style: const TextStyle(
                                    fontSize: 13.2,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _sectionTitle(context, 'الماكروز'),
                                const SizedBox(height: 8),
                                _macrosGrid(
                                  context,
                                  kcal: kcal,
                                  protein: p,
                                  carbs: c,
                                  fat: f,
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(key: ValueKey('collapsed')),
                  ),
                ],
              ),
            ),
            if (widget.topRight != null)
              Positioned(
                top: 0,
                right: 0,
                child: widget.topRight!,
              ),
          ],
        ),
      ),
    );
  }
}

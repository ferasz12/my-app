import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../features/users/ui/user_profile_page.dart';
import '../models/community_models.dart';
import '../services/community_service.dart';

class CommunityPage extends StatefulWidget {
  final CommunityCategory? initialCategory;
  final String? initialText;
  final String? linkedRecipeId;
  final String? linkedRecipeTitle;

  const CommunityPage({
    super.key,
    this.initialCategory,
    this.initialText,
    this.linkedRecipeId,
    this.linkedRecipeTitle,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final CommunityService _service = CommunityService.instance;

  CommunitySort _sort = CommunitySort.latest;
  CommunityFeedView _view = CommunityFeedView.all;
  CommunityCategory? _category;
  bool _openingComposer = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    final hasInitialDraft = (widget.initialText ?? '').trim().isNotEmpty;
    if (hasInitialDraft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openComposer(
          initialCategory: widget.initialCategory ?? CommunityCategory.recipe,
          initialText: widget.initialText,
          recipeId: widget.linkedRecipeId,
          recipeTitle: widget.linkedRecipeTitle,
        );
      });
    }
  }

  Future<void> _openComposer({
    CommunityCategory? initialCategory,
    String? initialText,
    String? recipeId,
    String? recipeTitle,
  }) async {
    if (_openingComposer) return;
    _openingComposer = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        builder: (_) => _ComposePostSheet(
          initialCategory: initialCategory ?? CommunityCategory.question,
          initialText: initialText,
          linkedRecipeId: recipeId,
          linkedRecipeTitle: recipeTitle,
          onSubmit: (category, content) async {
            await _service.createPost(
              category: category,
              content: content,
              recipeId: recipeId,
              recipeTitle: recipeTitle,
            );
          },
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      _openingComposer = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openComposer(
              initialCategory: _category ?? CommunityCategory.question),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('بوست جديد'),
        ),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('مجتمع وازن'),
          actions: [
            IconButton(
              tooltip: 'بوست جديد',
              onPressed: () => _openComposer(
                  initialCategory: _category ?? CommunityCategory.question),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            _CommunityBackground(colorScheme: cs),
            SafeArea(
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _CommunityHeader(onPost: () => _openComposer()),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _FiltersBar(
                        view: _view,
                        sort: _sort,
                        category: _category,
                        onViewChanged: (v) => setState(() => _view = v),
                        onSortChanged: (s) => setState(() => _sort = s),
                        onCategoryChanged: (c) => setState(() => _category = c),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    sliver: _buildFeed(uid),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed(String? uid) {
    if (_view == CommunityFeedView.liked) {
      if (uid == null) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyCommunityState(
            title: 'سجل دخولك أولًا',
            message: 'بعد تسجيل الدخول تقدر تشوف البوستات اللي أعجبتك.',
          ),
        );
      }
      return StreamBuilder<List<String>>(
        stream: _service.streamMyLikedPostIds(uid),
        builder: (context, likedSnap) {
          if (likedSnap.connectionState == ConnectionState.waiting) {
            return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()));
          }
          final ids = likedSnap.data ?? const <String>[];
          if (ids.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyCommunityState(
                title: 'ما عندك إعجابات بعد',
                message: 'أي بوست تضغط عليه إعجاب بيظهر هنا.',
              ),
            );
          }
          return FutureBuilder<List<CommunityPost>>(
            future: _service.getPostsByIds(ids),
            builder: (context, postsSnap) {
              if (postsSnap.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()));
              }
              final posts = _applyLocalFilters(
                  postsSnap.data ?? const <CommunityPost>[], uid);
              return _postsSliver(posts, uid);
            },
          );
        },
      );
    }

    return StreamBuilder<List<CommunityPost>>(
      stream: _service.streamPosts(sort: _sort),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyCommunityState(
              title: 'تعذر تحميل المجتمع',
              message: 'تأكد من اتصالك أو قواعد Firestore ثم حاول مرة أخرى.',
              details: snap.error.toString(),
            ),
          );
        }
        final posts =
            _applyLocalFilters(snap.data ?? const <CommunityPost>[], uid);
        return _postsSliver(posts, uid);
      },
    );
  }

  List<CommunityPost> _applyLocalFilters(
      List<CommunityPost> input, String? uid) {
    Iterable<CommunityPost> out = input;
    if (_category != null) out = out.where((p) => p.category == _category);
    if (_view == CommunityFeedView.mine && uid != null) {
      out = out.where((p) => p.authorUid == uid);
    }
    final list = out.toList(growable: false);
    if (_view == CommunityFeedView.liked) {
      switch (_sort) {
        case CommunitySort.latest:
          break;
        case CommunitySort.mostLiked:
          list.sort((a, b) => b.likesCount.compareTo(a.likesCount));
          break;
        case CommunitySort.mostCommented:
          list.sort((a, b) => b.commentsCount.compareTo(a.commentsCount));
          break;
        case CommunitySort.trending:
          list.sort((a, b) => b.trendScore.compareTo(a.trendScore));
          break;
      }
    }
    return list;
  }

  Widget _postsSliver(List<CommunityPost> posts, String? uid) {
    if (posts.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyCommunityState(
          title: _view == CommunityFeedView.mine
              ? 'ما نشرت بوستات بعد'
              : 'المجتمع هادئ حاليًا',
          message: 'ابدأ أول نقاش في مجتمع وازن وخل الناس تستفيد من تجربتك.',
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index.isOdd) return const SizedBox(height: 12);
          final post = posts[index ~/ 2];
          return _CommunityPostCard(
            post: post,
            currentUid: uid,
            service: _service,
          );
        },
        childCount: posts.length * 2 - 1,
      ),
    );
  }
}


class _CommunityHeader extends StatelessWidget {
  final VoidCallback onPost;
  const _CommunityHeader({required this.onPost});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.20),
            cs.surface.withOpacity(0.94),
            cs.tertiaryContainer.withOpacity(0.28),
          ],
        ),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.13),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [cs.primary, cs.primaryContainer],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(Icons.forum_rounded, color: cs.onPrimary, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مجتمع وازن',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'مكان الأسئلة، المعلومات، الوصفات، والتجارب الصحية المختصرة.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.66),
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _HeaderMiniPill(icon: Icons.help_rounded, label: 'أسئلة'),
              _HeaderMiniPill(icon: Icons.lightbulb_rounded, label: 'معلومات'),
              _HeaderMiniPill(icon: Icons.restaurant_menu_rounded, label: 'وصفات'),
              _HeaderMiniPill(icon: Icons.timeline_rounded, label: 'تجارب'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPost,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('اكتب بوست في المجتمع'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderMiniPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

extension _CommunityCategoryUiX on CommunityCategory {
  IconData get icon {
    switch (this) {
      case CommunityCategory.question:
        return Icons.help_rounded;
      case CommunityCategory.info:
        return Icons.lightbulb_rounded;
      case CommunityCategory.recipe:
        return Icons.restaurant_menu_rounded;
      case CommunityCategory.progress:
        return Icons.trending_up_rounded;
      case CommunityCategory.experience:
        return Icons.auto_stories_rounded;
    }
  }

  String get headline {
    switch (this) {
      case CommunityCategory.question:
        return 'سؤال يحتاج جواب';
      case CommunityCategory.info:
        return 'معلومة صحية';
      case CommunityCategory.recipe:
        return 'وصفة من المجتمع';
      case CommunityCategory.progress:
        return 'تقدّم وإنجاز';
      case CommunityCategory.experience:
        return 'تجربة شخصية';
    }
  }

  String get description {
    switch (this) {
      case CommunityCategory.question:
        return 'اكتب سؤالك بوضوح وخله سهل على الناس يجاوبونك.';
      case CommunityCategory.info:
        return 'شارك معلومة قصيرة ومفيدة بدون تعقيد.';
      case CommunityCategory.recipe:
        return 'اكتب مكونات الوصفة وطريقتها بشكل مرتب.';
      case CommunityCategory.progress:
        return 'شارك إنجازك أو تغيّر بسيط حفّزك اليوم.';
      case CommunityCategory.experience:
        return 'احكِ تجربة واقعية ممكن تفيد غيرك.';
    }
  }

  String get composerHint {
    switch (this) {
      case CommunityCategory.question:
        return 'مثال: وش أفضل فطور عالي بروتين وسعراته قليلة؟';
      case CommunityCategory.info:
        return 'مثال: معلومة مهمة عن البروتين أو الماء أو النوم...';
      case CommunityCategory.recipe:
        return 'مثال: وصفة سريعة: المكونات، الطريقة، والسعرات التقريبية...';
      case CommunityCategory.progress:
        return 'مثال: اليوم كملت هدفي في الماء والخطوات...';
      case CommunityCategory.experience:
        return 'مثال: تجربتي مع تنظيم الوجبات خلال أسبوع...';
    }
  }

  String get template {
    switch (this) {
      case CommunityCategory.question:
        return '**سؤالي:**\n\n**هدفي:** \n\n**وش جربت؟** \n\n**أحتاج رأيكم في:** ';
      case CommunityCategory.info:
        return '**معلومة سريعة:**\n\n- \n\n**ليش تفيدك؟**\n';
      case CommunityCategory.recipe:
        return '**اسم الوصفة:**\n\n**المكونات:**\n- \n\n**الطريقة:**\n1. \n\n**مناسبة لـ:** ';
      case CommunityCategory.progress:
        return '**إنجاز اليوم:**\n\n**الشيء اللي ساعدني:**\n- \n\n**هدفي الجاي:** ';
      case CommunityCategory.experience:
        return '**تجربتي:**\n\n**النتيجة:**\n\n**نصيحتي لكم:** ';
    }
  }

  Color accent(ColorScheme cs) {
    switch (this) {
      case CommunityCategory.question:
        return cs.primary;
      case CommunityCategory.info:
        return cs.tertiary;
      case CommunityCategory.recipe:
        return cs.secondary;
      case CommunityCategory.progress:
        return cs.primary;
      case CommunityCategory.experience:
        return cs.error;
    }
  }

  List<Color> softGradient(ColorScheme cs) {
    final a = accent(cs);
    return [a.withOpacity(0.16), a.withOpacity(0.06), cs.surface.withOpacity(0.92)];
  }
}


class _FiltersBar extends StatelessWidget {
  final CommunityFeedView view;
  final CommunitySort sort;
  final CommunityCategory? category;
  final ValueChanged<CommunityFeedView> onViewChanged;
  final ValueChanged<CommunitySort> onSortChanged;
  final ValueChanged<CommunityCategory?> onCategoryChanged;

  const _FiltersBar({
    required this.view,
    required this.sort,
    required this.category,
    required this.onViewChanged,
    required this.onSortChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.88),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.50)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<CommunityFeedView>(
              showSelectedIcon: false,
              segments: CommunityFeedView.values
                  .map((v) => ButtonSegment(value: v, label: Text(v.labelAr)))
                  .toList(),
              selected: {view},
              onSelectionChanged: (s) => onViewChanged(s.first),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.tune_rounded, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<CommunitySort>(
                  value: sort,
                  decoration: InputDecoration(
                    labelText: 'رتّب البوستات',
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withOpacity(0.34),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  items: CommunitySort.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.labelAr)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onSortChanged(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CategoryFilterChip(
                  label: 'الكل',
                  icon: Icons.grid_view_rounded,
                  selected: category == null,
                  onTap: () => onCategoryChanged(null),
                ),
                const SizedBox(width: 8),
                ...CommunityCategory.values.map(
                  (c) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: _CategoryFilterChip(
                      label: c.labelAr,
                      icon: c.icon,
                      selected: category == c,
                      onTap: () => onCategoryChanged(c),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.14) : cs.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? cs.primary.withOpacity(0.34) : cs.outlineVariant.withOpacity(0.50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? cs.primary : cs.onSurface.withOpacity(0.62)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                color: selected ? cs.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _CommunityPostCard extends StatelessWidget {
  final CommunityPost post;
  final String? currentUid;
  final CommunityService service;

  const _CommunityPostCard({
    required this.post,
    required this.currentUid,
    required this.service,
  });

  bool get _isMine => currentUid != null && currentUid == post.authorUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = post.supportDisplay ? cs.primary : post.category.accent(cs);
    final supportGradient = [
      cs.primary.withOpacity(0.11),
      cs.tertiary.withOpacity(0.05),
      cs.surface.withOpacity(0.98),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: post.supportDisplay
              ? supportGradient
              : [
                  cs.surface.withOpacity(0.97),
                  cs.surface.withOpacity(0.94),
                ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withOpacity(post.supportDisplay ? 0.24 : 0.18), width: post.supportDisplay ? 1.25 : 1),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(post.supportDisplay ? 0.16 : 0.10),
            blurRadius: post.supportDisplay ? 28 : 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            if (post.supportDisplay)
              PositionedDirectional(
                end: -18,
                top: -10,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withOpacity(0.07),
                  ),
                  child: Icon(Icons.support_agent_rounded, color: cs.primary.withOpacity(0.16), size: 44),
                ),
              ),
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 5, color: accent.withOpacity(0.82)),
            ),
            PositionedDirectional(
              end: -34,
              top: -34,
              child: Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.055),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PostCategoryBanner(post: post),
                  const SizedBox(height: 13),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: post.supportDisplay ? null : () => _openProfile(context, post.authorUid),
                        child: _CommunityAvatar(
                          name: post.authorName,
                          photoUrl: post.authorPhotoUrl,
                          support: post.supportDisplay,
                          radius: 22,
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
                                    post.authorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                if (post.supportDisplay) ...[
                                  const SizedBox(width: 7),
                                  const _SmallBadge(text: 'دعم وازن'),
                                ],
                                if (_isMine) ...[
                                  const SizedBox(width: 7),
                                  const _SmallBadge(text: 'منشورك'),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _relativeAr(post.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.52),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isMine)
                        PopupMenuButton<String>(
                          tooltip: 'خيارات',
                          onSelected: (v) async {
                            if (v == 'delete') await _confirmDelete(context);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('حذف المنشور')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _RichCommunityText(text: post.content),
                  if ((post.recipeTitle ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 13),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            accent.withOpacity(0.12),
                            cs.surfaceContainerHighest.withOpacity(0.30),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: accent.withOpacity(0.16)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.restaurant_menu_rounded, size: 19, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              post.recipeTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 13),
                  _PostActions(post: post, currentUid: currentUid, service: service),
                  if (post.commentsCount > 0) ...[
                    const SizedBox(height: 10),
                    _CommentsPreview(post: post, service: service, currentUid: currentUid),
                  ],
                  const SizedBox(height: 10),
                  _InlineCommentBox(post: post, service: service),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, String uid) {
    if (uid.trim().isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المنشور؟'),
        content: const Text('سيتم إخفاء المنشور من مجتمع وازن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.deletePost(post);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المنشور')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف المنشور: $e')));
    }
  }
}

class _PostCategoryBanner extends StatelessWidget {
  final CommunityPost post;
  const _PostCategoryBanner({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = post.supportDisplay ? cs.primary : post.category.accent(cs);
    final bannerColors = post.supportDisplay
        ? [
            cs.primary.withOpacity(0.18),
            cs.tertiary.withOpacity(0.08),
            cs.surface.withOpacity(0.95),
          ]
        : post.category.softGradient(cs);
    final bannerIcon = post.supportDisplay ? Icons.support_agent_rounded : post.category.icon;
    final headline = post.supportDisplay ? 'رسالة من دعم وازن' : post.category.headline;
    final label = post.supportDisplay ? 'دعم وازن' : post.category.labelAr;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: bannerColors,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(post.supportDisplay ? 0.22 : 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(bannerIcon, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: accent),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.58),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (post.supportDisplay)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withOpacity(0.14)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 15, color: accent),
                  const SizedBox(width: 5),
                  Text('رسمي', style: TextStyle(fontWeight: FontWeight.w900, color: accent, fontSize: 12)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.66),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withOpacity(0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 15, color: accent),
                const SizedBox(width: 5),
                Text('${post.commentsCount}', style: TextStyle(fontWeight: FontWeight.w900, color: accent, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostActions extends StatelessWidget {
  final CommunityPost post;
  final String? currentUid;
  final CommunityService service;

  const _PostActions(
      {required this.post, required this.currentUid, required this.service});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (currentUid == null) {
      return _ActionsShell(
        children: [
          _ActionItem(
              icon: Icons.favorite_border_rounded,
              label: '${post.likesCount}',
              onTap: null),
          _ActionItem(
              icon: Icons.mode_comment_outlined,
              label: '${post.commentsCount}',
              onTap: () => _openComments(context)),
          _ActionItem(
              icon: Icons.flag_outlined,
              label: 'إبلاغ',
              color: cs.error,
              onTap: () => _openReport(context)),
        ],
      );
    }

    return StreamBuilder<bool>(
      stream: service.streamIsLiked(post.id, currentUid!),
      builder: (context, snap) {
        final liked = snap.data ?? false;
        return _ActionsShell(
          children: [
            _ActionItem(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: '${post.likesCount}',
              color: liked ? cs.primary : null,
              onTap: () async {
                try {
                  await service.toggleLike(post);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تعذر حفظ الإعجاب: $e')));
                }
              },
            ),
            _ActionItem(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentsCount}',
                onTap: () => _openComments(context)),
            _ActionItem(
                icon: Icons.flag_outlined,
                label: 'إبلاغ',
                color: cs.error,
                onTap: () => _openReport(context)),
          ],
        );
      },
    );
  }

  Future<void> _openReport(BuildContext context) async {
    if (currentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل دخولك أولًا حتى ترسل بلاغًا')),
      );
      return;
    }
    if (currentUid == post.authorUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكنك الإبلاغ عن منشورك')),
      );
      return;
    }

    final outerContext = context;
    final detailsCtrl = TextEditingController();
    String selectedReason = 'abuse';
    bool sending = false;

    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) {
          final cs = Theme.of(sheetContext).colorScheme;
          final tt = Theme.of(sheetContext).textTheme;
          final reasons = const <String, String>{
            'abuse': 'إساءة أو تنمّر',
            'spam': 'سبام أو إعلان مزعج',
            'misleading': 'معلومة مضللة',
            'unsafe': 'محتوى غير آمن',
            'other': 'سبب آخر',
          };

          return Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                Future<void> submit() async {
                  if (sending) return;
                  setSheetState(() => sending = true);
                  try {
                    await service.reportPost(
                      post: post,
                      reason: selectedReason,
                      details: detailsCtrl.text,
                    );
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    if (!outerContext.mounted) return;
                    ScaffoldMessenger.of(outerContext).showSnackBar(
                      const SnackBar(
                          content: Text('وصل البلاغ للدعم. شكرًا لك')),
                    );
                  } catch (e) {
                    if (!sheetContext.mounted) return;
                    setSheetState(() => sending = false);
                    if (!outerContext.mounted) return;
                    ScaffoldMessenger.of(outerContext).showSnackBar(
                      SnackBar(content: Text('تعذر إرسال البلاغ: $e')),
                    );
                  }
                }

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    MediaQuery.of(sheetContext).viewInsets.bottom + 18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: cs.error.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.flag_rounded, color: cs.error),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('إبلاغ عن منشور',
                                    style: tt.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 3),
                                Text(
                                  'سيصل البلاغ مباشرة إلى لوحة الدعم لمراجعته.',
                                  style: tt.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.62)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...reasons.entries.map(
                        (entry) => RadioListTile<String>(
                          value: entry.key,
                          groupValue: selectedReason,
                          onChanged: sending
                              ? null
                              : (v) => setSheetState(
                                  () => selectedReason = v ?? 'other'),
                          title: Text(entry.value),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: detailsCtrl,
                        enabled: !sending,
                        maxLines: 3,
                        maxLength: 700,
                        decoration: const InputDecoration(
                          labelText: 'تفاصيل إضافية اختيارية',
                          hintText: 'مثال: إساءة في الكلام أو معلومة مضللة...',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: sending ? null : submit,
                          icon: sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_rounded),
                          label: const Text('إرسال البلاغ للدعم'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      detailsCtrl.dispose();
    }
  }

  void _openComments(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _CommentsSheet(post: post, service: service),
    );
  }
}

class _ActionsShell extends StatelessWidget {
  final List<Widget> children;
  const _ActionsShell({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 8, children: children);
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionItem(
      {required this.icon, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18, color: color ?? cs.onSurface.withOpacity(0.68)),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

class _CommentsPreview extends StatelessWidget {
  final CommunityPost post;
  final CommunityService service;
  final String? currentUid;

  const _CommentsPreview({
    required this.post,
    required this.service,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityComment>>(
      stream: service.streamComments(post.id, limit: 2),
      builder: (context, snap) {
        final comments = snap.data ?? const <CommunityComment>[];
        if (comments.isEmpty) return const SizedBox.shrink();
        return Column(
          children: comments
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CommentTile(
                      comment: c,
                      post: post,
                      service: service,
                      currentUid: currentUid,
                      compact: true,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _InlineCommentBox extends StatefulWidget {
  final CommunityPost post;
  final CommunityService service;
  const _InlineCommentBox({required this.post, required this.service});

  @override
  State<_InlineCommentBox> createState() => _InlineCommentBoxState();
}

class _InlineCommentBoxState extends State<_InlineCommentBox> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await widget.service.addComment(post: widget.post, text: text);
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر إرسال التعليق: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.only(
          start: 12, end: 6, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.40),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'اكتب تعليقك...',
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _CommentsSheet extends StatelessWidget {
  final CommunityPost post;
  final CommunityService service;
  const _CommentsSheet({required this.post, required this.service});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'التعليقات',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<CommunityComment>>(
                  stream: service.streamComments(post.id, limit: 0),
                  builder: (context, snap) {
                    final comments = snap.data ?? const <CommunityComment>[];
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (comments.isEmpty) {
                      return const Center(child: Text('لا توجد تعليقات بعد'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _CommentTile(
                        comment: comments[i],
                        post: post,
                        service: service,
                        currentUid: FirebaseAuth.instance.currentUser?.uid,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _InlineCommentBox(post: post, service: service),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommunityComment comment;
  final CommunityPost post;
  final CommunityService service;
  final String? currentUid;
  final bool compact;

  const _CommentTile({
    required this.comment,
    required this.post,
    required this.service,
    required this.currentUid,
    this.compact = false,
  });

  bool get _isCreator => comment.authorUid == post.authorUid;
  bool get _canDelete => currentUid != null && currentUid == comment.authorUid;
  bool get _canPin => currentUid != null && currentUid == post.authorUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasMenu = _canDelete || _canPin;
    return Container(
      padding: EdgeInsets.fromLTRB(10, compact ? 8 : 10, 10, compact ? 8 : 10),
      decoration: BoxDecoration(
        color: comment.isPinned
            ? cs.primary.withOpacity(0.075)
            : cs.surfaceContainerHighest.withOpacity(0.36),
        borderRadius: BorderRadius.circular(18),
        border: comment.isPinned
            ? Border.all(color: cs.primary.withOpacity(0.20))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommunityAvatar(
            name: comment.authorName,
            photoUrl: comment.authorPhotoUrl,
            support: comment.supportDisplay,
            radius: compact ? 15 : 17,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (comment.supportDisplay) ...[
                      const SizedBox(width: 6),
                      const _SmallBadge(text: 'دعم وازن'),
                    ],
                    if (_isCreator) ...[
                      const SizedBox(width: 6),
                      const _SmallBadge(text: 'المنشئ'),
                    ],
                    if (comment.isPinned) ...[
                      const SizedBox(width: 6),
                      const _SmallBadge(text: 'مثبت'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
          if (hasMenu)
            PopupMenuButton<String>(
              tooltip: 'خيارات التعليق',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz_rounded,
                  size: compact ? 19 : 21,
                  color: cs.onSurface.withOpacity(0.62)),
              onSelected: (value) => _handleAction(context, value),
              itemBuilder: (_) => [
                if (_canPin)
                  PopupMenuItem(
                    value: comment.isPinned ? 'unpin' : 'pin',
                    child: Text(comment.isPinned
                        ? 'إلغاء تثبيت التعليق'
                        : 'تثبيت التعليق'),
                  ),
                if (_canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف التعليق'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String value) async {
    try {
      if (value == 'pin' || value == 'unpin') {
        await service.setCommentPinned(
          post: post,
          comment: comment,
          pinned: value == 'pin',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value == 'pin'
                ? 'تم تثبيت التعليق'
                : 'تم إلغاء تثبيت التعليق'),
          ),
        );
        return;
      }

      if (value == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('حذف التعليق؟'),
            content: const Text('سيتم إخفاء تعليقك من هذا المنشور.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await service.deleteComment(post: post, comment: comment);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف التعليق')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ الإجراء: $e')),
      );
    }
  }
}

class _ComposePostSheet extends StatefulWidget {
  final CommunityCategory initialCategory;
  final String? initialText;
  final String? linkedRecipeId;
  final String? linkedRecipeTitle;
  final Future<void> Function(CommunityCategory category, String content)
      onSubmit;

  const _ComposePostSheet({
    required this.initialCategory,
    required this.onSubmit,
    this.initialText,
    this.linkedRecipeId,
    this.linkedRecipeTitle,
  });

  @override
  State<_ComposePostSheet> createState() => _ComposePostSheetState();
}


class _ComposePostSheetState extends State<_ComposePostSheet> {
  late CommunityCategory _category;
  late final TextEditingController _controller;
  bool _submitting = false;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _controller = TextEditingController(text: widget.initialText ?? '');
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _wrapSelection(String start, String end, {String placeholder = 'النص'}) {
    final text = _controller.text;
    final selection = _controller.selection;
    final rawStart = selection.isValid ? selection.start : text.length;
    final rawEnd = selection.isValid ? selection.end : text.length;
    final a = rawStart.clamp(0, text.length).toInt();
    final b = rawEnd.clamp(0, text.length).toInt();
    final from = a <= b ? a : b;
    final to = a <= b ? b : a;
    final selected = from == to ? placeholder : text.substring(from, to);
    final next = text.replaceRange(from, to, '$start$selected$end');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: from + start.length + selected.length),
    );
  }

  void _insertAtCursor(String value) {
    final text = _controller.text;
    final selection = _controller.selection;
    final rawStart = selection.isValid ? selection.start : text.length;
    final rawEnd = selection.isValid ? selection.end : rawStart;
    final a = rawStart.clamp(0, text.length).toInt();
    final b = rawEnd.clamp(0, text.length).toInt();
    final from = a <= b ? a : b;
    final to = a <= b ? b : a;
    final next = text.replaceRange(from, to, value);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: from + value.length),
    );
  }

  void _insertTemplate() {
    final current = _controller.text.trim();
    if (current.isEmpty) {
      _controller.text = _category.template;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      return;
    }
    _insertAtCursor('\n\n${_category.template}');
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.length < 3 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_category, content);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر البوست في مجتمع وازن')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر النشر: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = _category.accent(cs);
    final contentLength = _controller.text.trim().length;
    final canPost = contentLength >= 3 && !_submitting;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(_category.icon, color: accent),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('بوست جديد', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                          _category.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.62),
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: CommunityCategory.values.map((c) {
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: _ComposerCategoryCard(
                        category: c,
                        selected: _category == c,
                        onTap: () => setState(() => _category = c),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if ((widget.linkedRecipeTitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant_menu_rounded, color: cs.primary, size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.linkedRecipeTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.34),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accent.withOpacity(0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FormatButton(icon: Icons.format_bold_rounded, label: 'عريض', onTap: () => _wrapSelection('**', '**')),
                            const SizedBox(width: 8),
                            _FormatButton(icon: Icons.title_rounded, label: 'عنوان', onTap: () => _insertAtCursor('\n# عنوان\n')),
                            const SizedBox(width: 8),
                            _FormatButton(icon: Icons.format_list_bulleted_rounded, label: 'نقاط', onTap: () => _insertAtCursor('\n- ')),
                            const SizedBox(width: 8),
                            _FormatButton(icon: Icons.format_list_numbered, label: 'ترقيم', onTap: () => _insertAtCursor('\n1. ')),
                            const SizedBox(width: 8),
                            _FormatButton(icon: Icons.format_quote_rounded, label: 'اقتباس', onTap: () => _insertAtCursor('\n> ')),
                            const SizedBox(width: 8),
                            _FormatButton(icon: Icons.remove_rounded, label: 'فاصل', onTap: () => _insertAtCursor('\n---\n')),
                            const SizedBox(width: 8),
                            _FormatButton(icon: Icons.auto_fix_high_rounded, label: 'قالب', onTap: _insertTemplate),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _showPreview
                            ? Container(
                                key: const ValueKey('preview'),
                                width: double.infinity,
                                constraints: const BoxConstraints(minHeight: 190),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cs.surface.withOpacity(0.78),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                                ),
                                child: _controller.text.trim().isEmpty
                                    ? Text('المعاينة بتظهر هنا بعد الكتابة', style: TextStyle(color: cs.onSurface.withOpacity(0.45), fontWeight: FontWeight.w700))
                                    : _RichCommunityText(text: _controller.text),
                              )
                            : TextField(
                                key: const ValueKey('editor'),
                                controller: _controller,
                                minLines: 8,
                                maxLines: 14,
                                maxLength: 1800,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: _category.composerHint,
                                  counterText: '',
                                ),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          _TextCounterPill(current: contentLength, max: 1800),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() => _showPreview = !_showPreview),
                            icon: Icon(_showPreview ? Icons.edit_rounded : Icons.visibility_rounded, size: 18),
                            label: Text(_showPreview ? 'رجوع للتحرير' : 'معاينة'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canPost ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.publish_rounded),
                  label: Text(_submitting ? 'جاري النشر...' : 'نشر في المجتمع'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerCategoryCard extends StatelessWidget {
  final CommunityCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _ComposerCategoryCard({required this.category, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = category.accent(cs);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 138,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: category.softGradient(cs))
              : null,
          color: selected ? null : cs.surfaceContainerHighest.withOpacity(0.32),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent.withOpacity(0.35) : cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(category.icon, color: accent, size: 22),
            const SizedBox(height: 9),
            Text(category.labelAr, style: TextStyle(fontWeight: FontWeight.w900, color: selected ? accent : null)),
            const SizedBox(height: 4),
            Text(category.headline, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.54))),
          ],
        ),
      ),
    );
  }
}

class _TextCounterPill extends StatelessWidget {
  final int current;
  final int max;
  const _TextCounterPill({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final close = current > max * 0.86;
    final color = close ? cs.error : cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Text(
        '$current / $max',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: color),
      ),
    );
  }
}


class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _FormatButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: cs.primary),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}


class _RichCommunityText extends StatelessWidget {
  final String text;
  const _RichCommunityText({required this.text});

  @override
  Widget build(BuildContext context) {
    final lines = text.trimRight().split('\n');
    final visible = lines.isEmpty ? const <String>[] : lines;
    if (visible.where((l) => l.trim().isNotEmpty).isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < visible.length; i++)
          _FormattedCommunityLine(line: visible[i], isLast: i == visible.length - 1),
      ],
    );
  }
}

class _FormattedCommunityLine extends StatelessWidget {
  final String line;
  final bool isLast;
  const _FormattedCommunityLine({required this.line, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final raw = line;
    final trimmed = raw.trim();
    final base = theme.textTheme.bodyLarge?.copyWith(height: 1.55, fontWeight: FontWeight.w600) ?? const TextStyle(fontSize: 16, height: 1.55);

    if (trimmed.isEmpty) return SizedBox(height: isLast ? 0 : 8);
    if (trimmed == '---' || trimmed == '——') {
      return Padding(
        padding: EdgeInsets.only(top: 7, bottom: isLast ? 0 : 9),
        child: Divider(color: cs.outlineVariant.withOpacity(0.70), height: 1),
      );
    }

    final heading = _stripHeading(trimmed);
    if (heading != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 8, top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 24,
              margin: const EdgeInsetsDirectional.only(end: 8, top: 3),
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(999)),
            ),
            Expanded(
              child: RichText(
                textDirection: TextDirection.rtl,
                text: TextSpan(
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.35) ?? base.copyWith(fontWeight: FontWeight.w900),
                  children: _inlineSpans(heading, base.copyWith(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (trimmed.startsWith('>')) {
      final quote = trimmed.replaceFirst(RegExp(r'^>\s*'), '');
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: BorderDirectional(start: BorderSide(color: cs.primary.withOpacity(0.55), width: 3)),
          ),
          child: RichText(
            textDirection: TextDirection.rtl,
            text: TextSpan(style: base.copyWith(color: cs.onSurface.withOpacity(0.82)), children: _inlineSpans(quote, base)),
          ),
        ),
      );
    }

    final bullet = _stripBullet(trimmed);
    if (bullet != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsetsDirectional.only(end: 9, top: 10),
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
            ),
            Expanded(
              child: RichText(
                textDirection: TextDirection.rtl,
                text: TextSpan(style: base, children: _inlineSpans(bullet, base)),
              ),
            ),
          ],
        ),
      );
    }

    final numbered = _stripNumbered(trimmed);
    if (numbered != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsetsDirectional.only(end: 9, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
              child: Text(numbered.$1, style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary, fontSize: 11)),
            ),
            Expanded(
              child: RichText(
                textDirection: TextDirection.rtl,
                text: TextSpan(style: base, children: _inlineSpans(numbered.$2, base)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 7),
      child: RichText(
        textDirection: TextDirection.rtl,
        text: TextSpan(style: base, children: _inlineSpans(raw.trimRight(), base)),
      ),
    );
  }

  String? _stripHeading(String value) {
    final m = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(value);
    return m?.group(2)?.trim();
  }

  String? _stripBullet(String value) {
    final m = RegExp(r'^[-•]\s+(.+)$').firstMatch(value);
    return m?.group(1)?.trim();
  }

  (String, String)? _stripNumbered(String value) {
    final m = RegExp(r'^(\d+)[\.)]\s+(.+)$').firstMatch(value);
    if (m == null) return null;
    return ('${m.group(1)}', m.group(2)?.trim() ?? '');
  }

  List<TextSpan> _inlineSpans(String input, TextStyle base) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    int last = 0;
    for (final m in regex.allMatches(input)) {
      if (m.start > last) spans.add(TextSpan(text: input.substring(last, m.start)));
      final boldText = m.group(1) ?? '';
      spans.add(TextSpan(text: boldText, style: base.copyWith(fontWeight: FontWeight.w900)));
      last = m.end;
    }
    if (last < input.length) spans.add(TextSpan(text: input.substring(last)));
    return spans;
  }
}

class _CommunityAvatar extends StatelessWidget {
  final String name;
  final String photoUrl;
  final bool support;
  final double radius;

  const _CommunityAvatar({
    required this.name,
    required this.photoUrl,
    required this.support,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (support) {
      return SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    cs.primary.withOpacity(0.95),
                    cs.primaryContainer.withOpacity(0.85),
                  ],
                ),
                border: Border.all(color: cs.primary.withOpacity(0.22)),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.help_outline_rounded,
                color: cs.onPrimary,
                size: radius * 1.05,
              ),
            ),
            PositionedDirectional(
              end: -1,
              bottom: -1,
              child: Container(
                width: radius * 0.78,
                height: radius * 0.78,
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: cs.primary,
                  size: radius * 0.70,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasPhoto = photoUrl.trim().startsWith('http');
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary.withOpacity(0.10),
      backgroundImage: hasPhoto ? NetworkImage(photoUrl.trim()) : null,
      child: hasPhoto
          ? null
          : Text(
              _initial(name),
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
            ),
    );
  }

  String _initial(String value) {
    final s = value.trim();
    if (s.isEmpty) return 'و';
    return s.substring(0, 1);
  }
}

class _SmallBadge extends StatelessWidget {
  final String text;
  const _SmallBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.13)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w900, color: cs.primary),
      ),
    );
  }
}

class _EmptyCommunityState extends StatelessWidget {
  final String title;
  final String message;
  final String? details;

  const _EmptyCommunityState(
      {required this.title, required this.message, this.details});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.90),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, color: cs.primary, size: 42),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.45)),
              if ((details ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(details!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityBackground extends StatelessWidget {
  final ColorScheme colorScheme;
  const _CommunityBackground({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              cs.primary.withOpacity(0.16),
              cs.surface,
              cs.secondary.withOpacity(0.10),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeAr(DateTime dt) {
  final diff = DateTime.now().difference(dt);
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

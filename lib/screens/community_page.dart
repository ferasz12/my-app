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
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(0.16),
            cs.surface.withOpacity(0.90),
            cs.secondaryContainer.withOpacity(0.35),
          ],
        ),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.10),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.forum_rounded, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مجتمع وازن',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'اسأل، شارك معلومة، أو انشر وصفة مكتوبة بدون صور.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.66),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
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
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
        ],
      ),
    );
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
        color: cs.surface.withOpacity(0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<CommunitySort>(
                  value: sort,
                  decoration: InputDecoration(
                    labelText: 'الترتيب',
                    isDense: true,
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  items: CommunitySort.values
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s.labelAr)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onSortChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<CommunityCategory?>(
                  value: category,
                  decoration: InputDecoration(
                    labelText: 'التصنيف',
                    isDense: true,
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  items: [
                    const DropdownMenuItem<CommunityCategory?>(
                        value: null, child: Text('الكل')),
                    ...CommunityCategory.values.map(
                      (c) => DropdownMenuItem<CommunityCategory?>(
                          value: c, child: Text(c.labelAr)),
                    ),
                  ],
                  onChanged: onCategoryChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'أكتب محتوى يفيد مجتمع وازن ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.58),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.93),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: post.supportDisplay
                      ? null
                      : () => _openProfile(context, post.authorUid),
                  child: _CommunityAvatar(
                    name: post.authorName,
                    photoUrl: post.authorPhotoUrl,
                    support: post.supportDisplay,
                    radius: 21,
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
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (post.supportDisplay) ...[
                            const SizedBox(width: 7),
                            const _SmallBadge(text: 'الدعم'),
                          ],
                          if (_isMine) ...[
                            const SizedBox(width: 7),
                            const _SmallBadge(text: 'منشورك'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${post.category.labelAr} · ${_relativeAr(post.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.55),
                          fontWeight: FontWeight.w700,
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
                      PopupMenuItem(
                          value: 'delete', child: Text('حذف المنشور')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _RichCommunityText(text: post.content),
            if ((post.recipeTitle ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restaurant_menu_rounded,
                        size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        post.recipeTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _PostActions(post: post, currentUid: currentUid, service: service),
            if (post.commentsCount > 0) ...[
              const SizedBox(height: 10),
              _CommentsPreview(
                post: post,
                service: service,
                currentUid: currentUid,
              ),
            ],
            const SizedBox(height: 10),
            _InlineCommentBox(post: post, service: service),
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, String uid) {
    if (uid.trim().isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المنشور؟'),
        content: const Text('سيتم إخفاء المنشور من مجتمع وازن.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.deletePost(post);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حذف المنشور')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر حذف المنشور: $e')));
    }
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

  void _openThread(BuildContext context, CommunityComment replyTo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CommentsSheet(
        post: post,
        service: service,
        initialReplyTo: replyTo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityComment>>(
      stream: service.streamComments(post.id, limit: 3),
      builder: (context, snap) {
        final comments = snap.data ?? const <CommunityComment>[];
        if (comments.isEmpty) return const SizedBox.shrink();
        return Column(
          children: comments
              .map(
                (comment) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CommentTile(
                    comment: comment,
                    post: post,
                    service: service,
                    currentUid: currentUid,
                    compact: true,
                    onReply: currentUid == null
                        ? null
                        : (value) => _openThread(context, value),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _InlineCommentBox extends StatefulWidget {
  final CommunityPost post;
  final CommunityService service;
  final CommunityComment? replyTo;
  final VoidCallback? onCancelReply;
  final VoidCallback? onSent;
  final FocusNode? focusNode;

  const _InlineCommentBox({
    required this.post,
    required this.service,
    this.replyTo,
    this.onCancelReply,
    this.onSent,
    this.focusNode,
  });

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
      await widget.service.addComment(
        post: widget.post,
        text: text,
        replyTo: widget.replyTo,
      );
      _controller.clear();
      widget.onSent?.call();
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
    final replyTo = widget.replyTo;
    final mention = replyTo?.mentionLabel ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyTo != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withOpacity(0.16)),
            ),
            child: Row(
              children: [
                Icon(Icons.reply_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withOpacity(0.68),
                          ),
                      children: [
                        const TextSpan(text: 'الرد على '),
                        TextSpan(
                          text: mention.isNotEmpty
                              ? mention
                              : replyTo.authorName,
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إلغاء الرد',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onCancelReply,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
        Container(
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            end: 6,
            top: 4,
            bottom: 4,
          ),
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
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 700,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: replyTo == null
                        ? 'اكتب تعليقك...'
                        : 'اكتب ردك على ${mention.isNotEmpty ? mention : replyTo.authorName}...',
                    counterText: '',
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final CommunityPost post;
  final CommunityService service;
  final CommunityComment? initialReplyTo;

  const _CommentsSheet({
    required this.post,
    required this.service,
    this.initialReplyTo,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  CommunityComment? _replyTo;
  final FocusNode _commentFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _replyTo = widget.initialReplyTo;
    if (_replyTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _startReply(CommunityComment comment) {
    setState(() => _replyTo = comment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commentFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'التعليقات والردود',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<CommunityComment>>(
                  stream: widget.service.streamComments(widget.post.id, limit: 0),
                  builder: (context, snap) {
                    final comments = snap.data ?? const <CommunityComment>[];
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (comments.isEmpty) {
                      return const Center(child: Text('لا توجد تعليقات بعد'));
                    }
                    return ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => _CommentTile(
                        comment: comments[index],
                        post: widget.post,
                        service: widget.service,
                        currentUid: FirebaseAuth.instance.currentUser?.uid,
                        onReply: _startReply,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _InlineCommentBox(
                  post: widget.post,
                  service: widget.service,
                  replyTo: _replyTo,
                  focusNode: _commentFocusNode,
                  onCancelReply: () => setState(() => _replyTo = null),
                  onSent: () => setState(() => _replyTo = null),
                ),
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
  final ValueChanged<CommunityComment>? onReply;

  const _CommentTile({
    required this.comment,
    required this.post,
    required this.service,
    required this.currentUid,
    this.compact = false,
    this.onReply,
  });

  bool get _isCreator => comment.authorUid == post.authorUid;
  bool get _canDelete => currentUid != null && currentUid == comment.authorUid;
  bool get _canPin => currentUid != null && currentUid == post.authorUid;

  Future<void> _openProfile(BuildContext context) async {
    if (comment.supportDisplay) return;
    final uid = await service.resolveCommentAuthorUid(comment);
    if (!context.mounted) return;
    if (uid == null || uid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر العثور على ملف هذا المستخدم القديم')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)),
    );
  }

  Future<void> _openReplyTargetProfile(BuildContext context) async {
    final uid = await service.resolveReplyTargetUid(comment);
    if (!context.mounted) return;
    if (uid == null || uid.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasMenu = _canDelete || (_canPin && !comment.isReply);
    final mention = comment.mentionLabel;

    return Padding(
      padding: EdgeInsetsDirectional.only(start: comment.isReply ? 30 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comment.isReply) ...[
            Container(
              width: 3,
              height: compact ? 58 : 74,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.23),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                10,
                compact ? 8 : 10,
                10,
                compact ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: comment.isPinned
                    ? cs.primary.withOpacity(0.075)
                    : comment.isReply
                        ? cs.surfaceContainerHighest.withOpacity(0.24)
                        : cs.surfaceContainerHighest.withOpacity(0.38),
                borderRadius: BorderRadius.circular(18),
                border: comment.isPinned
                    ? Border.all(color: cs.primary.withOpacity(0.20))
                    : comment.isReply
                        ? Border.all(color: cs.outlineVariant.withOpacity(0.32))
                        : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: comment.supportDisplay ? null : () => _openProfile(context),
                    child: _CommunityAvatar(
                      name: comment.authorName,
                      photoUrl: comment.authorPhotoUrl,
                      support: comment.supportDisplay,
                      radius: compact ? 15 : 17,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            InkWell(
                              onTap: comment.supportDisplay
                                  ? null
                                  : () => _openProfile(context),
                              child: Text(
                                comment.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              comment.hasKnownCreatedAt
                                  ? _relativeAr(comment.createdAt)
                                  : 'تعليق سابق',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.50),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (comment.supportDisplay)
                              const _SmallBadge(text: 'الدعم'),
                            if (_isCreator) const _SmallBadge(text: 'المنشئ'),
                            if (comment.isPinned)
                              const _SmallBadge(text: 'مثبت'),
                          ],
                        ),
                        if (comment.isReply) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 3,
                            children: [
                              Text(
                                'رد على',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.58),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _openReplyTargetProfile(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    mention.isNotEmpty
                                        ? mention
                                        : (comment.replyToName ?? 'مستخدم وازن'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          comment.text,
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.38),
                        ),
                        if (onReply != null && currentUid != null) ...[
                          const SizedBox(height: 5),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onReply!(comment),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              child: Text(
                                'رد',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasMenu)
                    PopupMenuButton<String>(
                      tooltip: 'خيارات التعليق',
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: compact ? 19 : 21,
                        color: cs.onSurface.withOpacity(0.62),
                      ),
                      onSelected: (value) => _handleAction(context, value),
                      itemBuilder: (_) => [
                        if (_canPin && !comment.isReply)
                          PopupMenuItem(
                            value: comment.isPinned ? 'unpin' : 'pin',
                            child: Text(
                              comment.isPinned
                                  ? 'إلغاء تثبيت التعليق'
                                  : 'تثبيت التعليق',
                            ),
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
            ),
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
            content: Text(
              value == 'pin'
                  ? 'تم تثبيت التعليق'
                  : 'تم إلغاء تثبيت التعليق',
            ),
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

enum _PostBlockType { paragraph, heading, bold, bullets }

extension _PostBlockTypeX on _PostBlockType {
  String get label {
    switch (this) {
      case _PostBlockType.paragraph:
        return 'نص عادي';
      case _PostBlockType.heading:
        return 'عنوان';
      case _PostBlockType.bold:
        return 'نص عريض';
      case _PostBlockType.bullets:
        return 'قائمة نقاط';
    }
  }

  IconData get icon {
    switch (this) {
      case _PostBlockType.paragraph:
        return Icons.notes_rounded;
      case _PostBlockType.heading:
        return Icons.title_rounded;
      case _PostBlockType.bold:
        return Icons.format_bold_rounded;
      case _PostBlockType.bullets:
        return Icons.format_list_bulleted_rounded;
    }
  }

  String get hint {
    switch (this) {
      case _PostBlockType.paragraph:
        return 'اكتب الفقرة هنا...';
      case _PostBlockType.heading:
        return 'اكتب العنوان هنا...';
      case _PostBlockType.bold:
        return 'اكتب النص الذي تريده عريضًا...';
      case _PostBlockType.bullets:
        return 'اكتب كل نقطة في سطر مستقل';
    }
  }
}

class _PostBlockDraft {
  final _PostBlockType type;
  final TextEditingController controller;
  final FocusNode focusNode;

  _PostBlockDraft(this.type, {String text = ''})
      : controller = TextEditingController(text: text),
        focusNode = FocusNode();

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _ComposePostSheetState extends State<_ComposePostSheet> {
  late CommunityCategory _category;
  final List<_PostBlockDraft> _blocks = <_PostBlockDraft>[];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    final initial = (widget.initialText ?? '').trim();
    _blocks.add(_PostBlockDraft(_PostBlockType.paragraph, text: initial));
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _addBlock(_PostBlockType type) {
    final block = _PostBlockDraft(type);
    setState(() => _blocks.add(block));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) block.focusNode.requestFocus();
    });
  }

  void _removeBlock(int index) {
    if (_blocks.length == 1) {
      _blocks.first.controller.clear();
      return;
    }
    final removed = _blocks.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  String _buildContent() {
    final parts = <String>[];
    for (final block in _blocks) {
      final value = block.controller.text.trim();
      if (value.isEmpty) continue;
      switch (block.type) {
        case _PostBlockType.paragraph:
          parts.add(value);
          break;
        case _PostBlockType.heading:
          parts.add('## $value');
          break;
        case _PostBlockType.bold:
          parts.add('**$value**');
          break;
        case _PostBlockType.bullets:
          final lines = value
              .split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .map((line) => line.replaceFirst(RegExp(r'^[\-•]+\s*'), ''))
              .where((line) => line.isNotEmpty)
              .take(20)
              .map((line) => '- $line')
              .toList(growable: false);
          if (lines.isNotEmpty) parts.add(lines.join('\n'));
          break;
      }
    }
    return parts.join('\n\n').trim();
  }

  Future<void> _submit() async {
    final content = _buildContent();
    if (_submitting) return;
    if (content.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب محتوى البوست أولًا')),
      );
      return;
    }
    if (content.length > 1800) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('النص طويل جدًا. الحد الأقصى 1800 حرف.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_category, content);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر البوست في مجتمع وازن')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر النشر: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'بوست جديد',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'أضف نوع المحتوى ثم اكتب مباشرة؛ لن تظهر رموز التنسيق داخل النص.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CommunityCategory.values.map((category) {
                  return ChoiceChip(
                    selected: _category == category,
                    label: Text(category.labelAr),
                    onSelected: (_) => setState(() => _category = category),
                  );
                }).toList(growable: false),
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
                      Icon(
                        Icons.restaurant_menu_rounded,
                        color: cs.primary,
                        size: 19,
                      ),
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
              const SizedBox(height: 14),
              Text(
                'إضافة تنسيق',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FormatButton(
                    icon: Icons.notes_rounded,
                    label: 'نص',
                    onTap: () => _addBlock(_PostBlockType.paragraph),
                  ),
                  _FormatButton(
                    icon: Icons.format_bold_rounded,
                    label: 'عريض',
                    onTap: () => _addBlock(_PostBlockType.bold),
                  ),
                  _FormatButton(
                    icon: Icons.title_rounded,
                    label: 'عنوان',
                    onTap: () => _addBlock(_PostBlockType.heading),
                  ),
                  _FormatButton(
                    icon: Icons.format_list_bulleted_rounded,
                    label: 'نقاط',
                    onTap: () => _addBlock(_PostBlockType.bullets),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(_blocks.length, (index) {
                final block = _blocks[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PostBlockEditor(
                    block: block,
                    onRemove: () => _removeBlock(index),
                  ),
                );
              }),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: const Text('نشر في المجتمع'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
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

class _PostBlockEditor extends StatelessWidget {
  final _PostBlockDraft block;
  final VoidCallback onRemove;

  const _PostBlockEditor({
    required this.block,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHeading = block.type == _PostBlockType.heading;
    final isBold = block.type == _PostBlockType.bold;
    final isBullets = block.type == _PostBlockType.bullets;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 5, 0),
            child: Row(
              children: [
                Icon(block.type.icon, size: 18, color: cs.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    block.type.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف هذا الجزء',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBullets) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Icon(Icons.circle, size: 7, color: cs.primary),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextField(
                    controller: block.controller,
                    focusNode: block.focusNode,
                    minLines: isBullets ? 3 : (isHeading ? 1 : 2),
                    maxLines: isBullets ? 8 : (isHeading ? 2 : 7),
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      fontSize: isHeading ? 19 : 15,
                      height: 1.45,
                      fontWeight: isHeading || isBold
                          ? FontWeight.w900
                          : FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: block.type.hint,
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

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FormatButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: cs.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodyLarge?.copyWith(
          height: 1.55,
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(fontSize: 16, height: 1.55);
    final lines = text.replaceAll('\r\n', '\n').split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: lines.map((rawLine) {
        final line = rawLine.trimRight();
        final trimmed = line.trim();
        if (trimmed.isEmpty) return const SizedBox(height: 8);

        if (trimmed.startsWith('## ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: RichText(
              textDirection: TextDirection.rtl,
              text: TextSpan(
                style: theme.textTheme.titleLarge?.copyWith(
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
                children: _boldSpans(trimmed.substring(3), base),
              ),
            ),
          );
        }

        if (trimmed.startsWith('- ') || trimmed.startsWith('• ')) {
          final value = trimmed.substring(2).trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Icon(Icons.circle, size: 7, color: cs.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    textDirection: TextDirection.rtl,
                    text: TextSpan(
                      style: base.copyWith(color: cs.onSurface),
                      children: _boldSpans(value, base),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: RichText(
            textDirection: TextDirection.rtl,
            text: TextSpan(
              style: base.copyWith(color: cs.onSurface),
              children: _boldSpans(line, base),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  List<TextSpan> _boldSpans(String input, TextStyle base) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    var last = 0;
    for (final match in regex.allMatches(input)) {
      if (match.start > last) {
        spans.add(TextSpan(text: input.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1) ?? '',
          style: base.copyWith(fontWeight: FontWeight.w900),
        ),
      );
      last = match.end;
    }
    if (last < input.length) {
      spans.add(TextSpan(text: input.substring(last)));
    }
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

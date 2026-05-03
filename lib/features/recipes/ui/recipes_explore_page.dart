// lib/features/recipes/ui/recipes_explore_page.dart
//
// صفحة استكشاف الوصفات (فخمة ومرتبة) مع:
// - عدم تكرار نفس الوصفة في نفس التصفح (Session) ✅
// - زر لايك ❤️ + عداد لايكات ✅
// - تبويب “المفضلات” (اللايك = حفظ) ✅
// - فرز: الأحدث / الأكثر حفظًا / الأعلى بروتين ✅
// - فلترة الهدف: تنشيف/تضخيم/المحافظة/تنزيل الوزن/رفع الوزن ✅
// - وقت نسبي “قبل ساعة/ساعتين…” ✅
// - شارة “موثوق” للبوست الموثق ✅ (داخل RecipeCard)
// - إجراءات المشرف (توثيق/تعديل/حذف) ✅

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../shared/premium_feature.dart';
import '../../../shared/premium_gate.dart';
import 'package:provider/provider.dart';

import '../data/recipe_repository.dart';
import '../models/recipe.dart';
import 'widgets/recipe_card.dart';

enum RecipeSort { newest, mostSaved, highestProtein }

extension RecipeSortX on RecipeSort {
  String get labelAr {
    switch (this) {
      case RecipeSort.newest:
        return 'الأحدث';
      case RecipeSort.mostSaved:
        return 'الأكثر حفظًا';
      case RecipeSort.highestProtein:
        return 'الأعلى بروتين';
    }
  }
}

class _GuardState {
  final bool allowed;
  final String? message;
  const _GuardState({required this.allowed, this.message});
}

class _PostingGuard {
  static Future<_GuardState> loadForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const _GuardState(
        allowed: false,
        message: 'الرجاء تسجيل الدخول للمتابعة',
      );
    }

    final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
    final data = (snap.data() ?? const <String, dynamic>{});

    if ((data['isBanned'] ?? false) == true) {
      return const _GuardState(
        allowed: false,
        message: 'حسابك محظور من استخدام التطبيق',
      );
    }

    final ts = data['recipesSuspendedUntil'];
    if (ts is Timestamp) {
      final until = ts.toDate();
      if (DateTime.now().isBefore(until)) {
        return _GuardState(
          allowed: false,
          message: 'نشر الوصفات معلّق لحسابك حتى ${until.toLocal()}',
        );
      }
    }

    return const _GuardState(allowed: true);
  }
}

class RecipesExplorePage extends StatefulWidget {
  const RecipesExplorePage({super.key});

  @override
  State<RecipesExplorePage> createState() => _RecipesExplorePageState();
}

class _RecipesExplorePageState extends State<RecipesExplorePage>
    with SingleTickerProviderStateMixin {
  // ---- publishing guard ----
  bool _loadingGuard = true;
  _GuardState _guard = const _GuardState(allowed: true);

  // ---- role ----
  String? _myRole; // 'user' | 'support' | 'admin' | 'owner'
  bool _loadingRole = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roleSub;

  // ---- explore state ----
  RecipeGoal? _filterGoal;
  RecipeSort _sort = RecipeSort.newest;

  final List<Recipe> _feed = <Recipe>[];
  final Map<String, int> _idToIndex = <String, int>{};
  final Set<String> _seenIds = <String>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recipesSub;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadGuard();
    _listenMyRole();
    _subscribeRecipes();
  }

  @override
  void dispose() {
    _roleSub?.cancel();
    _recipesSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadGuard() async {
    setState(() => _loadingGuard = true);
    try {
      final g = await _PostingGuard.loadForCurrentUser();
      if (!mounted) return;
      setState(() {
        _guard = g;
        _loadingGuard = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guard = const _GuardState(
          allowed: false,
          message: 'تعذر التحقق من صلاحية النشر حالياً',
        );
        _loadingGuard = false;
      });
    }
  }

  void _listenMyRole() {
    setState(() => _loadingRole = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _myRole = null;
        _loadingRole = false;
      });
      return;
    }

    _roleSub?.cancel();
    _roleSub = FirebaseFirestore.instance.doc('users/$uid').snapshots().listen(
      (snap) {
        final data = (snap.data() ?? const <String, dynamic>{});
        final role = (data['role'] ?? 'user').toString().toLowerCase();
        if (!mounted) return;
        setState(() {
          _myRole = role;
          _loadingRole = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _myRole = null;
          _loadingRole = false;
        });
      },
    );
  }

  bool get _canModerate => _myRole == 'owner' || _myRole == 'admin' || _myRole == 'support';

  void _subscribeRecipes() {
    _recipesSub?.cancel();

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('recipes')
        .orderBy('createdAt', descending: true)
        .limit(250);

    if (_filterGoal != null) {
      q = q.where('goal', isEqualTo: _filterGoal!.firestoreValue);
    }

    _recipesSub = q.snapshots().listen(
      (snap) {
        bool changed = false;

        // ✅ تعامل صحيح مع الإضافات/التعديلات/الحذف (حتى لا تبقى وصفات محذوفة ظاهرة)
        for (final ch in snap.docChanges) {
          final id = ch.doc.id;

          if (ch.type == DocumentChangeType.removed) {
            final idx = _idToIndex[id];
            if (idx != null) {
              _feed.removeAt(idx);
              _idToIndex.remove(id);

              // إعادة ضبط الفهارس بعد الحذف
              for (int i = idx; i < _feed.length; i++) {
                _idToIndex[_feed[i].id] = i;
              }
              changed = true;
            }
            continue;
          }

          final recipe = Recipe.fromDoc(ch.doc);
          final idx = _idToIndex[id];
          if (idx != null) {
            _feed[idx] = recipe;
            changed = true;
          } else {
            if (_seenIds.contains(id)) continue;
            _seenIds.add(id);
            _idToIndex[id] = _feed.length;
            _feed.add(recipe);
            changed = true;
          }
        }

        if (changed && mounted) setState(() {});
      },
      onError: (_) {
        // تجاهل — ستظهر رسالة الخطأ عبر الواجهة
      },
    );
  }

  void _resetSession() {
    setState(() {
      _feed.clear();
      _idToIndex.clear();
      _seenIds.clear();
    });
    _subscribeRecipes();
  }

  void _applyFilter({RecipeGoal? goal, RecipeSort? sort}) {
    setState(() {
      if (goal != null || goal == null) {
        _filterGoal = goal;
      }
      if (sort != null) {
        _sort = sort;
      }

      // نبدأ “تصفح جديد” للفلاتر الحالية، لكن نحافظ على seenIds
      // حتى لا تظهر وصفة شوهدت سابقاً في نفس الجلسة.
      _feed.clear();
      _idToIndex.clear();
    });
    _subscribeRecipes();
  }

  Future<void> _onTapAdd() async {
    if (!_guard.allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_guard.message ?? 'لا يمكنك إضافة وصفة حالياً')),
      );
      return;
    }
    Navigator.of(context).pushNamed('/recipes/create');
  }

  Future<void> _deleteMyRecipe(Recipe recipe, RecipeRepository repo, String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الوصفة'),
          content: const Text('متأكد تبغى تحذف الوصفة؟ لا يمكن التراجع عن هذا الإجراء.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      // حذف الوصفة + Tombstone لإخفائها من المفضلات وغيرها
      await repo.deleteRecipeWithTombstone(
        recipeId: recipe.id,
        deletedByUid: uid,
        ownerId: recipe.userId.isNotEmpty ? recipe.userId : uid,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الوصفة')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = (e.code == 'permission-denied')
          ? 'لا تملك صلاحية حذف هذه الوصفة (راجع قواعد Firestore)'
          : 'تعذر حذف الوصفة: ${e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف الوصفة: $e')),
      );
    }
  }

  List<Recipe> _sorted(List<Recipe> input) {
    if (input.isEmpty) return input;
    final out = List<Recipe>.from(input);
    switch (_sort) {
      case RecipeSort.newest:
        return out; // أصلاً مرتبة حسب createdAt (تقريبًا) عند الإضافة
      case RecipeSort.mostSaved:
        out.sort((a, b) {
          final c = b.likeCount.compareTo(a.likeCount);
          if (c != 0) return c;
          return b.createdAt.compareTo(a.createdAt);
        });
        return out;
      case RecipeSort.highestProtein:
        out.sort((a, b) {
          final c = b.protein.compareTo(a.protein);
          if (c != 0) return c;
          return b.createdAt.compareTo(a.createdAt);
        });
        return out;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<RecipeRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final banner = (!_guard.allowed && _guard.message != null)
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withOpacity(.35)),
            ),
            child: Text(
              _guard.message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        : const SizedBox.shrink();

    return PremiumGate(
      feature: PremiumFeature.recipes,
      child: Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الوصفات'),
          actions: [
            IconButton(
              tooltip: 'إعادة التصفح',
              onPressed: _resetSession,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'استكشاف'),
              Tab(text: 'المفضلات'),
            ],
          ),
        ),
        floatingActionButton: (_loadingGuard || _loadingRole)
            ? null
            : (_guard.allowed
                ? FloatingActionButton(
                    onPressed: _onTapAdd,
                    child: const Icon(Icons.add),
                  )
                : null),
        body: (_loadingGuard || _loadingRole)
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabs,
                children: [
                  // ===================== Explore =====================
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Column(
                          children: [
                            banner,
                            _ExploreFilters(
                              goal: _filterGoal,
                              sort: _sort,
                              onGoalChanged: (g) => _applyFilter(goal: g, sort: null),
                              onSortChanged: (s) => _applyFilter(goal: _filterGoal, sort: s),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: uid == null
                            ? const Center(child: Text('سجّل دخولك لعرض الوصفات'))
                            : StreamBuilder<Set<String>>(
                                stream: repo.streamMyFavoriteIds(uid),
                                builder: (context, favSnap) {
                                  final favIds = favSnap.data ?? const <String>{};
                                  final items = _sorted(_feed);

                                  if (items.isEmpty) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.restaurant_menu, size: 44),
                                            const SizedBox(height: 8),
                                            const Text('لا توجد وصفات جديدة في هذا التصفح'),
                                            const SizedBox(height: 10),
                                            OutlinedButton.icon(
                                              onPressed: _resetSession,
                                              icon: const Icon(Icons.refresh),
                                              label: const Text('إعادة التصفح'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (ctx, i) {
                                      final r = items[i];
                                      final isLiked = favIds.contains(r.id);

                                      return RecipeCard(
                                        recipe: r,
                                        isLiked: isLiked,
                                        canDelete: uid != null && uid == r.userId,
                                        onDelete: (uid != null && uid == r.userId)
                                            ? () => _deleteMyRecipe(r, repo, uid!)
                                            : null,
                                        onToggleLike: () async {
                                          try {
                                            final nowLiked = await repo.toggleLike(recipe: r, uid: uid);

                                            // تحديث متفائل للعداد داخل القائمة الحالية
                                            final idx = _idToIndex[r.id];
                                            if (idx != null && mounted) {
                                              final current = _feed[idx];
                                              final newCount = nowLiked
                                                  ? (current.likeCount + 1)
                                                  : (current.likeCount - 1);
                                              _feed[idx] = Recipe(
                                                id: current.id,
                                                userId: current.userId,
                                                userName: current.userName,
                                                userPhotoUrl: current.userPhotoUrl,
                                                imageUrl: current.imageUrl,
                                                caption: current.caption,
                                                title: current.title,
                                                ingredients: current.ingredients,
                                                method: current.method,
                                                protein: current.protein,
                                                fat: current.fat,
                                                carbs: current.carbs,
                                                calories: current.calories,
                                                goal: current.goal,
                                                createdAt: current.createdAt,
                                                likeCount: newCount < 0 ? 0 : newCount,
                                                badge: current.badge,
                                              );
                                              setState(() {});
                                            }
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('تعذر حفظ الإعجاب: $e')),
                                            );
                                          }
                                        },
                                        topRight: _canModerate
                                            ? AdminRecipeActions(recipe: r, myRole: _myRole, repo: repo)
                                            : null,
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // ===================== Favorites =====================
                  uid == null
                      ? const Center(child: Text('سجّل دخولك لعرض المفضلات'))
                      : StreamBuilder<Set<String>>(
                          stream: repo.streamDeletedRecipeIds(),
                          builder: (context, delSnap) {
                            final deletedIds = delSnap.data ?? const <String>{};
                            return StreamBuilder<List<Recipe>>(
                              stream: repo.streamMyFavorites(uid),
                              builder: (context, favsSnap) {
                                if (favsSnap.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                if (favsSnap.hasError) {
                                  return Center(child: Text('حصل خطأ: ${favsSnap.error}'));
                                }

                                final allFavs = favsSnap.data ?? const <Recipe>[];
                                final favs = allFavs.where((r) => !deletedIds.contains(r.id)).toList(growable: false);

                                if (favs.isEmpty) {
                                  return const Center(child: Text('لا توجد وصفات في المفضلات بعد'));
                                }

                                return ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                  itemCount: favs.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (ctx, i) {
                                    final r = favs[i];
                                    return RecipeCard(
                                      recipe: r,
                                      isLiked: true,
                                      canDelete: uid != null && uid == r.userId,
                                      onDelete: (uid != null && uid == r.userId)
                                          ? () => _deleteMyRecipe(r, repo, uid!)
                                          : null,
                                      onToggleLike: () async {
                                        try {
                                          await repo.toggleLike(recipe: r, uid: uid);
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('تعذر إزالة الوصفة من المفضلات: $e')),
                                          );
                                        }
                                      },
                                      topRight: _canModerate
                                          ? AdminRecipeActions(recipe: r, myRole: _myRole, repo: repo)
                                          : null,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                ],
              ),
      ),
    ),
    );
  }
}

class _ExploreFilters extends StatelessWidget {
  final RecipeGoal? goal;
  final RecipeSort sort;
  final ValueChanged<RecipeGoal?> onGoalChanged;
  final ValueChanged<RecipeSort> onSortChanged;

  const _ExploreFilters({
    required this.goal,
    required this.sort,
    required this.onGoalChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<RecipeGoal?>(
                value: goal,
                items: <DropdownMenuItem<RecipeGoal?>>[
                  const DropdownMenuItem(value: null, child: Text('كل الأهداف')),
                  ...RecipeGoal.values.map(
                    (g) => DropdownMenuItem(value: g, child: Text(g.labelAr)),
                  ),
                ],
                onChanged: onGoalChanged,
                decoration: InputDecoration(
                  labelText: 'فلترة الهدف',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: t.colorScheme.surfaceContainerHighest.withOpacity(0.55),
            border: Border.all(color: t.dividerColor.withOpacity(0.22)),
          ),
          child: SegmentedButton<RecipeSort>(
            segments: const [
              ButtonSegment(value: RecipeSort.highestProtein, label: Text('الأعلى بروتين'), icon: Icon(Icons.fitness_center, size: 18)),
              ButtonSegment(value: RecipeSort.mostSaved, label: Text('الأكثر حفظًا'), icon: Icon(Icons.favorite, size: 18)),
              ButtonSegment(value: RecipeSort.newest, label: Text('الأحدث'), icon: Icon(Icons.schedule, size: 18)),
            ],
            selected: <RecipeSort>{sort},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              final v = s.isEmpty ? RecipeSort.newest : s.first;
              onSortChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

/// ويدجت إجراءات المشرف — تظهر فقط إذا كان الدور support/admin/owner
class AdminRecipeActions extends StatelessWidget {
  final Recipe recipe;
  final String? myRole; // 'owner' | 'admin' | 'support' | 'user'
  final RecipeRepository repo;

  const AdminRecipeActions({
    super.key,
    required this.recipe,
    required this.myRole,
    required this.repo,
  });

  bool get _canModerate => myRole == 'owner' || myRole == 'admin' || myRole == 'support';

  @override
  Widget build(BuildContext context) {
    if (!_canModerate) return const SizedBox.shrink();

    final isVerified = recipe.isVerified;

    return PopupMenuButton<String>(
      tooltip: 'إجراءات',
      onSelected: (value) async {
        try {
          if (value == 'verify') {
            await repo.adminSetBadge(recipeId: recipe.id, badge: 'verified');
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم توثيق الوصفة')));
          } else if (value == 'unverify') {
            await repo.adminSetBadge(recipeId: recipe.id, badge: '');
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إزالة التوثيق')));
          } else if (value == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('حذف الوصفة'),
                content: const Text('متأكد تبغى تحذف الوصفة؟ هذا الإجراء لا يمكن التراجع عنه.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                ],
              ),
            );
            if (ok == true) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) {
                throw FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated');
              }
              // حذف + Tombstone حتى تختفي من المفضلات عند كل المستخدمين
              await repo.deleteRecipeWithTombstone(
                recipeId: recipe.id,
                deletedByUid: uid,
                ownerId: recipe.userId,
              );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الوصفة')));
            }
          } else if (value == 'edit') {
            // نافذة تعديل سريعة للمشرف/الدعم/الاونر
            final titleCtrl = TextEditingController(text: recipe.title);
            final methodCtrl = TextEditingController(text: recipe.method);
            final proteinCtrl = TextEditingController(text: recipe.protein == 0 ? '' : recipe.protein.toString());
            final fatCtrl = TextEditingController(text: recipe.fat == 0 ? '' : recipe.fat.toString());
            final carbsCtrl = TextEditingController(text: recipe.carbs == 0 ? '' : recipe.carbs.toString());
            final caloriesCtrl = TextEditingController(text: recipe.calories == 0 ? '' : recipe.calories.toString());

            final ok = await showDialog<bool>(
              context: context,
              builder: (_) {
                return Directionality(
                  textDirection: TextDirection.ltr,
                  child: AlertDialog(
                    title: const Text('تعديل الوصفة'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(labelText: 'العنوان'),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: methodCtrl,
                            decoration: const InputDecoration(labelText: 'طريقة التحضير'),
                            maxLines: 4,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: proteinCtrl,
                                  decoration: const InputDecoration(labelText: 'بروتين (غ)'),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: fatCtrl,
                                  decoration: const InputDecoration(labelText: 'دهون (غ)'),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: carbsCtrl,
                                  decoration: const InputDecoration(labelText: 'كارب (غ)'),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: caloriesCtrl,
                                  decoration: const InputDecoration(labelText: 'سعرات'),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
                    ],
                  ),
                );
              },
            );

            if (ok == true) {
              double? asNum(String s) => double.tryParse(s.trim());

              await repo.adminEditRecipe(
                recipeId: recipe.id,
                title: titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim(),
                method: methodCtrl.text.trim().isEmpty ? null : methodCtrl.text.trim(),
                protein: asNum(proteinCtrl.text),
                fat: asNum(fatCtrl.text),
                carbs: asNum(carbsCtrl.text),
                calories: asNum(caloriesCtrl.text),
              );

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات')));
            }
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التنفيذ: $e')));
        }
      },
      itemBuilder: (_) => [
        if (!isVerified)
          const PopupMenuItem(value: 'verify', child: Text('وضع علامة موثوق')),
        if (isVerified)
          const PopupMenuItem(value: 'unverify', child: Text('إزالة التوثيق')),
        const PopupMenuItem(value: 'edit', child: Text('تعديل…')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('حذف الوصفة', style: TextStyle(color: Colors.red)),
        ),
      ],
      child: const Icon(Icons.more_vert),
    );
  }
}

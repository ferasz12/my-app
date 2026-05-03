// lib/features/recipes/data/recipe_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../recipes/models/recipe.dart'; // عدّل المسار إذا كان مختلف عندك

class RecipeRepository {
  final FirebaseFirestore _db;
  RecipeRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('recipes');

  DocumentReference<Map<String, dynamic>> recipeRef(String recipeId) => _col.doc(recipeId);

  CollectionReference<Map<String, dynamic>> _userFavCol(String uid) =>
      _db.collection('users').doc(uid).collection('favoriteRecipes');

  DocumentReference<Map<String, dynamic>> _userFavRef(String uid, String recipeId) =>
      _userFavCol(uid).doc(recipeId);

  DocumentReference<Map<String, dynamic>> _recipeLikeRef(String recipeId, String uid) =>
      _col.doc(recipeId).collection('likes').doc(uid);

  CollectionReference<Map<String, dynamic>> get _deletedCol =>
      _db.collection('deletedRecipes');

  /// بثّ معرّفات الوصفات المحذوفة (Tombstones)
  ///
  /// الهدف: إخفاء الوصفات المحذوفة من أي صفحات تعتمد على Snapshot محفوظ (مثل المفضلات).
  Stream<Set<String>> streamDeletedRecipeIds() {
    return _deletedCol.snapshots().map(
          (s) => s.docs.map((d) => d.id).toSet(),
        );
  }

  /// حذف وصفة (مالكها) مع إنشاء Tombstone لإخفائها من كل مكان داخل التطبيق.
  ///
  /// - يحذف recipes/{recipeId}
  /// - يضيف deletedRecipes/{recipeId} (للاخفاء في المفضلات وغيرها)
  /// - ينظف إعجاب/مفضلة المستخدم الحالي إن وجدت
  ///
  /// ملاحظة: حذف subcollections لكل المستخدمين يتطلب Cloud Function.
  Future<void> deleteRecipeWithTombstone({
    required String recipeId,
    required String deletedByUid,
    String? ownerId,
  }) async {
    final rRef = recipeRef(recipeId);
    final batch = _db.batch();

    batch.set(
      _deletedCol.doc(recipeId),
      {
        'deletedAt': Timestamp.now(),
        'deletedBy': deletedByUid,
        if (ownerId != null && ownerId.trim().isNotEmpty) 'ownerId': ownerId.trim(),
      },
      SetOptions(merge: true),
    );

    batch.delete(rRef);

    // تنظيف أثر المستخدم الحالي (مفضلة/إعجاب) - لا يضر لو لم تكن موجودة
    batch.delete(_userFavRef(deletedByUid, recipeId));
    batch.delete(_recipeLikeRef(recipeId, deletedByUid));

    await batch.commit();
  }

  // ---------------- Guards: حظر/تعليق النشر (للمستخدم العادي) ----------------
  Future<void> _assertPostingAllowed(String uid) async {
    final userSnap = await _db.doc('users/$uid').get();
    if (!userSnap.exists) {
      throw Exception('User document not found');
    }
    final data = (userSnap.data() as Map<String, dynamic>? ?? {});

    final isBanned = (data['isBanned'] ?? false) == true;
    if (isBanned) {
      throw Exception('User is banned from the app');
    }

    final suspendedUntil = data['recipesSuspendedUntil'];
    if (suspendedUntil is Timestamp) {
      final until = suspendedUntil.toDate();
      if (DateTime.now().isBefore(until)) {
        throw Exception('Recipe posting is suspended until $until');
      }
    }
  }

  // ---------------- Reads ----------------
  Future<Recipe?> getRecipeById(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return Recipe.fromDoc(snap);
  }

  Stream<List<Recipe>> streamRecipes({RecipeGoal? goal}) {
    Query<Map<String, dynamic>> q =
        _col.orderBy('createdAt', descending: true);
    if (goal != null) {
      q = q.where('goal', isEqualTo: goal.firestoreValue);
    }
    return q.snapshots().map(
      (s) => s.docs.map((d) => Recipe.fromDoc(d)).toList(growable: false),
    );
  }

  /// بثّ معرّفات المفضلات/الإعجابات للمستخدم الحالي (لاستخدامها في الواجهة).
  Stream<Set<String>> streamMyFavoriteIds(String uid) {
    return _userFavCol(uid)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// بثّ الوصفات المفضلة للمستخدم.
  ///
  /// نُخزّن Snapshot مبسّط للوصفة داخل users/{uid}/favoriteRecipes/{recipeId}
  /// لكي لا نحتاج استعلامات whereIn متكررة.
  Stream<List<Recipe>> streamMyFavorites(String uid) {
    return _userFavCol(uid)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((s) {
      final out = <Recipe>[];
      for (final d in s.docs) {
        final data = d.data();
        // إذا لم تُحفظ Snapshot لسبب ما، نتخطى العنصر بدل ما نخرب الصفحة.
        if (data.isEmpty) continue;
        out.add(Recipe.fromMap(id: d.id, data: data));
      }
      return out;
    });
  }

  /// تبديل إعجاب/حفظ (❤️)
  ///
  /// - إذا لم يكن مُعجبًا: نضيف likes/{uid} + favoriteRecipes/{recipeId}
  /// - إذا كان مُعجبًا: نحذفهم
  ///
  /// نحاول تحديث likeCount داخل recipe بعملية Transaction.
  /// لو فشل تحديث likeCount بسبب القواعد، الإعجاب نفسه يظل شغال.
  Future<bool> toggleLike({
    required Recipe recipe,
    required String uid,
  }) async {
    final recipeId = recipe.id;
    final likeRef = _recipeLikeRef(recipeId, uid);
    final favRef = _userFavRef(uid, recipeId);
    final rRef = recipeRef(recipeId);

    bool nowLiked = false;

    // 1) أولاً: نفذ Transaction قدر الإمكان (likeCount + likes)
    try {
      await _db.runTransaction((tx) async {
        final likeSnap = await tx.get(likeRef);
        if (likeSnap.exists) {
          // unlike
          tx.delete(likeRef);
          tx.delete(favRef);
          tx.update(rRef, {
            'likeCount': FieldValue.increment(-1),
            'updatedAt': Timestamp.now(),
          });
          nowLiked = false;
        } else {
          // like
          tx.set(likeRef, {
            'createdAt': Timestamp.now(),
          });

          // خزّن Snapshot مبسط للوصفة داخل المفضلات
          final favData = <String, dynamic>{
            ...recipe.toMap(),
            // وقت الإضافة للمفضلة (للترتيب)
            'addedAt': Timestamp.now(),
          };
          tx.set(favRef, favData);

          tx.update(rRef, {
            'likeCount': FieldValue.increment(1),
            'updatedAt': Timestamp.now(),
          });
          nowLiked = true;
        }
      });
      return nowLiked;
    } catch (_) {
      // 2) Fallback: إذا فشل الترانزاكشن، خلّ الإعجاب يشتغل بدون likeCount.
    }

    // fallback: اقرأ حالة like الحالية ثم نفذ set/delete بسيط
    final likeSnap = await likeRef.get();
    if (likeSnap.exists) {
      await likeRef.delete();
      await favRef.delete();
      // محاولة تحديث العداد (اختياري)
      try {
        await rRef.update({'likeCount': FieldValue.increment(-1), 'updatedAt': Timestamp.now()});
      } catch (_) {}
      return false;
    } else {
      await likeRef.set({'createdAt': Timestamp.now()});
      await favRef.set({
        ...recipe.toMap(),
        'addedAt': Timestamp.now(),
      });
      try {
        await rRef.update({'likeCount': FieldValue.increment(1), 'updatedAt': Timestamp.now()});
      } catch (_) {}
      return true;
    }
  }

  Stream<List<Recipe>> streamUserRecipes(String userId) {
    final q = _col
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true);
    return q.snapshots().map(
      (s) => s.docs.map((d) => Recipe.fromDoc(d)).toList(growable: false),
    );
  }

  // ---------------- Writes (مستخدم عادي) ----------------
  Future<String> addRecipe(Recipe recipe) async {
    await _assertPostingAllowed(recipe.userId);

    final data = <String, dynamic>{
      ...recipe.toMap(), // يحتوي createdAt من الموديل
      // تأكيد وجود userId (احتياط)
      'userId': recipe.userId,
    };

    final doc = await _col.add(data);
    return doc.id;
  }

  Future<void> updateRecipe(Recipe recipe) async {
    if (recipe.id.isEmpty) {
      throw Exception('Recipe ID is required for update');
    }

    await _assertPostingAllowed(recipe.userId);

    final ref = _col.doc(recipe.id);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('Recipe not found');
    }

    final current = snap.data()!;
    final ownerId = current['userId'] as String?;
    if (ownerId == null || ownerId != recipe.userId) {
      throw Exception('Not authorized to update this recipe');
    }

    // القواعد تمنع تعديل createdAt في update
    final updateData = <String, dynamic>{
      ...recipe.toMap(),
    }..remove('createdAt');

    updateData['updatedAt'] = Timestamp.now();

    await ref.update(updateData);
  }

  Future<void> deleteRecipe({
    required String recipeId,
    required String currentUserId,
  }) async {
    final ref = _col.doc(recipeId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('Recipe not found');
    }

    final data = snap.data()!;
    final ownerId = data['userId'] as String?;
    if (ownerId == null || ownerId != currentUserId) {
      throw Exception('Not authorized to delete this recipe');
    }

    await ref.delete();
  }

  // ---------------- Admin/Support/Owner Operations (إشراف) ----------------

  /// وضع/إزالة علامة التوثيق على وصفة (badge = 'verified' أو حذف الحقل)
  Future<void> adminSetBadge({
    required String recipeId,
    required String badge, // مثال: 'verified' أو '' لإزالة
  }) async {
    final ref = _col.doc(recipeId);
    await ref.update({
      if (badge.isEmpty)
        'badge': FieldValue.delete()
      else
        'badge': badge,
      'updatedAt': Timestamp.now(),
    });
  }

  /// تعديل وصفة كمشرف — يطابق الحقول المسموح بها في القواعد
  Future<void> adminEditRecipe({
    required String recipeId,
    String? title,
    List<String>? ingredients,
    String? method,
    double? protein,
    double? fat,
    double? carbs,
    double? calories,
    String? goal, // أرسل goal.name إذا كان enum
  }) async {
    final ref = _col.doc(recipeId);
    final update = <String, dynamic>{};

    if (title != null) update['title'] = title;
    if (ingredients != null) update['ingredients'] = ingredients;
    if (method != null) update['method'] = method;
    if (protein != null) update['protein'] = protein;
    if (fat != null) update['fat'] = fat;
    if (carbs != null) update['carbs'] = carbs;
    if (calories != null) update['calories'] = calories;
    if (goal != null) update['goal'] = goal;

    if (update.isEmpty) return;

    update['updatedAt'] = Timestamp.now();
    await ref.update(update);
  }

  /// حذف أي وصفة كمشرف
  Future<void> adminDeleteRecipe(String recipeId) async {
    await _col.doc(recipeId).delete();
  }
}

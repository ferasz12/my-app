import 'package:cloud_firestore/cloud_firestore.dart';

/// أسماء المجموعات في مكان واحد لتوحيد الاستخدام
class Col {
  static const String users = 'users';
  static const String posts = 'posts';

  // Subcollections تحت users/{uid}
  static const String weights = 'weights';
  static const String intakes = 'intakes';
  static const String water   = 'water';
  static const String goals   = 'goals';

  // Subcollections تحت posts/{postId}
  static const String comments = 'comments';
  static const String likes    = 'likes';
}

/// تهيئة Firestore + تمكين الكاش دون حد (مفيد للتطبيقات الصحية التي تعمل أوفلاين)
class DB {
  DB._();

  static final FirebaseFirestore fs = FirebaseFirestore.instance
    ..settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

  /// === مرجع المستخدم ووثائقه الفرعية ===
  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      fs.collection(Col.users).doc(uid);

  static CollectionReference<Map<String, dynamic>> userWeights(String uid) =>
      userDoc(uid).collection(Col.weights);

  static CollectionReference<Map<String, dynamic>> userIntakes(String uid) =>
      userDoc(uid).collection(Col.intakes);

  static CollectionReference<Map<String, dynamic>> userWater(String uid) =>
      userDoc(uid).collection(Col.water);

  static CollectionReference<Map<String, dynamic>> userGoals(String uid) =>
      userDoc(uid).collection(Col.goals);

  /// === المنشورات + التفاعلات ===
  static CollectionReference<Map<String, dynamic>> posts() =>
      fs.collection(Col.posts);

  static DocumentReference<Map<String, dynamic>> postDoc(String postId) =>
      posts().doc(postId);

  static CollectionReference<Map<String, dynamic>> postComments(String postId) =>
      postDoc(postId).collection(Col.comments);

  static CollectionReference<Map<String, dynamic>> postLikes(String postId) =>
      postDoc(postId).collection(Col.likes);

  /// === مُساعدات وقت الخادم ===
  static FieldValue tsNow() => Timestamp.now();

  /// === عمليات كتابة آمنة ===
  ///
  /// create: يضيف createdAt + updatedAt تلقائيًا (يفشل لو الوثيقة موجودة).
  static Future<void> create(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) {
    final now = tsNow();
    return ref.set({
      ...data,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  /// setMerge: يدمج البيانات ويحدّث updatedAt.
  static Future<void> setMerge(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) {
    return ref.set(
      {
        ...data,
        'updatedAt': tsNow(),
      },
      SetOptions(merge: true),
    );
  }

  /// updateSafe: يُحدِّث فقط الحقول الممرّرة + updatedAt (يتجاهل إن لم تكن موجودة).
  static Future<void> updateSafe(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) {
    return ref.update({
      ...data,
      'updatedAt': tsNow(),
    });
  }

  /// upsert: ينشئ إن لم تكن الوثيقة موجودة، وإلا يدمج (مع updatedAt دائمًا).
  static Future<void> upsert(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final snap = await ref.get();
    if (snap.exists) {
      await setMerge(ref, data);
    } else {
      await create(ref, data);
    }
  }
}

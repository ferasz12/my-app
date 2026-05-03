// lib/features/recipes/models/recipe.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// أهداف الوصفة (تُخزن كسلاسل في Firestore).
///
/// ملاحظة: حافظنا على القيم القديمة (cutting/bulking/maintenance)
/// وأضفنا أهداف الوزن (weight_loss/weight_gain) كما طلبت.
enum RecipeGoal {
  cutting,      // تنشيف
  bulking,      // تضخيم
  maintenance,  // المحافظة
  weightLoss,   // تنزيل الوزن
  weightGain,   // رفع الوزن
}

extension RecipeGoalX on RecipeGoal {
  String get labelAr {
    switch (this) {
      case RecipeGoal.cutting:
        return 'تنشيف';
      case RecipeGoal.bulking:
        return 'تضخيم';
      case RecipeGoal.maintenance:
        return 'المحافظة';
      case RecipeGoal.weightLoss:
        return 'تنزيل الوزن';
      case RecipeGoal.weightGain:
        return 'رفع الوزن';
    }
  }

  /// القيمة المخزنة في Firestore.
  String get firestoreValue {
    switch (this) {
      case RecipeGoal.weightLoss:
        return 'weight_loss';
      case RecipeGoal.weightGain:
        return 'weight_gain';
      default:
        return name; // cutting/bulking/maintenance
    }
  }

  static RecipeGoal fromFirestore(dynamic v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'cutting':
      case 'تنشيف':
        return RecipeGoal.cutting;
      case 'bulking':
      case 'تضخيم':
        return RecipeGoal.bulking;
      case 'maintenance':
      case 'maintain':
      case 'المحافظة':
      case 'حفاظ':
        return RecipeGoal.maintenance;
      case 'weight_loss':
      case 'weightloss':
      case 'loss':
      case 'تنزيل الوزن':
        return RecipeGoal.weightLoss;
      case 'weight_gain':
      case 'weightgain':
      case 'gain':
      case 'رفع الوزن':
        return RecipeGoal.weightGain;
      default:
        return RecipeGoal.maintenance;
    }
  }
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0.0;
  return 0.0;
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

DateTime _asDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
  }
  if (v is num) {
    // لو مخزّن كـ millisSinceEpoch
    return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  }
  return DateTime.now();
}

List<String> _asStringList(dynamic v) {
  if (v is List) {
    return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
  return const <String>[];
}

class Recipe {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;

  /// صورة للوجبة/الوصفة (اختياري)
  final String? imageUrl;

  /// وصف مختصر للبوست (اختياري)
  final String? caption;

  final String title;
  final List<String> ingredients;
  final String method;

  final double protein;
  final double fat;
  final double carbs;
  final double calories;

  final RecipeGoal goal;
  final DateTime createdAt;

  /// عدد الإعجابات (للترتيب ولعرضها للناس).
  final int likeCount;

  /// حقل اختياري لتوافق التوثيق (badge = 'verified')
  final String? badge;
  bool get isVerified => (badge == 'verified');

  Recipe({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    this.imageUrl,
    this.caption,
    required this.title,
    required this.ingredients,
    required this.method,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.calories,
    required this.goal,
    required this.createdAt,
    this.likeCount = 0,
    this.badge,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (caption != null) 'caption': caption,
        'title': title,
        'ingredients': ingredients,
        'method': method,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        'calories': calories,
        'goal': goal.firestoreValue,
        'createdAt': Timestamp.fromDate(createdAt),
        'likeCount': likeCount,
        if (badge != null) 'badge': badge,
      };

  factory Recipe.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};

    final goalEnum = RecipeGoalX.fromFirestore(data['goal']);

    // بعض النسخ القديمة قد تستخدم 'instructions' بدل 'method'
    final methodText = (data['method'] ?? data['instructions'] ?? '').toString();

    // ✅ توافق مع نسخ قديمة: قد تُحفظ المعرّفات بأسماء مختلفة
    // مثل uid/ownerId/authorId أو داخل كائن user.
    String _pickUserId(Map<String, dynamic> d) {
      final v = d['userId'] ?? d['uid'] ?? d['ownerId'] ?? d['authorId'] ?? d['createdBy'] ?? d['user_id'];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      final u = d['user'];
      if (u is Map) {
        final m = Map<String, dynamic>.from(u as Map);
        final vv = m['uid'] ?? m['id'] ?? m['userId'];
        if (vv != null && vv.toString().trim().isNotEmpty) return vv.toString().trim();
      }
      return '';
    }

    String _pickUserName(Map<String, dynamic> d) {
      final v = d['userName'] ?? d['displayName'] ?? d['name'] ?? d['username'];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      final u = d['user'];
      if (u is Map) {
        final m = Map<String, dynamic>.from(u as Map);
        final vv = m['displayName'] ?? m['name'] ?? m['userName'];
        if (vv != null && vv.toString().trim().isNotEmpty) return vv.toString().trim();
      }
      return '';
    }

    String? _pickUserPhoto(Map<String, dynamic> d) {
      final v = d['userPhotoUrl'] ?? d['photoUrl'] ?? d['avatarUrl'] ?? d['photoURL'];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      final u = d['user'];
      if (u is Map) {
        final m = Map<String, dynamic>.from(u as Map);
        final vv = m['photoUrl'] ?? m['userPhotoUrl'] ?? m['avatarUrl'];
        if (vv != null && vv.toString().trim().isNotEmpty) return vv.toString().trim();
      }
      return null;
    }

    return Recipe(
      id: doc.id,
      userId: _pickUserId(data),
      userName: _pickUserName(data),
      userPhotoUrl: _pickUserPhoto(data),
      imageUrl: (data['imageUrl'] ?? data['photoUrl'] ?? data['image'] ?? data['imageURL'] ?? '').toString().trim().isEmpty
          ? null
          : (data['imageUrl'] ?? data['photoUrl'] ?? data['image'] ?? data['imageURL']).toString().trim(),
      caption: (data['caption'] ?? data['description'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      ingredients: _asStringList(data['ingredients']),
      method: methodText,
      protein: _asDouble(data['protein']),
      fat: _asDouble(data['fat']),
      carbs: _asDouble(data['carbs']),
      calories: _asDouble(data['calories']),
      goal: goalEnum,
      createdAt: _asDateTime(data['createdAt']),
      likeCount: _asInt(data['likeCount']),
      badge: (data['badge'] == null) ? null : data['badge'].toString(),
    );
  }

  /// قراءة من Map (مثلاً من users/{uid}/favoriteRecipes)
  factory Recipe.fromMap({required String id, required Map<String, dynamic> data}) {
    return Recipe(
      id: id,
      userId: (data['userId'] ?? data['uid'] ?? data['ownerId'] ?? data['authorId'] ?? '').toString(),
      userName: (data['userName'] ?? data['displayName'] ?? data['name'] ?? '').toString(),
      userPhotoUrl: (data['userPhotoUrl'] ?? data['photoUrl'] ?? data['avatarUrl']) == null
          ? null
          : (data['userPhotoUrl'] ?? data['photoUrl'] ?? data['avatarUrl']).toString(),
      imageUrl: (data['imageUrl'] ?? data['photoUrl'] ?? data['image'] ?? data['imageURL']) == null
          ? null
          : (data['imageUrl'] ?? data['photoUrl'] ?? data['image'] ?? data['imageURL']).toString(),
      caption: (data['caption'] ?? data['description'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      ingredients: _asStringList(data['ingredients']),
      method: (data['method'] ?? data['instructions'] ?? '').toString(),
      protein: _asDouble(data['protein']),
      fat: _asDouble(data['fat']),
      carbs: _asDouble(data['carbs']),
      calories: _asDouble(data['calories']),
      goal: RecipeGoalX.fromFirestore(data['goal']),
      createdAt: _asDateTime(data['createdAt']),
      likeCount: _asInt(data['likeCount']),
      badge: (data['badge'] == null) ? null : data['badge'].toString(),
    );
  }
}

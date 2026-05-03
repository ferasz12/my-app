// lib/models/meal.dart
//
// نموذج وجبة موحّد.
// - يُستخدم للبيانات الثابتة (assets) وكذلك البيانات القادمة من Firestore.
// - الحقول الإضافية (imageUrl/description) اختيارية حتى لا نكسر البيانات القديمة.

class Meal {
  final String id;
  final String restaurant; // اسم المنشأة (مطعم/مقهى)
  final String name;
  final String category;
  final String serving;

  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  // اختياري
  final String? imageUrl;
  final String? description;

  const Meal({
    required this.id,
    required this.restaurant,
    required this.name,
    required this.category,
    required this.serving,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.imageUrl,
    this.description,
  });

  Meal copyWith({
    String? id,
    String? restaurant,
    String? name,
    String? category,
    String? serving,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    String? imageUrl,
    String? description,
  }) {
    return Meal(
      id: id ?? this.id,
      restaurant: restaurant ?? this.restaurant,
      name: name ?? this.name,
      category: category ?? this.category,
      serving: serving ?? this.serving,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
    );
  }
}

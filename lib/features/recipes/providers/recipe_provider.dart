import 'package:flutter/foundation.dart';
import '../data/recipe_repository.dart';
import '../models/recipe.dart';

class RecipeProvider with ChangeNotifier {
  final RecipeRepository repo;
  RecipeProvider(this.repo);

  RecipeGoal? filterGoal;
  List<Recipe> _items = [];
  List<Recipe> get items => _items;

  Stream<List<Recipe>>? _sub;
  void init() {
    _sub?.drain();
    _sub = repo.streamRecipes(goal: filterGoal);
    _sub!.listen((data) {
      _items = data;
      notifyListeners();
    });
  }

  void setGoal(RecipeGoal? goal) {
    filterGoal = goal;
    init();
  }

  Future<void> create({
    required String userId,
    required String userName,
    required String? userPhotoUrl,
    required String title,
    required List<String> ingredients,
    required String method,
    required double protein,
    required double fat,
    required double carbs,
    required double calories,
    required RecipeGoal goal,
  }) async {
    final r = Recipe(
      id: '_',
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      title: title,
      ingredients: ingredients,
      method: method,
      protein: protein,
      fat: fat,
      carbs: carbs,
      calories: calories,
      goal: goal,
      createdAt: DateTime.now(),
    );
    await repo.addRecipe(r);
  }
}

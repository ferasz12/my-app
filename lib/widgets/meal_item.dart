import 'package:flutter/material.dart';
import '../models/meal.dart';

class MealItem extends StatelessWidget {
  final Meal meal;
  final VoidCallback onDelete;

  const MealItem({super.key, required this.meal, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: ListTile(
        title: Text(meal.name),
        subtitle: Text(
            'سعرات: ${meal.calories.toStringAsFixed(1)} , بروتين: ${meal.protein.toStringAsFixed(1)} , كارب: ${meal.carbs.toStringAsFixed(1)} , دهون: ${meal.fat.toStringAsFixed(1)}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

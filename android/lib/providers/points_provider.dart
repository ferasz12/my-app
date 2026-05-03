import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PointsProvider extends ChangeNotifier {
  int _points = 0;

  int get points => _points;

  PointsProvider() {
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    _points = prefs.getInt('userPoints') ?? 0;
    notifyListeners();
  }

  Future<void> addPoints(int value) async {
    _points += value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userPoints', _points);
    notifyListeners();
  }

  List<String> get achievements {
    List<String> list = [];
    if (_points >= 50) list.add("🔥 مجتهد");
    if (_points >= 100) list.add("🏅 مثابر");
    if (_points >= 200) list.add("💪 أسطورة");
    return list;
  }
}

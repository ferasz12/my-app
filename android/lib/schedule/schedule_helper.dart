// lib/schedule/schedule_helper.dart
class WorkoutHelper {
  static const Map<int, String> arabicDays = {
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
  };

  static String todayNameArabic() {
    return arabicDays[DateTime.now().weekday] ?? 'اليوم';
  }

  static const List<String> orderedArabicDays = [
    'السبت','الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة'
  ];

  /// Return sorted keys by our arabic weekday order
  static List<String> sortByWeekOrder(Iterable<String> days) {
    final order = {for (var i = 0; i < orderedArabicDays.length; i++) orderedArabicDays[i]: i};
    final list = days.toList();
    list.sort((a, b) => (order[a] ?? 99).compareTo(order[b] ?? 99));
    return list;
  }
}

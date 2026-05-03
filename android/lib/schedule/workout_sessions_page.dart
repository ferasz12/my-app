// lib/schedule/workout_sessions_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// صفحة "جلسات التمرين"
/// تعديل كامل لقراءة/الهجرة من المفتاح القديم 'workout_sessions' (List<String>)
/// إلى المفتاح الجديد 'workoutSessions_<email>' (String يحوي JSON Array)
class WorkoutSessionsPage extends StatefulWidget {
  const WorkoutSessionsPage({super.key});

  @override
  State<WorkoutSessionsPage> createState() => _WorkoutSessionsPageState();
}

class _WorkoutSessionsPageState extends State<WorkoutSessionsPage> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// إرجاع بريد المستخدم المخزن محليًا (إن وُجد) لاشتقاق مفتاح التخزين
  Future<String> _resolveEmail(SharedPreferences prefs) async {
    // جرّب أكثر من مفتاح محتمل حسب أجزاء المشروع
    final candidates = <String?>[
      prefs.getString('currentEmail'),
      prefs.getString('email'),
      prefs.getString('userEmail'),
      prefs.getString('user_email'),
    ];
    return (candidates.firstWhere((e) => (e != null && e.trim().isNotEmpty),
            orElse: () => 'unknown_user'))!
        .trim()
        .toLowerCase();
  }

  /// ترتيب بسيط: حسب التاريخ ثم وقت البدء إن توفرت الحقول (تصاعدي)
  int _sessionComparator(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ad = (a['date'] ?? '').toString();
    final bd = (b['date'] ?? '').toString();
    final at = (a['start'] ?? a['startTime'] ?? '').toString();
    final bt = (b['start'] ?? b['startTime'] ?? '').toString();
    final c1 = ad.compareTo(bd);
    return c1 != 0 ? c1 : at.compareTo(bt);
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final keyNew = 'workoutSessions_$email';
    const keyOld = 'workout_sessions';
    const keyOldAlt = 'workoutSessions'; // احتياطي إن وُجد استخدام بدون إيميل

    final parsed = <Map<String, dynamic>>[];

    // 1) الصيغة الجديدة: String يحوي JSON Array
    final sNew = prefs.getString(keyNew);
    if (sNew != null) {
      try {
        final decoded = jsonDecode(sNew);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) parsed.add(Map<String, dynamic>.from(e));
          }
        } else if (decoded is Map && decoded['sessions'] is List) {
          // دعم نادر لصيغة { "sessions": [ ... ] }
          for (final e in (decoded['sessions'] as List)) {
            if (e is Map) parsed.add(Map<String, dynamic>.from(e));
          }
        }
      } catch (_) {}
    }

    // 2) توافق مع الصيغة/المفتاح القديم: List<String> وكل عنصر JSON
    if (parsed.isEmpty) {
      for (final legacyKey in [keyOld, keyOldAlt]) {
        final raw = prefs.getStringList(legacyKey) ?? const [];
        if (raw.isEmpty) continue;
        for (final s in raw) {
          try {
            final m = json.decode(s);
            if (m is Map) parsed.add(Map<String, dynamic>.from(m));
          } catch (_) {}
        }
        if (parsed.isNotEmpty) {
          // وجدنا بيانات في مفتاح قديم — توقف عن محاولة مفاتيح أخرى
          break;
        }
      }
    }

    // ترتيب
    parsed.sort(_sessionComparator);

    if (!mounted) return;
    setState(() {
      _sessions = parsed;
      _loading = false;
    });

    // 3) هجرة تلقائية: لو قرأنا من القديم، اكتبها في المفتاح الجديد واحذف القديم
    if (sNew == null && parsed.isNotEmpty) {
      await prefs.setString(keyNew, jsonEncode(parsed));
      await prefs.remove(keyOld);
      await prefs.remove(keyOldAlt);
    }
  }

  Future<void> _delete(int index) async {
    if (index < 0 || index >= _sessions.length) return;

    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final keyNew = 'workoutSessions_$email';

    // احذف من الذاكرة
    setState(() {
      _sessions.removeAt(index);
    });

    // أعد حفظ القائمة كلها بصيغة JSON Array في المفتاح الجديد
    await prefs.setString(keyNew, jsonEncode(_sessions));

    // (اختياري) تأكد من إزالة المفتاح القديم إن وُجد
    await prefs.remove('workout_sessions');
    await prefs.remove('workoutSessions');
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _resolveEmail(prefs);
    final keyNew = 'workoutSessions_$email';

    setState(() => _sessions.clear());
    await prefs.setString(keyNew, jsonEncode(_sessions));
    await prefs.remove('workout_sessions');
    await prefs.remove('workoutSessions');
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _sessions.isEmpty
            ? const Center(child: Text('لا توجد جلسات محفوظة بعد.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _sessions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = _sessions[i];
                  final day =
                      (m['day'] ?? m['اليوم'] ?? '').toString().trim();
                  final date = (m['date'] ?? '').toString().trim();
                  final st =
                      (m['start'] ?? m['startTime'] ?? '').toString().trim();
                  final en =
                      (m['end'] ?? m['endTime'] ?? '').toString().trim();
                  final plan =
                      (m['plan'] ?? m['planName'] ?? '').toString().trim();

                  final title = day.isNotEmpty ? day : 'جلسة رقم ${i + 1}';
                  final details = <String>[
                    if (date.isNotEmpty) date,
                    if (st.isNotEmpty && en.isNotEmpty) 'من $st إلى $en',
                    if (plan.isNotEmpty) 'الجدول: $plan',
                  ].join(' • ');

                  return ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: Text(title),
                    subtitle: Text(details),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever),
                      onPressed: () => _delete(i),
                      tooltip: 'حذف الجلسة',
                    ),
                  );
                },
              );

    return Scaffold(
      appBar: AppBar(
        title: const Text('جلسات التمرين'),
        actions: [
          if (!_loading && _sessions.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              icon: const Icon(Icons.cleaning_services),
              tooltip: 'حذف الكل',
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: body is Widget ? body : const SizedBox.shrink(),
      ),
    );
  }
}

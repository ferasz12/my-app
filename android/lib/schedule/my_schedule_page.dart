// lib/schedule/my_schedule_page.dart
import 'package:flutter/material.dart';
import 'schedule_storage.dart';
import 'selected_schedule_page.dart';

/// صفحة "جدولي" — تعيد التوجيه تلقائيًا دائمًا للجدول المحفوظ (إن وجد)
class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> {
  String? _planName;
  bool _loading = true;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final name = await ScheduleStorage.loadSelectedPlan();
    if (!mounted) return;
    setState(() {
      _planName = name;
      _loading = false;
    });
  }

  Future<void> _checkAndRedirect() async {
    if (_navigating) return;
    // اقرأ أحدث قيمة في كل مرة ترجع فيها لهذه الصفحة
    final name = await ScheduleStorage.loadSelectedPlan();
    if (!mounted) return;
    if (name != null && name.isNotEmpty) {
      _navigating = true;
      // نستخدم pushReplacement حتى ما نرجع لهذه الصفحة مباشرة ونصير في حلقة
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SelectedSchedulePage(planName: name)),
      );
    }
  }

  /// فتح صفحة اختيار الجداول (الجاهزة + جداولي المخصّصة)
  Future<void> _pickNew() async {
    final result = await Navigator.pushNamed(context, '/schedulePicker');
    if (!mounted) return;
    if (result is String && result.isNotEmpty) {
      await ScheduleStorage.saveSelectedPlan(result);
      // بعد الحفظ نوجّه مباشرة لعرض الجدول
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SelectedSchedulePage(planName: result)),
      );
    }
  }

  /// زر + (إنشاء جدول جديد). بعد الحفظ يفتح قائمة الجداول ليظهر الجدول فورًا.
  Future<void> _createNew() async {
    final created = await Navigator.pushNamed(context, '/createSchedule');
    if (!mounted) return;
    if (created == true) {
      // عرض قائمة الجداول ليتأكد المستخدم أن الجدول الجديد أُضيف
      await Navigator.pushNamed(context, '/schedulePicker');
      // نحدّث النص الظاهر تحت العنوان في حال رجع بدون اختيار
      final name = await ScheduleStorage.loadSelectedPlan();
      if (!mounted) return;
      setState(() => _planName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    // نفحص كل مرة تُبنى فيها الصفحة (مفيد مع التابات/الرجوع)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRedirect();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('📅 جدولي'),
        actions: [
          IconButton(
            tooltip: 'إنشاء جدول جديد',
            icon: const Icon(Icons.add),
            onPressed: _createNew,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _planName == null
                          ? 'ما اخترت جدول بعد.'
                          : 'آخر جدول محفوظ: $_planName',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _pickNew,
                      icon: const Icon(Icons.style),
                      label: Text(
                        _planName == null ? 'اختيار جدول جديد' : 'تغيير الجدول',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

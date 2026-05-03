// lib/schedule/my_schedule_page.dart
import 'package:flutter/material.dart';
import 'schedule_storage.dart';
import 'selected_schedule_page.dart';

/// صفحة "جدولي" — تعيد التوجيه تلقائيًا للجدول المحفوظ (إن وجد)
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
    if (_loading || _navigating) return;

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

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

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
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        cs.primaryContainer.withOpacity(.70),
                        cs.surface,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(Icons.event_available_rounded, color: cs.onPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _planName == null || _planName!.isEmpty
                                  ? 'اختر جدولك الآن'
                                  : 'جدولك الحالي',
                              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _planName == null || _planName!.isEmpty
                                  ? 'اختر جدول جاهز أو أنشئ جدول خاص في دقائق.'
                                  : _planName!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(.75),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'الخطوات السريعة',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _pickNew,
                          icon: const Icon(Icons.style_rounded),
                          label: Text(_planName == null ? 'اختيار جدول' : 'تغيير الجدول'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _createNew,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('إنشاء جدول مخصّص'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'ملاحظة: يمكنك تعديل جدولك في أي وقت من هنا بدون ما يتأثر باقي التطبيق.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(.70),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// lib/screens/keto_regimen_log_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_app/regimens/keto_guard.dart';

class KetoRegimenLogPage extends StatefulWidget {
  const KetoRegimenLogPage({super.key});

  @override
  State<KetoRegimenLogPage> createState() => _KetoRegimenLogPageState();
}

class _KetoRegimenLogPageState extends State<KetoRegimenLogPage> {
  List<Map<String, dynamic>> _log = [];
  bool _loading = true;

  Future<void> _load() async {
    final l = await KetoGuard.getLog();
    if (!mounted) return;
    setState(() {
      _log = l;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('yyyy-MM-dd').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجلّ رجيم الكيتو')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _log.isEmpty
              ? const Center(child: Text('لا يوجد سجل بعد'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _log.length,
                    separatorBuilder: (_, __)=> const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = _log[i];
                      final start = (e['start'] ?? '').toString();
                      final end = (e['end'] ?? '').toString();
                      final score = ((e['avgScore'] ?? 0.0) as num).toDouble();
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_available),
                          title: Text('${_fmt(start)} → ${_fmt(end)}'),
                          subtitle: Text('نسبة الإنجاز: ${(score * 100).round()}%'),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// lib/water/water_pages.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'water_store.dart';

Future<void> showWaterQuickAddSheet(BuildContext context) async {
  final cupSizes = <int>[200, 250, 300, 330, 500]; // مليلتر
  int selectedCup = 250;
  int cups = 1;
  final litersCtl = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant, borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('تسجيل الماء', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),

            // إدخال بالأكواب
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: selectedCup,
                    decoration: const InputDecoration(
                      labelText: 'حجم الكوب (مل)',
                      border: OutlineInputBorder(),
                    ),
                    items: cupSizes.map((ml) =>
                      DropdownMenuItem(value: ml, child: Text('$ml مل'))).toList(),
                    onChanged: (v) { if (v != null) selectedCup = v; },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '$cups',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد الأكواب',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      cups = (n == null || n <= 0) ? 1 : n;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.local_drink),
                label: const Text('إضافة كأكواب'),
                onPressed: () async {
                  final liters = (selectedCup * cups) / 1000.0;
                  await WaterStore.addLiters(liters);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تمت إضافة ${liters.toStringAsFixed(2)} لتر')),
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 8),
            // إدخال مباشر باللتر
            TextField(
              controller: litersCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'كمية باللتر (مثال: 0.5)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('إضافة باللتر'),
                onPressed: () async {
                  final v = double.tryParse(litersCtl.text.trim()) ?? 0;
                  if (v <= 0) return;
                  await WaterStore.addLiters(v);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تمت إضافة ${v.toStringAsFixed(2)} لتر')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class WaterHistoryPage extends StatefulWidget {
  const WaterHistoryPage({super.key});
  @override
  State<WaterHistoryPage> createState() => _WaterHistoryPageState();
}

class _WaterHistoryPageState extends State<WaterHistoryPage> {
  List<MapEntry<String, double>> data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await WaterStore.recent(days: 30);
    if (mounted) setState(() => data = list);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الماء')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: data.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = data[i];
            final d = DateTime.parse(e.key);
            final liters = e.value;
            final plenty = liters >= kPlentyWaterThresholdLiters;
            return ListTile(
              leading: Icon(Icons.water_drop, color: plenty ? Colors.teal : null),
              title: Text(df.format(d)),
              subtitle: Text('${liters.toStringAsFixed(2)} لتر'),
              trailing: plenty
                  ? const Chip(label: Text('شرب كثير ✅'))
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}

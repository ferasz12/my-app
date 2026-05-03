// lib/screens/venues_list_page.dart
import 'package:flutter/material.dart';
import '../models/meal.dart';
import '../models/venue.dart';
import '../data/venues_registry.dart';

class VenuesListPage extends StatefulWidget {
  final VenueType type;
  final String title;
  const VenuesListPage({super.key, required this.type, required this.title});

  @override
  State<VenuesListPage> createState() => _VenuesListPageState();
}

class _VenuesListPageState extends State<VenuesListPage> {
  final TextEditingController _search = TextEditingController();
  late List<Venue> _venues;
  late List<Venue> _filtered;

  @override
  void initState() {
    super.initState();
    _venues = venuesByType(widget.type);
    _filtered = _venues;
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = _venues.where((v) {
        final s = (v.name + ' ' + v.meals.map((m) => '${m.name} ${m.category}').join(' ')).toLowerCase();
        return s.contains(q);
      }).toList();
    });
  }

  String _fmt(num n) => n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'ابحث بالمنشأة أو الوجبة…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('لا توجد نتائج'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final v = _filtered[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 3,
                        child: Column(
                          children: [
                            // صورة المنشأة
                            if (v.imageAsset != null)
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Image.asset(
                                  v.imageAsset!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image, size: 48)),
                                ),
                              ),
                            ListTile(
                              title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(v.type == VenueType.restaurant ? 'مطعم' : 'مقهى'),
                            ),
                            // الوجبات كتوسعة
                            ExpansionTile(
                              title: const Text('الوجبات'),
                              children: v.meals.map((m) {
                                return ListTile(
                                  title: Text(m.name),
                                  subtitle: Text(
                                    'الصنف: ${m.category} • الحصة: ${m.serving}\n'
                                    '⚡ ${m.calories} كال  •  🥩 ${_fmt(m.protein)}غ  •  🍞 ${_fmt(m.carbs)}غ  •  🧈 ${_fmt(m.fat)}غ',
                                  ),
                                  isThreeLine: true,
                                  trailing: Chip(label: Text('${m.calories} كال')),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

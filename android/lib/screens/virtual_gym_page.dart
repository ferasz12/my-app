// lib/screens/virtual_gym_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ استيراد باكيج ثابت (يفضّل دائمًا)
// لو ملفك فعليًا في lib/virtual_gym/exercise_data.dart غيّر السطر إلى:
// import 'package:my_app/virtual_gym/exercise_data.dart';
import 'package:my_app/data/exercise_data.dart';

class VirtualGymPage extends StatefulWidget {
  const VirtualGymPage({super.key});

  @override
  State<VirtualGymPage> createState() => _VirtualGymPageState();
}

class _VirtualGymPageState extends State<VirtualGymPage> {
  bool filterByGoal = false;
  String userGoal = "";

  // نحمل لاحقاً بعد نجاح الاستيراد
  List<Exercise> _all = [];

  // حالة التصفية/البحث
  String _search = "";
  String? _group; // الصدر/الظهر/...
  bool? _isHome; // null=الكل، true=منزلي، false=نادي
  String? _level; // Beginner/Intermediate/Advanced

  // تحميل تدريجي
  static const int _pageSize = 48;
  int _shown = _pageSize;
  final _scroll = ScrollController();

  String? _loadError;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _boot();
  }

  Future<void> _boot() async {
    await loadUserGoal();
    await _loadExercises();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> loadUserGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'unknown_user';
    setState(() {
      userGoal = prefs.getString('goal_$email') ?? '';
    });
  }

  Future<void> _loadExercises() async {
    try {
      final generated = ExerciseData.generate();
      setState(() {
        _all = generated;
        _loadError = null;
        _shown = _pageSize;
      });
    } catch (e) {
      setState(() {
        _all = [];
        _loadError = 'تعذّر تحميل التمارين: $e';
      });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      final total = _filtered().length;
      if (_shown < total) {
        setState(() => _shown = (_shown + _pageSize).clamp(0, total));
      }
    }
  }

  List<String> get _groups {
    final g = _all.map((e) => e.group).toSet().toList();
    g.sort();
    return g;
  }

  List<Exercise> _filtered() {
    Iterable<Exercise> q = _all;

    if (filterByGoal && userGoal.isNotEmpty) {
      q = q.where((e) => e.goals.contains(userGoal));
    }
    if (_group != null && _group!.isNotEmpty) {
      q = q.where((e) => e.group == _group);
    }
    if (_isHome != null) {
      q = q.where((e) => e.isHome == _isHome);
    }
    if (_level != null && _level!.isNotEmpty) {
      q = q.where((e) => e.level == _level);
    }
    if (_search.isNotEmpty) {
      final s = _search.toLowerCase();
      q = q.where((e) =>
          e.name.toLowerCase().contains(s) ||
          e.baseName.toLowerCase().contains(s) ||
          e.group.toLowerCase().contains(s));
    }

    final list = q.toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        if (g != 0) return g;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    final data = _filtered();
    final shown = data.take(_shown).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("النادي الافتراضي", style: text.titleLarge),
        actions: [
          IconButton(
            icon: Icon(filterByGoal ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: filterByGoal ? "إلغاء تصفية الهدف" : "تصفية حسب الهدف",
            onPressed: () => setState(() => filterByGoal = !filterByGoal),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "بحث",
            onPressed: () async {
              final result = await showSearch<String?>(
                context: context,
                delegate: ExerciseSearchDelegate(initial: _search),
              );
              if (result != null) {
                setState(() {
                  _search = result;
                  _shown = _pageSize;
                });
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _HeaderSummary(
            total: data.length,
            shown: shown.length,
            activeGoal: filterByGoal && userGoal.isNotEmpty ? userGoal : null,
          ),
          _buildFilters(context),
          const Divider(height: 0),
          Expanded(
            child: _buildListArea(data, shown, text),
          ),
        ],
      ),
    );
  }

  Widget _buildListArea(
      List<Exercise> data, List<Exercise> shown, TextTheme text) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _loadExercises,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('جارِ تحميل التمارين…', style: text.bodyMedium),
            ],
          ),
        ),
      );
    }

    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 40),
              const SizedBox(height: 8),
              Text('لا توجد نتائج للتصفية/البحث الحالية', style: text.bodyMedium),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _group = null;
                  _isHome = null;
                  _level = null;
                  _search = "";
                  _shown = _pageSize;
                }),
                icon: const Icon(Icons.clear),
                label: const Text("مسح التصفية"),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      itemCount: shown.length + 1,
      itemBuilder: (context, index) {
        if (index == shown.length) {
          final more = _shown < data.length;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: more
                  ? const CircularProgressIndicator()
                  : Text("تم عرض ${data.length} تمرين", style: text.bodyMedium),
            ),
          );
        }
        final ex = shown[index];
        return ExerciseCard(ex: ex);
      },
    );
  }

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // صف سريع: فلترة الهدف + توضيح الهدف الحالي إن وجد
              Row(
                children: [
                  Switch.adaptive(
                    value: filterByGoal,
                    onChanged: (v) => setState(() => filterByGoal = v),
                  ),
                  const SizedBox(width: 6),
                  const Text("تصفية حسب الهدف"),
                  const SizedBox(width: 8),
                  if (filterByGoal && userGoal.isNotEmpty)
                    Chip(
                      label: Text('هدفك: $userGoal'),
                      backgroundColor: cs.primary.withOpacity(0.08),
                      side: BorderSide(color: cs.primary),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _group = null;
                      _isHome = null;
                      _level = null;
                      _search = "";
                      _shown = _pageSize;
                    }),
                    icon: const Icon(Icons.clear),
                    label: const Text("مسح"),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // عناصر التصفية المنسّقة
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String?>(
                      value: _group,
                      decoration: const InputDecoration(
                        labelText: "الجزء",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(value: null, child: Text("الكل")),
                        ..._groups.map(
                          (g) => DropdownMenuItem<String?>(
                            value: g,
                            child: Text(g),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _group = v;
                        _shown = _pageSize;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<bool?>(
                      value: _isHome,
                      decoration: const InputDecoration(
                        labelText: "نوع التمرين",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<bool?>>[
                        DropdownMenuItem<bool?>(value: null, child: Text("الكل")),
                        DropdownMenuItem<bool?>(value: true, child: Text("منزلي")),
                        DropdownMenuItem<bool?>(value: false, child: Text("نادي/معدات")),
                      ],
                      onChanged: (v) => setState(() {
                        _isHome = v;
                        _shown = _pageSize;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String?>(
                      value: _level,
                      decoration: const InputDecoration(
                        labelText: "المستوى",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(value: null, child: Text("الكل")),
                        ...ExerciseData.levels.map(
                          (lv) => DropdownMenuItem<String?>(value: lv, child: Text(lv)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _level = v;
                        _shown = _pageSize;
                      }),
                    ),
                  ),
                ],
              ),

              // شِيبس توضح التصفيات المفعّلة (تُزال بنقرة ×)
              const SizedBox(height: 10),
              _ActiveFiltersChips(
                group: _group,
                isHome: _isHome,
                level: _level,
                onClearGroup: () => setState(() {
                  _group = null; _shown = _pageSize;
                }),
                onClearHome: () => setState(() {
                  _isHome = null; _shown = _pageSize;
                }),
                onClearLevel: () => setState(() {
                  _level = null; _shown = _pageSize;
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Widgets =====

class _HeaderSummary extends StatelessWidget {
  final int total;
  final int shown;
  final String? activeGoal;
  const _HeaderSummary({required this.total, required this.shown, this.activeGoal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Icon(Icons.fitness_center, color: cs.primary),
          const SizedBox(width: 8),
          Text("التمارين المعروضة: $shown / $total", style: text.bodyMedium),
          const Spacer(),
          if (activeGoal != null)
            Chip(
              label: Text("هدفك: $activeGoal"),
              backgroundColor: cs.secondaryContainer,
              side: BorderSide(color: cs.secondary),
            ),
        ],
      ),
    );
  }
}

class _ActiveFiltersChips extends StatelessWidget {
  final String? group;
  final bool? isHome;
  final String? level;
  final VoidCallback onClearGroup;
  final VoidCallback onClearHome;
  final VoidCallback onClearLevel;

  const _ActiveFiltersChips({
    required this.group,
    required this.isHome,
    required this.level,
    required this.onClearGroup,
    required this.onClearHome,
    required this.onClearLevel,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (group != null && group!.isNotEmpty) {
      chips.add(_ClosableChip(label: "الجزء: $group", onClose: onClearGroup));
    }
    if (isHome != null) {
      chips.add(_ClosableChip(label: isHome! ? "منزلي" : "نادي/معدات", onClose: onClearHome));
    }
    if (level != null && level!.isNotEmpty) {
      chips.add(_ClosableChip(label: "المستوى: $level", onClose: onClearLevel));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

class _ClosableChip extends StatelessWidget {
  final String label;
  final VoidCallback onClose;
  const _ClosableChip({required this.label, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      deleteIcon: const Icon(Icons.close),
      onDeleted: onClose,
      backgroundColor: cs.surfaceVariant.withOpacity(0.6),
    );
  }
}

class ExerciseCard extends StatelessWidget {
  final Exercise ex;
  const ExerciseCard({super.key, required this.ex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان التمرين + شارة النوع
            Row(
              children: [
                Expanded(
                  child: Text(
                    ex.name,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.primary),
                  ),
                  child: Text(ex.isHome ? "منزلي" : "نادي", style: text.labelMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TagChip(text: "المجموعة: ${ex.group}"),
                TagChip(text: "المستوى: ${ex.level}"),
                if (ex.equipment.isNotEmpty)
                  TagChip(text: "أدوات: ${ex.equipment.join(", ")}"),
              ],
            ),

            const SizedBox(height: 10),
            if (ex.description.isNotEmpty) ...[
              _SectionTitle('الوصف'),
              Text(ex.description, style: text.bodyMedium),
              const SizedBox(height: 8),
            ],
            if (ex.benefits.isNotEmpty) ...[
              _SectionTitle('الفوائد'),
              Text(ex.benefits, style: text.bodyMedium),
              const SizedBox(height: 8),
            ],
            const Divider(height: 16),

            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_circle),
                label: const Text("شاهد التمرين"),
                onPressed: () async {
                  final uri = Uri.parse(ex.youtube);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class TagChip extends StatelessWidget {
  final String text;
  const TagChip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chipTheme = ChipTheme.of(context);

    return Chip(
      label: Text(text, style: chipTheme.labelStyle),
      backgroundColor: chipTheme.backgroundColor ?? cs.primary.withOpacity(0.08),
      side: chipTheme.side ?? BorderSide(color: cs.primary),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class ExerciseSearchDelegate extends SearchDelegate<String?> {
  ExerciseSearchDelegate({String initial = ""}) {
    query = initial;
  }

  @override
  String? get searchFieldLabel => "ابحث باسم التمرين أو الجزء";

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = "")
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    close(context, query);
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();
}

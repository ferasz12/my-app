// lib/screens/virtual_gym_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:my_app/data/exercise_data.dart';

/// النادي الافتراضي — نسخة مطورة:
/// - خريطة جسم تفاعلية بشكل فخم بدون مكتبات خارجية.
/// - الضغط على العضلة يفتح مقاطع التمارين الخاصة بها.
/// - يدعم العضلات المتوفرة في ExerciseData: الصدر، الظهر، الأكتاف، تراي، باي.
class VirtualGymPage extends StatefulWidget {
  const VirtualGymPage({super.key});

  @override
  State<VirtualGymPage> createState() => _VirtualGymPageState();
}

class _VirtualGymPageState extends State<VirtualGymPage> {
  _BodySide _side = _BodySide.front;
  String _selectedGroup = 'الصدر';
  late final List<Exercise> _library = ExerciseData.generateLibrary();

  int _countFor(String group) => _library.where((e) => e.group == group).length;

  void _openGroup(String group) {
    setState(() => _selectedGroup = group);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VirtualGymExplorerPage(
          title: 'تمارين $group',
          initialGroup: group,
          simpleMode: true,
          showFilters: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PremiumGate(
        feature: PremiumFeature.virtualGym,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: Text(
              'النادي الافتراضي',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'عرض كل التمارين',
                icon: const Icon(Icons.video_library_rounded),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VirtualGymExplorerPage(
                        title: 'كل تمارين النادي الافتراضي',
                        simpleMode: true,
                        showFilters: true,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _VirtualGymHero(
                selectedGroup: _selectedGroup,
                availableCount: _countFor(_selectedGroup),
              ),
              const SizedBox(height: 14),
              _SideSwitch(
                side: _side,
                onChanged: (v) => setState(() => _side = v),
              ),
              const SizedBox(height: 14),
              _MuscleAtlasCard(
                side: _side,
                selectedGroup: _selectedGroup,
                countFor: _countFor,
                onSelect: _openGroup,
              ),
              const SizedBox(height: 16),
              _AvailableMusclesSection(
                selectedGroup: _selectedGroup,
                countFor: _countFor,
                onTap: _openGroup,
              ),
              const SizedBox(height: 12),
              _TipCard(
                text:
                    'اضغط على العضلة من الرسم، ووازن يفتح لك مقاطع التمارين الخاصة فيها مباشرة.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VirtualGymHero extends StatelessWidget {
  const _VirtualGymHero({required this.selectedGroup, required this.availableCount});

  final String selectedGroup;
  final int availableCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primaryContainer.withOpacity(0.92),
            cs.surfaceContainerHighest,
            cs.surface,
          ],
          stops: const [0.0, 0.58, 1.0],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.10),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -42,
            start: -24,
            child: _GlowCircle(color: cs.primary.withOpacity(0.13), size: 130),
          ),
          PositionedDirectional(
            bottom: -54,
            end: -28,
            child: _GlowCircle(color: cs.tertiary.withOpacity(0.10), size: 160),
          ),
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.42),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.28)),
                ),
                child: Icon(Icons.fitness_center_rounded, color: cs.primary, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اختر العضلة وابدأ تمرينك',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'واجهة تفاعلية تربط كل عضلة بالمقاطع المناسبة لها داخل وازن.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.68),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniInfoChip(icon: Icons.touch_app_rounded, label: 'اضغط على العضلة'),
                        _MiniInfoChip(
                          icon: Icons.play_circle_rounded,
                          label: '$availableCount مقاطع لـ $selectedGroup',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

enum _BodySide { front, back }

class _SideSwitch extends StatelessWidget {
  const _SideSwitch({required this.side, required this.onChanged});
  final _BodySide side;
  final ValueChanged<_BodySide> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwitchButton(
              selected: side == _BodySide.front,
              icon: Icons.accessibility_new_rounded,
              label: 'الأمام',
              onTap: () => onChanged(_BodySide.front),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SwitchButton(
              selected: side == _BodySide.back,
              icon: Icons.accessibility_rounded,
              label: 'الخلف',
              onTap: () => onChanged(_BodySide.back),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({required this.selected, required this.icon, required this.label, required this.onTap});

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: selected ? cs.onPrimary : cs.onSurfaceVariant),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuscleAtlasCard extends StatelessWidget {
  const _MuscleAtlasCard({
    required this.side,
    required this.selectedGroup,
    required this.countFor,
    required this.onSelect,
  });

  final _BodySide side;
  final String selectedGroup;
  final int Function(String group) countFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.84),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.sports_gymnastics_rounded, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'خريطة العضلات',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      side == _BodySide.front ? 'واجهة أمامية للجسم' : 'واجهة خلفية للجسم',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              _MiniInfoChip(
                icon: Icons.video_camera_back_rounded,
                label: '${countFor(selectedGroup)} مقطع',
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(280.0, 520.0);
              return Center(
                child: SizedBox(
                  width: width,
                  height: width * 1.34,
                  child: _BodyDiagram(
                    side: side,
                    selectedGroup: selectedGroup,
                    countFor: countFor,
                    onSelect: onSelect,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BodyDiagram extends StatelessWidget {
  const _BodyDiagram({
    required this.side,
    required this.selectedGroup,
    required this.countFor,
    required this.onSelect,
  });

  final _BodySide side;
  final String selectedGroup;
  final int Function(String group) countFor;
  final ValueChanged<String> onSelect;

  bool _selected(String group) => selectedGroup == group;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surface;
    final outline = cs.outlineVariant.withOpacity(0.72);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.primary.withOpacity(0.08),
                  cs.surface.withOpacity(0.65),
                  cs.tertiary.withOpacity(0.05),
                ],
              ),
            ),
          ),
        ),
        _BodyPart(top: 0.04, left: 0.42, width: 0.16, height: 0.12, radius: 999, color: base, border: outline),
        _BodyPart(top: 0.16, left: 0.35, width: 0.30, height: 0.34, radius: 34, color: base, border: outline),
        _BodyPart(top: 0.19, left: 0.18, width: 0.14, height: 0.34, radius: 999, color: base, border: outline),
        _BodyPart(top: 0.19, left: 0.68, width: 0.14, height: 0.34, radius: 999, color: base, border: outline),
        _BodyPart(top: 0.49, left: 0.37, width: 0.11, height: 0.36, radius: 999, color: base, border: outline),
        _BodyPart(top: 0.49, left: 0.52, width: 0.11, height: 0.36, radius: 999, color: base, border: outline),
        _BodyPart(top: 0.82, left: 0.36, width: 0.12, height: 0.09, radius: 999, color: base, border: outline),
        _BodyPart(top: 0.82, left: 0.52, width: 0.12, height: 0.09, radius: 999, color: base, border: outline),
        if (side == _BodySide.front) ...[
          _MuscleHotspot(
            group: 'الصدر',
            label: 'الصدر',
            top: 0.205,
            left: 0.365,
            width: 0.27,
            height: 0.12,
            selected: _selected('الصدر'),
            count: countFor('الصدر'),
            onTap: () => onSelect('الصدر'),
          ),
          _MuscleHotspot(
            group: 'الأكتاف',
            label: 'الأكتاف',
            top: 0.18,
            left: 0.265,
            width: 0.13,
            height: 0.10,
            selected: _selected('الأكتاف'),
            count: countFor('الأكتاف'),
            onTap: () => onSelect('الأكتاف'),
          ),
          _MuscleHotspot(
            group: 'الأكتاف',
            label: 'الأكتاف',
            top: 0.18,
            left: 0.605,
            width: 0.13,
            height: 0.10,
            selected: _selected('الأكتاف'),
            count: countFor('الأكتاف'),
            onTap: () => onSelect('الأكتاف'),
          ),
          _MuscleHotspot(
            group: 'باي',
            label: 'باي',
            top: 0.29,
            left: 0.195,
            width: 0.12,
            height: 0.15,
            selected: _selected('باي'),
            count: countFor('باي'),
            onTap: () => onSelect('باي'),
          ),
          _MuscleHotspot(
            group: 'باي',
            label: 'باي',
            top: 0.29,
            left: 0.685,
            width: 0.12,
            height: 0.15,
            selected: _selected('باي'),
            count: countFor('باي'),
            onTap: () => onSelect('باي'),
          ),
          _UnavailableHotspot(label: 'قريبًا', top: 0.34, left: 0.39, width: 0.22, height: 0.12),
          _UnavailableHotspot(label: 'قريبًا', top: 0.52, left: 0.36, width: 0.12, height: 0.24),
          _UnavailableHotspot(label: 'قريبًا', top: 0.52, left: 0.52, width: 0.12, height: 0.24),
        ] else ...[
          _MuscleHotspot(
            group: 'الظهر',
            label: 'الظهر',
            top: 0.205,
            left: 0.355,
            width: 0.29,
            height: 0.21,
            selected: _selected('الظهر'),
            count: countFor('الظهر'),
            onTap: () => onSelect('الظهر'),
          ),
          _MuscleHotspot(
            group: 'الأكتاف',
            label: 'الأكتاف',
            top: 0.18,
            left: 0.265,
            width: 0.13,
            height: 0.10,
            selected: _selected('الأكتاف'),
            count: countFor('الأكتاف'),
            onTap: () => onSelect('الأكتاف'),
          ),
          _MuscleHotspot(
            group: 'الأكتاف',
            label: 'الأكتاف',
            top: 0.18,
            left: 0.605,
            width: 0.13,
            height: 0.10,
            selected: _selected('الأكتاف'),
            count: countFor('الأكتاف'),
            onTap: () => onSelect('الأكتاف'),
          ),
          _MuscleHotspot(
            group: 'تراي',
            label: 'تراي',
            top: 0.30,
            left: 0.19,
            width: 0.13,
            height: 0.15,
            selected: _selected('تراي'),
            count: countFor('تراي'),
            onTap: () => onSelect('تراي'),
          ),
          _MuscleHotspot(
            group: 'تراي',
            label: 'تراي',
            top: 0.30,
            left: 0.68,
            width: 0.13,
            height: 0.15,
            selected: _selected('تراي'),
            count: countFor('تراي'),
            onTap: () => onSelect('تراي'),
          ),
          _UnavailableHotspot(label: 'قريبًا', top: 0.52, left: 0.36, width: 0.12, height: 0.24),
          _UnavailableHotspot(label: 'قريبًا', top: 0.52, left: 0.52, width: 0.12, height: 0.24),
        ],
      ],
    );
  }
}

class _BodyPart extends StatelessWidget {
  const _BodyPart({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
    required this.border,
  });

  final double top;
  final double left;
  final double width;
  final double height;
  final double radius;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment.topLeft,
        widthFactor: width,
        heightFactor: height,
        child: FractionalTranslation(
          translation: Offset(left / width, top / height),
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.82),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MuscleHotspot extends StatelessWidget {
  const _MuscleHotspot({
    required this.group,
    required this.label,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final String group;
  final String label;
  final double top;
  final double left;
  final double width;
  final double height;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.secondary;

    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment.topLeft,
        widthFactor: width,
        heightFactor: height,
        child: FractionalTranslation(
          translation: Offset(left / width, top / height),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  color: color.withOpacity(selected ? 0.92 : 0.68),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? cs.onPrimary.withOpacity(0.72) : color.withOpacity(0.72),
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(selected ? 0.35 : 0.16),
                      blurRadius: selected ? 22 : 12,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$count مقاطع',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: cs.onPrimary.withOpacity(0.88),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableHotspot extends StatelessWidget {
  const _UnavailableHotspot({required this.label, required this.top, required this.left, required this.width, required this.height});

  final String label;
  final double top;
  final double left;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment.topLeft,
        widthFactor: width,
        heightFactor: height,
        child: FractionalTranslation(
          translation: Offset(left / width, top / height),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.60),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailableMusclesSection extends StatelessWidget {
  const _AvailableMusclesSection({
    required this.selectedGroup,
    required this.countFor,
    required this.onTap,
  });

  final String selectedGroup;
  final int Function(String group) countFor;
  final ValueChanged<String> onTap;

  static const groups = <String>['الصدر', 'الظهر', 'الأكتاف', 'باي', 'تراي'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'العضلات المتاحة الآن',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groups.map((g) {
              final selected = g == selectedGroup;
              final count = countFor(g);
              return ActionChip(
                avatar: Icon(
                  _iconForGroup(g),
                  size: 18,
                  color: selected ? cs.onPrimary : cs.primary,
                ),
                label: Text('$g  •  $count'),
                labelStyle: TextStyle(
                  color: selected ? cs.onPrimary : cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
                backgroundColor: selected ? cs.primary : cs.surface,
                side: BorderSide(color: selected ? cs.primary : cs.outlineVariant),
                onPressed: () => onTap(g),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

IconData _iconForGroup(String group) {
  switch (group) {
    case 'الصدر':
      return Icons.favorite_rounded;
    case 'الظهر':
      return Icons.accessibility_rounded;
    case 'الأكتاف':
      return Icons.sports_martial_arts_rounded;
    case 'باي':
      return Icons.fitness_center_rounded;
    case 'تراي':
      return Icons.trending_up_rounded;
    default:
      return Icons.fitness_center_rounded;
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class VirtualGymExplorerPage extends StatefulWidget {
  const VirtualGymExplorerPage({
    super.key,
    this.title,
    this.initialGroup,
    this.simpleMode = false,
    this.showFilters = true,
  });

  final String? title;
  final String? initialGroup;
  final bool simpleMode;
  final bool showFilters;

  @override
  State<VirtualGymExplorerPage> createState() => _VirtualGymExplorerPageState();
}

class _VirtualGymExplorerPageState extends State<VirtualGymExplorerPage> {
  bool filterByGoal = false;
  String userGoal = '';

  List<Exercise> _all = [];

  String _search = '';
  String? _group;
  bool? _isHome;
  String? _level;

  static const int _pageSize = 48;
  int _shown = _pageSize;
  final _scroll = ScrollController();

  String? _loadError;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
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
    if (!mounted) return;
    setState(() {
      userGoal = prefs.getString('goal_$email') ?? '';
    });
  }

  Future<void> _loadExercises() async {
    try {
      final generated = widget.simpleMode ? ExerciseData.generateLibrary() : ExerciseData.generate();
      if (!mounted) return;
      setState(() {
        _all = generated;
        _loadError = null;
        _shown = _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _loadError = 'تعذّر تحميل التمارين: $e';
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
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
      q = q.where(
        (e) =>
            e.name.toLowerCase().contains(s) ||
            e.baseName.toLowerCase().contains(s) ||
            e.group.toLowerCase().contains(s),
      );
    }

    final list = q.toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        if (g != 0) return g;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  void _clearFilters() => setState(() {
        _group = widget.initialGroup;
        _isHome = null;
        _level = null;
        _search = '';
        _shown = _pageSize;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    final data = _filtered();
    final shown = data.take(_shown).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title ?? 'النادي الافتراضي',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          actions: [
            if (widget.showFilters)
              IconButton(
                icon: Icon(filterByGoal ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded),
                tooltip: filterByGoal ? 'إلغاء تصفية الهدف' : 'تصفية حسب الهدف',
                onPressed: () => setState(() => filterByGoal = !filterByGoal),
              ),
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'بحث',
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
              group: _group,
              activeGoal: filterByGoal && userGoal.isNotEmpty ? userGoal : null,
            ),
            if (widget.showFilters) _buildFilters(context),
            Expanded(child: _buildListArea(data, shown, text)),
          ],
        ),
      ),
    );
  }

  Widget _buildListArea(List<Exercise> data, List<Exercise> shown, TextTheme text) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 10),
              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _loadExercises,
                icon: const Icon(Icons.refresh_rounded),
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
              const Icon(Icons.search_off_rounded, size: 42),
              const SizedBox(height: 8),
              Text('لا توجد مقاطع لهذه التصفية حاليًا', style: text.bodyMedium),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('مسح التصفية'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
      itemCount: shown.length + 1,
      itemBuilder: (context, index) {
        if (index == shown.length) {
          final more = _shown < data.length;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: more ? const CircularProgressIndicator() : Text('تم عرض ${data.length} تمرين', style: text.bodyMedium),
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
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Switch.adaptive(
                  value: filterByGoal,
                  onChanged: (v) => setState(() => filterByGoal = v),
                ),
                const SizedBox(width: 4),
                const Expanded(child: Text('تصفية حسب هدفك')),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('مسح'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String?>(
                    value: _group,
                    decoration: InputDecoration(
                      labelText: 'العضلة',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                      ..._groups.map((g) => DropdownMenuItem<String?>(value: g, child: Text(g))),
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
                    decoration: InputDecoration(
                      labelText: 'نوع التمرين',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                    items: const <DropdownMenuItem<bool?>>[
                      DropdownMenuItem<bool?>(value: null, child: Text('الكل')),
                      DropdownMenuItem<bool?>(value: true, child: Text('منزلي')),
                      DropdownMenuItem<bool?>(value: false, child: Text('نادي/معدات')),
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
                    decoration: InputDecoration(
                      labelText: 'المستوى',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                      ...ExerciseData.levels.map((lv) => DropdownMenuItem<String?>(value: lv, child: Text(lv))),
                    ],
                    onChanged: (v) => setState(() {
                      _level = v;
                      _shown = _pageSize;
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({required this.total, required this.shown, this.group, this.activeGoal});

  final int total;
  final int shown;
  final String? group;
  final String? activeGoal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_iconForGroup(group ?? ''), color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group == null ? 'كل التمارين' : 'تمارين $group', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('المعروض: $shown / $total', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (activeGoal != null)
            Chip(
              label: Text('هدفك: $activeGoal'),
              backgroundColor: cs.secondaryContainer,
              side: BorderSide(color: cs.secondary.withOpacity(0.5)),
            ),
        ],
      ),
    );
  }
}

class ExerciseCard extends StatelessWidget {
  const ExerciseCard({super.key, required this.ex});
  final Exercise ex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: cs.shadow.withOpacity(0.07),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.10),
                    cs.secondary.withOpacity(0.06),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(_iconForGroup(ex.group), color: cs.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ex.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _SoftTag(text: ex.group, icon: Icons.accessibility_new_rounded),
                            _SoftTag(text: ex.isHome ? 'منزلي' : 'نادي', icon: Icons.location_on_rounded),
                            if (ex.level.isNotEmpty && ex.level != '—') _SoftTag(text: ex.level, icon: Icons.trending_up_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ex.description.isNotEmpty) ...[
                    _SectionTitle('طريقة الأداء'),
                    Text(ex.description, style: text.bodyMedium?.copyWith(height: 1.42)),
                    const SizedBox(height: 12),
                  ],
                  if (ex.benefits.isNotEmpty) ...[
                    _SectionTitle('الفائدة'),
                    Text(ex.benefits, style: text.bodyMedium?.copyWith(height: 1.42, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                  ],
                  if (ex.equipment.isNotEmpty) ...[
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: ex.equipment.map((e) => _SoftTag(text: e, icon: Icons.fitness_center_rounded)).toList(),
                    ),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_circle_rounded),
                      label: const Text('شاهد مقطع التمرين'),
                      onPressed: () async {
                        final uri = Uri.tryParse(ex.youtube);
                        if (uri == null) return;
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftTag extends StatelessWidget {
  const _SoftTag({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
    );
  }
}

class ExerciseSearchDelegate extends SearchDelegate<String?> {
  ExerciseSearchDelegate({String initial = ''}) {
    query = initial;
  }

  @override
  String? get searchFieldLabel => 'ابحث باسم التمرين أو العضلة';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const BackButtonIcon(),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    close(context, query);
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = <String>['الصدر', 'الظهر', 'الأكتاف', 'باي', 'تراي']
        .where((s) => query.trim().isEmpty || s.contains(query.trim()))
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        children: suggestions
            .map(
              (s) => ListTile(
                leading: Icon(_iconForGroup(s)),
                title: Text(s),
                onTap: () {
                  query = s;
                  close(context, s);
                },
              ),
            )
            .toList(),
      ),
    );
  }
}

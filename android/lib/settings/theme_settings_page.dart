// UPDATED: صفحة اختيار المظهر — Slivers + ضبط نسب البطاقات + قسم حجم الخط
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final items = _themeItems();

    final scale = MediaQuery.textScaleFactorOf(context);
    final sizes = const ['صغير', 'متوسط', 'كبير', 'كبير جدًا'];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المظهر')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;

              // أعمدة الشبكة حسب العرض
              final cols = w >= 920 ? 4 : (w >= 700 ? 3 : 2);

              // ارتفاع بطاقة مرن مع تكبير الخط (نتجنّب Overflow)
              const baseH = 128.0;
              final tileH = baseH * (scale > 1.10 ? (1.0 + (scale - 1.10) * 0.75) : 1.0);
              final spacing = 12.0;
              final tileW = (w - 32 - spacing * (cols - 1)) / cols; // 32 = Padding أفقي
              // childAspectRatio ثابت وآمن
              final ratio = tileW / tileH;

              return CustomScrollView(
                slivers: [
                  // وصف بسيط
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'اختر المظهر الافتراضي أو اتبع النظام. يمكنك تغيير حجم الخط من الأسفل.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),

                  // شبكة المظاهر
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        childAspectRatio: ratio,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final it = items[index];
                          final selected = theme.current == it.id;

                          final borderColor = selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant;

                          return InkWell(
                            onTap: () => theme.setTheme(it.id),
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: borderColor,
                                  width: selected ? 2.0 : 1.2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _ThemePreview(colors: it.previewColors),
                                      const SizedBox(height: 8),
                                      Text(
                                        it.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: Theme.of(context).colorScheme.onBackground,
                                        ),
                                      ),
                                      if (it.subtitle != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          it.subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                      // مسافة بسيطة لتجنّب ضغط المحتوى
                                      const SizedBox(height: 6),
                                    ],
                                  ),
                                  PositionedDirectional(
                                    bottom: 6,
                                    end: 6,
                                    child: Icon(
                                      selected ? Icons.check_circle : Icons.circle_outlined,
                                      size: 20,
                                      color: selected
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),

                  // فاصل
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // قسم حجم الخط (قائمة مرتبة بالشيب)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('حجم الخط', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sizes.map((s) {
                              final selected = theme.fontSize == s;
                              return ChoiceChip(
                                label: Text(s),
                                selected: selected,
                                onSelected: (_) => theme.updateFontSize(s),
                                labelStyle: TextStyle(
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                ),
                                selectedColor: Theme.of(context).colorScheme.secondaryContainer,
                                showCheckmark: false,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ThemeItem {
  final AppThemeId id;
  final String title;
  final String? subtitle;
  final List<Color> previewColors;
  const _ThemeItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.previewColors,
  });
}

List<_ThemeItem> _themeItems() => const [
  _ThemeItem(
    id: AppThemeId.systemDefault,
    title: 'افتراضي (حسب النظام)',
    subtitle: 'فاتح/داكن تلقائي',
    previewColors: [Color(0xFF28B4AC), Colors.white, Colors.black],
  ),
  _ThemeItem(
    id: AppThemeId.softBlackLight,
    title: 'أبيض × سواد خفيف',
    subtitle: 'أسلوب نظيف بحدود خفيفة',
    previewColors: [Color(0xFF0F172A), Colors.white, Color(0xFFF5F6F8)],
  ),
  _ThemeItem(
    id: AppThemeId.classicGreen,
    title: 'الأخضر الكلاسيكي',
    previewColors: [Color(0xFF28B4AC), Color(0xFF9FE7E1), Color(0xFF0C4E4A)],
  ),
  _ThemeItem(
    id: AppThemeId.pureBlack,
    title: 'أسود/أبيض',
    previewColors: [Colors.black, Colors.white, Color(0xFF111111)],
  ),
  _ThemeItem(
    id: AppThemeId.redGreen,
    title: 'أحمر × أخضر',
    previewColors: [Color(0xFFE63946), Color(0xFF0A8754), Colors.white],
  ),
  _ThemeItem(
    id: AppThemeId.blueOrange,
    title: 'أزرق × برتقالي',
    previewColors: [Color(0xFF1D4ED8), Color(0xFFF97316), Colors.white],
  ),
  _ThemeItem(
    id: AppThemeId.purpleMint,
    title: 'بنفسجي × نعناع',
    previewColors: [Color(0xFF7C3AED), Color(0xFF10B981), Colors.white],
  ),
  _ThemeItem(
    id: AppThemeId.highContrastLight,
    title: 'تباين عالي (فاتح)',
    previewColors: [Colors.white, Colors.black, Colors.blueGrey],
  ),
  _ThemeItem(
    id: AppThemeId.highContrastDark,
    title: 'تباين عالي (داكن)',
    previewColors: [Colors.black, Colors.white, Colors.amber],
  ),
];

class _ThemePreview extends StatelessWidget {
  final List<Color> colors;
  const _ThemePreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 50,
        child: Row(
          children: colors.map((c) => Expanded(child: ColoredBox(color: c))).toList(growable: false),
        ),
      ),
    );
  }
}

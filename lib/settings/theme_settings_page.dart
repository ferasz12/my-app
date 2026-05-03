// UPDATED: صفحة اختيار المظهر — بطاقات فخمة + معاينة محسّنة + قسم حجم الخط
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import '../providers/theme_provider.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final items = _themeItems();

    final scale = MediaQuery.textScaleFactorOf(context);
    final sizes = const ['صغير', 'متوسط', 'كبير', 'كبير جدًا'];
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('المظهر')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;

              // أعمدة الشبكة حسب العرض
              final cols = w >= 920 ? 4 : (w >= 700 ? 3 : 2);

              // ارتفاع بطاقة مرن مع تكبير الخط (نتجنّب Overflow)
              const baseH = 156.0;
              final tileH = baseH * (scale > 1.10 ? (1.0 + (scale - 1.10) * 0.75) : 1.0);
              const spacing = 12.0;
              final tileW = (w - 32 - spacing * (cols - 1)) / cols; // 32 = Padding أفقي
              final ratio = tileW / tileH;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: _HeaderCard(
                        title: 'اختَر مظهر يناسب يومك',
                        subtitle: 'مظهر وازن الأصلي هو الافتراضي عند الدخول، وباقي المظاهر اختيارية لتجربة صحية أفخم.',
                        icon: Icons.spa_rounded,
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
                          return _ThemeTile(
                            item: it,
                            selected: selected,
                            onTap: () { _handleThemeTap(context, theme, it); },
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 18)),

                  // قسم حجم الخط
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'حجم الخط',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
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
                                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                ),
                                selectedColor: cs.secondaryContainer.withOpacity(0.90),
                                showCheckmark: false,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),
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

  Future<void> _handleThemeTap(BuildContext context, ThemeProvider theme, _ThemeItem it) async {
    if (it.premium) {
      final ok = await PremiumAccess.ensureSubscribed(context, feature: PremiumFeature.theme);
      if (!ok) return;
    }
    await theme.setTheme(it.id);
  }

}

class _ThemeItem {
  final AppThemeId id;
  final String title;
  final String? subtitle;
  final List<Color> previewColors;
  final IconData icon;
  final String? badge;
  final bool premium;

  const _ThemeItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.previewColors,
    required this.icon,
    this.badge,
    this.premium = false,
  });
}

List<_ThemeItem> _themeItems() => const [
      _ThemeItem(
        id: AppThemeId.systemDefault,
        title: 'افتراضي (حسب النظام)',
        subtitle: 'فاتح/داكن تلقائي',
        icon: Icons.settings_suggest_rounded,
        previewColors: [Color(0xFF28B4AC), Color(0xFF0A3D62), Colors.white],
      ),
      _ThemeItem(
        id: AppThemeId.classicGreen,
        title: 'مظهر وازن',
        subtitle: 'المظهر الأصلي للتطبيق',
        icon: Icons.spa_rounded,
        badge: 'الأصلي',
        previewColors: [Color(0xFF28B4AC), Color(0xFF9FE7E1), Color(0xFFF6F8FA)],
      ),
      _ThemeItem(
        id: AppThemeId.softBlackLight,
        title: 'بورسلين فاخر',
        subtitle: 'أبيض مطفي + نعناع',
                premium: true,
        icon: Icons.auto_awesome_rounded,
        previewColors: [Color(0xFF0F172A), Color(0xFF28B4AC), Colors.white],
      ),
      _ThemeItem(
        id: AppThemeId.pureBlack,
        title: 'منتصف الليل',
        subtitle: 'داكن فاخر + نعناع',
                premium: true,
        icon: Icons.nightlight_round,
        previewColors: [Color(0xFF28B4AC), Color(0xFF070A0D), Color(0xFF0E141A)],
      ),
      _ThemeItem(
        id: AppThemeId.redGreen,
        title: 'ورد × نعناع',
        subtitle: 'تحفيز لطيف',
                premium: true,
        icon: Icons.favorite_rounded,
        previewColors: [Color(0xFF0B6E4F), Color(0xFFE35D6A), Colors.white],
      ),
      _ThemeItem(
        id: AppThemeId.blueOrange,
        title: 'محيط × شروق',
        subtitle: 'طاقة بدون حِدة',
                premium: true,
        icon: Icons.waves_rounded,
        previewColors: [Color(0xFF0B4F6C), Color(0xFFF59E0B), Colors.white],
      ),
      _ThemeItem(
        id: AppThemeId.purpleMint,
        title: 'لافندر × نعناع',
        subtitle: 'هدوء وتركيز',
                premium: true,
        icon: Icons.psychology_alt_rounded,
        previewColors: [Color(0xFF5B21B6), Color(0xFF2DD4BF), Colors.white],
      ),
      _ThemeItem(
        id: AppThemeId.highContrastLight,
        title: 'تباين عالي (فاتح)',
        subtitle: 'وضوح أكثر',
                premium: true,
        icon: Icons.visibility_rounded,
        previewColors: [Colors.white, Colors.black, Color(0xFFCBD5E1)],
      ),
      _ThemeItem(
        id: AppThemeId.highContrastDark,
        title: 'تباين عالي (داكن)',
        subtitle: 'وضوح أكثر',
                premium: true,
        icon: Icons.visibility_rounded,
        previewColors: [Colors.black, Colors.white, Color(0xFFF59E0B)],
      ),
    ];

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final border = cs.outlineVariant.withOpacity(isDark ? 0.22 : 0.70);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withOpacity(isDark ? 0.20 : 0.12),
            cs.secondary.withOpacity(isDark ? 0.18 : 0.10),
            cs.tertiary.withOpacity(isDark ? 0.14 : 0.08),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final _ThemeItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final borderColor = selected ? cs.primary : cs.outlineVariant.withOpacity(isDark ? 0.35 : 0.70);
    final shadow = Colors.black.withOpacity(isDark ? 0.35 : 0.10);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: selected ? 2.0 : 1.2),
        boxShadow: [
          BoxShadow(
            color: shadow,
            blurRadius: selected ? 18 : 12,
            offset: Offset(0, selected ? 8 : 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(isDark ? 0.20 : 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(item.icon, size: 18, color: cs.primary),
                        ),
                        const Spacer(),
                        Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          size: 20,
                          color: selected ? cs.primary : cs.outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ThemePreview(colors: item.previewColors),
                    const SizedBox(height: 10),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: cs.onSurface,
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.premium)
                  const PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: _BadgePill(text: 'VIP'),
                  ),
                if (item.badge != null)
                  PositionedDirectional(
                    top: 6,
                    start: 6,
                    child: _BadgePill(text: item.badge!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  const _BadgePill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(isDark ? 0.35 : 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  final List<Color> colors;
  const _ThemePreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    final primary = colors.isNotEmpty ? colors[0] : Theme.of(context).colorScheme.primary;
    final accent = colors.length > 1 ? colors[1] : primary;
    final surface = colors.length > 2 ? colors[2] : Theme.of(context).colorScheme.surface;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadow = Colors.black.withOpacity(isDark ? 0.45 : 0.14);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    primary.withOpacity(0.95),
                    accent.withOpacity(0.90),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            PositionedDirectional(
              start: 10,
              end: 10,
              top: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: shadow,
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 9,
                      width: 58,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          height: 10,
                          width: 34,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.24),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

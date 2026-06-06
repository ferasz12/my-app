import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({
    super.key,
    this.fromUpdatePrompt = false,
    this.versionLabel,
  });

  final bool fromUpdatePrompt;
  final String? versionLabel;

  static const List<_ReleaseHighlight> _latestHighlights = [
    _ReleaseHighlight(
      title: 'تحسين تجربة الاستخدام',
      body:
          'تحسينات على الواجهات وتجربة الدخول لتكون رحلة المستخدم أوضح وأسهل.',
    ),
    _ReleaseHighlight(
      title: 'تحسين بياناتك الصحية',
      body:
          'تحسينات على صفحة البيانات والخطة لعرض الوزن والطول والهدف بشكل أوضح.',
    ),
    _ReleaseHighlight(
      title: 'تحسينات التتبع اليومي',
      body:
          'تحسينات تساعد على متابعة السعرات والماكروز والبيانات اليومية بشكل أكثر تنظيمًا.',
    ),
    _ReleaseHighlight(
      title: 'مجتمع وازن',
      body: 'تم إطلاق مجتمع وازن لمشاركة الأسئلة، المعلومات، الوصفات، التجارب والإنجازات.',
    ),
    _ReleaseHighlight(
      title: 'المزامنة السحابية',
      body: 'إمكانية حفظ واسترجاع البيانات المهمة من السحابة للمشتركين.',
    ),
    _ReleaseHighlight(
      title: 'تبويب صحتي',
      body: 'عرض بيانات النشاط، النوم، المسافة، نبض الراحة ودقائق التمرين عند توفرها من تطبيق الصحة.',
    ),
  ];

  static const List<_ReleaseHistoryItem> _history = [
    _ReleaseHistoryItem(
      version: 'v1.2.0',
      title: 'إضافة المطاعم والمقاهي',
      body: 'تقدر تستعرض خيارات جاهزة من مطاعم ومقاهي وتضيفها ليومك بسهولة.',
    ),
    _ReleaseHistoryItem(
      version: 'v1.1.0',
      title: 'تحسين واجهة المستخدم',
      body: 'تحسينات عامة على شكل التطبيق وترتيب الصفحات.',
    ),
    _ReleaseHistoryItem(
      version: 'v1.0.0',
      title: 'إطلاق وازن',
      body: 'تفعيل الدخول عبر Apple وبداية تجربة وازن الأساسية.',
    ),
  ];

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final primary = cs.primary;
    final surface = isDark ? cs.surface : Colors.white;
    final bgTop = _mix(surface, primary, isDark ? 0.16 : 0.07);
    final bgBottom = _mix(surface, primary, isDark ? 0.30 : 0.22);
    final readableVersion = (versionLabel ?? '').trim();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('ما الجديد'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, _mix(bgTop, bgBottom, 0.55), bgBottom],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                _HeroCard(
                  primary: primary,
                  isDark: isDark,
                  versionLabel:
                      readableVersion.isEmpty ? null : readableVersion,
                  title: 'ما الجديد في وازن',
                  subtitle:
                      'تحديثات جديدة لتحسين المتابعة اليومية وتجربة الاستخدام داخل وازن.',
                ),
                const SizedBox(height: 16),
                Text(
                  'أبرز الجديد',
                  style: (tt.titleLarge ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                ..._latestHighlights.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HighlightTile(
                      item: item,
                      primary: primary,
                      isDark: isDark,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (fromUpdatePrompt) ...[
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('متابعة'),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        textStyle:
                            (tt.titleMedium ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(
                    'تحديثات سابقة',
                    style: (tt.titleLarge ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._history.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HistoryTile(item: item, primary: primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.primary,
    required this.isDark,
    required this.title,
    required this.subtitle,
    this.versionLabel,
  });

  final Color primary;
  final bool isDark;
  final String title;
  final String subtitle;
  final String? versionLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                cs.surface.withOpacity(isDark ? 0.58 : 0.86),
                primary.withOpacity(isDark ? 0.14 : 0.08),
              ],
            ),
            border:
                Border.all(color: primary.withOpacity(isDark ? 0.18 : 0.13)),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(isDark ? 0.16 : 0.12),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 5,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.26),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: (tt.headlineSmall ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  if (versionLabel != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: primary.withOpacity(0.18)),
                      ),
                      child: Text(
                        versionLabel!,
                        style: (tt.bodySmall ?? const TextStyle()).copyWith(
                          color: primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                subtitle,
                style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                  color: cs.onSurface.withOpacity(0.66),
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile(
      {required this.item, required this.primary, required this.isDark});

  final _ReleaseHighlight item;
  final Color primary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.70 : 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primary.withOpacity(isDark ? 0.16 : 0.11)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 56,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.72),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: (tt.titleMedium ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.body,
                  style: (tt.bodySmall ?? const TextStyle()).copyWith(
                    color: cs.onSurface.withOpacity(0.62),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.primary});

  final _ReleaseHistoryItem item;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.version,
              style: (tt.bodySmall ?? const TextStyle()).copyWith(
                color: primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: (tt.titleSmall ?? const TextStyle())
                        .copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: (tt.bodySmall ?? const TextStyle()).copyWith(
                    color: cs.onSurface.withOpacity(0.58),
                    height: 1.42,
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

class _ReleaseHighlight {
  const _ReleaseHighlight({required this.title, required this.body});

  final String title;
  final String body;
}

class _ReleaseHistoryItem {
  const _ReleaseHistoryItem(
      {required this.version, required this.title, required this.body});

  final String version;
  final String title;
  final String body;
}

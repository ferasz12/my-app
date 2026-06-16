import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../shared/wazen_coach_avatar.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({
    super.key,
    this.fromUpdatePrompt = false,
    this.versionLabel,
  });

  /// true لما الصفحة تنفتح تلقائيًا بعد تحديث التطبيق.
  /// false لما تنفتح من الإعدادات > ما الجديد.
  final bool fromUpdatePrompt;
  final String? versionLabel;

  // ✅ عدّل هذا القسم فقط مع كل تحديث جديد في وازن.
  // خله مختصر وواضح للمستخدم: وش تحسّن؟ وش انضاف؟ وش صار أذكى؟
  static const List<_ReleaseHighlight> _latestHighlights = [
    _ReleaseHighlight(
      title: 'مدرب وازن الذكي صار أذكى',
      body:
          'صار يفهم أسئلتك عن أكلك ووصفاتك وجدولك بشكل أفضل، ويرد عليك بشكل أوضح وأسرع.',
    ),
    _ReleaseHighlight(
      title: 'تطوير واجهة المستخحدم',
      body: ' تم تحسين تجربة المستخدم ليصبح التنقل عبر الشاشات سهل وسلس',
    ),
    _ReleaseHighlight(
      title: 'اقتراح وصفات بشكل أذكى',
      body:
          'مدرب وازن صار يقدر يرشح لك وصفات من وصفات وازن، أو يسوي لك وصفة جديدة عند الطلب فقط.',
    ),
    _ReleaseHighlight(
      title: 'إنشاء جدول تمارين وحفظه لك',
      body:
          'تحسينات على جداول التمارين بحيث يقدر المدرب ينشئ لك جدولًا ويجهزه لك داخل صفحة الجداول بشكل أفضل.',
    ),
    _ReleaseHighlight(
      title: 'بحث جديد في استكشاف الوصفات',
      body: 'أضفنا بحث في صفحة استكشاف الوصفات .',
    ),
    _ReleaseHighlight(
      title: '  صار يمديك تضيف أكلك في اليوم الي قبله  ',
      body:
          '  الان صار يمديك تضيف أكلك بالايام الي فاتتك وترجع تقفل اليوم نفسه وتحفظه .',
    ),
  ];

  static const List<_ReleaseHistoryItem> _history = [
    _ReleaseHistoryItem(
      version: 'هذا التحديث',
      title: 'تطويرات كبيرة على مدرب وازن الذكي',
      body:
          'شملت تحسين فهم الأسئلة، اقتراح الوصفات، تحديث البيانات، وتحسين تجربة الجداول والماكروز.',
    ),
    _ReleaseHistoryItem(
      version: 'v1.2.0',
      title: ' المطاعم والمقاهي',
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
      body: 'بداية تجربة وازن الأساسية وتتبع السعرات والماكروز.',
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
          title: Text(fromUpdatePrompt ? 'وش الجديد؟' : 'ما الجديد'),
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
                  title: 'وش الجديد في وازن؟',
                  subtitle:
                      'في هذا التحديث ركزنا على مدرب وازن الذكي، الوصفات، والجداول، مع تحسينات تخلي رحلتك الصحية أذكى وأسهل.',
                ),
                const SizedBox(height: 16),
                _CoachSpotlightCard(primary: primary, isDark: isDark),
                const SizedBox(height: 18),
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
                      child: const Text('تمام، خلني أبدأ'),
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

class _CoachSpotlightCard extends StatelessWidget {
  const _CoachSpotlightCard({required this.primary, required this.isDark});

  final Color primary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(isDark ? 0.72 : 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: primary.withOpacity(isDark ? 0.18 : 0.11)),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(isDark ? 0.14 : 0.09),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: primary.withOpacity(0.08),
            ),
            alignment: Alignment.center,
            child: const WazenCoachAvatar(
              size: 76,
              headOnly: false,
              withCircle: false,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ' مين مدرب وازن الذكي ؟ ',
                  style: (tt.titleLarge ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '  مدرب وازن صار يساعدك على تحقيق هدفك بطريقة أسهل  .',
                  style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                    height: 1.5,
                    color: cs.onSurface.withOpacity(0.74),
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

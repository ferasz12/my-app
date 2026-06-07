// lib/screens/achievements_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Helper موحّد لقراءة نقاط المستخدم.
int readUserPoints(Map<String, dynamic>? data) {
  if (data == null) return 0;

  // 1) المصدر الأساسي
  final root = data['points_total'];
  if (root is num) return root.toInt();
  if (root is String) return int.tryParse(root) ?? 0;

  // 2) بديل قديم
  final stats = data['stats'];
  if (stats is Map) {
    final sp = stats['points'];
    if (sp is num) return sp.toInt();
    if (sp is String) return int.tryParse(sp) ?? 0;
  }

  return 0;
}

/// ===== نموذج إنجاز: لقب + شارة (إيموجي) =====
class Achievement {
  final String id;
  final int pointsRequired;
  final String titleName; // اسم اللقب
  final String emoji;     // الإيموجي/الشارة
  final String description;
  final IconData icon;

  const Achievement({
    required this.id,
    required this.pointsRequired,
    required this.titleName,
    required this.emoji,
    required this.description,
    this.icon = Icons.emoji_events,
  });
}

/// ===== الألقاب/الشارات حتى 1000 نقطة =====
const kAchievements = <Achievement>[
  Achievement(
    id: 'rank_bronze',
    pointsRequired: 100,
    titleName: 'برونزي',
    emoji: '🥉',
    description: 'لقب برونزي + شارة برونزية.',
    icon: Icons.military_tech,
  ),
  Achievement(
    id: 'rank_silver',
    pointsRequired: 200,
    titleName: 'فضّي',
    emoji: '🥈',
    description: 'لقب فضّي + شارة فضّية.',
    icon: Icons.military_tech,
  ),
  Achievement(
    id: 'rank_gold',
    pointsRequired: 300,
    titleName: 'ذهبي',
    emoji: '🥇',
    description: 'لقب ذهبي + شارة ذهبية.',
    icon: Icons.military_tech,
  ),
  Achievement(
    id: 'rank_platinum',
    pointsRequired: 400,
    titleName: 'بلاتيني',
    emoji: '💎',
    description: 'لقب بلاتيني + شارة ماسية.',
    icon: Icons.diamond,
  ),
  Achievement(
    id: 'rank_master',
    pointsRequired: 500,
    titleName: 'ماستر',
    emoji: '🏆',
    description: 'لقب ماستر + كأس.',
    icon: Icons.emoji_events,
  ),
  Achievement(
    id: 'rank_600',
    pointsRequired: 600,
    titleName: 'أسطوري I',
    emoji: '🔥',
    description: 'ارتقاء إلى أسطوري المستوى الأول.',
    icon: Icons.local_fire_department,
  ),
  Achievement(
    id: 'rank_700',
    pointsRequired: 700,
    titleName: 'أسطوري II',
    emoji: '💠',
    description: 'أسطوري المستوى الثاني.',
    icon: Icons.workspace_premium,
  ),
  Achievement(
    id: 'rank_800',
    pointsRequired: 800,
    titleName: 'نخبة',
    emoji: '⭐',
    description: 'وصلت مستوى النخبة.',
    icon: Icons.star,
  ),
  Achievement(
    id: 'rank_900',
    pointsRequired: 900,
    titleName: 'جراند ماستر',
    emoji: '🧠',
    description: 'ترتيب جراند ماستر.',
    icon: Icons.psychology_alt,
  ),
  Achievement(
    id: 'rank_1000',
    pointsRequired: 1000,
    titleName: 'معضل',
    emoji: '👑',
    description: 'أعلى لقب — البطل!',
    icon: Icons.workspace_premium_outlined,
  ),
];

/// ===== تخزين على Firestore (ألقاب/شارات فقط) =====
class AchievementsStore {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  /// نستخدم وثيقة واحدة داخل subcollection (عشان ما تنكسر الـ Rules التي تمنع تعديل points_total في root)
  /// users/{uid}/achievements/totals
  static DocumentReference<Map<String, dynamic>> _ref() {
    final uid = _uid;
    final base = _db.collection('users').doc(uid ?? '_guest_');
    return base.collection('achievements').doc('totals');
  }

  static Future<void> _ensureDoc() async {
    final ref = _ref();
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'points_total': 0,
        'achievements': {
          'claimed': <String>[],
          'badgeEmojis': <String>[],
          'title': '',
          'season': 1,
        },
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }
  }

  /// بث مباشر لتغيرات المستخدم (من totals)
  static Stream<Map<String, dynamic>> watchMe() async* {
    await _ensureDoc();
    yield* _ref().snapshots().map((s) => s.data() ?? <String, dynamic>{});
  }

  static Future<int> getPoints() async {
    await _ensureDoc();
    final s = await _ref().get();
    final m = s.data() ?? {};
    return (m['points_total'] as num?)?.toInt() ?? 0;
  }

  static Future<void> addPoints(int delta) async {
    if (delta == 0) return;
    await _ensureDoc();
    await _db.runTransaction((tx) async {
      final ref = _ref();
      final snap = await tx.get(ref);
      final cur = ((snap.data()?['points_total']) as num?)?.toInt() ?? 0;
      final next = (cur + delta).clamp(0, 100000000);
      tx.set(ref, {
        'points_total': next,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    });
  }

  static Future<Set<String>> claimed() async {
    await _ensureDoc();
    final s = await _ref().get();
    final m = s.data() ?? {};
    final ach = (m['achievements'] as Map<String, dynamic>?) ?? const {};
    final cl = (ach['claimed'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return cl.toSet();
  }

  /// يضيف إنجاز: union على claimed و badgeEmojis + يحدّث أعلى لقب title
  static Future<void> markClaimedWithBadge(Achievement a, {required int currentPoints}) async {
    await _ensureDoc();

    // حدّد أعلى لقب بحسب نقاطك الحالية
    String bestTitle = '';
    for (final ach in kAchievements) {
      if (currentPoints >= ach.pointsRequired) {
        bestTitle = ach.titleName;
      }
    }

    await _ref().set({
      'achievements': {
        'claimed': FieldValue.arrayUnion([a.id]),
        'badgeEmojis': FieldValue.arrayUnion([a.emoji]),
        'title': bestTitle,
      },
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  /// تصفير النقاط وبداية موسم جديد
  static Future<void> resetProgress() async {
    await _ensureDoc();
    await _db.runTransaction((tx) async {
      final ref = _ref();
      final snap = await tx.get(ref);
      final ach = (snap.data()?['achievements'] as Map<String, dynamic>?) ?? {};
      final season = (ach['season'] as num?)?.toInt() ?? 1;

      tx.set(ref, {
        'points_total': 0,
        'achievements': {
          'claimed': <String>[],
          'badgeEmojis': <String>[],
          'title': '',
          'season': season + 1,
        },
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    });
  }
}

/// ===== صفحة الإنجازات (UI) =====
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  int points = 0;
  Set<String> claimedIds = {};
  String currentTitle = '';
  List<String> badgeEmojis = [];

  // زر تجريبي لإضافة نقاط — غيّره لـ false بالإنتاج
  static const bool _showDebugAddPoints = true;

  StreamSubscription? _subDoc;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _subDoc?.cancel();
    super.dispose();
  }

  Future<void> _subscribe() async {
    _subDoc?.cancel();
    _subDoc = AchievementsStore.watchMe().listen((m) {
      final pts = (m['points_total'] as num?)?.toInt() ?? 0;
      final ach = (m['achievements'] as Map<String, dynamic>?) ?? const {};
      final cl = (ach['claimed'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
      final title = (ach['title'] ?? '').toString();
      final badges = (ach['badgeEmojis'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

      setState(() {
        points = pts;
        claimedIds = cl;
        currentTitle = title;
        badgeEmojis = badges;
      });
    });
  }

  Future<void> _reloadOnce() async {
    final pts = await AchievementsStore.getPoints();
    final cl = await AchievementsStore.claimed();
    if (!mounted) return;
    setState(() {
      points = pts;
      claimedIds = cl;
    });
  }

  Future<void> _claim(Achievement a) async {
    final unlocked = points >= a.pointsRequired;
    final already = claimedIds.contains(a.id);
    if (!unlocked || already) return;

    await AchievementsStore.markClaimedWithBadge(a, currentPoints: points);

    // تحقق إن كانت كل الإنجازات مُطالب بها
    final claimedAfter = await AchievementsStore.claimed();
    final allClaimed = kAchievements.every((x) => claimedAfter.contains(x.id));
    if (allClaimed) {
      await AchievementsStore.resetProgress();
      await _reloadOnce();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مبروك! خلّصت كل الألقاب 🎉 تم تصفير النقاط وبدأ موسم جديد.')),
      );
      return;
    }

    await _reloadOnce();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم فتح اللقب: ${a.titleName} ${a.emoji}')),
    );
  }

  Future<void> _debugAddPoints() async {
    await AchievementsStore.addPoints(100); // +100 نقطة للتجربة
    await _reloadOnce();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final next = kAchievements
        .where((a) => a.pointsRequired > points)
        .fold<int?>(null, (min, a) => min == null ? a.pointsRequired : (a.pointsRequired < min ? a.pointsRequired : min));
    final target = next ?? (kAchievements.isEmpty ? 0 : kAchievements.last.pointsRequired);
    final progress = target == 0 ? 1.0 : (points / target).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('الإنجازات')),
      floatingActionButton: _showDebugAddPoints
          ? FloatingActionButton.extended(
              onPressed: _debugAddPoints,
              icon: const Icon(Icons.add),
              label: const Text('+100 نقطة'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _reloadOnce,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // بطاقة رأس — نقاط + اللقب الحالي + شاراتك
            Card(
              color: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نقاطك الحالية', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('$points', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Icon(Icons.bolt, color: cs.primary),
                        const Spacer(),
                        if (currentTitle.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.workspace_premium_outlined),
                              const SizedBox(width: 6),
                              Text('لقبك: $currentTitle'),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: cs.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      next == null ? 'فتحت كل الألقاب، أحسنت! 🎉' : 'المتبقي للقب التالي: ${target - points} نقطة',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (badgeEmojis.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8, runSpacing: 8, children: badgeEmojis.map((e) => _badgeChip(e, context)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // قائمة الإنجازات/الألقاب
            ...kAchievements.map((a) {
              final unlocked = points >= a.pointsRequired;
              final already = claimedIds.contains(a.id);
              final canClaim = unlocked && !already;

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0.5,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: unlocked ? cs.primaryContainer : cs.surfaceContainerHighest,
                    child: Text(a.emoji, style: const TextStyle(fontSize: 18)),
                  ),
                  title: Text('${a.titleName} ${a.emoji}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text('${a.description}\nيتطلب: ${a.pointsRequired} نقطة', style: theme.textTheme.bodySmall),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    onPressed: canClaim ? () => _claim(a) : null,
                    child: Text(already ? 'مُطالَب' : (unlocked ? 'مطالبة' : 'مغلق')),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _badgeChip(String emoji, BuildContext context) {
    return Chip(
      label: Text(emoji, style: const TextStyle(fontSize: 16)),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6),
    );
  }
}

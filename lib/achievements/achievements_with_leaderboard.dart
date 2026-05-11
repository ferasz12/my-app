// lib/achievements/achievements_with_leaderboard.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// يفتح بروفايل المستخدم الجديد (بدون مجتمع)
import 'package:my_app/features/users/ui/user_profile_page.dart';

/// Helper موحّد لقراءة نقاط المستخدم.
/// ✅ يدعم الحقول الشائعة كلها: points_total, stats.points, points, pointsTotal
int readUserPoints(Map<String, dynamic>? data) {
  if (data == null) return 0;

  final dynamic v = data['points_total'] ??
      (data['stats'] is Map ? (data['stats']['points']) : null) ??
      data['points'] ??
      data['pointsTotal'];

  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// هل المستخدم مخفي من قائمة المتسابقين؟ (خيار خصوصية)
/// ندعم أكثر من حقل للتوافق.
bool isLeaderboardHidden(Map<String, dynamic>? data) {
  if (data == null) return false;

  final v1 = data['leaderboardHidden'];
  if (v1 is bool) return v1;

  final privacy = data['privacy'];
  if (privacy is Map) {
    final v2 = privacy['hideFromLeaderboard'] ??
        privacy['leaderboardHidden'] ??
        privacy['hideLeaderboard'];
    if (v2 is bool) return v2;
  }

  return false;
}

String _readUserDisplayName(Map<String, dynamic>? data, String uid) {
  if (data == null) return 'مستخدم وازن';
  final raw = data['name'] ??
      data['displayName'] ??
      data['fullName'] ??
      data['username'] ??
      (data['profile'] is Map ? (data['profile'] as Map)['name'] : null) ??
      (data['profile'] is Map ? (data['profile'] as Map)['displayName'] : null);
  final name = raw?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;

  final email = data['email']?.toString().trim() ?? '';
  if (email.isNotEmpty && email.contains('@')) return email.split('@').first;

  if (uid.length >= 6) return 'مستخدم ${uid.substring(0, 6)}';
  return 'مستخدم وازن';
}

String _readUserPhoto(Map<String, dynamic>? data) {
  if (data == null) return '';
  final raw = data['photoUrl'] ??
      data['photoURL'] ??
      data['avatarUrl'] ??
      data['image'] ??
      (data['profile'] is Map ? (data['profile'] as Map)['photoUrl'] : null) ??
      (data['profile'] is Map ? (data['profile'] as Map)['avatarUrl'] : null);
  return raw?.toString().trim() ?? '';
}

String _readAchievementTitle(Map<String, dynamic>? data) {
  final achievements = data?['achievements'];
  if (achievements is Map) {
    return achievements['title']?.toString().trim() ?? '';
  }
  return '';
}

List<String> _readBadgeEmojis(Map<String, dynamic>? data) {
  final achievements = data?['achievements'];
  if (achievements is! Map) return const <String>[];
  final raw = achievements['badgeEmojis'];
  if (raw is! List) return const <String>[];
  return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
}

/// =======================
/// نماذج/مستودع البيانات
/// =======================

class LeaderboardEntry {
  final String uid;
  final int points;
  final String displayName;
  final String photoUrl;
  final String title;
  final List<String> badgeEmojis;

  const LeaderboardEntry({
    required this.uid,
    required this.points,
    required this.displayName,
    required this.photoUrl,
    required this.title,
    required this.badgeEmojis,
  });
}

class AchievementDef {
  final String id;
  final int pointsRequired;
  final String titleName; // اسم اللقب (يُخزن كأعلى لقب)
  final String emoji; // شارة/إيموجي يُضاف للقائمة
  final String description;
  final IconData icon;

  const AchievementDef({
    required this.id,
    required this.pointsRequired,
    required this.titleName,
    required this.emoji,
    required this.description,
    this.icon = Icons.emoji_events,
  });
}

/// الألقاب/الشارات حتى 1000 نقطة
const List<AchievementDef> kDefs = [
  AchievementDef(
    id: 'rank_bronze',
    pointsRequired: 100,
    titleName: 'برونزي',
    emoji: '🥉',
    description: 'أول وسام في رحلة الالتزام داخل وازن.',
    icon: Icons.military_tech,
  ),
  AchievementDef(
    id: 'rank_silver',
    pointsRequired: 200,
    titleName: 'فضّي',
    emoji: '🥈',
    description: 'استمرار ممتاز وتقدم واضح في النقاط.',
    icon: Icons.military_tech,
  ),
  AchievementDef(
    id: 'rank_gold',
    pointsRequired: 300,
    titleName: 'ذهبي',
    emoji: '🥇',
    description: 'دخلت مستوى المنافسين الجادين.',
    icon: Icons.military_tech,
  ),
  AchievementDef(
    id: 'rank_platinum',
    pointsRequired: 400,
    titleName: 'بلاتيني',
    emoji: '💎',
    description: 'التزامك صار ثابت وواضح.',
    icon: Icons.diamond,
  ),
  AchievementDef(
    id: 'rank_master',
    pointsRequired: 500,
    titleName: 'ماستر',
    emoji: '🏆',
    description: 'وصلت مرحلة قوية من الاستمرارية.',
    icon: Icons.emoji_events,
  ),
  AchievementDef(
    id: 'rank_600',
    pointsRequired: 600,
    titleName: 'أسطوري I',
    emoji: '🔥',
    description: 'مستوى أسطوري أول، كمل بنفس القوة.',
    icon: Icons.local_fire_department,
  ),
  AchievementDef(
    id: 'rank_700',
    pointsRequired: 700,
    titleName: 'أسطوري II',
    emoji: '💠',
    description: 'منافس قوي في قائمة وازن.',
    icon: Icons.workspace_premium,
  ),
  AchievementDef(
    id: 'rank_800',
    pointsRequired: 800,
    titleName: 'نخبة',
    emoji: '⭐',
    description: 'وصلت مستوى النخبة في الالتزام.',
    icon: Icons.star,
  ),
  AchievementDef(
    id: 'rank_900',
    pointsRequired: 900,
    titleName: 'جراند ماستر',
    emoji: '🧠',
    description: 'تحكم عالي في العادات اليومية.',
    icon: Icons.psychology_alt,
  ),
  AchievementDef(
    id: 'rank_1000',
    pointsRequired: 1000,
    titleName: 'تشامبيون',
    emoji: '👑',
    description: 'أعلى لقب — بطل وازن!',
    icon: Icons.workspace_premium_outlined,
  ),
];

/// مخطط Firestore المستخدم هنا:
/// users/{uid}
///   points_total: number
///   stats.points: number (اختياري/قديم)
///   achievements: { claimed: [ids...], badgeEmojis: [emoji...], title: String, season: int }
class AchievementsRepo {
  final _db = FirebaseFirestore.instance;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMe(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  Query<Map<String, dynamic>> _leaderboardQuery({
    required int visibleLimit,
    required int fetchLimit,
  }) {
    final serverLimit = fetchLimit < visibleLimit ? visibleLimit : fetchLimit;
    return _db
        .collection('users')
        .orderBy('points_total', descending: true)
        .limit(serverLimit);
  }

  List<LeaderboardEntry> _mapLeaderboardDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required int visibleLimit,
  }) {
    final out = <LeaderboardEntry>[];

    for (final d in docs) {
      final m = d.data();
      final pts = readUserPoints(m);
      if (pts <= 0) continue;
      if (isLeaderboardHidden(m)) continue;

      out.add(
        LeaderboardEntry(
          uid: d.id,
          points: pts,
          displayName: _readUserDisplayName(m, d.id),
          photoUrl: _readUserPhoto(m),
          title: _readAchievementTitle(m),
          badgeEmojis: _readBadgeEmojis(m),
        ),
      );

      if (out.length >= visibleLimit) break;
    }

    return out;
  }

  /// ✅ قائمة المتسابقين:
  /// - نعرض أول 100 فقط (بعد تطبيق خيار الإخفاء).
  /// - نقرأ الاسم والصورة واللقب من نفس مستند المستخدم، بدون طلبات إضافية لكل لاعب.
  Stream<List<LeaderboardEntry>> watchLeaderboard({
    int visibleLimit = 100,
    int fetchLimit = 300,
  }) {
    return _leaderboardQuery(
      visibleLimit: visibleLimit,
      fetchLimit: fetchLimit,
    ).snapshots().map((qs) {
      return _mapLeaderboardDocs(qs.docs, visibleLimit: visibleLimit);
    });
  }

  Future<List<LeaderboardEntry>> fetchLeaderboardOnce({
    int visibleLimit = 100,
    int fetchLimit = 300,
  }) async {
    final qs = await _leaderboardQuery(
      visibleLimit: visibleLimit,
      fetchLimit: fetchLimit,
    ).get();
    return _mapLeaderboardDocs(qs.docs, visibleLimit: visibleLimit);
  }

  Future<void> setLeaderboardHidden({
    required String uid,
    required bool hidden,
  }) async {
    await _db.collection('users').doc(uid).set(
      {
        'leaderboardHidden': hidden,
        'privacy.hideFromLeaderboard': hidden,
        'updatedAt': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// ✅ إضافة نقاط مع تحديث كل الحقول الشائعة للتوافق (قديم/جديد)
  Future<void> addPoints(String uid, int delta) async {
    if (delta == 0) return;
    await _db.collection('users').doc(uid).set(
      {
        'points_total': FieldValue.increment(delta),
        'stats': {'points': FieldValue.increment(delta)},
        // توافق قديم:
        'points': FieldValue.increment(delta),
        'pointsTotal': FieldValue.increment(delta),
        'updatedAt': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// المطالبة بإنجاز: تضيف id + الإيموجي + تحدّث أعلى لقب.
  Future<void> claimAchievementWithBadge({
    required String uid,
    required AchievementDef def,
  }) async {
    final doc = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(doc);
      final data = snap.data() ?? <String, dynamic>{};
      final points = readUserPoints(data);

      final achievements = Map<String, dynamic>.from(data['achievements'] ?? const {});
      final claimed = List<String>.from(achievements['claimed'] ?? const <String>[]);
      final emojis = List<String>.from(achievements['badgeEmojis'] ?? const <String>[]);

      if (claimed.contains(def.id)) return; // سبق وطالب بها
      if (points < def.pointsRequired) return; // ما فتحها بعد

      claimed.add(def.id);
      if (!emojis.contains(def.emoji)) emojis.add(def.emoji);

      // احسب أعلى لقب حالياً بناءً على النقاط
      String bestTitle = '';
      for (final a in kDefs) {
        if (points >= a.pointsRequired) bestTitle = a.titleName;
      }

      tx.set(
        doc,
        {
          'achievements': {
            'claimed': claimed,
            'badgeEmojis': emojis,
            'title': bestTitle,
          },
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );
    });
  }
}

/// =======================
/// واجهة المستخدم
/// =======================

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage>
    with SingleTickerProviderStateMixin {
  final _repo = AchievementsRepo();
  String? _uid;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    _uid = u?.uid;
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: const Text('الإنجازات'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: cs.primary,
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  labelColor: cs.onPrimary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  tabs: const [
                    Tab(icon: Icon(Icons.stars_rounded, size: 20), text: 'إنجازاتي'),
                    Tab(icon: Icon(Icons.emoji_events_rounded, size: 20), text: 'المتسابقين'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MyAchievementsTab(uid: _uid!, repo: _repo),
            _LeaderboardTab(uid: _uid!, repo: _repo),
          ],
        ),
      ),
    );
  }
}

/// تبويب "إنجازاتي"
class _MyAchievementsTab extends StatelessWidget {
  final String uid;
  final AchievementsRepo repo;

  const _MyAchievementsTab({required this.uid, required this.repo});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchMe(uid),
      builder: (context, snap) {
        final m = snap.data?.data() ?? const <String, dynamic>{};
        final points = readUserPoints(m);
        final isFirstLoad = snap.connectionState == ConnectionState.waiting && !snap.hasData;

        final ach = (m['achievements'] as Map<String, dynamic>?) ?? const {};
        final claimed = List<String>.from(ach['claimed'] ?? const <String>[]);
        final currentTitle = (ach['title'] ?? '').toString();
        final badgeEmojis = List<String>.from(ach['badgeEmojis'] ?? const <String>[]);

        final next = _nextAchievement(points);
        final target = next?.pointsRequired ?? (kDefs.isEmpty ? 0 : kDefs.last.pointsRequired);
        final progress = target == 0
            ? 1.0
            : ((points / target).clamp(0.0, 1.0)).toDouble();
        final claimedCount = claimed.length.clamp(0, kDefs.length).toInt();

        if (isFirstLoad) {
          return const _AchievementsLoadingView();
        }

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            key: const PageStorageKey('my_achievements_list'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _AchievementHeroCard(
                points: points,
                currentTitle: currentTitle,
                badgeEmojis: badgeEmojis,
                next: next,
                target: target,
                progress: progress,
                claimedCount: claimedCount,
              ),
              const SizedBox(height: 14),
              _SectionHeader(
                title: 'مسار الألقاب',
                subtitle: 'كل ما جمعت نقاط أكثر، فتحت وسام ولقب جديد.',
                icon: Icons.route_rounded,
              ),
              const SizedBox(height: 10),
              ...kDefs.map((a) {
                final unlocked = points >= a.pointsRequired;
                final already = claimed.contains(a.id);
                final canClaim = unlocked && !already;
                final previous = _previousRequiredFor(a);
                final itemProgress = a.pointsRequired <= previous
                    ? 1.0
                    : (((points - previous) / (a.pointsRequired - previous))
                            .clamp(0.0, 1.0))
                        .toDouble();

                return _AchievementCard(
                  def: a,
                  unlocked: unlocked,
                  claimed: already,
                  canClaim: canClaim,
                  progress: itemProgress,
                  onClaim: () => repo.claimAchievementWithBadge(uid: uid, def: a),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  AchievementDef? _nextAchievement(int points) {
    for (final a in kDefs) {
      if (a.pointsRequired > points) return a;
    }
    return null;
  }

  int _previousRequiredFor(AchievementDef def) {
    final index = kDefs.indexWhere((a) => a.id == def.id);
    if (index <= 0) return 0;
    return kDefs[index - 1].pointsRequired;
  }
}

class _AchievementHeroCard extends StatelessWidget {
  final int points;
  final String currentTitle;
  final List<String> badgeEmojis;
  final AchievementDef? next;
  final int target;
  final double progress;
  final int claimedCount;

  const _AchievementHeroCard({
    required this.points,
    required this.currentTitle,
    required this.badgeEmojis,
    required this.next,
    required this.target,
    required this.progress,
    required this.claimedCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final remaining = (target - points).clamp(0, 999999);
    final percent = (progress * 100).clamp(0, 100).round();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary,
            Color.alphaBlend(cs.secondary.withOpacity(0.35), cs.primary),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -26,
            end: -18,
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 128,
              color: cs.onPrimary.withOpacity(0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: cs.onPrimary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.bolt_rounded, color: cs.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'نقاطك الحالية',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onPrimary.withOpacity(0.82),
                            ),
                          ),
                          Text(
                            '$points نقطة',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _HeroMiniBadge(
                      text: currentTitle.isNotEmpty ? currentTitle : 'ابدأ الآن',
                      emoji: badgeEmojis.isNotEmpty ? badgeEmojis.last : '⭐',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: cs.onPrimary.withOpacity(0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        next == null
                            ? 'فتحت كل الألقاب، أسطورة يا بطل 🎉'
                            : 'باقي $remaining نقطة للقب ${next!.titleName} ${next!.emoji}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onPrimary.withOpacity(0.9),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStatPill(
                        title: 'الأوسمة',
                        value: '$claimedCount/${kDefs.length}',
                        icon: Icons.military_tech_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroStatPill(
                        title: 'اللقب القادم',
                        value: next?.emoji ?? '👑',
                        icon: Icons.flag_rounded,
                      ),
                    ),
                  ],
                ),
                if (badgeEmojis.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: badgeEmojis.map((e) => _BadgeChip(emoji: e)).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMiniBadge extends StatelessWidget {
  final String text;
  final String emoji;

  const _HeroMiniBadge({required this.text, required this.emoji});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 124),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _HeroStatPill({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onPrimary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.onPrimary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimary.withOpacity(0.72),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w900,
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

class _AchievementCard extends StatelessWidget {
  final AchievementDef def;
  final bool unlocked;
  final bool claimed;
  final bool canClaim;
  final double progress;
  final VoidCallback onClaim;

  const _AchievementCard({
    required this.def,
    required this.unlocked,
    required this.claimed,
    required this.canClaim,
    required this.progress,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = unlocked ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    final bg = unlocked ? cs.primaryContainer : cs.surfaceContainerHighest;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: unlocked ? cs.primary.withOpacity(0.20) : cs.outlineVariant.withOpacity(0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(def.emoji, style: const TextStyle(fontSize: 27)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          def.titleName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _StatusPill(
                        text: claimed ? 'مفتوح' : (unlocked ? 'جاهز' : 'مغلق'),
                        icon: claimed
                            ? Icons.verified_rounded
                            : (unlocked ? Icons.lock_open_rounded : Icons.lock_rounded),
                        active: unlocked,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    def.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(unlocked ? cs.primary : cs.outline),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يتطلب ${def.pointsRequired} نقطة',
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: canClaim ? onClaim : null,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(claimed ? 'تم' : (unlocked ? 'خذها' : 'قريب')),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===== تبويب قائمة المتسابقين =====
class _LeaderboardTab extends StatefulWidget {
  final String uid;
  final AchievementsRepo repo;

  const _LeaderboardTab({required this.uid, required this.repo});

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab>
    with AutomaticKeepAliveClientMixin<_LeaderboardTab> {
  final Map<String, String> _resolvedPhotos = {};
  final Set<String> _resolvingPhotoUids = {};
  StreamSubscription<List<LeaderboardEntry>>? _leaderboardSub;

  List<LeaderboardEntry> _rows = const <LeaderboardEntry>[];
  bool _loadedOnce = false;
  bool _refreshing = false;
  Object? _lastError;
  bool? _localHiddenOverride; // خيار إخفاء الحساب (محلي/فوري)

  @override
  void initState() {
    super.initState();
    _loadLocalHidden();
    _subscribeLeaderboard();
  }

  @override
  void dispose() {
    _leaderboardSub?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true; // لا تفكّك التبويب

  Future<void> _loadLocalHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('lb_hidden_${widget.uid}');
      if (v != null && mounted) {
        setState(() => _localHiddenOverride = v);
      }
    } catch (_) {}
  }

  void _subscribeLeaderboard() {
    _leaderboardSub?.cancel();
    _leaderboardSub = widget.repo.watchLeaderboard(visibleLimit: 100).listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _loadedOnce = true;
          _lastError = null;
        });
        _resolveVisiblePhotos(rows.take(24));
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _lastError = e;
          _loadedOnce = true;
        });
      },
    );
  }

  Future<void> _refreshLeaderboard() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final rows = await widget.repo.fetchLeaderboardOnce(visibleLimit: 100);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loadedOnce = true;
        _lastError = null;
      });
      _resolveVisiblePhotos(rows.take(24));
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = e);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _setHidden(bool v) async {
    setState(() => _localHiddenOverride = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('lb_hidden_${widget.uid}', v);
    } catch (_) {}

    try {
      await widget.repo.setLeaderboardHidden(uid: widget.uid, hidden: v);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(v ? 'تم إخفاء حسابك من المسابقة.' : 'تم إظهار حسابك في المسابقة.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم تطبيق التغيير على السيرفر الآن. تأكد من اتصال الإنترنت.')),
        );
      }
    }
  }

  Future<String?> _toHttpUrl(String s) async {
    try {
      if (s.isEmpty) return null;
      if (s.startsWith('http')) return s;
      if (s.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(s);
        return await ref.getDownloadURL();
      }
      if (!s.contains('://')) {
        final ref = FirebaseStorage.instance.ref(s);
        return await ref.getDownloadURL();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _resolveVisiblePhotos(Iterable<LeaderboardEntry> rows) async {
    final pending = rows.where((e) {
      final raw = e.photoUrl.trim();
      if (raw.isEmpty || raw.startsWith('http')) return false;
      if (_resolvedPhotos.containsKey(e.uid)) return false;
      return !_resolvingPhotoUids.contains(e.uid);
    }).take(12).toList(growable: false);

    if (pending.isEmpty) return;

    for (final e in pending) {
      _resolvingPhotoUids.add(e.uid);
      _toHttpUrl(e.photoUrl.trim()).then((url) {
        _resolvingPhotoUids.remove(e.uid);
        if (url != null && mounted) {
          setState(() => _resolvedPhotos[e.uid] = url);
        }
      });
    }
  }

  List<LeaderboardEntry> _visibleRows(bool hidden) {
    if (!hidden) return _rows;
    return _rows.where((e) => e.uid != widget.uid).toList(growable: false);
  }

  String _photoFor(LeaderboardEntry e) {
    final raw = e.photoUrl.trim();
    if (raw.startsWith('http')) return raw;
    return _resolvedPhotos[e.uid] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.repo.watchMe(widget.uid),
      builder: (context, meSnap) {
        final meData = meSnap.data?.data();
        final hidden = _localHiddenOverride ?? isLeaderboardHidden(meData);
        final rows = _visibleRows(hidden);
        final myRank = _findMyRank();
        final myPoints = readUserPoints(meData);

        return RefreshIndicator(
          onRefresh: _refreshLeaderboard,
          child: CustomScrollView(
            key: const PageStorageKey('wazen_leaderboard_scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _LeaderboardHeaderCard(
                    hidden: hidden,
                    myRank: myRank,
                    myPoints: myPoints,
                    refreshing: _refreshing,
                    onChangedHidden: _setHidden,
                    onRefresh: _refreshLeaderboard,
                  ),
                ),
              ),
              if (!_loadedOnce)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LeaderboardLoadingView(),
                )
              else if (_lastError != null && rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'تعذر تحميل المتسابقين',
                    subtitle: 'اسحب للأسفل للتحديث أو تأكد من اتصال الإنترنت.',
                  ),
                )
              else if (rows.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'لا يوجد متسابقون بعد',
                    subtitle: 'ابدأ بجمع النقاط وكن أول اسم في القائمة.',
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _PodiumSection(
                      rows: rows.take(3).toList(growable: false),
                      photoFor: _photoFor,
                      onTap: _openProfile,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'قائمة المتسابقين',
                      subtitle: 'يتم عرض أول 100 متسابق فقط.',
                      icon: Icons.leaderboard_rounded,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final e = rows[i];
                      final rank = i + 1;
                      return _LeaderboardTile(
                        entry: e,
                        rank: rank,
                        photoUrl: _photoFor(e),
                        isMe: e.uid == widget.uid,
                        onTap: () => _openProfile(e.uid),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  int? _findMyRank() {
    final i = _rows.indexWhere((e) => e.uid == widget.uid);
    if (i < 0) return null;
    return i + 1;
  }

  void _openProfile(String uid) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfilePage(uid: uid)),
    );
  }
}

class _LeaderboardHeaderCard extends StatelessWidget {
  final bool hidden;
  final int? myRank;
  final int myPoints;
  final bool refreshing;
  final ValueChanged<bool> onChangedHidden;
  final Future<void> Function() onRefresh;

  const _LeaderboardHeaderCard({
    required this.hidden,
    required this.myRank,
    required this.myPoints,
    required this.refreshing,
    required this.onChangedHidden,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.surfaceContainerHighest,
            Color.alphaBlend(cs.primary.withOpacity(0.06), cs.surface),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.emoji_events_rounded, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تحدي وازن',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'نافس على النقاط، وافتح ألقابك خطوة بخطوة.',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SoftStatCard(
                    title: 'ترتيبك',
                    value: myRank == null ? '—' : '#$myRank',
                    icon: Icons.trending_up_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SoftStatCard(
                    title: 'نقاطك',
                    value: '$myPoints',
                    icon: Icons.bolt_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SwitchListTile.adaptive(
                value: hidden,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Text('إخفاء اسمي وصورتي من المسابقة'),
                subtitle: const Text('عند التفعيل لن يظهر حسابك في قائمة المتسابقين.'),
                onChanged: onChangedHidden,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PodiumSection extends StatelessWidget {
  final List<LeaderboardEntry> rows;
  final String Function(LeaderboardEntry entry) photoFor;
  final void Function(String uid) onTap;

  const _PodiumSection({
    required this.rows,
    required this.photoFor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final first = rows.isNotEmpty ? rows[0] : null;
    final second = rows.length > 1 ? rows[1] : null;
    final third = rows.length > 2 ? rows[2] : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: second == null
              ? const SizedBox.shrink()
              : _PodiumCard(
                  entry: second,
                  rank: 2,
                  height: 150,
                  photoUrl: photoFor(second),
                  onTap: () => onTap(second.uid),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: first == null
              ? const SizedBox.shrink()
              : _PodiumCard(
                  entry: first,
                  rank: 1,
                  height: 184,
                  photoUrl: photoFor(first),
                  onTap: () => onTap(first.uid),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: third == null
              ? const SizedBox.shrink()
              : _PodiumCard(
                  entry: third,
                  rank: 3,
                  height: 136,
                  photoUrl: photoFor(third),
                  onTap: () => onTap(third.uid),
                ),
        ),
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final double height;
  final String photoUrl;
  final VoidCallback onTap;

  const _PodiumCard({
    required this.entry,
    required this.rank,
    required this.height,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: rank == 1 ? cs.primaryContainer : cs.surfaceContainerHighest,
          border: Border.all(
            color: rank == 1 ? cs.primary.withOpacity(0.25) : cs.outlineVariant.withOpacity(0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(rank == 1 ? 0.07 : 0.035),
              blurRadius: rank == 1 ? 20 : 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isFirst = rank == 1;
            final avatarRadius = isFirst ? 24.0 : 18.0;
            final badgeLarge = isFirst && constraints.maxHeight >= 150;

            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RankBadge(rank: rank, large: badgeLarge),
                    const SizedBox(height: 6),
                    _Avatar(
                      name: entry.displayName,
                      photoUrl: photoUrl,
                      radius: avatarRadius,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.points} نقطة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final String photoUrl;
  final bool isMe;
  final VoidCallback onTap;

  const _LeaderboardTile({
    required this.entry,
    required this.rank,
    required this.photoUrl,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badges = entry.badgeEmojis.take(3).toList(growable: false);

    return Material(
      color: isMe ? cs.primaryContainer.withOpacity(0.45) : cs.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isMe ? cs.primary.withOpacity(0.25) : cs.outlineVariant.withOpacity(0.45),
            ),
          ),
          child: Row(
            children: [
              _RankBadge(rank: rank),
              const SizedBox(width: 10),
              _Avatar(name: entry.displayName, photoUrl: photoUrl, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (isMe) const _MePill(),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${entry.points} نقطة',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (entry.title.isNotEmpty)
                          Text(
                            '• ${entry.title}',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ...badges.map((e) => Text(e, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  final bool large;

  const _RankBadge({required this.rank, this.large = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = large ? 34.0 : 30.0;
    final isTop = rank <= 3;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isTop ? cs.primary : cs.surfaceContainerHighest,
        border: Border.all(color: isTop ? cs.primary : cs.outlineVariant),
      ),
      child: Text(
        rank == 1 ? '👑' : '$rank',
        style: TextStyle(
          color: isTop ? cs.onPrimary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w900,
          fontSize: rank == 1 ? 15 : 12,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String photoUrl;
  final double radius;

  const _Avatar({required this.name, required this.photoUrl, required this.radius});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(
              _initial(name),
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onPrimaryContainer),
            )
          : null,
    );
  }

  String _initial(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'و';
    return t.characters.isNotEmpty ? t.characters.first.toUpperCase() : 'و';
  }
}

class _MePill extends StatelessWidget {
  const _MePill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'أنت',
        style: TextStyle(color: cs.onPrimary, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool active;

  const _StatusPill({required this.text, required this.icon, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String emoji;

  const _BadgeChip({required this.emoji});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.onPrimary.withOpacity(0.12)),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 16)),
    );
  }
}

class _SoftStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SoftStatCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionHeader({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AchievementsLoadingView extends StatelessWidget {
  const _AchievementsLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: const [
        _SkeletonBox(height: 230, radius: 28),
        SizedBox(height: 14),
        _SkeletonBox(height: 70, radius: 18),
        SizedBox(height: 10),
        _SkeletonBox(height: 96, radius: 22),
        SizedBox(height: 10),
        _SkeletonBox(height: 96, radius: 22),
        SizedBox(height: 10),
        _SkeletonBox(height: 96, radius: 22),
      ],
    );
  }
}

class _LeaderboardLoadingView extends StatelessWidget {
  const _LeaderboardLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: const [
        _SkeletonBox(height: 154, radius: 24),
        SizedBox(height: 12),
        _SkeletonBox(height: 78, radius: 22),
        SizedBox(height: 10),
        _SkeletonBox(height: 78, radius: 22),
        SizedBox(height: 10),
        _SkeletonBox(height: 78, radius: 22),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  final double radius;

  const _SkeletonBox({required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

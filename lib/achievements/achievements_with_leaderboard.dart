// lib/achievements/achievements_with_leaderboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// يفتح بروفايل المستخدم الجديد (بدون مجتمع)
import 'package:my_app/features/users/ui/user_profile_page.dart';

/// Helper موحّد لقراءة نقاط المستخدم.
/// ✅ يدعم الحقول الشائعة كلها: points_total, stats.points, points, pointsTotal
int readUserPoints(Map<String, dynamic>? data) {
  if (data == null) return 0;

  dynamic v =
      data['points_total'] ??
      (data['stats'] is Map ? (data['stats']['points']) : null) ??
      data['points'] ??
      data['pointsTotal'];

  if (v is int) return v;
  if (v is double) return v.round();
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

/// =======================
/// نماذج/مستودع البيانات
/// =======================

class LeaderboardEntry {
  final String uid;
  final int points;
  LeaderboardEntry({required this.uid, required this.points});
}

class AchievementDef {
  final String id;
  final int pointsRequired;
  final String titleName; // اسم اللقب (يُخزن كأعلى لقب)
  final String emoji;     // شارة/إيموجي يُضاف للقائمة
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
    description: 'لقب برونزي + شارة برونزية.',
    icon: Icons.military_tech,
  ),
  AchievementDef(
    id: 'rank_silver',
    pointsRequired: 200,
    titleName: 'فضّي',
    emoji: '🥈',
    description: 'لقب فضّي + شارة فضّية.',
    icon: Icons.military_tech,
  ),
  AchievementDef(
    id: 'rank_gold',
    pointsRequired: 300,
    titleName: 'ذهبي',
    emoji: '🥇',
    description: 'لقب ذهبي + شارة ذهبية.',
    icon: Icons.military_tech,
  ),
  AchievementDef(
    id: 'rank_platinum',
    pointsRequired: 400,
    titleName: 'بلاتيني',
    emoji: '💎',
    description: 'لقب بلاتيني + شارة ماسية.',
    icon: Icons.diamond,
  ),
  AchievementDef(
    id: 'rank_master',
    pointsRequired: 500,
    titleName: 'ماستر',
    emoji: '🏆',
    description: 'لقب ماستر + كأس.',
    icon: Icons.emoji_events,
  ),
  AchievementDef(
    id: 'rank_600',
    pointsRequired: 600,
    titleName: 'أسطوري I',
    emoji: '🔥',
    description: 'ارتقاء إلى أسطوري المستوى الأول.',
    icon: Icons.local_fire_department,
  ),
  AchievementDef(
    id: 'rank_700',
    pointsRequired: 700,
    titleName: 'أسطوري II',
    emoji: '💠',
    description: 'أسطوري المستوى الثاني.',
    icon: Icons.workspace_premium,
  ),
  AchievementDef(
    id: 'rank_800',
    pointsRequired: 800,
    titleName: 'نخبة',
    emoji: '⭐',
    description: 'وصلت مستوى النخبة.',
    icon: Icons.star,
  ),
  AchievementDef(
    id: 'rank_900',
    pointsRequired: 900,
    titleName: 'جراند ماستر',
    emoji: '🧠',
    description: 'ترتيب جراند ماستر.',
    icon: Icons.psychology_alt,
  ),
  AchievementDef(
    id: 'rank_1000',
    pointsRequired: 1000,
    titleName: 'تشامبيون',
    emoji: '👑',
    description: 'أعلى لقب — البطل!',
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


  /// ✅ قائمة المتسابقين:
  /// - نعرض **أول 100** فقط (بعد تطبيق خيار الإخفاء).
  /// - إذا بعض الحسابات مخفية، نطلب أكثر من 100 من السيرفر ثم نقصّها محليًا.
  Stream<List<LeaderboardEntry>> watchLeaderboard({
    int visibleLimit = 100,
    int fetchLimit = 300,
  }) {
    final serverLimit = fetchLimit < visibleLimit ? visibleLimit : fetchLimit;
    return _db
        .collection('users')
        .orderBy('points_total', descending: true)
        .limit(serverLimit)
        .snapshots()
        .map((qs) {
      final out = <LeaderboardEntry>[];
      for (final d in qs.docs) {
        final m = d.data();
        final pts = readUserPoints(m);
        if (pts <= 0) continue;
        if (isLeaderboardHidden(m)) continue;

        out.add(LeaderboardEntry(uid: d.id, points: pts));
        if (out.length >= visibleLimit) break;
      }
      return out;
    });
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
      final data = (snap.data() ?? <String, dynamic>{});
      final points = readUserPoints(data);

      final achievements =
          Map<String, dynamic>.from(data['achievements'] ?? const {});
      final claimed =
          List<String>.from(achievements['claimed'] ?? const <String>[]);
      final emojis =
          List<String>.from(achievements['badgeEmojis'] ?? const <String>[]);

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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإنجازات'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.stars), text: 'إنجازاتي'),
              Tab(icon: Icon(Icons.emoji_events), text: 'قائمة المتسابقين'),
            ],
          ),
          actions: const [],
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchMe(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final m = snap.data?.data() ?? const <String, dynamic>{};
        final points = readUserPoints(m);

        final ach = (m['achievements'] as Map<String, dynamic>?) ?? const {};
        final claimed = List<String>.from(ach['claimed'] ?? const <String>[]);
        final currentTitle = (ach['title'] ?? '').toString();
        final badgeEmojis =
            List<String>.from(ach['badgeEmojis'] ?? const <String>[]);

        // التقدم نحو الهدف التالي
        final next = kDefs
            .where((a) => a.pointsRequired > points)
            .fold<int?>(null, (min, a) => min == null ? a.pointsRequired : (a.pointsRequired < min ? a.pointsRequired : min));
        final target = next ?? (kDefs.isEmpty ? 0 : kDefs.last.pointsRequired);
        final progress = target == 0 ? 1.0 : (points / target).clamp(0.0, 1.0);

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // بطاقة رأس: نقاط + اللقب + الشارات
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
                          Text(
                            '$points',
                            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          if (currentTitle.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.workspace_premium_outlined),
                                const SizedBox(width: 6),
                                Text('وسامك: ${badgeEmojis.isNotEmpty ? badgeEmojis.last : '⭐️'}'),
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
                        next == null
                            ? 'فتحت كل الألقاب، أحسنت! 🎉'
                            : 'المتبقي للقب التالي: ${target - points} نقطة',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (badgeEmojis.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: badgeEmojis
                              .map((e) => Chip(
                                    label: Text(e, style: const TextStyle(fontSize: 16)),
                                    backgroundColor: cs.secondaryContainer.withOpacity(0.6),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // الإنجازات/الألقاب
              ...kDefs.map((a) {
                final unlocked = points >= a.pointsRequired;
                final already = claimed.contains(a.id);
                final canClaim = unlocked && !already;

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0.5,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: unlocked ? cs.primaryContainer : cs.surfaceContainerHighest,
                      child: Text(a.emoji, style: const TextStyle(fontSize: 18)),
                    ),
                    title: Text(
                      a.emoji,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'يتطلب: ${a.pointsRequired} نقطة',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: ElevatedButton(
                      onPressed: canClaim
                          ? () => repo.claimAchievementWithBadge(uid: uid, def: a)
                          : null,
                      child: Text(already ? 'مُطالَب' : (unlocked ? 'مطالبة' : 'مغلق')),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// ===== تبويب قائمة المتسابقين (بدون فليكر + يحتفظ بالحالة) =====
class _LeaderboardTab extends StatefulWidget {
  final String uid;
  final AchievementsRepo repo;
  const _LeaderboardTab({required this.uid, required this.repo});

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _UserPreview {
  final String uid;
  final String display;
  final String photoUrl;
  const _UserPreview({required this.uid, required this.display, required this.photoUrl});
}

class _LeaderboardTabState extends State<_LeaderboardTab>
    with AutomaticKeepAliveClientMixin<_LeaderboardTab> {
  final _db = FirebaseFirestore.instance;

  // كاش ثابت طول عمر الـ State
  final Map<String, _UserPreview> _cache = {};
  bool _fetching = false;
  bool? _localHiddenOverride; // خيار إخفاء الحساب (محلي/فوري)

  @override
  void initState() {
    super.initState();
    _loadLocalHidden();
  }

  Future<void> _loadLocalHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('lb_hidden_${widget.uid}');
      if (v != null && mounted) {
        setState(() => _localHiddenOverride = v);
      }
    } catch (_) {}
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


  @override
  bool get wantKeepAlive => true; // لا تفكّك التبويب

  // محول صورة لأي قيمة إلى رابط http صالح
  Future<String?> _toHttpUrl(String s) async {
    try {
      if (s.isEmpty) return null;
      if (s.startsWith('http')) return s;
      if (s.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(s);
        return await ref.getDownloadURL();
      }
      // مسار نسبي مثل avatars/uid.jpg
      if (!s.contains('://')) {
        final ref = FirebaseStorage.instance.ref(s);
        return await ref.getDownloadURL();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchMissingUsers(Set<String> uids) async {
    if (uids.isEmpty || _fetching) return;
    _fetching = true;
    try {
      final list = uids.toList();
      for (var i = 0; i < list.length; i += 10) {
        final chunk = list.sublist(i, (i + 10).clamp(0, list.length));
        final qs = await _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final d in qs.docs) {
          final m = d.data();

          // الاسم للعرض (نستخدم الاسم الحقيقي بدل اليوزرنيم في لوحة الإنجازات)
          final name = ((m['name'] ??
                      m['displayName'] ??
                      m['fullName']) as String?)
                  ?.trim() ??
              '';
          final email = (m['email'] as String?)?.trim() ?? '';
          // ✅ لا نعرض اليوزرنيم هنا: نفضّل الاسم، ثم displayName/fullName، ثم جزء من الإيميل
          final display =
              name.isNotEmpty ? name : (email.isNotEmpty ? email.split('@').first : 'مستخدم');

          // عدة حقول للصورة
          String? raw = (m['photoUrl'] ??
                  m['avatarUrl'] ??
                  m['image'] ??
                  (m['profile'] is Map
                      ? (((m['profile'] as Map)['photoUrl'] ??
                              (m['profile'] as Map)['avatarUrl']) as String?)
                      : null))
              as String?;
          String photo = (raw ?? '').trim();

          // fallback على auth لو هو نفس المستخدم وما فيه حقول
          if (photo.isEmpty && d.id == FirebaseAuth.instance.currentUser?.uid) {
            photo = (FirebaseAuth.instance.currentUser?.photoURL ?? '').trim();
          }

          // حوّل gs:// أو المسارات النسبية
          if (photo.isNotEmpty && !photo.startsWith('http')) {
            final resolved = await _toHttpUrl(photo);
            if (resolved != null) photo = resolved;
          }

          _cache[d.id] = _UserPreview(uid: d.id, display: display, photoUrl: photo);
        }
      }
      if (mounted) setState(() {}); // حدّث العناوين/الصور بعد الجلب
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.repo.watchMe(widget.uid),
      builder: (context, meSnap) {
        final meData = meSnap.data?.data();
        final hidden = _localHiddenOverride ?? isLeaderboardHidden(meData);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: hidden,
                        title: const Text('إخفاء اسمي وصورتي من المسابقة'),
                        subtitle: const Text(
                          'إذا فعّلت هذا الخيار، لن يظهر حسابك في قائمة المتسابقين حتى لو نقاطك عالية.',
                        ),
                        onChanged: (v) => _setHidden(v),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'يتم عرض أول 100 متسابق فقط.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<LeaderboardEntry>>(
                stream: widget.repo.watchLeaderboard(visibleLimit: 100),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var rows = snap.data ?? const <LeaderboardEntry>[];

                  // ✅ لو المستخدم مخفي محليًا/سيرفر: تأكد ما يظهر حتى لو رجع ضمن النتائج
                  if (hidden) {
                    rows = rows.where((e) => e.uid != widget.uid).toList(growable: false);
                  }

                  if (rows.isEmpty) {
                    return const Center(child: Text('لا يوجد متسابقون بعد.'));
                  }

                  // بعد الإطار الحالي اطلب المفقود دفعات
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final missing = rows.map((e) => e.uid).where((id) => !_cache.containsKey(id)).toSet();
                    _fetchMissingUsers(missing);
                  });

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = rows[i];
                      final rank = i + 1;
                      final pv = _cache[e.uid];
                      final display = pv?.display ?? 'جارِ التحميل…';
                      final photo = pv?.photoUrl ?? '';

                      return ListTile(
                        key: ValueKey(e.uid),
                        leading: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                              child: photo.isEmpty
                                  ? Text(_initial(display), style: const TextStyle(fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text('$rank', style: const TextStyle(fontSize: 11, color: Colors.white)),
                            ),
                          ],
                        ),
                        title: Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('${e.points} نقطة'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => UserProfilePage(uid: e.uid)),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }


  String _initial(String s) {
    if (s.isEmpty) return '?';
    final t = s.trim();
    // أول محرف مرئي
    return t.characters.isNotEmpty ? t.characters.first.toUpperCase() : '?';
  }
}

// lib/screens/guide_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';

// صفحات داخلية
import 'restaurants_page.dart';
import 'virtual_gym_page.dart';
import 'training_schedule_page.dart';
import '../features/recipes/ui/recipes_explore_page.dart';
import '../trainers/my_trainer_screen.dart';
import '../trainers/trainer_dashboard_screen.dart';
import '../trainers/trainer_contact_gate.dart';

// شارات/حساب
import '../community/local_repos.dart'; // LocalAuthRepo().currentUser()
import '../community/models.dart'; // AppUser
import '../models/badge.dart'; // enum BadgeType
import '../shared/user_badges_store.dart'; // مصدر الشارات

// ✅ صفحات المالك والدعم داخل features
import '../features/admin/owner_page.dart'; // OwnerPage
import '../features/support/support_page.dart'; // SupportPage

// أخرى (عدّل اسم الباكيج لو مو my_app)
import 'package:my_app/gyms/gyms_map_page.dart';

// خدمة الأدوار
import '../core/auth/roles_service.dart';

/// الغلاف: يسمح بالدخول لأي مستخدم مسجّل (غير المسجّل فقط يُمنع).
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          return const _NotAllowed(reason: "الرجاء تسجيل الدخول للوصول إلى هذه الصفحة");
        }
        return PremiumGate(
          feature: PremiumFeature.guide,
          child: const GuidePageInner(),
        );
      },
    );
  }
}

class _NotAllowed extends StatelessWidget {
  final String reason;
  const _NotAllowed({required this.reason});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("دليلك"),
      ),
      body: Stack(
        children: [
          _GuideBackground(colorScheme: cs),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _GlassPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 64, color: cs.primary),
                        const SizedBox(height: 14),
                        Text(
                          reason,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.25),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GuidePageInner extends StatefulWidget {
  const GuidePageInner({super.key});

  @override
  State<GuidePageInner> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePageInner> {
  final RolesService _roles = RolesService();
  final UserBadgesStore _badges = UserBadgesStore(); // غيّرها لو عندك Singleton مختلف
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AppUser? _me;
  BadgeType? _myBadge;

  bool _isOwner = false;
  bool _isSupport = false;
  bool _loading = true;

  StreamSubscription<AppRole>? _roleSub;
  bool _routeOpening = false;

  Future<void> _safePush(Widget page) async {
    if (_routeOpening || !mounted) return;
    _routeOpening = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    } finally {
      // نترك مهلة بسيطة حتى لا يضغط المستخدم مرتين ويفتح نفس الصفحة مرتين.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      _routeOpening = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveEverything();
  }

  @override
  void dispose() {
    _roleSub?.cancel();
    super.dispose();
  }

  Future<void> _resolveEverything() async {
    try {
      // 1) تحميل بيانات المستخدم/الشارة مرة واحدة
      final me = await LocalAuthRepo().currentUser();
      final badge = await _badges.getBadge(me.uid);

      if (!mounted) return;
      setState(() {
        _me = me;
        _myBadge = badge;
      });

      // 2) بثّ حي للدور — مهم عشان لما المالك يغير رتبة المستخدم تظهر مباشرة
      await _roleSub?.cancel();
      _roleSub = _roles.currentUserRoleStream().listen((role) {
        if (!mounted) return;
        setState(() {
          _isOwner = (role == AppRole.owner);
          // ✅ الأدمن لازم يشوف لوحة الدعم/الإدارة مثل الدعم
          _isSupport = (role == AppRole.support || role == AppRole.admin || _isOwner);
          _loading = false;
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isOwner = false;
        _isSupport = false;
        _myBadge = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // منطق الإظهار حسب الرتبة (لا تغيّر)
    final showTrainerPanel = _myBadge == BadgeType.coach;
    final showSupportPanel = _isOwner || _isSupport || _myBadge == BadgeType.support;
    final showOwnerPanel = _isOwner;

    final items = <_GuideCard>[
      _GuideCard(
        icon: Icons.restaurant,
        title: 'استكشف الوصفات',
        description: 'تصفّح وصفات المجتمع مع الماكروز والسعرات.',
        onTap: () => _safePush(RecipesExplorePage()),
      ),
      _GuideCard(
        icon: Icons.fastfood_rounded,
        title: 'المطاعم',
        description: 'دليل الأكل الجاهز والاختيارات المناسبة لأهدافك.',
        onTap: () => _safePush(RestaurantsPage()),
      ),
      _GuideCard(
        icon: Icons.fitness_center,
        title: 'الصالة الافتراضية',
        description: 'تمارين وفيديوهات بإرشادات بسيطة.',
        onTap: () => _safePush(VirtualGymPage()),
      ),
      _GuideCard(
        icon: Icons.schedule_rounded,
        title: 'جداول التدريب',
        description: 'أنشئ جدولك أو اختر من جداول جاهزة.',
        onTap: () => _safePush(TrainingSchedulePage()),
      ),
      _GuideCard(
        icon: Icons.map_outlined,
        title: 'النوادي القريبة',
        description: 'استكشف نوادي قريبة منك على الخريطة.',
        onTap: () => _safePush(GymsMapPage()),
      ),

      // 👇 تظهر حسب الصلاحيات (لا تغيّر)
      if (showTrainerPanel)
        _GuideCard(
          icon: Icons.dashboard_customize_rounded,
          title: 'لوحة المدرب',
          description: 'إدارة المتدربين وخططهم (للحسابات المصرّح لها).',
          onTap: () => _safePush(TrainerDashboardScreen()),
        ),

      if (showSupportPanel)
        _GuideCard(
          icon: Icons.support_agent,
          title: 'الدعم الفني',
          description: 'مراقبة التطبيق، إدارة المستخدمين والبلاغات.',
          onTap: () => _safePush(SupportPage()),
        ),

      if (showOwnerPanel)
        _GuideCard(
          icon: Icons.workspace_premium_rounded,
          title: 'لوحة المالك',
          description: 'تعديل الرتب، تبنيد، إيقاف وصفات، نقاط وإشعارات.',
          onTap: () => _safePush(OwnerPage()),
        ),

      _GuideCard(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'تواصل مع المدرب',
        description: 'بوابة تواصل — سيتم تحويلك لواجهة المدرب.',
        onTap: () => _safePush(
          TrainerContactGate(
            child: MyTrainerScreen(),
          ),
        ),
      ),
    ];

    final badgeLabel = (_myBadge == null) ? '' : _badgeLabel(_myBadge!);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Grid responsive (UI فقط)
    final w = MediaQuery.of(context).size.width;
    final crossAxisCount = w >= 980 ? 3 : (w >= 640 ? 2 : 1);
    final childAspectRatio = crossAxisCount == 1 ? 2.95 : 1.65;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: const Text("دليلك"),
        actions: [
          if (badgeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: _BadgePill(text: badgeLabel),
            ),
        ],
      ),
      body: Stack(
        children: [
          _GuideBackground(colorScheme: cs),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: _GlassPanel(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Row(
                          children: [
                            _AvatarMark(colorScheme: cs),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ✅ اسم المستخدم/اليوزر يتحدّث فورًا من Firestore بدون الحاجة لإعادة فتح الصفحة.
                                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                    stream: (uid == null)
                                        ? null
                                        : _db.collection('users').doc(uid).snapshots(),
                                    builder: (context, snap) {
                                      AppUser? live;
                                      final data = snap.data?.data();
                                      if (uid != null && data != null) {
                                        try {
                                          live = AppUser.fromJson(data, uid: uid);
                                        } catch (_) {
                                          live = null;
                                        }
                                      }

                                      final name = _displayName(live ?? _me);
                                      return Text(
                                        name.isEmpty ? 'مرحبًا' : 'مرحبًا، $name',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'اختر وجهتك  — وصفات، مطاعم، تمارين، ونوادي قريبة.',
                                    style: tt.bodyMedium?.copyWith(
                                      color: tt.bodyMedium?.color?.withOpacity(.78),
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: childAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _GuideCardWidget(
                        card: items[index],
                        cs: cs,
                        tt: tt,
                      ),
                      childCount: items.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// تسمية مرنة لأي قيمة من enum BadgeType عندك
  String _badgeLabel(BadgeType badge) {
    final raw = badge.toString();
    final name = raw.contains('.') ? raw.split('.').last : raw;
    final lowered = name.toLowerCase();
    if (lowered.isEmpty || lowered == 'none') return '';
    return name[0].toUpperCase() + name.substring(1);
  }

  String _displayName(AppUser? me) {
    if (me == null) return '';

    // AppUser في مشروعك يحتوي على: displayName / username / email
    // نخلي العرض آمن 100% بدون استخدام dynamic (عشان ما يصير NoSuchMethodError).
    final String fromName = me.displayName.trim();
    if (fromName.isNotEmpty) return fromName;

    final String username = me.username.trim();
    if (username.isNotEmpty) return username;

    final String email = me.email.trim();
    if (email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }
    return '';
  }
}

/// موديل البطاقة (لا تغيّر)
class _GuideCard {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  _GuideCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
}

/// واجهة البطاقة (UI فقط)
class _GuideCardWidget extends StatelessWidget {
  final _GuideCard card;
  final ColorScheme cs;
  final TextTheme tt;

  const _GuideCardWidget({
    required this.card,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    // دخول أنيق بدون أي باكج إضافي
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 10),
            child: child,
          ),
        );
      },
      child: _GlassCard(
        onTap: card.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              _IconBadge(icon: card.icon, colorScheme: cs),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      card.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        color: tt.bodyMedium?.color?.withOpacity(.76),
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: cs.onSurface.withOpacity(.55)),
            ],
          ),
        ),
      ),
    );
  }
}

/// خلفية فخمة وخفيفة (بدون منطق)
class _GuideBackground extends StatelessWidget {
  final ColorScheme colorScheme;
  const _GuideBackground({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              cs.primary.withOpacity(.18),
              cs.surface,
              cs.secondary.withOpacity(.12),
            ],
          ),
        ),
        child: Stack(
          children: [
            // دوائر ضوء ناعمة
            Positioned(
              top: -80,
              right: -60,
              child: _GlowBlob(color: cs.primary.withOpacity(.22), size: 220),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: _GlowBlob(color: cs.secondary.withOpacity(.18), size: 240),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(.70),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.onSurface.withOpacity(.08)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _GlassCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _GlassPanel(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: cs.primary.withOpacity(.08),
          highlightColor: cs.primary.withOpacity(.04),
          child: child,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final ColorScheme colorScheme;
  const _IconBadge({required this.icon, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(.18),
            cs.secondary.withOpacity(.14),
          ],
        ),
        border: Border.all(color: cs.onSurface.withOpacity(.08)),
      ),
      child: Icon(icon, size: 28, color: cs.primary),
    );
  }
}

class _AvatarMark extends StatelessWidget {
  final ColorScheme colorScheme;
  const _AvatarMark({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            cs.primary.withOpacity(.22),
            cs.secondary.withOpacity(.18),
          ],
        ),
        border: Border.all(color: cs.onSurface.withOpacity(.10)),
      ),
      child: Icon(Icons.favorite_rounded, color: cs.primary, size: 22),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  const _BadgePill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _GlassPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

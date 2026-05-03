// lib/screens/guide_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// صفحات داخلية
import 'restaurants_page.dart';
import 'virtual_gym_page.dart';
import 'training_schedule_page.dart';
import '../features/recipes/ui/recipes_explore_page.dart';
import '../trainers/my_trainer_screen.dart';
import '../trainers/trainer_dashboard_screen.dart';
import '../trainers/trainer_contact_gate.dart';

// شارات/حساب
import '../community/local_repos.dart';          // LocalAuthRepo().currentUser()
import '../community/models.dart';               // AppUser
import '../models/badge.dart';                   // enum BadgeType
import '../shared/user_badges_store.dart';       // مصدر الشارات

// ✅ صفحات المالك والدعم داخل features (تم التعديل هنا)
import '../features/admin/owner_page.dart';      // OwnerPage
import '../features/support/support_page.dart';  // SupportPage

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
        return const GuidePageInner();
      },
    );
  }
}

class _NotAllowed extends StatelessWidget {
  final String reason;
  const _NotAllowed({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("دليلك")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 16),
              Text(reason, textAlign: TextAlign.center),
            ],
          ),
        ),
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

  AppUser? _me;
  BadgeType? _myBadge;

  bool _isOwner = false;
  bool _isSupport = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveEverything();
  }

  Future<void> _resolveEverything() async {
    try {
      // 1) حسم الدور عبر الخدمة الموحّدة (UID/Email/Claims/Firestore)
      final role = await _roles.currentUserRoleOnce();

      // 2) تحميل الشارة (اختياري)
      final me = await LocalAuthRepo().currentUser();
      final badge = await _badges.getBadge(me.uid);

      if (!mounted) return;
      setState(() {
        _isOwner   = (role == AppRole.owner);
        _isSupport = (role == AppRole.support || _isOwner);
        _me = me;
        _myBadge = badge;
        _loading = false;
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

    // منطق الإظهار حسب الرتبة
    final showTrainerPanel = _myBadge == BadgeType.coach;
    final showSupportPanel = _isOwner || _isSupport || _myBadge == BadgeType.support;
    final showOwnerPanel   = _isOwner;

    final items = <_GuideCard>[
      _GuideCard(
        icon: Icons.restaurant,
        title: 'استكشف الوصفات',
        description: 'تصفّح وصفات المجتمع مع الماكروز والسعرات.',
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => RecipesExplorePage())),
      ),
      _GuideCard(
        icon: Icons.fastfood_rounded,
        title: 'المطاعم',
        description: 'دليل الأكل الجاهز والاختيارات المناسبة لأهدافك.',
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => RestaurantsPage())),
      ),
      _GuideCard(
        icon: Icons.fitness_center,
        title: 'الصالة الافتراضية',
        description: 'تمارين وفيديوهات بإرشادات بسيطة.',
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => VirtualGymPage())),
      ),
      _GuideCard(
        icon: Icons.schedule_rounded,
        title: 'جداول التدريب',
        description: 'أنشئ جدولك أو اختر من جداول جاهزة.',
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => TrainingSchedulePage())),
      ),
      _GuideCard(
        icon: Icons.map_outlined,
        title: 'النوادي القريبة',
        description: 'استكشف نوادي قريبة منك على الخريطة.',
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => GymsMapPage())),
      ),

      // 👇 تظهر حسب الصلاحيات:
      if (showTrainerPanel)
        _GuideCard(
          icon: Icons.dashboard_customize_rounded,
          title: 'لوحة المدرب',
          description: 'إدارة المتدربين وخططهم (للحسابات المصرّح لها).',
          onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => TrainerDashboardScreen())),
        ),

      if (showSupportPanel)
        _GuideCard(
          icon: Icons.support_agent,
          title: 'الدعم الفني',
          description: 'مراقبة التطبيق، إدارة المستخدمين والبلاغات.',
          onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => SupportPage())), // ✅ استخدم SupportPage
        ),

      if (showOwnerPanel)
        _GuideCard(
          icon: Icons.workspace_premium_rounded,
          title: 'لوحة المالك',
          description: 'تعديل الرتب، تبنيد، إيقاف وصفات، نقاط وإشعارات.',
          onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => OwnerPage())), // ✅ استخدم OwnerPage
        ),

      _GuideCard(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'تواصل مع المدرب',
        description: 'بوابة تواصل — سيتم تحويلك لواجهة المدرب.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrainerContactGate(
              child: MyTrainerScreen(),
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("دليلك"),
        actions: [
          if (_myBadge != null && _badgeLabel(_myBadge!).isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(child: Text(_badgeLabel(_myBadge!))),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: items
              .map((it) => _GuideCardWidget(card: it, cs: cs, tt: tt))
              .toList(),
        ),
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
}

/// موديل البطاقة
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

/// واجهة البطاقة
class _GuideCardWidget extends StatelessWidget {
  final _GuideCard card;
  final ColorScheme cs;
  final TextTheme tt;

  const _GuideCardWidget({required this.card, required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2.5,
      shadowColor: cs.shadow.withOpacity(.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: card.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(card.icon, size: 30, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.title,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.description,
                      style: tt.bodyMedium?.copyWith(
                        color: tt.bodyMedium?.color?.withOpacity(.75),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

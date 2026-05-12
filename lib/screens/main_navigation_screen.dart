// lib/screens/main_navigation_screen.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'my_data_page.dart';
import 'weight_tracking_page.dart';
import 'regimen_screen.dart';
import 'guide_page.dart';

import 'package:my_app/achievements/achievements_with_leaderboard.dart';
import '../shared/premium_gate.dart';
import '../shared/premium_feature.dart';
//import '../achievements/achievements_with_leaderboard.dart'; // يحتوي AchievementsPage
import 'settings_page.dart';
import '../settings/edit_username_page.dart';
import '../shared/user_goal_controller.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  bool _didPromptUsernameFix = false;
  bool _isShowingUsernameFix = false;

  bool _usernameNeedsFix(String username) {
    final t = username.trim();
    if (t.isEmpty) return false;
    if (RegExp(r'\s').hasMatch(t)) return true;
    // أي حرف عربي
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(t)) return true;
    return false;
  }

  Future<void> _checkAndForceUsernameFix() async {
    if (_didPromptUsernameFix || _isShowingUsernameFix) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.doc('users/${user.uid}').get();
      final username = (snap.data()?['username'] ?? '').toString();
      if (!_usernameNeedsFix(username)) return;
      if (!mounted) return;
      _didPromptUsernameFix = true;
      _isShowingUsernameFix = true;
      await _showUsernameFixSheet(currentUsername: username);
    } finally {
      _isShowingUsernameFix = false;
    }
  }

  Future<void> _showUsernameFixSheet({required String currentUsername}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return WillPopScope(
          onWillPop: () async => false,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 14,
              ),
              child: Material(
                color: cs.surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: cs.primary),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'يلزم تحديث اسم المستخدم',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'اسم المستخدم الحالي يحتوي على مسافة أو أحرف عربية.\nلازم تغيّره الآن إلى يوزر إنجليزي بدون مسافات (حروف/أرقام فقط).',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.85), height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Text(
                          'يوزرك الحالي: ${currentUsername.trim()}',
                          textAlign: TextAlign.start,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('تعديل اليوزر الآن'),
                          onPressed: () async {
                            await Navigator.of(sheetContext).push(
                              MaterialPageRoute(builder: (_) => const EditUsernamePage()),
                            );
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) return;
                            final snap = await FirebaseFirestore.instance.doc('users/${user.uid}').get();
                            final newUsername = (snap.data()?['username'] ?? '').toString();
                            if (!_usernameNeedsFix(newUsername)) {
                              if (Navigator.of(sheetContext).canPop()) {
                                Navigator.of(sheetContext).pop();
                              }
                            } else {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(content: Text('لازم تختار يوزر إنجليزي بدون مسافات وغير محجوز.')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ملاحظة: يوزر إنجليزي فقط (حروف/أرقام)، يبدأ بحرف، من 5 إلى 20.',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // مهم للأداء: لا نستخدم IndexedStack هنا.
  // IndexedStack كان يبقي كل التبويبات شغالة في الخلفية: Streams/Timers/صور/Firestore
  // وهذا يسبب تهنيق أو كراش بعد التنقل بين صفحات كثيرة.
  // الآن نبني الصفحة النشطة فقط، وأي صفحة تتركها يتم التخلص منها وإيقاف اشتراكاتها.
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  bool _switchLocked = false;

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const HomeScreen(key: PageStorageKey('home'));
      case 1:
        return const MyDataPage(key: PageStorageKey('mydata'));
      case 2:
        return const WeightTrackingPage(key: PageStorageKey('weight'));
      case 3:
        return const PremiumGate(
          feature: PremiumFeature.regimen,
          child: RegimenScreen(key: PageStorageKey('regimen')),
        );
      case 4:
        return const PremiumGate(
          feature: PremiumFeature.virtualClubGuide,
          child: GuidePage(key: PageStorageKey('guide')),
        );
      case 5:
        return AchievementsPage(key: const PageStorageKey('achievements'));
      case 6:
        return const SettingsPage(key: PageStorageKey('settings'));
      default:
        return const HomeScreen(key: PageStorageKey('home'));
    }
  }

  @override
  void initState() {
    super.initState();
    UserGoalController.loadGoal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndForceUsernameFix());
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex || _switchLocked) return;
    _switchLocked = true;
    FocusManager.instance.primaryFocus?.unfocus();

    // عند التنقل بين صفحات ثقيلة مثل الرجيم/الهوم/التصوير، نفرّغ كاش الصور
    // حتى لا يضغط iOS الذاكرة ويقفل التطبيق بعد عدة انتقالات.
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _selectedIndex = index);

    // حماية من الضغط السريع المتكرر على أكثر من تبويب بنفس اللحظة.
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      _switchLocked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<String>(
      valueListenable: UserGoalController.userGoal,
      builder: (context, _, __) {
        return Scaffold(
          body: SafeArea(
            top: false,
            bottom: false,
            child: PageStorage(
              bucket: _pageStorageBucket,
              child: KeyedSubtree(
                key: ValueKey<int>(_selectedIndex),
                child: _buildScreen(_selectedIndex),
              ),
            ),
          ),
          bottomNavigationBar: _GlassAdaptiveNavBar(
            currentIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            activeColor: cs.primary,
            inactiveColor: cs.onSurfaceVariant,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'الرئيسية'),
              NavigationDestination(icon: Icon(Icons.person), label: 'بياناتي'),
              NavigationDestination(icon: Icon(Icons.monitor_weight), label: 'تتبع الوزن'),
              NavigationDestination(icon: Icon(Icons.local_hospital), label: 'رجيمي'),
              NavigationDestination(icon: Icon(Icons.map), label: 'دليلك'),
              NavigationDestination(icon: Icon(Icons.emoji_events), label: 'الإنجازات'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
            ],
          ),
        );
      },
    );
  }
}

class _GlassAdaptiveNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final Color activeColor;
  final Color inactiveColor;

  const _GlassAdaptiveNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.activeColor,
    required this.inactiveColor,
  });

  double _targetHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    // ✅ لا نقيد التكبير هنا: حجم الخط يُطبّق على كامل التطبيق عبر MediaQuery في main.dart.
    // نرفع ارتفاع شريط التنقل فقط عند تكبير الخط لتفادي قصّ النص.
    final scale = mq.textScaleFactor;
    final shortest = mq.size.shortestSide;
    final isCompact = shortest < 360 || scale > 1.10;
    return isCompact ? 56.0 : 64.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final height = _targetHeight(context);

    return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [cs.surface.withOpacity(0.42), cs.surfaceVariant.withOpacity(0.30)]
                      : [cs.surface.withOpacity(0.70), cs.surfaceVariant.withOpacity(0.52)],
                ),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.28 : 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  height: height,
                  indicatorColor: activeColor.withOpacity(0.14),
                  labelTextStyle: MaterialStateProperty.resolveWith<TextStyle?>(
                    (states) {
                      final selected = states.contains(MaterialState.selected);
                      return TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? activeColor : inactiveColor,
                        height: 1.0,
                      );
                    },
                  ),
                  iconTheme: MaterialStateProperty.resolveWith<IconThemeData?>(
                    (states) {
                      final selected = states.contains(MaterialState.selected);
                      return IconThemeData(
                        color: selected ? activeColor : inactiveColor,
                        size: height <= 56 ? 22 : 24,
                      );
                    },
                  ),
                  labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedIndex: currentIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: destinations,
                ),
              ),
            ),
          ),
        ),
      );
  }
}

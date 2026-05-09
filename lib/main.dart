// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart'
    show
        kDebugMode,
        kReleaseMode,
        kIsWeb,
        defaultTargetPlatform,
        TargetPlatform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'app/auth_gate.dart' show AuthGate;

// Providers & Theme
import 'providers/theme_provider.dart';
import 'providers/user_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/goal_provider.dart';

// Screens
import 'screens/weight_tracking_page.dart';
import 'screens/user_input_page.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/settings_page.dart';
import 'screens/my_data_page.dart';
import 'screens/guide_page.dart';
import 'screens/restaurants_page.dart';
import 'screens/virtual_gym_page.dart';
import 'screens/login_page.dart';
import 'screens/register_page.dart';
import 'screens/welcome_screen.dart';
import 'screens/lifestyle_questions_page.dart';
import 'screens/verify_email_page.dart';
import 'screens/set_goal_page.dart';
import 'screens/goal_progress_onboarding_page.dart';
import 'screens/summary_page.dart';
import 'screens/keto_regimen_screen.dart';
import 'screens/food_capture_page.dart';

import 'models/weight_goal.dart';

// ✅ التجربة 3 أيام ثم إلزام الاشتراك
import 'settings/subscription_page.dart';
import 'app/app_nav.dart';
import 'notifications/fcm_marketing_push.dart';
import 'services/app_review_service.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'fasting/fasting_notifications.dart';
import 'notifications/app_notifications.dart';
import 'notifications/notification_sync_service.dart';
import 'notifications/tz_config.dart';
import 'shared/safe_prefs.dart';
import 'features/recipes/data/recipe_repository.dart';
import 'features/recipes/providers/recipe_provider.dart';
import 'features/recipes/ui/recipes_explore_page.dart';
import 'features/recipes/ui/recipe_create_page.dart';
import 'schedule/plan_picker_page.dart';
import 'schedule/create_schedule_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

bool get _isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Initializes Firebase App Check.
///
/// - Web: ReCaptcha
/// - Android: Debug / Play Integrity
/// - Apple: Debug / App Attest
/// - Windows: يتم التخطي لأنه غير مدعوم هنا في إعدادك الحالي
Future<void> setupAppCheck({required String recaptchaSiteKey}) async {
  try {
    if (_isWindows) {
      debugPrint('ℹ️ [AppCheck] Skipped on Windows.');
      return;
    }

    if (kIsWeb && recaptchaSiteKey.trim().isEmpty) {
      throw Exception('RECAPTCHA_SITE_KEY مطلوب لتفعيل App Check على الويب');
    }

    if (kIsWeb) {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider(recaptchaSiteKey),
      );
    } else if (_isAndroid) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kReleaseMode
            ? AndroidProvider.playIntegrity
            : AndroidProvider.debug,
      );
    } else if (_isApple) {
      await FirebaseAppCheck.instance.activate(
        appleProvider:
            kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
      );
    } else {
      debugPrint(
        'ℹ️ [AppCheck] Skipped on unsupported platform: $defaultTargetPlatform',
      );
      return;
    }

    // تمكين التحديث التلقائي للتوكن لضمان عدم انقطاع الجلسة
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    if (kDebugMode) {
      FirebaseAppCheck.instance.onTokenChange.listen((token) {
        final short = (token == null || token.length < 20)
            ? token
            : '${token.substring(0, 20)}...';
        debugPrint('🔐 [AppCheck] onTokenChange: $short');
      });

      try {
        final t = await FirebaseAppCheck.instance.getToken(true);
        final short =
            (t == null || t.length < 20) ? t : '${t.substring(0, 20)}...';
        debugPrint('🔐 [AppCheck] getToken(forceRefresh): $short');
      } catch (e) {
        debugPrint('⚠️ [AppCheck] getToken(forceRefresh) failed: $e');
      }

      debugPrint(
        'ℹ️ [AppCheck] Debug provider enabled. '
        'لإظهار "Firebase App Check Debug Token: <...>" في Xcode: '
        'أضف -FIRDebugEnabled في Run Scheme (Arguments Passed On Launch) ثم شغّل التطبيق من Xcode.',
      );
    }
  } catch (e, st) {
    debugPrint('⚠️ [AppCheck] Initialization Error: $e');
    debugPrint('$st');
  }
}

Future<void> _printEnvDiagnostics() async {
  final opts = DefaultFirebaseOptions.currentPlatform;
  final info = await PackageInfo.fromPlatform();
  debugPrint('🔎 Firebase appId: ${opts.appId}');
  debugPrint('🔎 Package name: ${info.packageName}');
  debugPrint('🔎 Build Mode: ${kReleaseMode ? "Release" : "Debug"}');
  debugPrint('🔎 Platform: $defaultTargetPlatform');
}

Future<void> _initNotificationsIfSupported() async {
  if (_isWindows) {
    debugPrint('ℹ️ Notifications init skipped on Windows.');
    return;
  }

  TzConfig.ensureInitialized();

  await FastingNotifications.instance.init();
  await AppNotifications.instance.init();
  await AppNotifications.instance.restoreFromLocalPrefs();

  // ✅ مزامنة إعدادات الإشعارات من Firestore + جدولة العروض (عند فتح التطبيق)
  NotificationSyncService.instance.start();
}

Future<void> _initFcmIfSupported() async {
  if (_isWindows) {
    debugPrint('ℹ️ FCM marketing push skipped on Windows.');
    return;
  }

  // ✅ FCM (عروض تسويقية): حفظ التوكن + Topics + Deeplink
  await FcmMarketingPush.instance.init();
}

Future<void> _safeStartupTask(
  String name,
  Future<void> Function() task,
) async {
  try {
    await task().timeout(const Duration(seconds: 8));
    debugPrint('✅ [$name] initialized');
  } catch (e, st) {
    // لا نخلي الخدمات الاختيارية مثل الإشعارات/FCM تمنع فتح التطبيق.
    debugPrint('⚠️ [$name] startup skipped: $e');
    debugPrint('$st');
  }
}

Future<void> _startOptionalServicesAfterFirstFrame() async {
  // شغّل FCM كخدمة مستقلة حتى لو تعطلت جدولة الإشعارات المحلية
  // أو أخذت وقت طويل. هذا مهم حتى تُحفظ التوكنات وتشتغل Topics.
  unawaited(_safeStartupTask('FCM', _initFcmIfSupported));

  await _safeStartupTask('Notifications', _initNotificationsIfSupported);
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. تشغيل الـ Env بشكل اختياري وآمن.
    // مهم: لا تستخدم dotenv.env إذا فشل تحميل .env، لأن هذا يسبب NotInitializedError.
    bool envLoaded = false;
    try {
      await dotenv.load(fileName: ".env");
      envLoaded = true;
      debugPrint('✅ .env loaded');
    } catch (e) {
      debugPrint(
        "⚠️ ملف .env غير موجود أو غير قابل للقراءة — سيتم استخدام الإعدادات الافتراضية.",
      );
      if (kDebugMode) debugPrint('dotenv load skipped: $e');
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 2. تفعيل App Check
    final recaptchaKey =
        envLoaded ? (dotenv.env['RECAPTCHA_SITE_KEY'] ?? '') : '';
    await setupAppCheck(recaptchaSiteKey: recaptchaKey);

    // ✅ ملاحظة تشخيصية: إذا استمر التعليق، عطل السطر أدناه لفحص السيرفر مباشرة
    // FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

    await _printEnvDiagnostics();
    await initializeDateFormatting('ar', null);

    // 3. تهيئة الإعدادات الأساسية فقط قبل runApp
    await SafePrefs.fixKnownMismatches();

    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('darkMode') ?? false;
    final fontSize = prefs.getString('fontSize') ?? 'متوسط';
    final themeProvider = await ThemeProvider.load(
      defaultDark: isDarkMode,
      defaultFontSize: fontSize,
    );

    runApp(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => UserDataProvider()),
            ChangeNotifierProvider(create: (_) => DietProvider()),
            ChangeNotifierProvider(create: (_) => GoalProvider()),
            Provider(
              create: (_) => RecipeRepository(FirebaseFirestore.instance),
            ),
            ChangeNotifierProvider(
              create: (c) => RecipeProvider(c.read<RecipeRepository>()),
            ),
          ],
          child: const CalorieApp(),
        ),
      ),
    );

    // 4. شغّل الخدمات الاختيارية بعد ظهور أول واجهة حتى لا تسبب شاشة بيضاء عند الإقلاع.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startOptionalServicesAfterFirstFrame());

      Future<void>.delayed(const Duration(seconds: 3), () {
        final context = AppNav.key.currentContext;
        if (context != null) {
          unawaited(AppReviewService.maybeShowPeriodicPrompt(context));
        }
      });
    });
  }, (Object error, StackTrace stack) {
    debugPrint('❌ UNCAUGHT ERROR: $error');
    debugPrint('$stack');
  });
}

class CalorieApp extends StatelessWidget {
  const CalorieApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return MaterialApp(
      navigatorKey: AppNav.key,
      title: ' تطبيق وازن',
      debugShowCheckedModeBanner: false,
      theme: theme.themeLight,
      darkTheme: theme.themeDark,
      themeMode: theme.themeMode,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaleFactor: theme.fontScale),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AuthGate(),
      routes: {
        '/settings': (context) => const SettingsPage(),
        '/profile': (context) => const MyDataPage(),
        '/weight': (context) => WeightTrackingPage(),
        '/guide': (context) => const GuidePage(),
        '/restaurants': (context) => const RestaurantsPage(),
        '/gym': (context) => const VirtualGymPage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const RegisterPage(),
        '/welcome': (context) => const WelcomeScreen(),
        '/lifestyle': (context) => const LifestyleQuestionsPage(),
        '/home': (context) => const MainNavigationScreen(),
        '/subscription': (context) => const SubscriptionPage(force: true),
        '/user_input': (context) => const UserInputPage(lifestyleScore: 0),
        '/set-goal': (context) => const SetGoalPage(),
        '/goal-progress': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final goal = (args is WeightGoal) ? args : null;
          return GoalProgressOnboardingPage(goal: goal);
        },
        '/summary': (context) => const SummaryPage(),
        '/keto': (context) => const KetoRegimenScreen(),
        '/schedulePicker': (context) => const PlanPickerPage(),
        '/createSchedule': (context) => const CreateSchedulePage(),
        '/recipes': (context) => const RecipesExplorePage(),
        '/recipes/create': (context) => const RecipeCreatePage(),
        '/food/capture': (context) => const FoodCapturePage(),
        '/verifyEmail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map?;
          final email = (args?['email'] as String?) ??
              (FirebaseAuth.instance.currentUser?.email ?? '');
          return VerifyEmailPage(email: email);
        },
      },
    );
  }
}

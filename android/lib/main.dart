// lib/main.dart
// AuthGate متوافق مع التحقّق من البريد + onBoarding من users/{uid}/meta/onboarding

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// ✅ استخدم AuthGate الموحّد من app/auth_gate.dart
import 'app/auth_gate.dart' show AuthGate;

// Providers & Theme
import 'providers/theme_provider.dart';
import 'providers/user_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/goal_provider.dart';

// Screens
import 'screens/splash_screen.dart' show SplashScreen, kSplashTotalMs;
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
import 'screens/summary_page.dart';
import 'screens/keto_regimen_screen.dart';

// ✅ صفحة التقاط الطعام الجديدة
import 'screens/food_capture_page.dart';

import 'package:shared_preferences/shared_preferences.dart';

// صيام
import 'fasting/fasting_notifications.dart';

// ✅ تنظيف المفاتيح الغلط
import 'shared/safe_prefs.dart';

import 'features/recipes/data/recipe_repository.dart';
import 'features/recipes/providers/recipe_provider.dart';
import 'features/recipes/ui/recipes_explore_page.dart';
import 'features/recipes/ui/recipe_create_page.dart';

// جداول
import 'schedule/plan_picker_page.dart';
import 'schedule/create_schedule_page.dart';

import 'package:package_info_plus/package_info_plus.dart';

Future<void> setupAppCheck({required String recaptchaSiteKey}) async {
  await FirebaseAppCheck.instance.activate(
    webProvider: ReCaptchaV3Provider(recaptchaSiteKey),
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: kReleaseMode ? AppleProvider.appAttestWithDeviceCheckFallback : AppleProvider.debug,
  );
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  if (kDebugMode) {
    try {
      final debugToken = await FirebaseAppCheck.instance.getToken(true);
      // ignore: avoid_print
      print('🔥 App Check debug token: $debugToken');
    } catch (e) {
      try {
        final t2 = await FirebaseAppCheck.instance.getLimitedUseToken();
        // ignore: avoid_print
        print('🔥 App Check limited-use token (fallback): $t2');
      } catch (e2) {
        // ignore: avoid_print
        print('⚠️ App Check token fetch failed: $e, fallback: $e2');
      }
    }
  }
}

Future<void> _printEnvDiagnostics() async {
  final opts = DefaultFirebaseOptions.currentPlatform;
  final info = await PackageInfo.fromPlatform();
  // ignore: avoid_print
  print('🔎 Firebase appId: ${opts.appId}');
  // ignore: avoid_print
  print('🔎 iOS bundleId / Android package: ${info.packageName}');
  // ignore: avoid_print
  print('🔎 kReleaseMode=$kReleaseMode  kDebugMode=$kDebugMode');
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await dotenv.load(fileName: ".env");
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    try {
      FirebaseAuth.instance.setLanguageCode('ar');
    } catch (_) {}

    final recaptchaKey = dotenv.env['RECAPTCHA_SITE_KEY'] ??
        const String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: 'unused');

    await setupAppCheck(recaptchaSiteKey: recaptchaKey);
    await _printEnvDiagnostics();
    await initializeDateFormatting('ar', null);

    await SafePrefs.fixKnownMismatches();
    await FastingNotifications.instance.init();

    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('darkMode') ?? false;
    final fontSize = prefs.getString('fontSize') ?? 'متوسط';

    final currentEmail = FirebaseAuth.instance.currentUser?.email ?? 'unknown_user';

    final themeProvider = await ThemeProvider.load(
      defaultDark: isDarkMode,
      defaultFontSize: fontSize,
    );

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
      Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.empty);
    };

    ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('\n============= PlatformDispatcher ERROR =============');
      debugPrint('Error: $error');
      debugPrintStack(stackTrace: stack);
      debugPrint('===================================================\n');
      return true;
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Colors.red.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'تعذّر تحميل الواجهة:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    };

    runApp(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => UserDataProvider()..loadUserData(currentEmail)),
            ChangeNotifierProvider(create: (_) => DietProvider()),
            ChangeNotifierProvider(create: (_) => GoalProvider()),
            Provider(create: (_) => RecipeRepository(FirebaseFirestore.instance)),
            ChangeNotifierProvider(create: (c) => RecipeProvider(c.read<RecipeRepository>())),
          ],
          child: const CalorieApp(),
        ),
      ),
    );
  }, (Object error, StackTrace stack) {
    debugPrint('\n================= UNCAUGHT ERROR =================');
    debugPrint('Error: $error');
    debugPrintStack(stackTrace: stack);
    debugPrint('==================================================\n');
  });
}

class CalorieApp extends StatelessWidget {
  const CalorieApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'تطبيق ميزان',
        debugShowCheckedModeBanner: false,

        theme: theme.themeLight,
        darkTheme: theme.themeDark,
        themeMode: theme.themeMode,

        builder: (context, child) {
          final scale = theme.fontScale;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          );
        },

        // ✅ نقطة الدخول: AuthGate الموحّد من app/auth_gate.dart
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
          '/user_input': (context) => const UserInputPage(lifestyleScore: 0),
          '/set-goal': (context) => const SetGoalPage(),
          '/summary': (context) => const SummaryPage(),
          '/keto': (context) => const KetoRegimenScreen(),

          '/schedulePicker': (context) => const PlanPickerPage(),
          '/createSchedule': (context) => const CreateSchedulePage(),

          '/recipes': (context) => const RecipesExplorePage(),
          '/recipes/create': (context) => const RecipeCreatePage(),

          // ✅ صفحة التقاط الطعام: افتحها من الهوم سكرين أو أي مكان
          '/food/capture': (context) => const FoodCapturePage(),

          // تمرير الإيميل لصفحة التحقق
          '/verifyEmail': (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map?;
            final email = (args?['email'] as String?) ?? (FirebaseAuth.instance.currentUser?.email ?? '');
            return VerifyEmailPage(email: email);
          },
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============ الهوية ============
/// - افتراضي: مظهر وازن الأصلي Classic Green (#28B4AC)
/// - يدعم: نظامي / أخضر / أسود-نقي / أحمر×أخضر / أزرق×برتقالي / بنفسجي×نعناع / تباين عالي (فاتح/داكن)
/// - تكبير النص عبر MediaQuery (لا نعدّل TextTheme لتفادي Assertions)
enum AppThemeId {
  systemDefault,
  classicGreen,
  softBlackLight,
  pureBlack,
  redGreen,
  blueOrange,
  purpleMint,
  highContrastLight,
  highContrastDark,
}

class ThemeProvider extends ChangeNotifier {
  // ===== توافق للخلف (لصفحات قديمة) =====
  bool isDarkMode;
  String fontSize;

  ThemeProvider({required this.isDarkMode, required this.fontSize});

  static const _keyTheme = 'app_theme';
  static const _keyFont  = 'fontSize';
  static const _keyDark  = 'darkMode';

  AppThemeId _current = AppThemeId.classicGreen;
  AppThemeId get current => _current;

  // حمّل من SharedPreferences
  static Future<ThemeProvider> load({
    bool defaultDark = false,
    String defaultFontSize = 'متوسط',
  }) async {
    final prefs      = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_keyTheme);
    final savedFont  = prefs.getString(_keyFont) ?? defaultFontSize;
    final savedDark  = prefs.getBool(_keyDark) ?? defaultDark;

    final p = ThemeProvider(isDarkMode: savedDark, fontSize: savedFont);

    final normalizedSavedTheme = savedTheme?.trim();
    final parsed = _fromString(normalizedSavedTheme);

    // ✅ مظهر وازن الأصلي هو الافتراضي دائمًا.
    // إذا كان المستخدم القديم عنده قيمة رمضانية محفوظة أو قيمة غير معروفة،
    // نرجّعه تلقائيًا إلى مظهر وازن ونصحّح التخزين.
    if (normalizedSavedTheme == null ||
        normalizedSavedTheme.isEmpty ||
        normalizedSavedTheme == 'ramadan' ||
        parsed == null) {
      p._current = AppThemeId.classicGreen;
      await prefs.setString(_keyTheme, p._current.name);
    } else {
      p._current = parsed;
    }
    return p;
  }

  // غيّر الثيم واحفظه
  Future<void> setTheme(AppThemeId id) async {
    _current = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, id.name);
    notifyListeners();
  }

  // غيّر حجم الخط واحفظه
  Future<void> updateFontSize(String value) async {
    fontSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFont, value);
    notifyListeners();
  }

  // تكبير النص (يُطبَّق في MaterialApp.builder عبر MediaQuery)
  double get fontScale {
    switch (fontSize) {
      case 'صغير':      return 0.9;
      case 'كبير':      return 1.1;
      case 'كبير جدًا': return 1.2;
      case 'متوسط':
      default:          return 1.0;
    }
  }

  // توافق قديم: سويتش داكن/فاتح (لو تُستخدمه شاشات قديمة)
  Future<void> toggleTheme(bool value) async {
    isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDark, value);
    notifyListeners();
  }

  // وضع الثيم (MaterialApp.themeMode)
  ThemeMode get themeMode {
    // يدعم زر الوضع الداكن القديم مع مظهر وازن الأصلي،
    // وفي نفس الوقت يحافظ على الثيمات التي تفرض الفاتح/الداكن.
    switch (_current) {
      case AppThemeId.systemDefault:
        return ThemeMode.system;
      case AppThemeId.classicGreen:
        return isDarkMode ? ThemeMode.dark : ThemeMode.light;
      case AppThemeId.highContrastDark:
      case AppThemeId.pureBlack:
        return ThemeMode.dark;
      default:
        return ThemeMode.light;
    }
  }

  // ثيمات MaterialApp: نرجّع الاثنين دائمًا (علشان systemDefault يشتغل)
  ThemeData get themeLight => _buildTheme(light: true);
  ThemeData get themeDark  => _buildTheme(light: false);

  // ================== مصانع الثيم ==================

  ThemeData _buildTheme({required bool light}) {
    switch (_current) {
      case AppThemeId.systemDefault:
      case AppThemeId.classicGreen:
        return _classicGreen(light: light);

      case AppThemeId.softBlackLight:
        return _softBlackLight(light: light);

      case AppThemeId.pureBlack:
        // داكن فقط (لكن نرجّع لايت احتياطي لو طُلب لايت)
        return light ? _classicGreen(light: true) : _pureBlack();

      case AppThemeId.redGreen:
        return _seeded(
          primarySeed: const Color(0xFF0B6E4F),
          secondarySeed: const Color(0xFFE35D6A),
          light: light,
        );

      case AppThemeId.blueOrange:
        return _seeded(
          primarySeed: const Color(0xFF0B4F6C),
          secondarySeed: const Color(0xFFF59E0B),
          light: light,
        );

      case AppThemeId.purpleMint:
        return _seeded(
          primarySeed: const Color(0xFF5B21B6),
          secondarySeed: const Color(0xFF2DD4BF),
          light: light,
        );

      case AppThemeId.highContrastLight:
        return light ? _highContrast(light: true) : _highContrast(light: false);

      case AppThemeId.highContrastDark:
        return light ? _classicGreen(light: true) : _highContrast(light: false);
    }
  }

  

// الافتراضي — مظهر وازن بنسخة داكنة نظيفة وموحدة
  ThemeData _classicGreen({required bool light}) {
    const brand = Color(0xFF22B8AE);
    const brandDeep = Color(0xFF0F766E);
    const brandSoft = Color(0xFFE6F7F5);
    const ink = Color(0xFF102326);
    const lightBg = Color(0xFFF7FAF9);

    // لوحة داكنة مثل تطبيقات التتبع العالمية: رمادي داكن ناعم، كروت ثابتة، بدون سواد حاد.
    const darkBg = Color(0xFF121212);
    const darkSurface = Color(0xFF1B1B1D);
    const darkCard = Color(0xFF222224);
    const darkSoft = Color(0xFF2A2A2D);
    const darkOutline = Color(0xFF3A3A3D);
    const darkText = Color(0xFFF5F5F7);
    const darkMuted = Color(0xFFB0B0B4);
    // لون الأكشن في الداكن صار Sage هادئ بدل التركوازي الفاقع.
    const darkAccent = Color(0xFF8FA5A1);
    const darkAction = Color(0xFF2B3433);

    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: light ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: light ? brandDeep : darkAccent,
      onPrimary: light ? Colors.white : darkText,
      secondary: light ? brand : darkAccent,
      onSecondary: light ? Colors.white : darkText,
      tertiary: light ? const Color(0xFF0A3D62) : const Color(0xFF8FD7FF),
      background: light ? lightBg : darkBg,
      onBackground: light ? ink : darkText,
      surface: light ? Colors.white : darkSurface,
      onSurface: light ? ink : darkText,
      surfaceVariant: light ? const Color(0xFFEAF3F1) : darkCard,
      onSurfaceVariant: light ? const Color(0xFF536461) : darkMuted,
      outline: light ? const Color(0xFFDCE8E5) : const Color(0xFF47474A),
      outlineVariant: light ? const Color(0xFFDCE8E5) : darkOutline,
      primaryContainer: light ? brandSoft : const Color(0xFF26312F),
      onPrimaryContainer: light ? const Color(0xFF064D45) : darkText,
      secondaryContainer: light ? const Color(0xFFE7F7F5) : const Color(0xFF252C2B),
      onSecondaryContainer: light ? const Color(0xFF064D45) : darkText,
      error: const Color(0xFFE74C3C),
      errorContainer: light ? const Color(0xFFFFE5E3) : const Color(0xFF3A2424),
    );

    final cardColor = light ? Colors.white : darkCard;
    final navColor = light ? Colors.white.withOpacity(.92) : const Color(0xF21E1E20);
    final shadow = Colors.black.withOpacity(light ? 0.045 : 0.28);

    return ThemeData(
      useMaterial3: true,
      brightness: light ? Brightness.light : Brightness.dark,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: scheme.background,
      canvasColor: scheme.background,
      splashColor: scheme.primary.withOpacity(.08),
      highlightColor: scheme.primary.withOpacity(.05),
      dividerColor: scheme.outlineVariant.withOpacity(light ? .70 : .55),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: 'Tajawal',
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(light ? .14 : .20),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            fontSize: 12,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: selected ? 25 : 23,
          );
        }),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: navColor,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),

      bottomAppBarTheme: BottomAppBarThemeData(
        color: navColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: light ? 0.8 : 0.0,
        shadowColor: shadow,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withOpacity(light ? .45 : .36)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      inputDecorationTheme: _inputTheme(isDark: !light, scheme: scheme),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: light ? scheme.primary : darkAction,
          foregroundColor: light ? Colors.white : darkText,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Tajawal'),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: light ? scheme.primary : darkAction,
          foregroundColor: light ? Colors.white : darkText,
          elevation: light ? 0.6 : 0,
          shadowColor: scheme.primary.withOpacity(.16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Tajawal'),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withOpacity(light ? .32 : .42)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Tajawal'),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Tajawal'),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(light ? .70 : .45)),
        backgroundColor: light ? brandSoft.withOpacity(.75) : darkSoft,
        selectedColor: scheme.primary.withOpacity(light ? .16 : .24),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: light ? const Color(0xFF064D45) : const Color(0xFF232326),
        contentTextStyle: TextStyle(
          color: light ? Colors.white : const Color(0xFFEAF7F5),
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: light ? scheme.primary : darkAction,
        foregroundColor: light ? Colors.white : darkText,
        elevation: light ? 0.8 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: light ? 3 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(
          fontFamily: 'Tajawal',
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withOpacity(light ? .65 : .50),
        thickness: 1,
        space: 24,
      ),

      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      ),
    );
  }

  ThemeData _pureBlack() {
    // Midnight Pro: داكن نظيف قريب من تطبيقات التتبع العالمية، بدون سواد حاد أو كروت فاقعة.
    const bg = Color(0xFF141414);
    const surface = Color(0xFF1C1C1E);
    const card = Color(0xFF222224);
    const cardSoft = Color(0xFF2A2A2D);
    const primary = Color(0xFF8FA5A1);
    const secondary = Color(0xFFC3D0CD);
    const on = Color(0xFFF5F5F7);
    const muted = Color(0xFFB0B0B4);
    const outline = Color(0xFF3A3A3D);

    final scheme = const ColorScheme.dark().copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Color(0xFF00110F),
      tertiary: Color(0xFF8FD7FF),
      background: bg,
      onBackground: on,
      surface: surface,
      onSurface: on,
      surfaceVariant: card,
      onSurfaceVariant: muted,
      outline: const Color(0xFF47474A),
      outlineVariant: outline,
      primaryContainer: const Color(0xFF253B39),
      onPrimaryContainer: on,
      secondaryContainer: const Color(0xFF2A3334),
      onSecondaryContainer: on,
      error: const Color(0xFFFF6B61),
      errorContainer: const Color(0xFF3A2424),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: outline.withOpacity(.65),
      splashColor: primary.withOpacity(.08),
      highlightColor: primary.withOpacity(.05),

      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: on,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          color: on,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),

      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: outline.withOpacity(.70)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: primary.withOpacity(.18),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 12,
            color: selected ? primary : muted,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return IconThemeData(
            color: selected ? primary : muted,
            size: selected ? 25 : 23,
          );
        }),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xF21E1E20),
        selectedItemColor: primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w900),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),

      bottomAppBarTheme: const BottomAppBarThemeData(
        color: Color(0xF21E1E20),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF2B3433),
        foregroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: cardSoft,
        selectedColor: primary.withOpacity(0.22),
        side: BorderSide(color: outline.withOpacity(.70)),
        labelStyle: const TextStyle(
          color: on,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      inputDecorationTheme: _inputTheme(isDark: true, scheme: scheme),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2B3433),
          foregroundColor: const Color(0xFFF5F5F7),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w900),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2B3433),
          foregroundColor: const Color(0xFFF5F5F7),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w900),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withOpacity(.42)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
        ),
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF232326),
        contentTextStyle: TextStyle(color: Color(0xFFEAF7F5), fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: const TextStyle(fontFamily: 'Tajawal', color: on, fontWeight: FontWeight.w900, fontSize: 18),
        contentTextStyle: const TextStyle(fontFamily: 'Tajawal', color: muted, fontWeight: FontWeight.w600),
      ),

      dividerTheme: DividerThemeData(
        color: outline.withOpacity(.70),
        thickness: 1,
        space: 24,
      ),

      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: primary,
        unselectedLabelColor: muted,
        indicatorColor: primary,
        labelStyle: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w900),
        unselectedLabelStyle: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Tajawal', color: on, fontWeight: FontWeight.w700),
      ),
    );
  }

  ThemeData _seeded({
    required Color primarySeed,
    required Color secondarySeed,
    required bool light,
  }) {
    // ثيمات إضافية (Health-Lux) — نظيفة وناعمة
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: light ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: primarySeed,
      onPrimary: Colors.white,
      secondary: secondarySeed,
      onSecondary: Colors.white,
      background: light ? const Color(0xFFF6F8FA) : const Color(0xFF0A1014),
      surface: light ? Colors.white : const Color(0xFF0E141A),
      onSurface: light ? const Color(0xFF0F172A) : Colors.white,
      onBackground: light ? const Color(0xFF0F172A) : Colors.white,
    );

    final outline = light ? const Color(0xFFE7EAF0) : Colors.white12;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: scheme.background,

      appBarTheme: AppBarTheme(
        backgroundColor: light ? Colors.white : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: light ? 0.6 : 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        color: light ? Colors.white : const Color(0xFF121A21),
        elevation: light ? 1.2 : 0.9,
        shadowColor: Colors.black.withOpacity(light ? 0.06 : 0.35),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
      ),

      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 24,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: light ? Colors.white : const Color(0xFF0E141A),
        selectedItemColor: scheme.primary,
        unselectedItemColor: light ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0.8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.secondaryContainer.withOpacity(light ? 0.32 : 0.20),
        selectedColor: scheme.secondaryContainer.withOpacity(light ? 0.48 : 0.30),
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      inputDecorationTheme: _inputTheme(isDark: !light, scheme: scheme),
    );
  }

  ThemeData _highContrast({required bool light}) {
    final scheme = light
        ? const ColorScheme.highContrastLight()
        : const ColorScheme.highContrastDark();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w800)),
          elevation: const WidgetStatePropertyAll(2),
        ),
      ),
      inputDecorationTheme: _inputTheme(isDark: !light, scheme: scheme),
      cardTheme: CardThemeData(
        color: light ? Colors.white : const Color(0xFF1A1F24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static AppThemeId? _fromString(String? v) {
    if (v == null) return null;
    for (final t in AppThemeId.values) {
      if (t.name == v) return t;
    }
    return null;
  }

  // ====== Inputs ======
  InputDecorationTheme _inputTheme({
    required bool isDark,
    required ColorScheme scheme,
  }) {
    final borderColor =
        isDark ? Colors.white.withOpacity(0.16) : scheme.outlineVariant;
    final focusColor = scheme.primary;
    final fillColor = isDark ? const Color(0xFF222224) : Colors.white;

    OutlineInputBorder border(Color c, {double width = 1}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: width),
        );

    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      hintStyle: TextStyle(color: isDark ? const Color(0xFF9AAEB6) : Colors.black45),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: border(borderColor),
      focusedBorder: border(focusColor, width: 1.6),
      errorBorder: border(const Color(0xFFE74C3C).withOpacity(.95)),
      focusedErrorBorder: border(const Color(0xFFE74C3C), width: 1.6),
      prefixIconColor: isDark ? const Color(0xFF9AAEB6) : Colors.black54,
      suffixIconColor: isDark ? const Color(0xFF9AAEB6) : Colors.black54,
      labelStyle:
          TextStyle(color: isDark ? const Color(0xFF9AAEB6) : Colors.black87),
    );
  }


ThemeData _softBlackLight({required bool light}) {
  // Porcelain: أبيض مطفي + حواف ناعمة + لمسة نعناع (فخم وصحي)
  const ink = Color(0xFF0F172A);
  const accent = Color(0xFF28B4AC);

  if (!light) {
    // نسخة داكنة هادئة (لو تم طلبها لأي سبب)
    const bg = Color(0xFF0A1014);
    const surface = Color(0xFF0E141A);
    const card = Color(0xFF121A21);

    final scheme = const ColorScheme.dark().copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      background: bg,
      surface: surface,
      onSurface: Colors.white,
      onBackground: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0.8,
        margin: EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: Color(0xFF94A3B8),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: _inputTheme(isDark: true, scheme: scheme),
    );
  }

  const bg = Color(0xFFF7F8FA);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: ink,
    onPrimary: Colors.white,
    secondary: accent,
    onSecondary: Colors.white,
    background: bg,
    surface: Colors.white,
    onSurface: ink,
    onBackground: ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Tajawal',
  );

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: bg,
      foregroundColor: ink,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.0,
      shadowColor: Colors.black.withOpacity(0.06),
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE7EAF0), thickness: 1, space: 24),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: Color(0xFFE7EAF0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: accent,
      unselectedItemColor: Color(0xFF64748B),
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: accent.withOpacity(0.10),
      selectedColor: accent.withOpacity(0.18),
      labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    inputDecorationTheme: _inputTheme(isDark: false, scheme: scheme),
  );
}
}

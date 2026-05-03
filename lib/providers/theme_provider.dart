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
    switch (_current) {
      case AppThemeId.systemDefault:
        return ThemeMode.system;
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

  
// الافتراضي — #28B4AC (متناغم فاتح/داكن)
  ThemeData _classicGreen({required bool light}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF28B4AC),
      brightness: light ? Brightness.light : Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor:
          light ? const Color(0xFFF6F8FA) : const Color(0xFF12161A),

      appBarTheme: AppBarTheme(
        backgroundColor: light ? Colors.white : scheme.surface,
        foregroundColor: light ? const Color(0xFF0A3D62) : Colors.white,
        elevation: light ? .6 : 0,
        centerTitle: true,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: light ? Colors.white : const Color(0xFF161B20),
        selectedItemColor: scheme.primary,
        unselectedItemColor: light ? Colors.grey.shade700 : Colors.white70,
        type: BottomNavigationBarType.fixed,
      ),

      // ⬅️ استخدم الأنواع المنتهية بـ Data
      cardTheme: CardThemeData(
        color: light ? Colors.white : const Color(0xFF1A1F24),
        elevation: light ? 1.5 : 1.2,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
      ),

      inputDecorationTheme: _inputTheme(isDark: !light, scheme: scheme),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor:
            scheme.secondaryContainer.withOpacity(light ? .30 : .26),
        selectedColor: scheme.secondaryContainer,
        labelStyle: TextStyle(
          color: light ? const Color(0xFF0A3D62) : Colors.white,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  ThemeData _pureBlack() {
    // Midnight: فاخر داكن مع لمسة نعناع (مناسب لتطبيق صحي)
    const bg = Color(0xFF070A0D);
    const surface = Color(0xFF0E141A);
    const card = Color(0xFF111A21);
    const primary = Color(0xFF28B4AC);
    const secondary = Color(0xFF9FE7E1);

    final scheme = const ColorScheme.dark().copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Color(0xFF00110F),
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
        elevation: 0.6,
        margin: EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF94A3B8),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0.8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primary.withOpacity(0.18),
        selectedColor: primary.withOpacity(0.28),
        labelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      inputDecorationTheme: _inputTheme(isDark: true, scheme: scheme),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      dividerColor: Colors.white10,
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
    final fillColor = isDark ? const Color(0xFF1A1F23) : Colors.white;

    OutlineInputBorder border(Color c, {double width = 1}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: width),
        );

    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black45),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: border(borderColor),
      focusedBorder: border(focusColor, width: 1.6),
      errorBorder: border(const Color(0xFFE74C3C).withOpacity(.95)),
      focusedErrorBorder: border(const Color(0xFFE74C3C), width: 1.6),
      prefixIconColor: isDark ? Colors.white70 : Colors.black54,
      suffixIconColor: isDark ? Colors.white70 : Colors.black54,
      labelStyle:
          TextStyle(color: isDark ? Colors.white70 : Colors.black87),
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

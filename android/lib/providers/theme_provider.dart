import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============ الهوية ============
/// - افتراضي: Classic Green (#28B4AC)
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
    p._current = _fromString(savedTheme) ?? AppThemeId.classicGreen;
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
          primarySeed: const Color(0xFF0A8754),
          secondarySeed: const Color(0xFFE63946),
          light: light,
        );

      case AppThemeId.blueOrange:
        return _seeded(
          primarySeed: const Color(0xFF1D4ED8),
          secondarySeed: const Color(0xFFF97316),
          light: light,
        );

      case AppThemeId.purpleMint:
        return _seeded(
          primarySeed: const Color(0xFF7C3AED),
          secondarySeed: const Color(0xFF10B981),
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
    const black = Colors.black;
    const white = Colors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: white,
        onPrimary: black,
        surface: black,
        onSurface: white,
        background: black,
        onBackground: white,
      ),
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: black,
      appBarTheme:
          const AppBarTheme(backgroundColor: black, foregroundColor: white),
      cardTheme: const CardThemeData(color: Color(0xFF111111)),
      dividerColor: Colors.white12,
    );
  }

  ThemeData _seeded({
    required Color primarySeed,
    required Color secondarySeed,
    required bool light,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: light ? Brightness.light : Brightness.dark,
    ).copyWith(
      secondary: secondarySeed,
      onSecondary: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor:
          light ? const Color(0xFFF7F9FB) : const Color(0xFF12161A),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: secondarySeed,
        foregroundColor: Colors.white,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: secondarySeed.withOpacity(light ? 0.12 : 0.20),
        selectedColor: secondarySeed.withOpacity(light ? 0.20 : 0.28),
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      inputDecorationTheme: _inputTheme(isDark: !light, scheme: scheme),
      cardTheme: CardThemeData(
        color: light ? Colors.white : const Color(0xFF1A1F24),
        elevation: light ? 1.2 : 1.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
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
  // White with soft-black accents theme (Material 3)
  const _softBlack = Color(0xFF000000);
  const _bg  = Color(0xFFF5F6F8);
  const _surface = Colors.white;
  const _outline = Color(0xFFE6E8EC);
  const _shadow  = Color(0x1A000000);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _softBlack,
      brightness: Brightness.light,
      primary: _softBlack,
      onPrimary: Colors.white,
      surface: _surface,
      onSurface: _softBlack,
      background: _bg,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: _bg,
    appBarTheme: const AppBarTheme(
      elevation: 0, scrolledUnderElevation: 0,
      backgroundColor: _bg, foregroundColor: _softBlack, centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _softBlack),
    ),
    cardTheme: CardThemeData(
      color: _surface, elevation: 0, surfaceTintColor: _surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(color: _outline, thickness: 1, space: 24),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _softBlack, foregroundColor: Colors.white, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _softBlack, side: const BorderSide(color: _outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: _surface, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _softBlack, width: 1.4)),
      labelStyle: const TextStyle(color: Color(0xFF6B7280)),
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _softBlack, foregroundColor: Colors.white, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _surface, selectedItemColor: _softBlack, unselectedItemColor: Color(0xFF94A3B8),
      type: BottomNavigationBarType.fixed, showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(color: _softBlack, fontWeight: FontWeight.w700),
      titleLarge: const TextStyle(color: _softBlack, fontWeight: FontWeight.w700),
      titleMedium: const TextStyle(color: _softBlack, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: _softBlack.withOpacity(.90)),
      bodyMedium: TextStyle(color: _softBlack.withOpacity(.85)),
      bodySmall: TextStyle(color: _softBlack.withOpacity(.70)),
      labelLarge: const TextStyle(fontWeight: FontWeight.w700),
      labelMedium: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}
}
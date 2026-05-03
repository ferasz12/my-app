import 'package:flutter/material.dart';

/// ثيم صحي فاخر (Light/Dark) — Material 3
/// ملاحظة: هذا ملف ثيم عام (اختياري).
/// تم تحديث كل الحقول لاستخدام الأنواع المنتهية بـ *ThemeData لتفادي أخطاء النوع.
class AppTheme {
  static const Color _seed      = Color(0xFF10C7B0);
  static const Color _brandDark = Color(0xFF0A3D62);
  static const Color _success   = Color(0xFF2ECC71);
  static const Color _warning   = Color(0xFFF1C40F);
  static const Color _error     = Color(0xFFE74C3C);

  static const _rSm = 12.0;
  static const _rMd = 16.0;
  static const _rLg = 20.0;

  static final _shapeSm =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm));
  static final _shapeMd =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rMd));
  static final _shapeLg =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rLg));

  static HealthColors _healthColors(bool dark) => HealthColors(
        success: _success,
        warning: _warning,
        info: dark ? const Color(0xFF58D3F7) : const Color(0xFF16A2D7),
      );

  // ================= Light =================
  static ThemeData getLightTheme(double scale) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: _seed,
      onPrimary: Colors.white,
      secondary: const Color(0xFF18B7AE),
      onSecondary: Colors.white,
      tertiary: _brandDark,
      surface: const Color(0xFFF6F8FA),
      onSurface: const Color(0xFF0F1418),
      error: _error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      primaryColor: scheme.primary,
      fontFamily: 'Tajawal',
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(Colors.black, scale),
      extensions: <ThemeExtension<dynamic>>[_healthColors(false)],

      appBarTheme: _appBarTheme(
        backgroundColor: Colors.white,
        foreground: _brandDark,
        scale: scale,
        elevation: .6,
      ),

      // ⬅️ Data classes
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1.5,
        shadowColor: Colors.black12,
        margin: const EdgeInsets.all(12),
        shape: _shapeLg,
        clipBehavior: Clip.antiAlias,
      ),

      elevatedButtonTheme: _elevatedButtonTheme(scheme),
      filledButtonTheme: _filledButtonTheme(scheme),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: _shapeMd,
          textStyle: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.primary,
          hoverColor: scheme.primary.withOpacity(.08),
          shape: _shapeSm,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        shape: _shapeMd,
      ),

      bottomAppBarTheme: BottomAppBarThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black12,
        shape: const AutomaticNotchedShape(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(_rLg)),
          ),
          StadiumBorder(),
        ),
      ),

      inputDecorationTheme: _inputTheme(isDark: false, scheme: scheme),

      dividerTheme: DividerThemeData(
        color: Colors.grey.shade300,
        thickness: 1,
        space: 24,
      ),

      chipTheme: ChipThemeData(
        shape: _shapeSm,
        backgroundColor: scheme.secondaryContainer.withOpacity(.30),
        selectedColor: scheme.secondaryContainer,
        labelStyle: TextStyle(color: _brandDark, fontSize: 13 * scale),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: _seed,
        textColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(_shapeSm),
          elevation: const WidgetStatePropertyAll(3),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        shape: _shapeSm,
        elevation: 3,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        shape: _shapeLg,
        headerForegroundColor: _brandDark,
        dayForegroundColor: const WidgetStatePropertyAll(Colors.black),
        todayForegroundColor: WidgetStatePropertyAll(scheme.primary),
        todayBackgroundColor:
            WidgetStatePropertyAll(scheme.primary.withOpacity(.10)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        shape: _shapeLg,
        hourMinuteTextColor: scheme.primary,
        dialHandColor: scheme.primary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: _shapeSm,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_rLg + 8)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 2,
        shape: _shapeLg,
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 18 * scale,
          fontWeight: FontWeight.w700,
          color: _brandDark,
        ),
        contentTextStyle:
            TextStyle(fontSize: 14 * scale, color: Colors.black87),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: scheme.primary.withOpacity(.14),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : Colors.grey.shade700,
            size: selected ? 26 : 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 12 * scale,
            color: selected ? scheme.primary : Colors.grey.shade700,
          );
        }),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: scheme.primary,
        unselectedItemColor: Colors.grey.shade700,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w700,
          fontSize: 12 * scale,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w600,
          fontSize: 12 * scale,
        ),
        type: BottomNavigationBarType.fixed,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: Colors.grey.shade600,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2.2),
          insets: const EdgeInsets.symmetric(horizontal: 12),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14 * scale,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14 * scale,
          fontWeight: FontWeight.w600,
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: _shapeMd,
        tileColor: Colors.white,
        selectedColor: scheme.primary,
        iconColor: _brandDark,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _brandDark,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(true),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(12),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.all(scheme.primary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme:
          RadioThemeData(fillColor: WidgetStateProperty.all(scheme.primary)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(scheme.primary),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withOpacity(0.5)
              : Colors.grey.shade300,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withOpacity(0.28),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ================= Dark =================
  static ThemeData getDarkTheme(double scale) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _seed,
      onPrimary: Colors.white,
      secondary: const Color(0xFF149C97),
      onSecondary: Colors.white,
      tertiary: const Color(0xFFB6D7FF),
      surface: const Color(0xFF12161A),
      onSurface: Colors.white,
      error: _error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      primaryColor: scheme.primary,
      fontFamily: 'Tajawal',
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(Colors.white, scale),
      extensions: <ThemeExtension<dynamic>>[_healthColors(true)],

      appBarTheme: _appBarTheme(
        backgroundColor: scheme.surface,
        foreground: Colors.white,
        scale: scale,
        elevation: 0,
      ),

      cardTheme: CardThemeData(
        color: const Color(0xFF1A1F24),
        elevation: 1.2,
        shadowColor: Colors.black45,
        margin: const EdgeInsets.all(12),
        shape: _shapeLg,
        clipBehavior: Clip.antiAlias,
      ),

      elevatedButtonTheme: _elevatedButtonTheme(scheme),
      filledButtonTheme: _filledButtonTheme(scheme),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: _shapeMd,
          textStyle: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.primary,
          hoverColor: scheme.primary.withOpacity(.14),
          shape: _shapeSm,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        shape: _shapeMd,
      ),

      bottomAppBarTheme: const BottomAppBarThemeData(
        color: Color(0xFF161B20),
        elevation: 0,
      ),

      inputDecorationTheme: _inputTheme(isDark: true, scheme: scheme),

      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.08),
        thickness: 1,
        space: 24,
      ),

      chipTheme: ChipThemeData(
        shape: _shapeSm,
        backgroundColor: scheme.secondaryContainer.withOpacity(.26),
        selectedColor: scheme.secondaryContainer,
        labelStyle: TextStyle(color: Colors.white, fontSize: 13 * scale),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: _seed,
        textColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              const WidgetStatePropertyAll(Color(0xFF171B20)),
          shape: WidgetStatePropertyAll(_shapeSm),
          elevation: const WidgetStatePropertyAll(3),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF171B20),
        shape: _shapeSm,
        elevation: 3,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFF171B20),
        shape: _shapeLg,
        headerForegroundColor: Colors.white,
        dayForegroundColor: const WidgetStatePropertyAll(Colors.white),
        todayForegroundColor: WidgetStatePropertyAll(scheme.primary),
        todayBackgroundColor:
            WidgetStatePropertyAll(scheme.primary.withOpacity(.18)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: const Color(0xFF171B20),
        shape: _shapeLg,
        hourMinuteTextColor: Colors.white,
        dialHandColor: scheme.primary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: _shapeSm,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF161B20),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_rLg + 8)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF161B20),
        shape: _shapeLg,
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 18 * scale,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14 * scale,
          color: Colors.white.withOpacity(.9),
        ),
      ),
      drawerTheme:
          const DrawerThemeData(backgroundColor: Color(0xFF161B20)),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF161B20),
        indicatorColor: scheme.primary.withOpacity(.22),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : Colors.white70,
            size: selected ? 26 : 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 12 * scale,
            color: selected ? scheme.primary : Colors.white70,
          );
        }),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF161B20),
        selectedItemColor: scheme.primary,
        unselectedItemColor: Colors.white70,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w700,
          fontSize: 12 * scale,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w600,
          fontSize: 12 * scale,
        ),
        type: BottomNavigationBarType.fixed,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: Colors.white70,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2.2),
          insets: const EdgeInsets.symmetric(horizontal: 12),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14 * scale,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14 * scale,
          fontWeight: FontWeight.w600,
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: _shapeMd,
        tileColor: const Color(0xFF1A1F24),
        selectedColor: _seed,
        iconColor: Colors.white,
      ),
      tooltipTheme: TooltipThemeData(
        decoration:
            BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(color: Colors.white),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(true),
        thickness: WidgetStatePropertyAll(6),
        radius: Radius.circular(12),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.all(scheme.primary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme:
          RadioThemeData(fillColor: WidgetStateProperty.all(scheme.primary)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(scheme.primary),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withOpacity(0.5)
              : Colors.grey.shade700,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withOpacity(0.28),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ========= Typography =========
  static TextTheme _textTheme(Color color, double scale) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 34 * scale,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.15,
      ),
      headlineMedium:
          TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w700, color: color),
      titleLarge:
          TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w700, color: color),
      titleMedium:
          TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w600, color: color),
      bodyLarge:
          TextStyle(fontSize: 16 * scale, color: color.withOpacity(0.92)),
      bodyMedium:
          TextStyle(fontSize: 14 * scale, color: color.withOpacity(0.84)),
      labelLarge:
          TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: color),
    );
  }

  // ========= AppBar =========
  static AppBarTheme _appBarTheme({
    required Color backgroundColor,
    required Color foreground,
    required double scale,
    double elevation = 0,
  }) {
    return AppBarTheme(
      backgroundColor: backgroundColor,
      elevation: elevation,
      centerTitle: true,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: foreground),
      titleTextStyle: TextStyle(
        fontSize: 20 * scale,
        fontWeight: FontWeight.w700,
        color: foreground,
        fontFamily: 'Tajawal',
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(_rSm)),
      ),
    );
  }

  // ========= Buttons =========
  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme s) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: _shapeMd,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(ColorScheme s) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: s.secondary,
        foregroundColor: s.onSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: _shapeMd,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme s) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: s.primary,
        side: BorderSide(color: s.primary, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: _shapeMd,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ========= Inputs =========
  static InputDecorationTheme _inputTheme({
    required bool isDark,
    required ColorScheme scheme,
  }) {
    final borderColor =
        isDark ? Colors.white.withOpacity(0.16) : scheme.outlineVariant;
    final focusColor = scheme.primary;
    final fillColor = isDark ? const Color(0xFF1A1F23) : Colors.white;

    OutlineInputBorder border(Color c, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_rSm + 2),
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
      errorBorder: border(_error.withOpacity(0.95)),
      focusedErrorBorder: border(_error, width: 1.6),
      prefixIconColor: isDark ? Colors.white70 : Colors.black54,
      suffixIconColor: isDark ? Colors.white70 : Colors.black54,
      labelStyle:
          TextStyle(color: isDark ? Colors.white70 : Colors.black87),
    );
  }
}

/// ThemeExtension لألوان الحالات
@immutable
class HealthColors extends ThemeExtension<HealthColors> {
  const HealthColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color info;

  @override
  HealthColors copyWith({Color? success, Color? warning, Color? info}) {
    return HealthColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  HealthColors lerp(ThemeExtension<HealthColors>? other, double t) {
    if (other is! HealthColors) return this;
    return HealthColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

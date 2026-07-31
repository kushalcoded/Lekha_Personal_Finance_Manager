import 'package:flutter/material.dart';

/// Semantic colors the Material [ColorScheme] doesn't carry (positive gains,
/// soft warnings). Negative maps to [ColorScheme.error], accent to primary.
@immutable
class CalmColors extends ThemeExtension<CalmColors> {
  final Color positive;
  final Color warning;

  const CalmColors({required this.positive, required this.warning});

  static const _fallback = CalmColors(
    positive: Color(0xFF46C98B),
    warning: Color(0xFFF0A13B),
  );

  /// Convenience lookup with a safe fallback.
  static CalmColors of(BuildContext context) {
    return Theme.of(context).extension<CalmColors>() ?? _fallback;
  }

  @override
  CalmColors copyWith({Color? positive, Color? warning}) {
    return CalmColors(
      positive: positive ?? this.positive,
      warning: warning ?? this.warning,
    );
  }

  @override
  CalmColors lerp(ThemeExtension<CalmColors>? other, double t) {
    if (other is! CalmColors) return this;
    return CalmColors(
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

class AppTheme {
  // "Midnight Terminal" tokens (locked spec, 30 Jul 2026).
  // The accent is light violet, so fills carry DARK text — white fails 3.2:1.
  static const _accent = Color(0xFF9083F0);
  static const _onAccent = Color(0xFF0A0A0D);
  static const _ground = Color(0xFF0A0A0D);
  static const _surface = Color(0xFF131318);
  static const _surface2 = Color(0xFF1A1A21);
  static const _text = Color(0xFFEDEDEF);
  static const _muted = Color(0xFF8A8F98);
  static const _hairline = Color(0x12FFFFFF); // white 7%
  static const _hairlineStrong = Color(0x24FFFFFF); // white 14%
  static const _positive = Color(0xFF46C98B);
  static const _negative = Color(0xFFF2555A);
  static const _warning = Color(0xFFF0A13B);

  /// Exposed for the rare place that needs the ground outside a Scaffold
  /// (splash, ambient background).
  static const Color ground = _ground;

  /// The app uses a single dark theme — violet accent on neutral near-black.
  static ThemeData get darkTheme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _accent,
          onPrimary: _onAccent,
          secondary: _accent,
          onSecondary: _onAccent,
          surface: _surface,
          onSurface: _text,
          onSurfaceVariant: _muted,
          surfaceContainerHighest: _surface2,
          tertiary: _positive,
          error: _negative,
          onError: Colors.white,
          outline: _hairlineStrong,
          outlineVariant: _hairline,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // Transparent so the global AmbientBackground provides the ground.
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: scheme,
      fontFamily: 'Inter',
      textTheme: _textTheme(),
      dividerColor: _hairline,
      // Desktop pointer states per spec: hover white 4%, pressed white 6%.
      hoverColor: const Color(0x0AFFFFFF),
      highlightColor: const Color(0x0FFFFFFF),
      // Thin unobtrusive scrollbars on web/desktop.
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
        crossAxisMargin: 2,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? const Color(0x47FFFFFF)
              : const Color(0x2EFFFFFF),
        ),
      ),
      extensions: const [CalmColors(positive: _positive, warning: _warning)],
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _text,
        surfaceTintColor: Colors.transparent,
        // Screen titles are one of the three sanctioned Space Grotesk roles
        // (money hero, screen title, stat value) — AppBar would otherwise
        // fall back to titleLarge, which is Inter.
        titleTextStyle: TextStyle(
          fontFamily: 'Space Grotesk',
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: _text,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _hairline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          // styleFrom's textStyle REPLACES labelLarge rather than merging, so
          // the family has to be repeated — without it filled buttons fall
          // back to the platform font while the rest of the app is Inter.
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _surface2,
          foregroundColor: _text,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: Color(0x809083F0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _accent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? _onAccent : _muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? _accent : _surface2,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : _hairlineStrong,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surface2,
        side: const BorderSide(color: _hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Space Grotesk is rationed: display + headline roles only (money heroes,
  /// screen titles, stat values). Everything else is Inter; data labels use
  /// bundled JetBrains Mono via [FieldLabel]-style widgets. Tabular figures
  /// everywhere so amounts line up in columns.
  static TextTheme _textTheme() {
    const tnum = [FontFeature.tabularFigures()];
    final base = Typography.material2021(
      platform: TargetPlatform.android,
    ).white;

    TextStyle display(TextStyle? s) => (s ?? const TextStyle()).copyWith(
      fontFamily: 'Space Grotesk',
      color: _text,
      fontFeatures: tnum,
    );
    TextStyle ui(TextStyle? s) => (s ?? const TextStyle()).copyWith(
      fontFamily: 'Inter',
      color: _text,
      fontFeatures: tnum,
    );

    return TextTheme(
      displayLarge: display(base.displayLarge),
      displayMedium: display(base.displayMedium),
      displaySmall: display(base.displaySmall),
      headlineLarge: display(base.headlineLarge),
      headlineMedium: display(base.headlineMedium),
      headlineSmall: display(base.headlineSmall),
      titleLarge: ui(base.titleLarge),
      titleMedium: ui(base.titleMedium),
      titleSmall: ui(base.titleSmall),
      bodyLarge: ui(base.bodyLarge),
      bodyMedium: ui(base.bodyMedium),
      bodySmall: ui(base.bodySmall),
      labelLarge: ui(base.labelLarge),
      labelMedium: ui(base.labelMedium),
      labelSmall: ui(base.labelSmall),
    );
  }
}

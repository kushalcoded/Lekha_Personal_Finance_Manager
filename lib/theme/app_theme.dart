import 'package:flutter/material.dart';

/// Semantic colors the Material [ColorScheme] doesn't carry (positive gains,
/// soft warnings). Negative maps to [ColorScheme.error], accent to primary.
@immutable
class CalmColors extends ThemeExtension<CalmColors> {
  final Color positive;
  final Color warning;

  const CalmColors({required this.positive, required this.warning});

  static const _fallback = CalmColors(
    positive: Color(0xFF5FBE93),
    warning: Color(0xFFD7A24C),
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
  // Calm Ledger tokens.
  static const _accent = Color(0xFF8B7CF6);
  static const _surface = Color(0xFF17151C);
  static const _tile = Color(0xFF1C1925);
  static const _text = Color(0xFFECEAF3);
  static const _muted = Color(0xFF968FA8);
  static const _border = Color(0x14FFFFFF); // ~8% white hairline
  static const _positive = Color(0xFF5FBE93);
  static const _negative = Color(0xFFE27C71);
  static const _warning = Color(0xFFD7A24C);

  /// The app uses a single dark theme — "Calm Ledger", violet accent.
  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _accent,
      onPrimary: Colors.white,
      secondary: _accent,
      surface: _surface,
      onSurface: _text,
      onSurfaceVariant: _muted,
      surfaceContainerHighest: _tile,
      tertiary: _positive,
      error: _negative,
      onError: Colors.white,
      outline: const Color(0x24FFFFFF),
      outlineVariant: _border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // Transparent so the global AmbientBackground shows through every screen
      // and glass surfaces have something to blur.
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: scheme,
      fontFamily: 'Inter',
      textTheme: _textTheme(),
      dividerColor: _border,
      extensions: const [
        CalmColors(positive: _positive, warning: _warning),
      ],
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _text,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _tile,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _tile,
          foregroundColor: _text,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _tile,
        side: const BorderSide(color: _border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _tile,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.4),
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

  /// Space Grotesk for display / headings / big money figures, Inter for UI
  /// and body. Tabular figures everywhere so amounts line up in columns.
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
      titleLarge: display(base.titleLarge),
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

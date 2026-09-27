import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material's defaults, pointed at the tokens so a stray Material widget (a
/// dialog, a scrollbar, a text selection handle) cannot bring its own palette.
/// Colour lives in tokens.dart and nowhere else.
class AppTheme {
  const AppTheme._();

  static const Color accent = T.accent;
  static const Color surface = T.page;
  static const Color surfaceRaised = T.surface2;
  static const Color border = T.borderDefault;
  static const Color muted = T.text2;
  static const Color statusOpen = T.amber;
  static const Color statusInProgress = T.accent;
  static const Color statusResolved = T.green;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: T.accent,
      onPrimary: T.onAccent,
      secondary: T.accent,
      onSecondary: T.onAccent,
      surface: T.surface1,
      onSurface: T.text1,
      error: T.red,
      onError: T.onAccent,
      outline: T.borderDefault,
      outlineVariant: T.borderSubtle,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: T.family,
      scaffoldBackgroundColor: T.page,
      canvasColor: T.page,
      textTheme: const TextTheme(
        bodyMedium: T.body,
        bodySmall: T.meta,
        titleMedium: T.cardBody,
        titleLarge: T.heading,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: T.accent,
        selectionColor: T.accentSubtle,
      ),
      dividerTheme: const DividerThemeData(color: T.borderSubtle, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: T.surface4,
          borderRadius: BorderRadius.circular(T.rControl),
          border: Border.all(color: T.borderDefault),
        ),
        textStyle: T.meta.copyWith(color: T.text1),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: T.surface4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rDialog),
          side: const BorderSide(color: T.borderDefault),
        ),
      ),
    );
  }
}

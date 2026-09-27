import 'package:flutter/material.dart';

/// Design tokens for the overlay chrome.
///
/// The values are `GUIDESTER_WEB_BUILD_SPEC.md` §1 — the palette eyedropped
/// from the approved frames. Where that document and
/// `GUIDESTER_DESIGN_SYSTEM.md` disagree on any colour, radius or dimension,
/// the web build spec wins; D45 ruled the opposite and that ruling is
/// reversed. The design system's *rules* still stand — priority owns colour,
/// status owns shape, no host theming in the SDK, the accessibility floor —
/// its hex values do not.
///
/// This file duplicates `apps/dashboard/web/tokens.css` because a published
/// package cannot reach into the monorepo. `test/tokens_parity_test.dart`
/// reads that stylesheet when it is present and fails on any drift, so the
/// duplication is checked rather than trusted.
class GT {
  const GT._();

  /// `--page`
  static const Color page = Color(0xFF000000);

  /// `--surface-1`
  ///
  /// Not used by floating chrome. These tokens were measured against a pure
  /// black dashboard page; the overlay floats over an app whose background
  /// nobody knows, and `#131313` over a warm dark host dissolves into it.
  static const Color surface1 = Color(0xFF131313);

  /// `--surface-2` — chips at rest, with a [chromeBorder] edge.
  static const Color surface2 = Color(0xFF1A1A1A);

  /// `--surface-3`
  static const Color surface3 = Color(0xFF1C1C1C);

  /// `--surface-4` — every floating surface: the sheet, the name prompt, the
  /// toast. The lightest step in the ramp, because separation from an unknown
  /// background cannot come from contrast we cannot predict.
  static const Color surface4 = Color(0xFF2A2A2A);

  static const Color text1 = Color(0xFFFFFFFF);

  /// `--text-2`
  static const Color text2 = Color(0xFFB4B4B4);

  /// `--text-3` — the screen tag, chip labels, hint text.
  ///
  /// Replaces `#8B94A6`, which came from the superseded palette.
  static const Color text3 = Color(0xFF8B8B8B);

  /// `--line` — borders and dividers.
  static const Color line = Color(0xFF1F1F1F);

  /// `--accent` — fills: the bubble, the Send button, the pin.
  static const Color accent = Color(0xFF2F59ED);

  /// `--accent-text` — accented glyphs and links.
  static const Color accentText = Color(0xFF446AEF);

  /// `--accent-dim` — disabled fill. A navy, not an opacity.
  static const Color accentDim = Color(0xFF16295C);

  /// `--teal`
  static const Color teal = Color(0xFF2DD4BF);

  /// `--amber`
  static const Color amber = Color(0xFFF59E0B);

  /// `--green`
  ///
  /// The completed-step token in onboarding. Deliberately **not** the sent
  /// toast: a green toast collides with that meaning, and the frames show
  /// "Comment Sent" as a dark pill.
  static const Color green = Color(0xFF22C55E);

  /// `--red` — send failures, and impact `BLOCKED`.
  static const Color red = Color(0xFFF87171);

  /// `--amber-ground` — dashboard-only, the screen-tag chip's ground (§5).
  /// Declared here so the two token files remain one palette.
  static const Color amberGround = Color(0xFF2A1D05);

  // Dashboard interaction states and edges. The overlay does not draw with
  // these; they are here so the two surfaces keep one palette
  // (tokens_parity_test).
  static const Color accentHover = Color(0xFF446AEF);
  static const Color accentPressed = Color(0xFF2549D0);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color borderSubtle = Color(0xFF1F1F1F);
  static const Color borderDefault = Color(0xFF2A2A2A);
  static const Color borderStrong = Color(0xFF3A3A3A);

  /// `--chrome-border` — the edge on every floating surface.
  ///
  /// The overlay floats over an app whose background nobody knows, so
  /// separation cannot come from contrast we cannot predict. `--line` is a
  /// divider measured against a black page and is far too dark to read as an
  /// edge here.
  static const Color chromeBorder = Color(0xFF3A3A3A);

  /// Controls and code blocks.
  static const double rControl = 6;

  /// Cards.
  static const double rCard = 12;

  /// Panels — the composer sheet's top corners.
  static const double rPanel = 16;

  /// Pills — the issue chips.
  static const double rPill = 999;

  /// The theme every piece of overlay chrome renders against.
  ///
  /// Built from tokens, not from the host: seeding a scheme would let Material
  /// derive its own values for anything not named here, which is how a host's
  /// accent gets back in.
  static ThemeData get theme {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: text1,
      secondary: accentText,
      onSecondary: text1,
      surface: surface4,
      onSurface: text1,
      error: red,
      onError: page,
      outline: chromeBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      // Explicitly not the host's font. Null means the platform default, which
      // is the same on every host; inheriting whatever the app set is not.
      fontFamily: null,
      canvasColor: surface4,
      scaffoldBackgroundColor: page,
      iconTheme: const IconThemeData(color: text1),
      dividerTheme: const DividerThemeData(color: chromeBorder, space: 1),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accentText,
        selectionColor: accentDim,
        selectionHandleColor: accentText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: const TextStyle(color: text3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rControl),
          borderSide: const BorderSide(color: chromeBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rControl),
          borderSide: const BorderSide(color: chromeBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rControl),
          borderSide: const BorderSide(color: accentText),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: text1,
          disabledBackgroundColor: accentDim,
          disabledForegroundColor: text3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rControl),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: text1),
    );
  }
}

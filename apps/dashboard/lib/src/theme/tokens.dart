import 'package:flutter/material.dart';

/// Design tokens, transcribed from `GUIDESTER_WEB_BUILD_SPEC.md` §1, which
/// measured the Figma frames. D75: those frames are the visual source.
///
/// `web/tokens.css` is the source of truth for colour. Flutter renders with
/// CanvasKit and never reads that stylesheet, so these constants mirror it —
/// and `test/tokens_test.dart` parses the CSS and asserts every value here
/// matches, which is what keeps "ONE source" true rather than aspirational.
///
/// Nothing outside this file may write a hex literal. `tool/check_tokens.sh`
/// fails the build if one appears.
class T {
  const T._();

  // --- Colour (§1) ---------------------------------------------------------

  /// `--page` — page background, all screens.
  static const Color page = Color(0xFF000000);

  /// `--surface-1` — cards: learn card, code blocks.
  static const Color surface1 = Color(0xFF131313);

  /// `--surface-2` — inputs, subscription row.
  static const Color surface2 = Color(0xFF1A1A1A);

  /// `--surface-3` — comment cards (hover state), preview cards.
  static const Color surface3 = Color(0xFF1C1C1C);

  /// `--surface-4` — file/terminal chips in the onboarding preview.
  static const Color surface4 = Color(0xFF2A2A2A);

  static const Color text1 = Color(0xFFFFFFFF);

  /// `--text-2` — body-supporting.
  static const Color text2 = Color(0xFFB4B4B4);

  /// `--text-3` — meta, breadcrumb, labels, placeholders.
  static const Color text3 = Color(0xFF8B8B8B);

  /// `--line` — dividers, table header rule.
  static const Color line = Color(0xFF1F1F1F);

  /// `--accent` — button and control fills.
  static const Color accent = Color(0xFF2F59ED);

  /// `--accent-text` — active nav label, its underline, and links.
  ///
  /// Lighter than [accent] on purpose: a fill carries its own contrast, a
  /// glyph on pure black does not.
  static const Color accentText = Color(0xFF446AEF);

  /// `--accent-dim` — disabled button fill. A navy, not opacity.
  static const Color accentDim = Color(0xFF16295C);

  /// `--teal` — status tabs only: active tab text + underline.
  static const Color teal = Color(0xFF2DD4BF);

  /// `--amber` — project initial badge, screen tag in the card variant.
  static const Color amber = Color(0xFFF59E0B);

  /// `--green` — completed step pill and its connector.
  static const Color green = Color(0xFF22C55E);

  /// `--red` — impact `BLOCKED` (§5) and error text.
  ///
  /// Not in §1. Ruled after the spec landed, because §5 asks for a `--red`
  /// that §1 never declares.
  static const Color red = Color(0xFFF87171);

  /// `--accent-hover` — the lighter blue already in the palette.
  static const Color accentHover = Color(0xFF446AEF);

  /// `--accent-pressed`.
  static const Color accentPressed = Color(0xFF2549D0);

  /// `--accent-subtle` — secondary button hover. Accent at 16%.
  static const Color accentSubtle = Color(0x292F59ED);

  /// `--on-accent` — a label on an accent fill. White is 5.57:1 on #2F59ED.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// `--border-subtle` — the same as [line].
  static const Color borderSubtle = Color(0xFF1F1F1F);

  /// `--border-default` — card and outlined-control edges.
  static const Color borderDefault = Color(0xFF2A2A2A);

  /// `--border-strong`.
  static const Color borderStrong = Color(0xFF3A3A3A);

  /// `--amber-ground` — the ground under the raised row's screen-tag chip.
  ///
  /// §5 gives this hex directly. It is a token rather than a literal because
  /// nothing outside the token files may carry a colour.
  static const Color amberGround = Color(0xFF2A1D05);

  /// `--chrome-border` — the SDK overlay's floating edge.
  ///
  /// Declared here only so the two token files stay one palette. **Nothing on
  /// the web surface may use it**: it is calibrated to separate chrome from an
  /// unknown host background, not from this page.
  static const Color chromeBorder = Color(0xFF3A3A3A);

  // --- Type (§1) -----------------------------------------------------------

  static const String family = 'Inter';
  static const String mono = 'JetBrains Mono';

  /// Code is shown as typed: JetBrains Mono's ligatures would draw `=>` as
  /// one arrow glyph that nobody can type.
  static const List<FontFeature> _noLigatures = [
    FontFeature.disable('calt'),
    FontFeature.disable('liga'),
  ];

  /// Counts, times and builds line up in columns.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// 48/1.1/700 — project title.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 48,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: text1,
  );

  /// 20/1.3/600 — section headings.
  static const TextStyle heading = TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: text1,
  );

  /// 17/1.4/400 — card body.
  static const TextStyle cardBody = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: text1,
  );

  /// 15/1.5/400 — body.
  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: text1,
  );

  /// 14/1.4/400 — UI.
  static const TextStyle ui = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: text1,
  );

  /// 13/1.4/400 — supporting.
  static const TextStyle supporting = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: text1,
  );

  /// 11/1.4/500, 0.06em, uppercase — meta. Uppercasing is the caller's job;
  /// the letter-spacing here assumes it.
  static const TextStyle meta = TextStyle(
    fontFamily: family,
    fontSize: 11,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 11 * 0.06,
    color: text3,
  );

  /// Mono 13 — code blocks.
  static const TextStyle code = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    height: 1.4,
    color: text1,
    fontFeatures: _noLigatures,
  );

  /// Mono 24 — the onboarding preview panes.
  static const TextStyle codeLarge = TextStyle(
    fontFamily: mono,
    fontSize: 24,
    height: 1.4,
    color: text1,
    fontFeatures: _noLigatures,
  );

  // --- Radius (§1) ---------------------------------------------------------

  /// Inputs, buttons, code blocks.
  static const double rControl = 6;

  /// Cards and skeletons.
  static const double rCard = 12;

  /// Detail panels and preview frames.
  static const double rPanel = 16;

  /// Step pills.
  static const double rPill = 999;

  /// Dialogs.
  static const double rDialog = 12;

  // --- Controls (§1) -------------------------------------------------------

  /// 32: the frames measure 31-33; the 4 px grid's step.
  static const double controlHeight = 32;

  /// Below [compactBreakpoint], every control is at least this tall.
  static const double touchTarget = 44;
  static const double compactBreakpoint = 600;

  // --- Shell geometry (§3) -------------------------------------------------

  /// The centred content column: x=408, w=624 at 1440.
  static const double columnWidth = 624;

  /// Nav tabs sit at y=61.
  static const double navTop = 61;

  /// Gap between nav tabs.
  static const double navGap = 32;

  /// Active nav tab underline.
  static const double navUnderline = 2;

  /// User chip origin, bottom-left.
  static const Offset userChip = Offset(24, 696);

  /// The chip is anchored to the bottom, not to y=696: the frame is 752 tall,
  /// and a fixed top put the chip mid-screen on a taller window.
  static const double userChipBottom = 16;
  static const double userChipHeight = 40;

  static const double avatarSize = 32;
}

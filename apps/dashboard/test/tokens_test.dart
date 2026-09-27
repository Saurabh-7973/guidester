import 'dart:io';
import 'dart:math' as math;

import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `web/tokens.css` is the source of truth for colour; `T` mirrors it because
/// CanvasKit cannot read CSS. This is what stops the mirror from drifting: it
/// parses the stylesheet and asserts the two agree, in both directions.
void main() {
  final css = File('web/tokens.css').readAsStringSync();

  /// `--name: #RRGGBB;` or `--name: rgba(r,g,b,a);`.
  final declared = <String, int>{
    for (final m in RegExp(
      r'--([a-z0-9-]+)\s*:\s*#([0-9A-Fa-f]{6})\s*;',
    ).allMatches(css))
      m.group(1)!: int.parse('FF${m.group(2)!}', radix: 16),
    for (final m in RegExp(
      r'--([a-z0-9-]+)\s*:\s*rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)\s*;',
    ).allMatches(css))
      m.group(1)!: Color.fromRGBO(
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        double.parse(m.group(5)!),
      ).toARGB32(),
  };

  final mirror = <String, Color>{
    'page': T.page,
    'surface-1': T.surface1,
    'surface-2': T.surface2,
    'surface-3': T.surface3,
    'surface-4': T.surface4,
    'text-1': T.text1,
    'text-2': T.text2,
    'text-3': T.text3,
    'line': T.line,
    'accent': T.accent,
    'accent-text': T.accentText,
    'accent-dim': T.accentDim,
    'accent-hover': T.accentHover,
    'accent-pressed': T.accentPressed,
    'accent-subtle': T.accentSubtle,
    'on-accent': T.onAccent,
    'border-subtle': T.borderSubtle,
    'border-default': T.borderDefault,
    'border-strong': T.borderStrong,
    'teal': T.teal,
    'amber': T.amber,
    'green': T.green,
    'red': T.red,
    'amber-ground': T.amberGround,
    'chrome-border': T.chromeBorder,
  };

  test('tokens.css parses', () {
    expect(declared, isNotEmpty, reason: 'no custom properties found');
  });

  test('every CSS token has a Dart constant', () {
    expect(
      declared.keys.toSet().difference(mirror.keys.toSet()),
      isEmpty,
      reason: 'a token was added to tokens.css but not to T',
    );
  });

  test('every Dart constant has a CSS token', () {
    expect(
      mirror.keys.toSet().difference(declared.keys.toSet()),
      isEmpty,
      reason: 'T carries a colour that tokens.css does not declare',
    );
  });

  test('the values match, token by token', () {
    for (final entry in mirror.entries) {
      expect(
        entry.value.toARGB32(),
        declared[entry.key],
        reason:
            '--${entry.key} is #${declared[entry.key]!.toRadixString(16).substring(2).toUpperCase()} '
            'in tokens.css but 0x${entry.value.toARGB32().toRadixString(16).toUpperCase()} in T',
      );
    }
  });

  // WCAG AA, 4.5:1, for every text colour on every surface it is set on.
  // Measured pairs, not every pair: accent-text is a link colour on the page,
  // and nothing sets text-3 on surface-4.
  group('text contrast, 4.5:1', () {
    final onSurfaces = {
      'page': T.page,
      'surface-1': T.surface1,
      'surface-2': T.surface2,
      'surface-3': T.surface3,
    };
    final text = {
      'text-1': T.text1,
      'text-2': T.text2,
      'text-3': T.text3,
      'teal': T.teal,
      'amber': T.amber,
      'green': T.green,
      'red': T.red,
    };
    for (final t in text.entries) {
      for (final s in onSurfaces.entries) {
        test('${t.key} on ${s.key}', () {
          expect(contrast(t.value, s.value), greaterThanOrEqualTo(4.5));
        });
      }
    }
    test('accent-text on the page', () {
      expect(contrast(T.accentText, T.page), greaterThanOrEqualTo(4.5));
    });
    test('button label on the accent', () {
      expect(contrast(T.onAccent, T.accent), greaterThanOrEqualTo(4.5));
    });
  });

  test('code shows what to type: no ligatures', () {
    // JetBrains Mono draws => as a single arrow glyph. In a snippet meant to
    // be typed or read aloud, that is a character that does not exist.
    for (final style in [T.code, T.codeLarge]) {
      expect(style.fontFeatures, contains(const FontFeature.disable('calt')));
      expect(style.fontFeatures, contains(const FontFeature.disable('liga')));
    }
  });

  // §5.7: first paint in under 2.5 s on fast 4G. The full Inter files were
  // ~400 KB each (every script Inter covers), 2.2 MB of fonts in all; the
  // dashboard's own text is Latin. Other scripts in a tester's comment still
  // render: Flutter web fetches a fallback font only when such text appears.
  test('bundled fonts stay subset: each under 150 KB, 700 KB in all', () {
    final files = Directory('fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .toList();
    var total = 0;
    for (final f in files) {
      final kb = f.lengthSync() ~/ 1024;
      total += kb;
      expect(kb, lessThan(150), reason: f.path);
    }
    expect(total, lessThan(700));
  });

  // Flutter web downloads Roboto from fonts.gstatic.com as its last-resort
  // fallback unless the app bundles a family by that name (engine
  // canvaskit/fonts.dart). §4.1: no runtime font fetch.
  test('a family named Roboto is bundled, so none is fetched', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: Roboto'));
  });

  test('code is JetBrains Mono, and bundled', () {
    expect(T.code.fontFamily, 'JetBrains Mono');
    expect(File('fonts/JetBrainsMono-Regular.ttf').existsSync(), isTrue);
  });

  test('app_theme.dart carries no colour of its own', () {
    final src = File('lib/src/theme/app_theme.dart').readAsStringSync();
    expect(RegExp(r'0x[0-9a-fA-F]{6,8}').hasMatch(src), isFalse);
  });

  test('the Material theme sits on the token surfaces', () {
    final theme = AppTheme.dark;
    expect(theme.scaffoldBackgroundColor, T.page);
    expect(theme.colorScheme.primary, T.accent);
    expect(theme.colorScheme.onPrimary, T.onAccent);
    expect(theme.colorScheme.error, T.red);
    expect(theme.textTheme.bodyMedium?.fontFamily, T.family);
  });
}

/// WCAG 2.x relative-luminance contrast of two opaque colours.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final hi = math.max(lum(a), lum(b));
  final lo = math.min(lum(a), lum(b));
  return (hi + 0.05) / (lo + 0.05);
}

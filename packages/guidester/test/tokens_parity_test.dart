import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/src/theme/tokens.dart';

/// Both surfaces read from one palette. The SDK cannot import the dashboard —
/// it is published to pub.dev on its own — so `GT` duplicates the values in
/// `apps/dashboard/web/tokens.css`. This asserts the duplicate is identical.
///
/// Outside the monorepo the stylesheet is absent and these skip: a consumer
/// running the package's tests should not fail on a file that was never
/// theirs. Inside CI the checkout always has it, which is where drift would
/// actually happen.
void main() {
  final css = File('../../apps/dashboard/web/tokens.css');

  test('the SDK palette matches the dashboard stylesheet', () {
    if (!css.existsSync()) {
      markTestSkipped('tokens.css not present — package checked out alone');
      return;
    }

    final declared = <String, int>{
      for (final m in RegExp(
        r'--([a-z0-9-]+)\s*:\s*#([0-9A-Fa-f]{6})\s*;',
      ).allMatches(css.readAsStringSync()))
        m.group(1)!: int.parse('FF${m.group(2)!}', radix: 16),
    };

    const mirror = <String, Color>{
      'page': GT.page,
      'surface-1': GT.surface1,
      'surface-2': GT.surface2,
      'surface-3': GT.surface3,
      'surface-4': GT.surface4,
      'text-1': GT.text1,
      'text-2': GT.text2,
      'text-3': GT.text3,
      'line': GT.line,
      'accent': GT.accent,
      'accent-text': GT.accentText,
      'accent-dim': GT.accentDim,
      'teal': GT.teal,
      'amber': GT.amber,
      'green': GT.green,
      'red': GT.red,
      'amber-ground': GT.amberGround,
      'chrome-border': GT.chromeBorder,
      'accent-hover': GT.accentHover,
      'accent-pressed': GT.accentPressed,
      'on-accent': GT.onAccent,
      'border-subtle': GT.borderSubtle,
      'border-default': GT.borderDefault,
      'border-strong': GT.borderStrong,
    };

    expect(
      declared.keys.toSet().difference(mirror.keys.toSet()),
      isEmpty,
      reason: 'the dashboard declares a token the SDK does not carry',
    );

    for (final entry in mirror.entries) {
      expect(
        entry.value.toARGB32(),
        declared[entry.key],
        reason: '--${entry.key} differs between the SDK and the dashboard',
      );
    }
  });

  test('the chrome theme is built from tokens, not from a seed', () {
    final theme = GT.theme;
    expect(theme.colorScheme.primary, GT.accent);
    expect(theme.colorScheme.surface, GT.surface4);
    expect(theme.colorScheme.error, GT.red);
    expect(theme.colorScheme.outline, GT.chromeBorder);
    expect(theme.brightness, Brightness.dark);
  });
}

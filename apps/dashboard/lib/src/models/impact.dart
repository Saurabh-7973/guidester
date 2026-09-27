import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// What the problem cost the tester, answered by the tester.
///
/// The meta row's second field, in a fixed position, because that is what lets
/// the eye find it down a column of thirty comments (spec §5).
///
/// **Impact owns colour.** Design-system Rule 1 gives colour to priority;
/// priority has no UI yet (D51), so impact holds it until it does. Nothing
/// else in a list row is coloured.
enum Impact {
  blocked('blocked', 'BLOCKED', T.red),
  annoying('annoying', 'ANNOYING', T.text2),
  cosmetic('cosmetic', 'COSMETIC', T.text3);

  const Impact(this.wire, this.label, this.color);

  final String wire;

  /// Already uppercase: the meta row is 11px uppercase throughout.
  final String label;

  final Color color;

  /// The column is NOT NULL with a default, so a row without one is a row from
  /// an SDK build that predates the chips — same meaning, same value.
  static const Impact fallback = Impact.annoying;

  static Impact fromWire(String? value) {
    for (final impact in Impact.values) {
      if (impact.wire == value) return impact;
    }
    return fallback;
  }
}

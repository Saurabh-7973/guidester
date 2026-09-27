import 'package:flutter/material.dart';

/// Mirrors the `comment_status` enum in the database.
///
/// [wire] is the exact Postgres value; never send [name] to the API — a
/// rename in Dart would silently stop matching the enum.
enum CommentStatus {
  open('open', 'Open', Icons.circle_outlined),
  inProgress('in_progress', 'In Progress', Icons.contrast),
  resolved('resolved', 'Resolved', Icons.check_circle_outline);

  const CommentStatus(this.wire, this.label, this.icon);

  final String wire;
  final String label;

  /// **Status owns shape, priority owns colour** — the design system's Rule 1,
  /// which survives the D47 reversal even though its palette does not. Status
  /// is drawn monochrome and told apart by its glyph, never by a colour.
  final IconData icon;

  static CommentStatus fromWire(String? value) => switch (value) {
    'in_progress' => CommentStatus.inProgress,
    'resolved' => CommentStatus.resolved,
    _ => CommentStatus.open,
  };
}

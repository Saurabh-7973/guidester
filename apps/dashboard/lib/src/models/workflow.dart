import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// What the tester says. Moves independently of [DevVerdict].
///
/// The real bugsheet keeps QA Status and Dev Status in two columns because they
/// genuinely disagree — a fix the developer has shipped is not a fix until the
/// tester has retested it on a build they can install.
enum TesterVerdict {
  open('open', 'Open'),
  verifying('verifying', 'Verifying'),
  accepted('accepted', 'Accepted'),
  rejected('rejected', 'Still broken');

  const TesterVerdict(this.wire, this.label);

  final String wire;
  final String label;

  static TesterVerdict fromWire(String? v) =>
      values.firstWhere((x) => x.wire == v, orElse: () => TesterVerdict.open);
}

/// What the developer says.
///
/// `blocked` is a state; **who** it is blocked on is [BlockedOn], deliberately
/// separate. The sheet crushed the two together as `Open Backend` / `Open BA` /
/// `Open Thence`, which is exactly why "how many are open?" could not be
/// answered without arguing about what counts.
enum DevVerdict {
  isNew('new', 'New'),
  inProgress('in_progress', 'In Progress'),
  fixed('fixed', 'Fixed'),
  blocked('blocked', 'Blocked'),
  deferred('deferred', 'Deferred'),
  wontFix('wont_fix', "Won't Fix");

  const DevVerdict(this.wire, this.label);

  final String wire;
  final String label;

  static DevVerdict fromWire(String? v) =>
      values.firstWhere((x) => x.wire == v, orElse: () => DevVerdict.isNew);
}

/// Who owes the next move. Null means nobody outside the team.
///
/// **Free text, not an enum, on purpose.** The team this was modelled on blocks
/// on `exchange`, `master data` and a named design vendor — none of which
/// generalise. A shipped taxonomy that does not fit is worse than free text:
/// people either pick the wrong value or abandon the field.
///
/// [defaults] is what the picker offers out of the box; a project can extend it
/// (`projects.blocked_on_options`) with whatever it actually blocks on.
class BlockedOn {
  const BlockedOn(this.value);

  final String value;

  /// The six that hold for any software team. Anything domain-specific belongs
  /// to the project that needs it, not to everyone who does not.
  static const List<String> defaults = [
    'backend',
    'frontend',
    'design',
    'product',
    'qa',
    'third-party',
  ];

  static String? fromWire(String? v) => (v == null || v.isEmpty) ? null : v;

  /// `third-party` reads as "Third party", `master data` as "Master data",
  /// `qa` as "QA".
  static String label(String value) {
    final words = value
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => _acronyms.contains(w.toLowerCase()) ? w.toUpperCase() : w)
        .join(' ');
    if (words.isEmpty) return words;
    return words[0].toUpperCase() + words.substring(1);
  }

  static const Set<String> _acronyms = {'qa', 'ui', 'ux', 'api', 'ios', 'sdk'};
}

/// One entry in a comment's history.
///
/// Replaces the date-prefixed prose people were typing into a spreadsheet cell
/// (`"24/06 : Fixed\n30/07 : Pls Recheck"`). The verdict is now the last event
/// rather than a separate column that silently lags behind the remark.
class CommentEvent {
  const CommentEvent({
    required this.id,
    required this.at,
    required this.kind,
    this.actor,
    this.body,
    this.field,
    this.fromValue,
    this.toValue,
    this.build,
  });

  final String id;
  final DateTime at;
  final String kind;
  final String? actor;
  final String? body;
  final String? field;
  final String? fromValue;
  final String? toValue;
  final String? build;

  factory CommentEvent.fromRow(Map<String, dynamic> row) => CommentEvent(
    id: row['id']?.toString() ?? '',
    at:
        DateTime.tryParse(row['at']?.toString() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    kind: row['kind']?.toString() ?? 'commented',
    actor: _nonEmpty(row['actor']),
    body: _nonEmpty(row['body']),
    field: _nonEmpty(row['field']),
    fromValue: _nonEmpty(row['from_value']),
    toValue: _nonEmpty(row['to_value']),
    build: _nonEmpty(row['build']),
  );

  /// One line, the way the sheet's remark column reads — but generated.
  String get summary => switch (kind) {
    'verdict_changed' =>
      fromValue == null
          ? '${_label(field)} set to ${_pretty(toValue)}'
          : '${_label(field)} ${_pretty(fromValue)} → ${_pretty(toValue)}',
    'assigned' => toValue == null ? 'Unassigned' : 'Assigned to ${toValue!}',
    'blocked' =>
      toValue == null ? 'Unblocked' : 'Blocked on ${_pretty(toValue)}',
    'build_marked' => '${_label(field)} $build',
    'reopened' => 'Reopened',
    'attachment_added' => 'Attachment added',
    _ => body ?? 'Commented',
  };

  static String _label(String? field) => switch (field) {
    'dev_verdict' => 'Dev',
    'tester_verdict' => 'Tester',
    'fixed_in_build' => 'Fixed in',
    'verified_in_build' => 'Verified in',
    _ => field ?? '',
  };

  static String _pretty(String? wire) => (wire ?? '').replaceAll('_', ' ');

  static String? _nonEmpty(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// The three questions the sheet could not answer without reading every row.
///
/// Deliberately not "all the counts you could compute" — these are the ones a
/// developer opens the board to ask.
class Board {
  const Board({
    required this.reportedToday,
    required this.reportedThisWeek,
    required this.fixedNotVerified,
    required this.blocked,
    required this.blockedBy,
    required this.openByAssignee,
  });

  final int reportedToday;
  final int reportedThisWeek;

  /// `dev_verdict = fixed` and the tester has not accepted it.
  ///
  /// The state the two-column spreadsheet makes invisible, and the one that
  /// costs a release.
  final int fixedNotVerified;

  final int blocked;
  final Map<String, int> blockedBy;
  final Map<String, int> openByAssignee;
}

/// Colour for a verdict chip. Impact owns colour in a list **row**; these are
/// controls in the detail pane, where a verdict is what you came to change.
Color devVerdictColor(DevVerdict v) => switch (v) {
  DevVerdict.fixed => T.green,
  DevVerdict.blocked => T.red,
  DevVerdict.inProgress => T.amber,
  DevVerdict.isNew => T.text2,
  DevVerdict.deferred || DevVerdict.wontFix => T.text3,
};

Color testerVerdictColor(TesterVerdict v) => switch (v) {
  TesterVerdict.accepted => T.green,
  TesterVerdict.rejected => T.red,
  TesterVerdict.verifying => T.amber,
  TesterVerdict.open => T.text2,
};

/// A part of the screenshot the platform composited and Flutter could not
/// capture. Sent by the SDK, normalised 0..1 like the pin.
class BlankRegion {
  const BlankRegion({
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// The render object's type, e.g. `RenderAndroidView`. Raw on purpose — a
  /// new platform-view class should read as itself, not as "unknown".
  final String kind;
  final double x;
  final double y;
  final double w;
  final double h;

  factory BlankRegion.fromJson(Map<String, dynamic> json) => BlankRegion(
    kind: json['kind']?.toString() ?? 'platform view',
    x: _d(json['x']),
    y: _d(json['y']),
    w: _d(json['w']),
    h: _d(json['h']),
  );

  /// What to call it in front of a developer. The class names are Flutter's,
  /// and most people reading a bug report have never seen them.
  String get label {
    if (kind.contains('Texture')) return 'video or camera';
    return 'map, chart or web view';
  }

  static double _d(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };
}

/// What `GuidesterRedact` did to a screenshot. Sent by SDK 0.6.0+ in the
/// comment's context: `{"regions": 3}`, or `{"failure": "not_laid_out"}` when
/// the screenshot was withheld.
class Redaction {
  const Redaction._({this.regions, this.failure});

  /// Areas painted over. Null when the screenshot was withheld.
  final int? regions;

  /// The SDK's wire name for why the screenshot was withheld.
  final String? failure;

  bool get withheld => failure != null;

  /// Null for anything that is not one of the two shapes the SDK sends, so a
  /// malformed context never shows a claim nobody made.
  static Redaction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final failure = raw['failure'];
    if (failure is String && failure.isNotEmpty) {
      return Redaction._(failure: failure.length > 64 ? 'unknown' : failure);
    }
    final regions = raw['regions'];
    if (regions is int && regions >= 0) return Redaction._(regions: regions);
    return null;
  }

  /// The line shown next to the screenshot.
  String get label {
    if (failure != null) return 'Screenshot withheld: $reason';
    final n = regions!;
    return n == 1 ? '1 region redacted' : '$n regions redacted';
  }

  /// Why, in words a developer fixing their `GuidesterRedact` can act on.
  String get reason => switch (failure) {
    'not_laid_out' => 'a redacted area was not laid out yet',
    'detached' => 'a redacted area was no longer on screen',
    'outside_boundary' =>
      'a redacted area is outside the part of the app Guidester captures',
    'not_a_box' => 'a redacted area is not a box widget',
    'composite_failed' => 'painting over a redacted area failed',
    'timeout' => 'redacting took too long',
    'capture_failed' => 'the capture failed on a redacted screen',
    _ => 'redaction could not complete ($failure)',
  };
}

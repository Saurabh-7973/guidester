/// One error the app threw before a comment was written.
///
/// Parsing is total, like every other model here: a row written by an older
/// SDK, or a field the client got wrong, degrades to something renderable
/// rather than blanking the comment it belongs to.
class CapturedError {
  const CapturedError({
    required this.exception,
    required this.stack,
    this.at,
    this.library,
    this.screen,
  });

  /// The exception's own text. Always present — the ingest function rejects an
  /// error without one, because an error that says nothing is a client bug
  /// rather than a report.
  final String exception;

  /// Frames, already trimmed on the device. Empty when the error had none: a
  /// dead platform channel throws with no Dart stack, and that error is still
  /// the most useful thing in the report.
  final String stack;

  /// When it was thrown, which is not when the comment was written. A tester
  /// types for half a minute after the screen breaks.
  final DateTime? at;

  /// Flutter's own label — `widgets library`, `rendering library`.
  final String? library;

  /// The route the app was on when it threw. Not always the screen the
  /// comment is filed against.
  final String? screen;

  factory CapturedError.fromJson(Map<String, dynamic> json) => CapturedError(
    exception: json['exception']?.toString() ?? 'Unknown error',
    stack: json['stack']?.toString() ?? '',
    at: DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal(),
    library: _nonEmpty(json['library']),
    screen: _nonEmpty(json['screen']),
  );

  /// The first frame in somebody's own code, which is the line a developer
  /// opens. Flutter's frames are the framework calling itself and answer
  /// nothing; the frame above them is where the bug lives.
  ///
  /// Null when the stack is all framework — a layout assertion thrown from
  /// inside `RenderFlex` genuinely has no host frame, and inventing one would
  /// send someone to the wrong file.
  String? get culprit {
    for (final line in stack.split('\n')) {
      final match = _packageFrame.firstMatch(line);
      if (match == null) continue;
      final package = match.group(1)!;
      if (package == 'flutter' || package == 'flutter_test') continue;
      return match.group(0);
    }
    return null;
  }

  /// The exception's first line. A Flutter assertion runs to a paragraph, and
  /// the paragraph belongs in the expanded view rather than in a header.
  String get headline => exception.split('\n').first.trim();

  /// `package:sahaj/screens/home.dart:42:9`, wherever a frame names one.
  static final RegExp _packageFrame = RegExp(
    r'package:([a-zA-Z0-9_]+)/[^\s)]+',
  );

  static String? _nonEmpty(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}

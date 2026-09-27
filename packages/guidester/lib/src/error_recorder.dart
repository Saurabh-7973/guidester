import 'package:flutter/foundation.dart';

import 'guidester.dart';

/// One Flutter error, bounded and ready to travel.
///
/// The stack is the whole point of this: "it crashed" is a sentence a
/// developer cannot act on, and the frame that names their own file is the
/// difference between a report and a bug they can open.
class CapturedError {
  CapturedError({
    required this.at,
    required this.exception,
    required this.stack,
    this.library,
    this.screen,
  });

  /// When it happened, not when the comment was written. A tester types for
  /// half a minute; a developer reading the report needs to know the error
  /// came before that, not during it.
  final DateTime at;

  /// The exception's own message, first line included.
  final String exception;

  /// Frames, already trimmed. Never the raw stack: a Flutter stack can run to
  /// hundreds of frames, and everything past the first few is the framework
  /// calling itself.
  final String stack;

  /// The framework's own label for where it was thrown — `widgets library`,
  /// `rendering library`. Null for a platform error, which has none.
  final String? library;

  /// The route the tester was on when it fired, when the observer is attached.
  /// A comment's own screen is where they wrote it, which is not always where
  /// it broke.
  final String? screen;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at.toUtc().toIso8601String(),
        'exception': exception,
        'stack': stack,
        if (library != null) 'library': library,
        if (screen != null) 'screen': screen,
      };
}

/// Catches what the app throws, so a comment can carry the cause.
///
/// The testers this is built for describe symptoms — *"the screen went
/// white"*, *"nothing happened"*. The exception behind that is already in
/// their device's log, where nobody will ever read it. Chaining the two
/// handlers Flutter already routes errors through costs the host nothing and
/// puts the stack on the comment instead.
///
/// Nothing here swallows an error. Both handlers call whatever was installed
/// before them, and the platform handler reports itself as unhandled, so a
/// crash still crashes and Crashlytics still sees what it saw.
class ErrorRecorder {
  ErrorRecorder._();

  /// The three most recent, oldest first.
  ///
  /// Three because the first error in a cascade is usually the cause and the
  /// last one is usually the symptom — keeping only the newest throws away the
  /// half that explains it — and because everything here has to fit inside the
  /// ingest function's 16 KB context bound with room to spare.
  static const int maxErrors = 3;

  /// Enough to reach the first frame in the host's own package, which is the
  /// line a developer actually opens. Flutter's own frames after that are the
  /// framework calling itself.
  static const int maxStackFrames = 24;
  static const int _maxStackChars = 4000;
  static const int _maxExceptionChars = 500;
  static const int _maxLibraryChars = 80;

  static final List<CapturedError> _errors = <CapturedError>[];
  static bool _installed = false;
  static FlutterExceptionHandler? _previousFlutterHandler;
  static bool Function(Object, StackTrace)? _previousPlatformHandler;

  static List<CapturedError> get errors => List.unmodifiable(_errors);

  /// Chain onto Flutter's error paths. Called from [Guidester.init], and only
  /// when the SDK is enabled: a production build installs nothing at all.
  ///
  /// Idempotent — a host that calls `init` twice does not get two handlers
  /// and does not lose the one it had.
  static void install() {
    if (_installed || !Guidester.isEnabled) return;
    _installed = true;

    _previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      record(
        details.exception,
        details.stack,
        library: details.library,
      );
      // Whatever the host had — including Flutter's own presenter, which is
      // what prints the red screen and the console dump. Replacing it would
      // hide errors from the developer to show them to ourselves.
      _previousFlutterHandler?.call(details);
    };

    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(error, stack);
      // False means "not handled": the error carries on to the zone and to
      // whatever else is listening. Returning true here would quietly turn a
      // crash into a silent no-op, which is a worse bug than the one being
      // reported.
      return _previousPlatformHandler?.call(error, stack) ?? false;
    };
  }

  /// Put an error in the buffer. Public because the recorder is testable this
  /// way without throwing real exceptions through the framework.
  static void record(Object error, StackTrace? stack, {String? library}) {
    _errors.add(
      CapturedError(
        at: DateTime.now(),
        exception: _clamp(error.toString(), _maxExceptionChars),
        stack: _trimStack(stack),
        library: library == null ? null : _clamp(library, _maxLibraryChars),
        screen: Guidester.observer.current,
      ),
    );
    // Oldest out. The buffer is a bound, not a log.
    while (_errors.length > maxErrors) {
      _errors.removeAt(0);
    }
  }

  /// The payload for a comment. Empty when nothing went wrong, which is the
  /// common case and costs the wire nothing.
  static List<Map<String, dynamic>> toJson() =>
      [for (final e in _errors) e.toJson()];

  static String _trimStack(StackTrace? stack) {
    if (stack == null) return '';
    final lines = stack
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(maxStackFrames)
        .toList();
    return _clamp(lines.join('\n'), _maxStackChars);
  }

  static String _clamp(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  /// Restores both handlers. Test seam, and the only way to undo [install].
  /// Called by `Guidester.debugReset`, so not annotated.
  static void debugReset() {
    if (_installed) {
      FlutterError.onError = _previousFlutterHandler;
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
    _previousFlutterHandler = null;
    _previousPlatformHandler = null;
    _installed = false;
    _errors.clear();
  }

  @visibleForTesting
  static bool get isInstalled => _installed;

  @visibleForTesting
  static int get bufferLength => _errors.length;
}

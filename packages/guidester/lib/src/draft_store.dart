import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'impact.dart';

/// A comment the tester started and did not send.
class Draft {
  const Draft({
    required this.text,
    required this.impact,
    required this.screenName,
  });

  final String text;
  final Impact impact;

  /// Where it was written. The next pin may be on another screen, and the
  /// tester deserves to be told rather than have it filed there silently.
  final String screenName;
}

/// The unsent comment, kept across a process death.
///
/// Written on every change, not on dispose: Android kills a backgrounded app
/// without running any Dart, so a save-on-close never happens in exactly the
/// case it exists for (field test S15, 25 Sep).
///
/// One draft, not a list. A tester composes one comment at a time, and a
/// queue of half-written ones is a feature nobody asked for.
class DraftStore {
  DraftStore._();

  static const String _key = 'guidester.draft';

  /// The saved draft, or null. Never throws: an unreadable store is no draft.
  static Future<Draft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(_key);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final text = decoded['text'];
      if (text is! String || text.trim().isEmpty) return null;
      final screen = decoded['screen'];
      return Draft(
        text: text,
        impact:
            Impact.fromWire(decoded['impact'] as String?) ?? Impact.fallback,
        screenName: screen is String ? screen : 'UNKNOWN',
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves [text], or clears the draft when it is blank.
  static Future<void> save({
    required String text,
    required Impact impact,
    required String screenName,
  }) async {
    if (text.trim().isEmpty) return clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'text': text,
          'impact': impact.wire,
          'screen': screenName,
        }),
      );
    } catch (_) {
      // A store that cannot be written costs the draft, never the comment.
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // As above.
    }
  }
}

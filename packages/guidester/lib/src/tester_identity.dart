import 'package:shared_preferences/shared_preferences.dart';

/// Device-local tester identity. Not an account, never a login.
///
/// The name is whatever the tester typed once; the id is a random handle
/// generated on first use so repeated comments from one device can be grouped.
class TesterIdentity {
  TesterIdentity._();

  static const String _nameKey = 'guidester.tester_name';
  static const String _idKey = 'guidester.tester_id';

  static String? _cachedName;
  static String? _cachedId;

  /// The tester's name, or null if they have not been asked yet.
  static Future<String?> name() async {
    if (_cachedName != null) return _cachedName;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _cachedName = prefs.getString(_nameKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setName(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _cachedName = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, trimmed);
    } catch (_) {
      // An unwritable prefs store must not block sending feedback.
    }
  }

  /// Stable per-device id, created on first use.
  static Future<String> id() async {
    if (_cachedId != null) return _cachedId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_idKey);
      if (existing != null && existing.isNotEmpty) return _cachedId = existing;
      final generated = _generateId();
      await prefs.setString(_idKey, generated);
      return _cachedId = generated;
    } catch (_) {
      return _cachedId = _generateId();
    }
  }

  static String _generateId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final entropy = Object().hashCode;
    return '${micros.toRadixString(16)}${entropy.toRadixString(16)}';
  }

  static void debugReset() {
    _cachedName = null;
    _cachedId = null;
  }
}

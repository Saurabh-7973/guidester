import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the tester dragged the bubble, remembered per app install.
///
/// Overrides B6's fixed bottom-right. D44: on Sahaj it lands on the "Me" tab,
/// and any host with bottom navigation hits the same thing — a fixed bubble
/// that overlaps a control is worse than either a movable one or none.
///
/// Stored as a fraction of the free area, not as pixels: a rotation or a
/// different device would otherwise put a remembered position off-screen.
class BubblePosition {
  BubblePosition._();

  static const String _edgeKey = 'guidester.bubble_edge_right';
  static const String _yKey = 'guidester.bubble_y_fraction';

  /// Bottom-right, matching the position B6 shipped.
  static const bool defaultOnRight = true;
  static const double defaultYFraction = 1.0;

  static bool? _cachedRight;
  static double? _cachedY;

  /// True when the bubble is snapped to the right edge.
  static Future<bool> onRight() async {
    if (_cachedRight != null) return _cachedRight!;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _cachedRight = prefs.getBool(_edgeKey) ?? defaultOnRight;
    } catch (_) {
      return _cachedRight = defaultOnRight;
    }
  }

  /// Vertical position as a fraction of the travel available to the bubble,
  /// 0 at the top, 1 at the bottom.
  static Future<double> yFraction() async {
    if (_cachedY != null) return _cachedY!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_yKey);
      return _cachedY = stored?.clamp(0.0, 1.0) ?? defaultYFraction;
    } catch (_) {
      return _cachedY = defaultYFraction;
    }
  }

  static Future<void> save({required bool right, required double y}) async {
    final clamped = y.clamp(0.0, 1.0);
    _cachedRight = right;
    _cachedY = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_edgeKey, right);
      await prefs.setDouble(_yKey, clamped);
    } catch (_) {
      // An unwritable prefs store must not break dragging; the position simply
      // does not survive a restart.
    }
  }

  /// Which edge a bubble released at [x] snaps to, given a [width].
  static bool snapsRight(double x, double width) =>
      x + _bubble / 2 >= width / 2;

  static const double _bubble = 52;

  @visibleForTesting
  static void debugReset() {
    _cachedRight = null;
    _cachedY = null;
  }
}

import 'package:flutter/rendering.dart';

/// A region of the screen that will be **blank** in the screenshot.
///
/// Platform views — maps, webviews, camera previews, native chart SDKs — are
/// composited by the platform, not by Flutter, so a `RepaintBoundary` capture
/// records a hole where they were. This is a Flutter limitation, not a bug in
/// any package: the incumbent has six issues about it spanning five years,
/// including its only `wontfix`, and every one was correctly answered "there is
/// nothing the library can do about that."
///
/// Being unable to fix it does not mean being unable to *say* it. A tester who
/// screenshots a broken chart and sends a black rectangle has wasted the round
/// trip; a developer who receives one has to work out why before they can even
/// start. Detecting the hole and naming it costs one tree walk.
class BlankRegion {
  const BlankRegion({required this.kind, required this.rect});

  /// The render object's type, e.g. `RenderAndroidView`, `TextureBox`. Kept raw
  /// rather than mapped to a friendly name: a new platform-view class should
  /// surface as itself rather than as "unknown".
  final String kind;

  /// Normalised 0..1 against the captured frame, so the dashboard can draw it
  /// over the screenshot at any scale — the same contract as the pin.
  final Rect rect;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        // Rounded: `Rect.width` is `right - left`, so a normalised rect arrives as
        // 0.30000000000000004 and would be sent, stored and rendered that way. Four
        // decimals is sub-pixel on any screen and keeps the payload small.
        'x': _round(rect.left),
        'y': _round(rect.top),
        'w': _round(rect.width),
        'h': _round(rect.height),
      };

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}

/// Finds the regions of [boundary] that the platform will composite and Flutter
/// will not capture.
///
/// Detection is by render-object type name. That is deliberately loose: the
/// concrete classes (`RenderAndroidView`, `RenderUiKitView`,
/// `PlatformViewRenderBox`, `TextureBox`) are private or platform-specific in
/// places, and a `is` check against each would miss the next one Flutter adds.
/// A name match degrades to "we did not warn", never to a wrong warning.
List<BlankRegion> findBlankRegions(RenderObject boundary) {
  final size = boundary.paintBounds.size;
  if (size.isEmpty) return const [];

  final found = <BlankRegion>[];

  void visit(RenderObject node) {
    final name = node.runtimeType.toString();
    if (_isPlatformComposited(name)) {
      final region = _rectIn(node, boundary, size);
      if (region != null) found.add(BlankRegion(kind: name, rect: region));
      // Do not descend: a platform view's children are not Flutter's to draw,
      // and reporting one hole per subtree beats reporting five nested ones.
      return;
    }
    node.visitChildren(visit);
  }

  boundary.visitChildren(visit);
  return found;
}

/// The render objects the platform composites over Flutter's output.
///
/// `Texture` is included because video players and camera previews use it and
/// it captures blank for the same reason.
bool _isPlatformComposited(String typeName) =>
    typeName.contains('PlatformView') ||
    typeName.contains('AndroidView') ||
    typeName.contains('UiKitView') ||
    typeName.contains('AppKitView') ||
    typeName == 'TextureBox' ||
    typeName.contains('RenderTexture');

/// The node's rect, normalised against the captured frame.
///
/// Returns null when the node has not laid out, is off-frame, or the transform
/// is not invertible — all of which mean "nothing useful to say" rather than
/// "warn anyway".
Rect? _rectIn(RenderObject node, RenderObject boundary, Size frame) {
  if (!node.attached || node.debugNeedsLayout) return null;

  final box = node is RenderBox ? node : null;
  if (box == null || !box.hasSize || box.size.isEmpty) return null;

  final Matrix4 transform;
  try {
    transform = node.getTransformTo(boundary);
  } catch (_) {
    return null;
  }

  final rect = MatrixUtils.transformRect(transform, Offset.zero & box.size);
  final clipped = rect.intersect(Offset.zero & frame);
  if (clipped.isEmpty) return null;

  return Rect.fromLTWH(
    clipped.left / frame.width,
    clipped.top / frame.height,
    clipped.width / frame.width,
    clipped.height / frame.height,
  );
}

/// How much of the frame the blank regions cover, 0..1.
///
/// Overlap is not corrected for; two stacked platform views would over-report.
/// The number drives a sentence, not a decision, and over-reporting a warning
/// is the safe direction.
double blankFraction(List<BlankRegion> regions) {
  var total = 0.0;
  for (final r in regions) {
    total += r.rect.width * r.rect.height;
  }
  return total.clamp(0.0, 1.0);
}

/// What to tell the tester, or null when there is nothing worth saying.
///
/// Deliberately not phrased as an error. Nothing has gone wrong, and the report
/// is still worth sending — the tester just needs to know the picture will not
/// show the thing they are pointing at, so they can describe it in words.
String? blankWarning(List<BlankRegion> regions) {
  if (regions.isEmpty) return null;
  final pct = (blankFraction(regions) * 100).round();
  if (pct < 2) return null;
  return 'Part of this screen (about $pct%) can’t appear in the screenshot — '
      'maps, charts and video are drawn by the phone, not the app. Describe '
      'what you see there.';
}

/// Diagnostic 5 of 6, for the developer's console rather than the tester's
/// screen.
///
/// [blankWarning] above is what the tester reads: it is about what to type
/// instead. This is what the developer reads, and it answers a different
/// question — a blank rectangle where a map or a webview was looks like a bug
/// in the capture, and it is a Flutter engine limitation that the incumbent
/// has too.
///
/// Returns null when there is nothing to say, so the caller never prints an
/// empty line.
String? blankDiagnostic(List<BlankRegion> regions) {
  if (regions.isEmpty) return null;
  final kinds = regions.map((r) => r.kind).toSet().join(', ');
  final plural = regions.length == 1 ? 'view' : 'views';
  return '[guidester] capture contained ${regions.length} platform $plural '
      '($kinds), which rendered blank. This is a Flutter engine limitation, '
      'not a bug in your app.';
}

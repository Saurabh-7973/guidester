import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'capture_warnings.dart';

/// Hides [child] from every Guidester screenshot.
///
/// Wrap anything a tester's screenshot must not carry off the device: a card
/// number, a balance, another user's name. The area is painted over with a
/// solid block before the screenshot is encoded, so the hidden pixels are never
/// in the image that is shown, queued, or sent.
///
/// ```dart
/// GuidesterRedact(child: Text(account.number))
/// ```
///
/// It fails closed. If a wrapped area cannot be located at capture time, the
/// comment is sent without a screenshot rather than with an unredacted one, and
/// the dashboard is told why.
///
/// Costs nothing when Guidester is disabled: the widget returns [child] and the
/// registry is only read when a screenshot is taken.
class GuidesterRedact extends StatefulWidget {
  const GuidesterRedact({super.key, required this.child});

  /// The part of your app to hide.
  final Widget child;

  @override
  State<GuidesterRedact> createState() => _GuidesterRedactState();
}

class _GuidesterRedactState extends State<GuidesterRedact> {
  // Resolved at capture time, not stored: the render object can be replaced
  // while this state lives, and a stale one is exactly the detached box the
  // plan has to refuse.
  late final RedactionTarget _target =
      RedactionTarget(() => mounted ? context.findRenderObject() : null);

  @override
  void initState() {
    super.initState();
    RedactionRegistry.register(_target);
  }

  @override
  void dispose() {
    RedactionRegistry.unregister(_target);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One area to hide, resolved to its render object only when a screenshot is
/// taken.
class RedactionTarget {
  RedactionTarget(this.resolve);

  final RenderObject? Function() resolve;
}

/// Every [GuidesterRedact] currently mounted.
abstract final class RedactionRegistry {
  static final Set<RedactionTarget> _targets = <RedactionTarget>{};

  static void register(RedactionTarget target) => _targets.add(target);
  static void unregister(RedactionTarget target) => _targets.remove(target);

  static Iterable<RedactionTarget> get targets => List.unmodifiable(_targets);

  /// Registers an arbitrary render object, for tests that need a box no widget
  /// can produce: one never laid out, one detached, one outside the capture.
  @visibleForTesting
  static RedactionTarget debugRegister(RenderObject? Function() resolve) {
    final target = RedactionTarget(resolve);
    _targets.add(target);
    return target;
  }

  @visibleForTesting
  static void debugReset() => _targets.clear();
}

/// The solid fill painted over a hidden area. Opaque by construction: a blur
/// can be reversed and is not redaction.
const Color redactionFill = Color(0xFF1F1F1F);

/// Where the hidden areas are in the captured image, or why they cannot be
/// found.
class RedactionPlan {
  const RedactionPlan._(this.rects, this.failure);

  const RedactionPlan.ok(List<Rect> rects) : this._(rects, null);
  const RedactionPlan.failed(RedactionFailure failure)
      : this._(const [], failure);

  /// In image pixels, rounded outward and clipped to the frame.
  final List<Rect> rects;
  final RedactionFailure? failure;
}

/// Maps every target into the pixels of a capture of [boundary] taken at
/// [pixelRatio].
///
/// Synchronous on purpose. Called after the frame is painted and before
/// `toImage`, with no await in between, so the rectangles and the pixels
/// describe the same frame.
///
/// A target that is registered but cannot be located fails the whole plan: a
/// screenshot is only safe to send when every hidden area is accounted for.
/// A target that is located but not painted — scrolled fully away, inside an
/// offstage route, at zero opacity — is skipped: there is nothing of it in
/// the picture to hide.
RedactionPlan planRedactions(
  RenderBox boundary,
  double pixelRatio,
  Iterable<RedactionTarget> targets,
) {
  final frame = Offset.zero & (boundary.size * pixelRatio);
  final rects = <Rect>[];
  for (final target in targets) {
    final RenderObject? object;
    try {
      object = target.resolve();
    } catch (_) {
      return const RedactionPlan.failed(RedactionFailure.detached);
    }
    if (object == null || !object.attached) {
      return const RedactionPlan.failed(RedactionFailure.detached);
    }
    if (object is! RenderBox) {
      return const RedactionPlan.failed(RedactionFailure.notABox);
    }
    if (!object.hasSize) {
      return const RedactionPlan.failed(RedactionFailure.notLaidOut);
    }

    // Walk up to the boundary. Reaching it proves the box is in the capture;
    // asking each ancestor whether it paints the child finds boxes that are
    // mounted but not drawn.
    var painted = true;
    RenderObject node = object;
    while (!identical(node, boundary)) {
      final parent = node.parent;
      if (parent == null) {
        return const RedactionPlan.failed(RedactionFailure.outsideBoundary);
      }
      if (!parent.paintsChild(node)) painted = false;
      node = parent;
    }
    if (!painted) continue;

    // The bounding box of the four transformed corners: a rotated or scaled
    // box is over-covered, never under-covered.
    final inBoundary = MatrixUtils.transformRect(
      object.getTransformTo(boundary),
      Offset.zero & object.size,
    );
    final px = Rect.fromLTRB(
      (inBoundary.left * pixelRatio).floorToDouble(),
      (inBoundary.top * pixelRatio).floorToDouble(),
      (inBoundary.right * pixelRatio).ceilToDouble(),
      (inBoundary.bottom * pixelRatio).ceilToDouble(),
    );
    if (!px.overlaps(frame)) continue; // wholly offscreen: nothing to hide
    // Partly offscreen is not a failure: the visible part is painted over.
    rects.add(px.intersect(frame));
  }
  return RedactionPlan.ok(rects);
}

/// A screenshot and what redaction did to it.
class CaptureOutcome {
  const CaptureOutcome(this.png, this.redaction);

  static const CaptureOutcome none = CaptureOutcome(null, null);

  /// The encoded screenshot, redacted. Null when there is none to send.
  final Uint8List? png;

  /// Null when no [GuidesterRedact] was mounted: there was nothing to report.
  final RedactionReport? redaction;
}

/// Captures [boundary], paints over every hidden area, and only then encodes.
///
/// The raw frame exists as a `ui.Image` in memory and is disposed here; the
/// only encoded bytes that ever exist are the redacted ones.
///
/// When hidden areas are registered, every failure is closed: the outcome
/// carries no image and says why. With none registered it behaves as capture
/// always has — a failure is simply no screenshot.
Future<CaptureOutcome> captureRedacted(
  RenderRepaintBoundary boundary, {
  required double pixelRatio,
  required Iterable<RedactionTarget> targets,
  required Duration timeout,
}) async {
  final registered = targets.toList();
  final redacting = registered.isNotEmpty;

  // Before any await: same frame as the pixels toImage is about to read.
  final plan = planRedactions(boundary, pixelRatio, registered);
  if (plan.failure != null) {
    return CaptureOutcome(null, RedactionReport.failed(plan.failure!));
  }

  RedactionFailure? failure;
  try {
    final png = await () async {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        if (plan.rects.isEmpty) return await _encode(image);
        try {
          return await _encode(
            await (debugCompositeRedactionsOverride ?? compositeRedactions)(
              image,
              plan.rects,
            ),
            dispose: true,
          );
        } catch (_) {
          failure = RedactionFailure.compositeFailed;
          return null;
        }
      } finally {
        image.dispose();
      }
    }()
        .timeout(timeout);
    if (failure != null) {
      return CaptureOutcome(null, RedactionReport.failed(failure!));
    }
    if (png == null) return CaptureOutcome.none;
    return CaptureOutcome(
      png,
      redacting ? RedactionReport.ok(plan.rects.length) : null,
    );
  } on TimeoutException {
    return redacting
        ? const CaptureOutcome(
            null,
            RedactionReport.failed(RedactionFailure.timeout),
          )
        : CaptureOutcome.none;
  } catch (_) {
    // The capture itself failed, before any redaction ran: no screenshot, as
    // before. Reported when areas were registered, so a missing picture on a
    // redacted screen is never unexplained.
    return redacting
        ? const CaptureOutcome(
            null,
            RedactionReport.failed(RedactionFailure.captureFailed),
          )
        : CaptureOutcome.none;
  }
}

/// Replaces [compositeRedactions] in tests, to make the paint-over throw or
/// hang on demand. Tests only; null in every build that ships.
Future<ui.Image> Function(ui.Image image, List<Rect> rects)?
    debugCompositeRedactionsOverride;

/// [image] with every rect in [rects] filled with [redactionFill].
///
/// A new image, not an edit: the caller still owns and disposes [image].
@visibleForTesting
Future<ui.Image> compositeRedactions(ui.Image image, List<Rect> rects) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
  final fill = Paint()
    ..color = redactionFill
    ..isAntiAlias = false // no half-covered edge pixels
    ..style = PaintingStyle.fill;
  for (final r in rects) {
    canvas.drawRect(r, fill);
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List?> _encode(ui.Image image, {bool dispose = false}) async {
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    if (dispose) image.dispose();
  }
}

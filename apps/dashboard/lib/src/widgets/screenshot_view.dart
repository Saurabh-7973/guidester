import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../models/workflow.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The screenshot, with the tester's pin drawn back on top of it.
///
/// The pin is stored as two normalised floats, so it lands in the right place
/// regardless of how the image is scaled here.
class ScreenshotView extends StatelessWidget {
  const ScreenshotView({
    super.key,
    required this.comment,
    required this.signedUrl,
    this.expired = false,
    this.onFailed,
  });

  final Comment comment;
  final String? signedUrl;

  /// The link failed once and a fresh one failed too.
  final bool expired;

  /// The image did not load. The caller decides whether to re-sign.
  final VoidCallback? onFailed;

  @override
  Widget build(BuildContext context) {
    final redaction = comment.redaction;
    if (comment.screenshotPath == null) {
      // A withheld screenshot says why: that is how a misplaced
      // GuidesterRedact gets found, since the tester is told only that none
      // was attached.
      return _Placeholder(
        message: redaction != null && redaction.withheld
            ? redaction.label
            : 'No screenshot with this comment',
      );
    }
    if (expired) {
      return const _Placeholder(
        message: 'Screenshot link expired. Reopen the comment.',
      );
    }
    if (signedUrl == null) {
      return const _Placeholder(message: 'Screenshot could not be loaded');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  signedUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const _Placeholder(message: 'Loading screenshot…'),
                  errorBuilder: (context, _, _) {
                    // After this frame: the caller re-signs, which rebuilds.
                    if (onFailed != null) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onFailed!(),
                      );
                    }
                    return const _Placeholder(message: 'Loading screenshot…');
                  },
                ),
              ),
              // Drawn under the pin: a labelled hole explains a black
              // rectangle that nothing can fix. The tester was warned at
              // capture time; this is the same fact on the developer's side.
              for (final region in comment.blankRegions)
                Positioned.fill(child: _BlankOverlay(region: region)),
              // Evidence redaction ran, next to the picture it ran on.
              if (redaction != null && !redaction.withheld)
                Positioned(
                  left: 8,
                  top: 8,
                  child: _RedactionChip(label: redaction.label),
                ),
              if (comment.hasPin)
                Positioned.fill(
                  child: Align(
                    // Alignment runs -1..1; the stored values are 0..1.
                    alignment: Alignment(
                      comment.tapX! * 2 - 1,
                      comment.tapY! * 2 - 1,
                    ),
                    child: const _PinDot(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PinDot extends StatelessWidget {
  const _PinDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Where the tester tapped',
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x662563EB),
              blurRadius: 10,
              spreadRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _RedactionChip extends StatelessWidget {
  const _RedactionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        key: const ValueKey('redaction-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xE6131313),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off_outlined, size: 12, color: T.text2),
            const SizedBox(width: 4),
            Text(label, style: T.supporting.copyWith(color: T.text2)),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: T.supporting.copyWith(color: T.text2),
      ),
    );
  }
}

/// Marks a region the platform composited over Flutter's output.
///
/// Not an error state. Platform views — maps, webviews, native chart SDKs,
/// video — are drawn by the OS, so no Flutter screenshot can contain them. The
/// incumbent has six issues about this spanning five years and every one was
/// correctly answered "nothing the library can do". Saying so is still free.
class _BlankOverlay extends StatelessWidget {
  const _BlankOverlay({required this.region});

  final BlankRegion region;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            Positioned(
              left: region.x * w,
              top: region.y * h,
              width: region.w * w,
              height: region.h * h,
              child: Semantics(
                label: 'Not captured: \${region.label}',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: T.amber),
                    color: T.amber.withValues(alpha: 0.06),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      color: T.amber,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'NOT CAPTURED · \${region.label}',
                        style: T.meta.copyWith(color: T.amberGround),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

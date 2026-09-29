import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The right half of §2's split canvas.
///
/// Every offset in this file is measured from the frame at 1440 and then
/// shifted by the panel's own x=860 origin: the `pubspec.yaml` chip at frame
/// x=938 is at 78 here. The panel is wider than the space it is given and is
/// clipped by the viewport on purpose — §2 says do not fit it inside.

/// Step 01 — the project screen this is about to create, dimmed until it has
/// a name.
///
/// The dimming is the frame's own idea and it is a good one: the preview is
/// inert until the input means something, and it brightens as you type, so
/// the screen demonstrates that the name you are entering is the name you
/// will see.
class ProjectPreview extends StatelessWidget {
  const ProjectPreview({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final named = name.isNotEmpty;
    return Opacity(
      opacity: named ? 1 : 0.6,
      child: Padding(
        padding: const EdgeInsets.only(top: 120, left: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              named ? name : 'Your project',
              style: T.title.copyWith(fontSize: 40),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 28),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Container(
                width: 520,
                height: 85,
                decoration: BoxDecoration(
                  color: T.surface1,
                  borderRadius: BorderRadius.circular(T.rCard),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Step 02 — the two files a developer touches, as chips with their contents
/// under them. Mono 24, because this pane is read from across a desk.
class InstallPreview extends StatelessWidget {
  const InstallPreview({super.key});

  /// Held to packages/guidester/pubspec.yaml by install_preview_test.
  static const String dependencyLine = '  guidester: ^0.6.0';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          left: 78,
          top: 182,
          child: _FileChip(
            icon: Icons.description_outlined,
            label: 'pubspec.yaml',
          ),
        ),
        const Positioned(
          left: 78,
          top: 262,
          child: _NumberedCode(lines: ['dependencies:', dependencyLine]),
        ),
        const Positioned(
          left: 78,
          top: 474,
          child: _FileChip(icon: Icons.terminal, label: 'terminal'),
        ),
        Positioned(
          left: 78,
          top: 554,
          // `get` in green: the frame highlights the word that means the
          // command did something.
          child: RichText(
            text: TextSpan(
              style: T.codeLarge.copyWith(color: T.text1),
              children: [
                const TextSpan(text: '> flutter pub '),
                TextSpan(
                  text: 'get',
                  style: T.codeLarge.copyWith(color: T.green),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 03 — the phone, the arrow and the bubble. §9 keeps this illustration:
/// it is doing real work, showing where the thing you just installed appears.
class PhonePreview extends StatelessWidget {
  const PhonePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 18,
          top: 0,
          bottom: 0,
          width: 472,
          child: Container(
            decoration: BoxDecoration(
              color: T.surface1,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          left: 62,
          top: 120,
          width: 384,
          child: Text(
            'Launch your test build. The bubble sits over your app, and the '
            'app keeps running underneath it.',
            style: T.body.copyWith(
              color: T.text2,
              fontStyle: FontStyle.italic,
              height: 1.6,
            ),
          ),
        ),
        // The hand-drawn curve from the copy down to the bubble.
        Positioned(
          left: 120,
          top: 260,
          width: 320,
          height: 380,
          child: CustomPaint(painter: _ArrowPainter()),
        ),
        Positioned(
          left: 412,
          top: 636,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: T.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 22,
              color: T.text1,
            ),
          ),
        ),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: T.surface4,
        borderRadius: BorderRadius.circular(T.rCard),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: T.text2),
          const SizedBox(width: 12),
          Text(label, style: T.body.copyWith(fontSize: 22, color: T.text1)),
        ],
      ),
    );
  }
}

class _NumberedCode extends StatelessWidget {
  const _NumberedCode({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${i + 1}',
                    style: T.codeLarge.copyWith(color: T.text3),
                  ),
                ),
                Text(lines[i], style: T.codeLarge.copyWith(color: T.text1)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The curved arrow. Hand-drawn in the frame, so it is a bezier here rather
/// than an icon: an arrow that points somewhere specific has to be drawn to
/// that point.
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = T.text3
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final start = Offset(size.width * 0.1, 0);
    final end = Offset(size.width * 0.92, size.height);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * 0.05,
        size.height * 0.55,
        size.width * 0.75,
        size.height * 0.45,
        end.dx,
        end.dy,
      );
    canvas.drawPath(path, paint);

    // The head, drawn along the curve's final direction rather than at a
    // fixed angle, so it points at the bubble instead of near it.
    const headLength = 14.0;
    final direction = (end - Offset(size.width * 0.75, size.height * 0.45));
    final angle = direction.direction;
    for (final spread in [2.7, -2.7]) {
      canvas.drawLine(
        end,
        end + Offset.fromDirection(angle + spread, headLength),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

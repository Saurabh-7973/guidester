import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../markup.dart';
import '../theme/tokens.dart';

/// The screenshot, full screen, to draw on with a finger: circle the broken
/// thing, strike through the wrong text, arrow to what is missing. Done hands
/// back the strokes; the overlay burns them into the image it sends.
class GuidesterMarkupView extends StatefulWidget {
  const GuidesterMarkupView({
    super.key,
    required this.screenshot,
    required this.aspectRatio,
    required this.onDone,
    required this.onCancel,
    this.initial = const [],
    this.pin,
  });

  final Uint8List screenshot;

  /// Width over height of the captured app, known without decoding the PNG.
  final double aspectRatio;

  final ValueChanged<List<MarkupStroke>> onDone;
  final VoidCallback onCancel;
  final List<MarkupStroke> initial;

  /// Where the tester tapped, as a fraction of the screenshot, so they see
  /// what they are marking around. Drawn here only; the board draws its own.
  final Offset? pin;

  @override
  State<GuidesterMarkupView> createState() => _GuidesterMarkupViewState();
}

class _GuidesterMarkupViewState extends State<GuidesterMarkupView> {
  late final List<MarkupStroke> _strokes = [
    for (final s in widget.initial) List.of(s),
  ];

  Offset _fraction(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Material(
      color: GT.page,
      child: Padding(
        padding: EdgeInsets.only(
          top: media.padding.top + 8,
          bottom: media.padding.bottom + 8,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const Expanded(
                    child: Text(
                      'Draw on the screenshot',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: GT.text2,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => widget.onDone(_strokes),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final size = Size(c.maxWidth, c.maxHeight);
                      return Semantics(
                        label: 'Screenshot. Drag to draw on it.',
                        child: GestureDetector(
                          key: const ValueKey('guidester-markup-canvas'),
                          onPanStart: (d) => setState(
                            () => _strokes.add([
                              _fraction(d.localPosition, size),
                            ]),
                          ),
                          onPanUpdate: (d) => setState(
                            () => _strokes.last.add(
                              _fraction(d.localPosition, size),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                widget.screenshot,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(painter: _Ink(_strokes)),
                              if (widget.pin != null)
                                Positioned(
                                  left: widget.pin!.dx * size.width - 9,
                                  top: widget.pin!.dy * size.height - 9,
                                  child: const IgnorePointer(
                                    child: _PinDot(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(_strokes.removeLast),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Undo'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed:
                      _strokes.isEmpty ? null : () => setState(_strokes.clear),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Ink extends CustomPainter {
  _Ink(this.strokes) : _count = strokes.fold(0, (n, s) => n + s.length);

  final List<MarkupStroke> strokes;

  /// Strokes grow in place, so the list identity never changes; the point
  /// count does.
  final int _count;

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, size, strokes);

  @override
  bool shouldRepaint(_Ink old) => old._count != _count;
}

class _PinDot extends StatelessWidget {
  const _PinDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GT.accent.withValues(alpha: 0.35),
          border: Border.all(color: GT.accent, width: 2),
        ),
      );
}

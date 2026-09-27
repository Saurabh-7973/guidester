import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// One finger stroke, in fractions of the screenshot (0..1 on both axes), so
/// it lands in the same place whatever size the screenshot was drawn at.
typedef MarkupStroke = List<Offset>;

/// The ink. Not the host's colour, and not the pin's blue: a mark must read
/// as the tester's hand on any screen.
const Color markupInk = Color(0xFFF43F5E);

/// Stroke width as a fraction of the screenshot's width, so a mark drawn on
/// a phone reads the same on the dashboard's larger view.
const double markupWidth = 0.012;

/// Draws [strokes] into [png] and returns the new PNG. Null when the bytes
/// cannot be decoded; the caller keeps the original screenshot then, since a
/// failed mark-up must never lose the capture it was drawn on.
Future<Uint8List?> burnStrokes(
  Uint8List png,
  List<MarkupStroke> strokes,
) async {
  if (strokes.every((s) => s.isEmpty)) return png;
  ui.Image? source;
  ui.Image? out;
  try {
    final codec = await ui.instantiateImageCodec(png);
    source = (await codec.getNextFrame()).image;
    codec.dispose();
    final w = source.width.toDouble();
    final h = source.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawImage(source, Offset.zero, Paint());
    paintStrokes(canvas, Size(w, h), strokes);
    out = await recorder.endRecording().toImage(source.width, source.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    source?.dispose();
    out?.dispose();
  }
}

/// Shared by the live view and the burn-in, so what the tester sees is what
/// the developer gets.
void paintStrokes(Canvas canvas, Size size, List<MarkupStroke> strokes) {
  final paint = Paint()
    ..color = markupInk
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = (size.width * markupWidth).clamp(2.0, 24.0);
  for (final s in strokes) {
    if (s.isEmpty) continue;
    Offset at(Offset f) => Offset(f.dx * size.width, f.dy * size.height);
    if (s.length == 1) {
      canvas.drawCircle(
        at(s.first),
        paint.strokeWidth / 2,
        Paint()..color = markupInk,
      );
      continue;
    }
    final path = Path()..moveTo(at(s.first).dx, at(s.first).dy);
    for (final p in s.skip(1)) {
      final q = at(p);
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path, paint);
  }
}

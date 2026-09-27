import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/src/impact.dart';
import 'package:guidester/src/markup.dart';
import 'package:guidester/src/ui/composer.dart';
import 'package:guidester/src/ui/markup_view.dart';

/// A flat white PNG, [w] x [h].
Future<Uint8List> _whitePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Color> _pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final i = (y * image.width + x) * 4;
  final b = raw!.buffer.asUint8List();
  image.dispose();
  return Color.fromARGB(b[i + 3], b[i], b[i + 1], b[i + 2]);
}

void main() {
  testWidgets('a stroke is burned into the pixels it crosses, and only those',
      (tester) async {
    await tester.runAsync(() async {
      final png = await _whitePng(200, 400);
      final out = await burnStrokes(png, [
        [const Offset(0.1, 0.5), const Offset(0.9, 0.5)],
      ]);
      expect(out, isNotNull);
      final onLine = await _pixel(out!, 100, 200);
      expect(onLine.r, greaterThan(0.8));
      expect(onLine.g, lessThan(0.5), reason: 'the ink, not white');
      final away = await _pixel(out, 100, 20);
      expect(away, const Color(0xFFFFFFFF), reason: 'untouched elsewhere');
    });
  });

  testWidgets('no strokes returns the capture as it was', (tester) async {
    await tester.runAsync(() async {
      final png = await _whitePng(10, 10);
      expect(await burnStrokes(png, const []), same(png));
    });
  });

  testWidgets(
      'bytes that are not an image lose nothing: null, caller keeps '
      'the original', (tester) async {
    await tester.runAsync(() async {
      expect(
        await burnStrokes(Uint8List.fromList([1, 2, 3]), [
          [Offset.zero, const Offset(1, 1)],
        ]),
        isNull,
      );
    });
  });

  testWidgets('drawing, Undo, Clear and Done in the mark-up view',
      (tester) async {
    late Uint8List png;
    await tester.runAsync(() async => png = await _whitePng(100, 200));
    List<MarkupStroke>? done;
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GuidesterMarkupView(
          screenshot: png,
          aspectRatio: 0.5,
          onDone: (s) => done = s,
          onCancel: () => cancelled = true,
        ),
      ),
    );
    final canvas = find.byKey(const ValueKey('guidester-markup-canvas'));
    await tester.drag(canvas, const Offset(60, 0));
    await tester.drag(canvas, const Offset(0, 60));
    await tester.pump();

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    expect(done, hasLength(1));
    expect(done!.single.length, greaterThan(1));
    for (final p in done!.single) {
      expect(p.dx, inInclusiveRange(0, 1));
      expect(p.dy, inInclusiveRange(0, 1));
    }

    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    expect(done, isEmpty);

    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });

  testWidgets('the composer offers mark-up only with a screenshot',
      (tester) async {
    Future<void> pump({VoidCallback? onMarkup, int marks = 0}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GuidesterComposer(
                screenName: 'HOME',
                sending: false,
                initialImpact: Impact.fallback,
                onSend: (_, __) {},
                onCancel: () {},
                onMarkup: onMarkup,
                marks: marks,
              ),
            ),
          ),
        );

    await pump();
    expect(find.text('Mark up screenshot'), findsNothing);

    var opened = false;
    await pump(onMarkup: () => opened = true);
    await tester.tap(find.text('Mark up screenshot'));
    expect(opened, isTrue);

    await pump(onMarkup: () {}, marks: 2);
    expect(find.text('Marked up'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/src/capture_warnings.dart';

/// Platform views screenshot blank. That is a Flutter limitation and nobody can
/// fix it — the incumbent has six issues about it across five years, including
/// its only `wontfix`, all correctly answered "nothing the library can do".
///
/// What *can* be done is say so. A tester who photographs a broken chart and
/// sends a black rectangle has wasted the round trip; a developer who receives
/// one has to work out why before they can start.
void main() {
  /// A stand-in for a platform view.
  ///
  /// A real `AndroidView` needs a platform channel, which a widget test has no
  /// engine for. Detection is by render-object type name, so a render object
  /// whose type name matches is exactly what the detector sees — and this test
  /// therefore exercises the real matching path rather than a mock of it.
  ///
  /// The names come from Flutter's own classes: `RenderAndroidView`,
  /// `RenderUiKitView`, `PlatformViewRenderBox`, `TextureBox`.
  Widget fakePlatformView({required double width, required double height}) =>
      _FakeAndroidView(child: SizedBox(width: width, height: height));

  Future<RenderObject> pump(WidgetTester tester, Widget child) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: RepaintBoundary(key: key, child: child)),
    );
    await tester.pump();
    return key.currentContext!.findRenderObject()!;
  }

  testWidgets('a screen of ordinary widgets warns about nothing', (
    tester,
  ) async {
    final boundary = await pump(
      tester,
      const Scaffold(body: Center(child: Text('all Flutter here'))),
    );

    expect(findBlankRegions(boundary), isEmpty);
    expect(blankWarning(const []), isNull);
  });

  testWidgets('a platform view is found, and located', (tester) async {
    final boundary = await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 100, child: Text('header')),
            fakePlatformView(width: 400, height: 400),
          ],
        ),
      ),
    );

    final regions = findBlankRegions(boundary);
    expect(regions, hasLength(1));
    expect(regions.single.kind, contains('AndroidView'));

    // Normalised against the frame, the same contract as the pin: 400x400
    // starting 100px down a 400x800 screen.
    final r = regions.single.rect;
    expect(r.left, 0);
    expect(r.top, closeTo(100 / 800, 0.01));
    expect(r.width, closeTo(1, 0.01));
    expect(r.height, closeTo(400 / 800, 0.01));
  });

  testWidgets('two platform views are both reported', (tester) async {
    final boundary = await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            fakePlatformView(width: 400, height: 200),
            fakePlatformView(width: 400, height: 200),
          ],
        ),
      ),
    );

    expect(findBlankRegions(boundary), hasLength(2));
  });

  testWidgets('a platform view off the bottom of the frame is ignored', (
    tester,
  ) async {
    // Nothing useful to say about a hole nobody can see. Positioned rather
    // than a Column, so the widget is genuinely off-frame instead of merely
    // overflowing one.
    final boundary = await pump(
      tester,
      Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: 900,
              left: 0,
              child: fakePlatformView(width: 400, height: 200),
            ),
          ],
        ),
      ),
    );

    expect(findBlankRegions(boundary), isEmpty);
  });

  test('the fraction is the area, clamped', () {
    const half = BlankRegion(
      kind: 'RenderAndroidView',
      rect: Rect.fromLTWH(0, 0, 1, 0.5),
    );
    expect(blankFraction(const [half]), closeTo(0.5, 0.001));
    expect(blankFraction(const []), 0);

    // Stacked views over-report rather than under-report; the number drives a
    // sentence, not a decision.
    expect(blankFraction(const [half, half, half]), 1.0);
  });

  test('a sliver of a screen is not worth a sentence', () {
    const sliver = BlankRegion(
      kind: 'TextureBox',
      rect: Rect.fromLTWH(0, 0, 0.1, 0.1),
    );
    expect(blankWarning(const [sliver]), isNull, reason: '1% is noise');
  });

  test('the warning names the cause and asks for words instead', () {
    const chart = BlankRegion(
      kind: 'RenderAndroidView',
      rect: Rect.fromLTWH(0, 0.2, 1, 0.5),
    );
    final warning = blankWarning(const [chart])!;

    expect(warning, contains('50%'));
    // Not an error. Nothing has gone wrong and the report is still worth
    // sending — the tester just has to describe what the picture will not show.
    expect(warning.toLowerCase(), isNot(contains('error')));
    expect(warning.toLowerCase(), isNot(contains('failed')));
    expect(warning, contains('Describe'));
  });

  test('a region serialises to the same shape the pin uses', () {
    const r = BlankRegion(
      kind: 'TextureBox',
      rect: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
    );
    expect(r.toJson(), {
      'kind': 'TextureBox',
      'x': 0.1,
      'y': 0.2,
      'w': 0.3,
      'h': 0.4,
    });
  });
}

/// A render object whose type name matches what the detector looks for.
class _FakeAndroidView extends SingleChildRenderObjectWidget {
  const _FakeAndroidView({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFakeAndroidView();
}

/// Named to match Flutter's real `RenderAndroidView`, because that is precisely
/// what the detector matches on.
class RenderFakeAndroidView extends RenderProxyBox {}

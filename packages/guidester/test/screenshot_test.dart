import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// §5.6 constraint 1: overlay chrome sits OUTSIDE the RepaintBoundary, so it
/// can never appear in a screenshot.
///
/// The widget-test binding cannot complete `toImage` on the SDK's own capture
/// path, so this asserts the property directly: find the RepaintBoundary the
/// overlay uses, rasterise it here, and check that no overlay pixel is in it.
/// If chrome ever moves inside that boundary, this fails.
class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 200, request: request);
}

/// The bubble's fill. If this colour shows up in the raster, chrome leaked in.
const Color kBubbleBlue = Color(0xFF2563EB);

/// A flat, unmistakable app background so we can prove we captured the app.
const Color kAppGreen = Color(0xFF00A000);

Future<Uint8List> _rasterise(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// True if [rgba] contains a pixel close to [target].
bool containsColour(Uint8List rgba, Color target, {int tolerance = 12}) {
  final tr = (target.r * 255).round();
  final tg = (target.g * 255).round();
  final tb = (target.b * 255).round();
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if ((rgba[i] - tr).abs() <= tolerance &&
        (rgba[i + 1] - tg).abs() <= tolerance &&
        (rgba[i + 2] - tb).abs() <= tolerance) {
      return true;
    }
  }
  return false;
}

void main() {
  setUp(() {
    Guidester.debugReset();
    SharedPreferences.setMockInitialValues({'guidester.tester_name': 'T'});
  });

  testWidgets('the captured boundary holds the app and none of the chrome',
      (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GuidesterOverlay(
          client: ApiClient(client: _NoopClient()),
          child: child!,
        ),
        home: const ColoredBox(
          color: kAppGreen,
          child: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    // The bubble is on screen — chrome is definitely rendered somewhere.
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);

    // The overlay's capture target is the RepaintBoundary wrapping the child.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );

    late Uint8List pixels;
    await tester.runAsync(() async {
      pixels = await _rasterise(boundary);
    });

    expect(
      containsColour(pixels, kAppGreen),
      isTrue,
      reason: 'the app itself must be in the capture',
    );
    expect(
      containsColour(pixels, kBubbleBlue),
      isFalse,
      reason: 'overlay chrome must never appear in the screenshot',
    );
  });

  testWidgets('the pin and composer are also outside the captured boundary',
      (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GuidesterOverlay(
          client: ApiClient(client: _NoopClient()),
          child: child!,
        ),
        home: const ColoredBox(
          color: kAppGreen,
          child: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    // Arm comment mode and place a pin, so pin + composer are on screen.
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );

    late Uint8List pixels;
    await tester.runAsync(() async {
      pixels = await _rasterise(boundary);
    });

    expect(containsColour(pixels, kAppGreen), isTrue);
    expect(
      containsColour(pixels, kBubbleBlue),
      isFalse,
      reason: 'pin and composer accent must not be in the capture either',
    );
  });
}

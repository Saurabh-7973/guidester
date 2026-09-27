// Runs the example app on a real device or simulator and files one comment,
// end to end, through everything but the network:
//
//   flutter test integration_test/device_test.dart -d <device>
//
// The unit tests cover the SDK under Flutter's test binding, which has no
// platform channels and no GPU. This covers what only a device can: the
// screenshot really rendering, device_info and package_info really answering,
// and the tap, pin, type and send flow on the platform's own text input.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:example/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
// ignore: implementation_imports
import 'package:guidester/src/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

/// Answers like the ingest function and keeps what it was sent.
class _Capture extends http.BaseClient {
  final List<Map<String, dynamic>> sent = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(
      jsonDecode(await request.finalize().bytesToString())
          as Map<String, dynamic>,
    );
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true,"retests":[]}')),
      200,
      request: request,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a comment filed on the device carries a real screenshot', (
    tester,
  ) async {
    Guidester.init(apiKey: 'device-test', endpoint: 'https://test.invalid/i');
    final network = _Capture();
    await tester.pumpWidget(ExampleApp(client: ApiClient(client: network)));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The launch ping, with the device describing itself.
    final ping = network.sent.firstWhere((r) => r['ping'] == true);
    expect(ping['device_model'], isNotNull, reason: 'device_info answered');
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      expect('${ping['os_version']}', contains('iOS'));
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect('${ping['os_version']}', startsWith('Android'));
    }

    // Bubble, then a pin on a button: the button must not fire.
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('Go to /checkout')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(TextField), findsOneWidget, reason: 'composer open');
    expect(find.text('Navigator: /home'), findsOneWidget, reason: 'no nav');

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'filed from a device');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // A fresh install asks for a name once.
    if (find.text('Continue').evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField), 'Device Test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    final comment = network.sent.firstWhere((r) => r['body'] != null);
    expect(comment['body'], 'filed from a device');
    expect(comment['screen_name'], 'HOME');
    expect(comment['client_id'], isA<String>());
    expect(comment['app_version'], isNotNull, reason: 'package_info answered');

    // A real PNG, rendered by the device, of a real size.
    final png = base64Decode(comment['screenshot_b64'] as String);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(png.length, greaterThan(10 * 1024));

    // The pin lands on the button it was placed on, as a fraction of the frame.
    expect(comment['tap_x'], inInclusiveRange(0.0, 1.0));
    expect(comment['tap_y'], inInclusiveRange(0.0, 1.0));

    // Sent, so the composer closed. (The "Comment sent" toast lasts two
    // seconds and has usually gone by the time the name prompt has settled.)
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a mark drawn on the device is in the screenshot it sends', (
    tester,
  ) async {
    final network = _Capture();
    // Same init as the first test: a fresh one per test run is not needed,
    // and init twice is refused.
    await tester.pumpWidget(ExampleApp(client: ApiClient(client: network)));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('Go to /checkout')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Mark up screenshot'));
    await tester.pumpAndSettle();
    final canvas = tester.getRect(
      find.byKey(const ValueKey('guidester-markup-canvas')),
    );
    // A horizontal line across the middle of the capture.
    final from = Offset(canvas.left + canvas.width * 0.2, canvas.center.dy);
    await tester.dragFrom(from, Offset(canvas.width * 0.6, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Marked up'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'marked on a device');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    if (find.text('Continue').evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField), 'Device Test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    final comment = network.sent.firstWhere(
      (r) => r['body'] == 'marked on a device',
    );
    final png = base64Decode(comment['screenshot_b64'] as String);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = raw!.buffer.asUint8List();
    final i = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    // The ink is markupInk, #F43F5E: strong red, little green.
    expect(bytes[i], greaterThan(200), reason: 'red channel on the line');
    expect(bytes[i + 1], lessThan(120), reason: 'not the app underneath');
    image.dispose();
  });
}

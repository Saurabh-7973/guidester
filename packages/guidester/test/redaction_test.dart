import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/capture_warnings.dart';
import 'package:guidester/src/markup.dart';
import 'package:guidester/src/outbox.dart';
import 'package:guidester/src/redact.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Redaction, end to end: every test here drives the real overlay — bubble,
/// pin, composer, Send — and inspects the bytes that leave it.
///
/// The capture runs inside `runAsync` because `toImage` only completes on real
/// time; everything after the pin is the ordinary fake-async flow.

/// The thing that must never leave the device. Nothing else in these apps is
/// this colour.
const Color kSecret = Color(0xFFFF00FF);

/// The app around it, so a test can prove the rest of the screen still went.
const Color kAppGreen = Color(0xFF00A000);

/// Records every request body; answers with [status].
class _Server extends http.BaseClient {
  _Server({this.status = 200});

  int status;
  final List<Map<String, dynamic>> bodies = [];

  Iterable<Map<String, dynamic>> get comments =>
      bodies.where((b) => b.containsKey('body'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    if (bytes.isNotEmpty) {
      bodies.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(status == 200 ? '{"ok":true}' : '{}')),
      status,
      request: request,
    );
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  _Server server, {
  required Widget home,
  TransitionBuilder? around,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        final overlay = GuidesterOverlay(
          client: ApiClient(client: server),
          child: child!,
        );
        return around == null ? overlay : around(context, overlay);
      },
      home: home,
    ),
  );
  await tester.pump();
}

/// Arms comment mode and drops a pin, letting the capture finish on real time.
Future<void> _placePin(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tapAt(const Offset(20, 20));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pump();
  await tester.pump();
  expect(find.byType(TextField), findsOneWidget);
}

Future<Map<String, dynamic>> _send(
  WidgetTester tester,
  _Server server,
  String text,
) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.text('Send'));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
  return server.comments.single;
}

/// The PNG, decoded to RGBA. Real time: the codec does not run on fake time.
Future<Uint8List> _pixels(WidgetTester tester, Uint8List png) async {
  late Uint8List rgba;
  await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    rgba = data!.buffer.asUint8List();
  });
  return rgba;
}

/// True if [rgba] contains a pixel close to [target]. Same test as
/// `screenshot_test.dart`.
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

Uint8List _screenshot(Map<String, dynamic> payload) =>
    base64Decode(payload['screenshot_b64'] as String);

Map<String, dynamic>? _redaction(Map<String, dynamic> payload) =>
    (payload['context'] as Map<String, dynamic>?)?['redaction']
        as Map<String, dynamic>?;

/// Green screen, one secret box in the middle, wrapped.
const Widget _secretScreen = ColoredBox(
  color: kAppGreen,
  child: Center(
    child: GuidesterRedact(
      child: SizedBox(
        width: 160,
        height: 60,
        child: ColoredBox(color: kSecret),
      ),
    ),
  ),
);

/// Asserts a screenshot is redacted: app present, secret gone, block present.
Future<void> _expectRedacted(WidgetTester tester, Uint8List png) async {
  final rgba = await _pixels(tester, png);
  expect(
    containsColour(rgba, kSecret),
    isFalse,
    reason: 'the hidden area must not be in the encoded bytes',
  );
  expect(containsColour(rgba, kAppGreen), isTrue, reason: 'the app still went');
  expect(
    containsColour(rgba, redactionFill, tolerance: 2),
    isTrue,
    reason: 'the opaque block is there, not a blur',
  );
}

void main() {
  late MemoryOutboxStore store;

  setUp(() {
    Guidester.debugReset();
    TesterIdentity.debugReset();
    RedactionRegistry.debugReset();
    debugBurnStrokesOverride = null;
    debugCompositeRedactionsOverride = null;
    SharedPreferences.setMockInitialValues({'guidester.tester_name': 'T'});
    store = MemoryOutboxStore();
    Outbox.debugStore = store;
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
  });

  tearDown(() {
    debugBurnStrokesOverride = null;
    debugCompositeRedactionsOverride = null;
  });

  // 1 ──────────────────────────────────────────────────────────────────────
  testWidgets(
      'a colour inside GuidesterRedact is absent from the bytes that are sent, '
      'and the tester previews exactly those bytes', (tester) async {
    final server = _Server();
    await _pumpApp(tester, server, home: _secretScreen);
    await _placePin(tester);

    // The composer shows the redacted screenshot to every tester.
    expect(find.byKey(const ValueKey('guidester-thumbnail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guidester-screenshot-note')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('guidester-thumbnail')));
    await tester.pump();
    final preview = tester.widget<Image>(
      find.byKey(const ValueKey('guidester-preview-image')),
    );
    final previewed = (preview.image as MemoryImage).bytes;
    await tester.tap(find.byKey(const ValueKey('guidester-preview-close')));
    await tester.pump();

    final payload = await _send(tester, server, 'card field is wrong');
    final sent = _screenshot(payload);

    expect(sent, previewed, reason: 'the preview is what gets sent');
    await _expectRedacted(tester, sent);
    expect(_redaction(payload), {'regions': 1});
  });

  // 2 ──────────────────────────────────────────────────────────────────────
  group('fails closed: no screenshot, the comment still goes', () {
    Future<void> expectClosed(
      WidgetTester tester,
      _Server server,
      RedactionFailure failure,
    ) async {
      expect(
        find.byKey(const ValueKey('guidester-screenshot-note')),
        findsOneWidget,
      );
      expect(find.text(redactionFailedNote), findsOneWidget);
      expect(find.byKey(const ValueKey('guidester-thumbnail')), findsNothing);

      final payload = await _send(tester, server, 'still sent');
      expect(payload['body'], 'still sent');
      expect(payload.containsKey('screenshot_b64'), isFalse);
      expect(_redaction(payload), {'failure': failure.wire});
    }

    testWidgets('a registered box that was never laid out', (tester) async {
      final server = _Server();
      final unlaid = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(const Size(10, 10)),
      )..attach(PipelineOwner());
      addTearDown(unlaid.detach);
      RedactionRegistry.debugRegister(() => unlaid);

      await _pumpApp(tester, server, home: _secretScreen);
      await _placePin(tester);
      await expectClosed(tester, server, RedactionFailure.notLaidOut);
    });

    testWidgets('a registered box detached from the tree', (tester) async {
      final server = _Server();
      final detached = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(const Size(10, 10)),
      );
      RedactionRegistry.debugRegister(() => detached);

      await _pumpApp(tester, server, home: _secretScreen);
      await _placePin(tester);
      await expectClosed(tester, server, RedactionFailure.detached);
    });

    testWidgets('a GuidesterRedact outside the captured boundary',
        (tester) async {
      final server = _Server();
      await _pumpApp(
        tester,
        server,
        home: const ColoredBox(color: kAppGreen, child: SizedBox.expand()),
        // Above MaterialApp.builder's overlay: mounted, but not in the capture.
        around: (context, overlay) => Stack(
          textDirection: TextDirection.ltr,
          children: [
            overlay!,
            const Positioned(
              left: 0,
              bottom: 0,
              child: GuidesterRedact(
                child: SizedBox(width: 10, height: 10),
              ),
            ),
          ],
        ),
      );
      await _placePin(tester);
      await expectClosed(tester, server, RedactionFailure.outsideBoundary);
    });

    testWidgets('the paint-over throws', (tester) async {
      final server = _Server();
      debugCompositeRedactionsOverride =
          (image, rects) async => throw StateError('composite');

      await _pumpApp(tester, server, home: _secretScreen);
      await _placePin(tester);
      await expectClosed(tester, server, RedactionFailure.compositeFailed);
    });

    testWidgets('the capture runs out of time', (tester) async {
      final server = _Server();
      // A paint-over that never finishes. Fake time runs the 3 s budget out.
      debugCompositeRedactionsOverride =
          (image, rects) => Completer<ui.Image>().future;

      await _pumpApp(tester, server, home: _secretScreen);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await expectClosed(tester, server, RedactionFailure.timeout);
    });
  });

  // 3 ──────────────────────────────────────────────────────────────────────
  testWidgets(
      'a failed mark-up burn falls back to the REDACTED capture, never the raw '
      'one', (tester) async {
    // `burned ?? raw` in _finishMarkup is only safe while raw is redacted. If
    // anyone reorders capture and redaction, this is the test that fails.
    final server = _Server();
    await _pumpApp(tester, server, home: _secretScreen);
    await _placePin(tester);

    var burnAsked = false;
    debugBurnStrokesOverride = (png, strokes) async {
      burnAsked = true;
      return null; // the burn failed
    };

    await tester.tap(find.byKey(const ValueKey('guidester-markup')));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('guidester-markup-canvas')),
      const Offset(60, 40),
    );
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump();
    expect(burnAsked, isTrue, reason: 'the fallback path actually ran');

    final payload = await _send(tester, server, 'marked');
    await _expectRedacted(tester, _screenshot(payload));
    expect(_redaction(payload), {'regions': 1});
  });

  // 4 ──────────────────────────────────────────────────────────────────────
  testWidgets('a comment queued for retry holds no unredacted pixels on disk',
      (tester) async {
    final server = _Server(status: 503); // retryable: goes to the outbox
    await _pumpApp(tester, server, home: _secretScreen);
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'offline');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(store.entries, hasLength(1));
    final queued =
        jsonDecode(store.entries.values.single) as Map<String, dynamic>;
    final payload = (queued['payload'] ?? queued) as Map<String, dynamic>;
    expect(payload['body'], 'offline');
    await _expectRedacted(tester, _screenshot(payload));
    expect(_redaction(payload), {'regions': 1});
  });

  // 5 ──────────────────────────────────────────────────────────────────────
  testWidgets(
      'a half-visible GuidesterRedact in a scrolled list still gets a '
      'screenshot, with the visible part covered', (tester) async {
    final server = _Server();
    await _pumpApp(
      tester,
      server,
      home: ColoredBox(
        color: kAppGreen,
        child: ListView(
          // Row 3 spans 300..400; scrolled 350, its top half is off screen.
          controller: ScrollController(initialScrollOffset: 350),
          children: [
            for (var i = 0; i < 20; i++)
              SizedBox(
                height: 100,
                child: i == 3
                    ? const GuidesterRedact(child: ColoredBox(color: kSecret))
                    : const ColoredBox(color: kAppGreen),
              ),
          ],
        ),
      ),
    );
    expect(find.byType(GuidesterRedact), findsOneWidget);
    await _placePin(tester);

    expect(find.byKey(const ValueKey('guidester-thumbnail')), findsOneWidget);
    final payload = await _send(tester, server, 'list');
    await _expectRedacted(tester, _screenshot(payload));
    expect(_redaction(payload), {'regions': 1});
  });
}

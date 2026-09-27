import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/capture_warnings.dart';
import 'package:guidester/src/screen_resolver.dart';
import 'package:http/http.dart' as http;

/// The five console diagnostics from the adoption plan, each proved to fire.
///
/// These exist because silence is the worst possible answer to a
/// misconfiguration: four of the five failure modes below produce the same
/// visible symptom — no bubble, or an `UNKNOWN` screen name — and a developer
/// cannot tell them apart without being told which one it is.
///
/// The suite's own `flutter_test_config.dart` turns these off for every other
/// file. Turning them back on here is the only way to be sure the tests are
/// testing them rather than testing the off switch.

/// Captures `debugPrint` for the duration of one test.
class _Console {
  final List<String> lines = [];
  DebugPrintCallback? _previous;

  void start() {
    _previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
  }

  /// Idempotent, and it must run BEFORE any expectation inside a `testWidgets`
  /// body: the test framework asserts that foundation debug variables were
  /// restored, and it checks that before a tearDown gets a turn.
  void stop() {
    if (_previous == null) return;
    debugPrint = _previous!;
    _previous = null;
  }

  bool has(String fragment) => lines.any((l) => l.contains(fragment));
  String get joined => lines.join('\n');
}

class _RejectingClient extends http.BaseClient {
  _RejectingClient(this.body);
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().bytesToString();
    return http.StreamedResponse(
      Stream.value(<int>[]),
      401,
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Console console;

  setUp(() {
    Guidester.debugReset();
    console = _Console()..start();
  });

  tearDown(() {
    console.stop();
    Guidester.debugMountWarningEnabled = false;
    ScreenResolver.debugRouteWarningEnabled = false;
    ScreenResolver.debugResetWarning();
  });

  test('1 — an empty key says so, instead of just not appearing', () {
    Guidester.init(apiKey: '', endpoint: 'https://e.test');
    expect(
      console.has('GUIDESTER_KEY is empty'),
      isTrue,
      reason: console.joined,
    );
  });

  test('1b — a configured build stays quiet', () {
    Guidester.debugMountWarningEnabled = false;
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test');
    expect(console.has('GUIDESTER_KEY is empty'), isFalse);
  });

  test('1c — a key with no endpoint says so, instead of just not appearing',
      () {
    // D71: no default backend. Same failure shape as an empty key — no bubble
    // and nothing sent — so it gets the same kind of line.
    Guidester.init(apiKey: 'k', endpoint: '');
    expect(
      console.has('GUIDESTER_ENDPOINT is empty'),
      isTrue,
      reason: console.joined,
    );
  });

  testWidgets('2 — init without an overlay is reported, not silent',
      (tester) async {
    Guidester.debugMountWarningEnabled = true;
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test');

    // The watchdog is a real delay, because MaterialApp's builder does not
    // necessarily run in the first frame after runApp.
    await tester.pump(const Duration(seconds: 6));
    console.stop();

    expect(
      console.has('GuidesterOverlay was never mounted'),
      isTrue,
      reason: console.joined,
    );
  });

  testWidgets('2b — mounting an overlay silences it', (tester) async {
    Guidester.debugMountWarningEnabled = true;
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GuidesterOverlay(child: child!),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    console.stop();

    expect(
      console.has('GuidesterOverlay was never mounted'),
      isFalse,
      reason: console.joined,
    );
  });

  test('3 — an unresolvable screen names the observer', () {
    ScreenResolver.debugRouteWarningEnabled = true;
    ScreenResolver.debugResetWarning();

    // No Router, no observer, no name: the Navigator 1.0 shape that fills a
    // dashboard with UNKNOWN.
    final r = ScreenResolver.resolveDetailed(null);

    expect(r.name, 'UNKNOWN');
    expect(console.has('navigatorObservers'), isTrue, reason: console.joined);
  });

  test('3b — it prints once a session, not once a tap', () {
    ScreenResolver.debugRouteWarningEnabled = true;
    ScreenResolver.debugResetWarning();

    ScreenResolver.resolveDetailed(null);
    ScreenResolver.resolveDetailed(null);
    ScreenResolver.resolveDetailed(null);

    final hits = console.lines.where((l) => l.contains('UNKNOWN')).length;
    expect(hits, 1, reason: console.joined);
  });

  test('4 — a revoked key is named as revoked, not as a generic failure',
      () async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test');
    final client =
        ApiClient(client: _RejectingClient('{"error":"key_revoked"}'));
    await client.ping();
    expect(console.has('key rejected (401'), isTrue, reason: console.joined);
  });

  testWidgets('the walk line names the tag AND the layer', (tester) async {
    // A tag alone cannot tell a developer whether the router answered or the
    // heuristic guessed, and on a Navigator 1.0 host every answer is a guess.
    Guidester.debugPrintResolvedScreen = true;
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GuidesterOverlay(child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    console.stop();

    expect(console.has('[guidester] screen:'), isTrue, reason: console.joined);
    expect(console.has('layer'), isTrue, reason: console.joined);

    Guidester.debugPrintResolvedScreen = false;
  });

  test('5 — a blank region explains itself, and an empty list says nothing',
      () {
    // The overlay prints exactly what this returns, so testing the function is
    // testing the message a developer sees.
    expect(blankDiagnostic(const []), isNull);

    final note = blankDiagnostic(const [
      BlankRegion(kind: 'RenderAndroidView', rect: Rect.fromLTWH(0, 0, 1, 1)),
      BlankRegion(kind: 'RenderAndroidView', rect: Rect.fromLTWH(0, 0, 1, 1)),
    ]);
    expect(note, isNotNull);
    expect(note, contains('2 platform views'));
    // Deduplicated: two Android views are one kind, not a repeated word.
    expect(note, contains('(RenderAndroidView)'));
    expect(note, contains('not a bug in your app'));
  });

  group('6 — an obfuscated build says so, once', () {
    test('a build whose own class names survive is not obfuscated', () {
      // The check is a class this package owns comparing its runtime name
      // against the literal. In this test build they match, and that is the
      // only environment where the negative case can be asserted at all.
      expect(ScreenResolver.looksObfuscated, isFalse);
    });

    test('a renamed class is what obfuscation looks like', () {
      // Measured on hardware: `flutter build apk --release --obfuscate` turned
      // HomeScreen into `Dw`. D67.
      expect(ScreenResolver.debugIsObfuscatedName('Dw'), isTrue);
      expect(
        ScreenResolver.debugIsObfuscatedName('GuidesterBuildProbe'),
        isFalse,
      );
    });

    test('init says it on an obfuscated build, before any comment exists', () {
      // A developer who never files a comment never resolves a screen, so a
      // warning that waits for a failed resolve waits forever. The dashboard
      // fills with UNKNOWN from the testers instead, and nothing on the
      // developer's machine ever said why.
      ScreenResolver.debugForceObfuscated = true;
      addTearDown(() => ScreenResolver.debugForceObfuscated = null);

      Guidester.init(apiKey: 'k', endpoint: 'https://e.test');
      console.stop();

      expect(console.has('obfuscated'), isTrue, reason: console.joined);
    });

    test('and says nothing on a build whose class names survived', () {
      Guidester.init(apiKey: 'k', endpoint: 'https://e.test');
      console.stop();

      expect(console.has('obfuscated'), isFalse, reason: console.joined);
    });

    test('a disabled build is silent about it, like every other diagnostic',
        () {
      // No key means no overlay, no resolve, and nothing to warn about. A
      // production build must not narrate its own build settings.
      ScreenResolver.debugForceObfuscated = true;
      addTearDown(() => ScreenResolver.debugForceObfuscated = null);

      Guidester.init(apiKey: '', endpoint: 'https://e.test');
      console.stop();

      expect(console.has('obfuscated'), isFalse, reason: console.joined);
    });

    testWidgets('said at init, it is not said again when a resolve fails',
        (tester) async {
      ScreenResolver.debugRouteWarningEnabled = true;
      ScreenResolver.debugResetWarning();
      ScreenResolver.debugForceObfuscated = true;
      addTearDown(() => ScreenResolver.debugForceObfuscated = null);

      Guidester.init(apiKey: 'k', endpoint: 'https://e.test');
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final ctx = tester.element(find.byType(SizedBox));
      ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);
      console.stop();

      final hits = console.lines.where((l) => l.contains('obfuscated')).length;
      expect(hits, 1, reason: console.joined);
    });

    testWidgets('UNKNOWN in an obfuscated build names obfuscation as the cause',
        (tester) async {
      ScreenResolver.debugRouteWarningEnabled = true;
      ScreenResolver.debugResetWarning();
      ScreenResolver.debugForceObfuscated = true;
      addTearDown(() => ScreenResolver.debugForceObfuscated = null);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final ctx = tester.element(find.byType(SizedBox));
      final r = ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);
      console.stop();

      expect(r.name, 'UNKNOWN');
      expect(console.has('obfuscated'), isTrue, reason: console.joined);
      // The Navigator 1.0 advice is wrong here and must not be the sentence a
      // developer acts on: no observer will bring layer 4 back.
      expect(
        console.has('add Guidester.observer'),
        isFalse,
        reason: console.joined,
      );
    });

    testWidgets('and only once, however many screens report UNKNOWN',
        (tester) async {
      ScreenResolver.debugRouteWarningEnabled = true;
      ScreenResolver.debugResetWarning();
      ScreenResolver.debugForceObfuscated = true;
      addTearDown(() => ScreenResolver.debugForceObfuscated = null);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final ctx = tester.element(find.byType(SizedBox));
      ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);
      ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);
      console.stop();

      final hits = console.lines.where((l) => l.contains('obfuscated')).length;
      expect(hits, 1, reason: console.joined);
    });
  });
}

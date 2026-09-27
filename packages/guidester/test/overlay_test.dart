import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/impact.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:guidester/src/theme/tokens.dart';
import 'package:guidester/src/ui/impact_chips.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/router_host.dart';

/// Records every request so we can assert on call count and payload shape.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.status = 200, this.body = '{"ok":true}', this.delay});

  final int status;
  final String body;
  final Duration? delay;
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = await request.finalize().bytesToString();
    requests.add(jsonDecode(payload) as Map<String, dynamic>);
    if (delay != null) await Future<void>.delayed(delay!);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('app content')));
}

/// A host with bottom navigation — Sahaj's shape, and the shape that made
/// armed-after-send unnavigable.
class _TabbedHost extends StatefulWidget {
  const _TabbedHost();

  @override
  State<_TabbedHost> createState() => _TabbedHostState();
}

class _TabbedHostState extends State<_TabbedHost> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(_index == 0 ? 'TODAY BODY' : 'PROFILE BODY')),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.today), label: 'Today'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('app content')));
}

Widget _app(ApiClient client, {Widget home = const HomeScreen()}) =>
    MaterialApp(
      navigatorObservers: [Guidester.observer],
      builder: (context, child) =>
          GuidesterOverlay(client: client, child: child!),
      home: home,
    );

/// A `MaterialApp.router` host — the shape of every go_router app, and the
/// shape that broke layer 3 for months (D43). `builder` wraps the Router from
/// above here, so the overlay's own boundary context has the Router *below* it.
///
/// Worth having as a whole send rather than only as a resolver unit test: the
/// name that reaches the wire comes from `_boundaryKey.currentContext`, and
/// nothing but a real send proves that context is the one that resolves.
Widget _routerApp(ApiClient client, {String path = '/today'}) =>
    MaterialApp.router(
      routerConfig: routerConfigFor(
        initialPath: path,
        child: const HomeScreen(),
      ),
      builder: (context, child) =>
          GuidesterOverlay(client: client, child: child!),
    );

/// Arms comment mode and places a pin.
///
/// The pump duration matters: screenshot capture cannot complete under the
/// widget-test binding (RenderRepaintBoundary.toImage needs a real engine
/// frame), so the overlay's capture timeout is what lets the flow proceed.
/// pumpAndSettle alone returns immediately, because no frame is pending while
/// that future is outstanding.
Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.text('Send'));
  // Context collection is bounded by a 2s timeout that will fire here, since
  // package_info/device_info have no plugin under the test binding.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
}

Future<void> _placePin(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.tapAt(const Offset(200, 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Guidester.debugReset();
    TesterIdentity.debugReset();
    SharedPreferences.setMockInitialValues({
      'guidester.tester_name': 'Test Tester',
    });
  });

  testWidgets('disabled: no bubble, and the child renders untouched',
      (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: false);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    expect(Guidester.isEnabled, isFalse);
    expect(find.text('app content'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    expect(rec.requests, isEmpty);
  });

  testWidgets('empty api key disables the SDK even when enabled: true',
      (tester) async {
    Guidester.init(apiKey: '', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(_app(ApiClient(client: _RecordingClient())));
    expect(Guidester.isEnabled, isFalse);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
  });

  testWidgets('enabled: bubble appears and arms comment mode', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(_app(ApiClient(client: _RecordingClient())));

    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    expect(find.text('Tap anywhere to comment'), findsOneWidget);
  });

  testWidgets('tapping places a pin and opens the composer', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(_app(ApiClient(client: _RecordingClient())));

    await _placePin(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('send posts once with a normalised pin and screen name',
      (tester) async {
    Guidester.init(
      apiKey: 'test-key',
      endpoint: 'https://e.test',
      enabled: true,
    );
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'the button is misaligned');
    await tester.pump();
    await _tapSend(tester);

    expect(rec.requests, hasLength(1));
    final sent = rec.requests.single;
    expect(sent['api_key'], 'test-key');
    expect(sent['body'], 'the button is misaligned');
    expect(sent['screen_name'], 'HOME');
    expect(sent['tester_name'], 'Test Tester');
    expect(sent['tap_x'], inInclusiveRange(0.0, 1.0));
    expect(sent['tap_y'], inInclusiveRange(0.0, 1.0));
    expect(sent['context'], isA<Map<String, dynamic>>());
  });

  testWidgets(
      'a router host puts the router path on the wire, not the widget '
      'class', (tester) async {
    // HomeScreen is in the tree, so layer 4 would also answer here — with
    // HOME. The path is /today. If this ever reports HOME, layer 3 has
    // silently stopped working for every go_router host and the only symptom
    // is a dashboard full of plausible, wrong screen names.
    Guidester.init(
      apiKey: 'test-key',
      endpoint: 'https://e.test',
      enabled: true,
    );
    final rec = _RecordingClient();
    await tester.pumpWidget(_routerApp(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'from a router host');
    await tester.pump();
    await _tapSend(tester);

    expect(rec.requests, hasLength(1));
    expect(rec.requests.single['screen_name'], 'TODAY');
  });

  testWidgets('a nested path keeps both segments on the wire', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(
      _routerApp(ApiClient(client: rec), path: '/library/session-3'),
    );

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'nested');
    await tester.pump();
    await _tapSend(tester);

    expect(rec.requests.single['screen_name'], 'LIBRARY/SESSION 3');
  });

  testWidgets('double-tap on send ships exactly one comment', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient(delay: const Duration(milliseconds: 300));
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'double tap me');
    await tester.pump();

    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.tap(find.text('Sending'), warnIfMissed: false);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(rec.requests, hasLength(1));
  });

  testWidgets('failure keeps the text and shows an error', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient(status: 401, body: '{"error":"invalid_key"}');
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'keep this text');
    await tester.pump();
    await _tapSend(tester);

    expect(find.textContaining('not configured correctly'), findsOneWidget);
    expect(find.text('keep this text'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('after a successful send, the overlay returns to idle',
      (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(_app(ApiClient(client: _RecordingClient())));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'first comment');
    await tester.pump();
    await _tapSend(tester);

    // Composer gone, mode bar gone, bubble back. Armed-after-send is what made
    // the app unnavigable; the second comment costs one tap on the bubble.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Tap anywhere to comment'), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });

  testWidgets('after a send, a nav tap reaches the host app', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(
      _app(ApiClient(client: _RecordingClient()), home: const _TabbedHost()),
    );

    expect(find.text('TODAY BODY'), findsOneWidget);

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'a comment on today');
    await tester.pump();
    await _tapSend(tester);

    // The assertion that matters: the tap lands on the host, not on a tap
    // catcher. Armed-after-send placed a pin here instead of navigating,
    // which is the whole of D44 and the field test's ONBOARDING rows.
    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(find.text('PROFILE BODY'), findsOneWidget);
    expect(find.text('TODAY BODY'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('while armed, a nav tap is swallowed and places a pin',
      (tester) async {
    // The other half of the ruling: arming still means arming. This is
    // correct behaviour, and it is exactly why it must not outlive a send.
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(
      _app(ApiClient(client: _RecordingClient()), home: const _TabbedHost()),
    );

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text('TODAY BODY'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a tester with no stored name is asked, with the consent line',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TesterIdentity.debugReset();
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'anonymous attempt');
    await tester.pump();
    await _tapSend(tester);

    expect(find.text('Your name'), findsOneWidget);
    expect(
      find.text('(so the developer knows who reported what)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(
      find.textContaining('sent with a screenshot of this screen'),
      findsOneWidget,
    );
    expect(rec.requests, isEmpty, reason: 'nothing sent before a name exists');
  });

  testWidgets('the composer grows to four lines, then scrolls', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(_app(ApiClient(client: _RecordingClient())));

    await _placePin(tester);

    // §4: growth is bounded at four lines. A field that grows without limit
    // eats the screen being reported on; one that stops at a single line
    // produces shorter, worse bug reports.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, 4);
    expect(field.decoration?.hintText, 'What went wrong?');

    // Measure after the pump: the field only resizes on the rebuild that
    // follows the edit.
    Future<double> heightAfter(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      return tester.getSize(find.byType(TextField)).height;
    }

    final oneLine = await heightAfter('one');
    final fourLines = await heightAfter('one\ntwo\nthree\nfour');
    final eightLines =
        await heightAfter('one\ntwo\nthree\nfour\nfive\nsix\nseven\neight');

    expect(fourLines, greaterThan(oneLine), reason: 'it grows');
    expect(eightLines, fourLines, reason: 'past four lines it scrolls');
  });

  testWidgets('the composer tags the screen the resolver named',
      (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);

    // §6: the tag is the resolver's own output, not a constant. A second
    // screen is what makes that testable — against HOME alone, a hardcoded
    // tag passes.
    final tag = tester.widget<Text>(find.text('HOME'));
    // --text-3 from the web build spec. #8B94A6 came from the design
    // system's palette, which D45 preferred and the reversal supersedes.
    expect(tag.style?.color, GT.text3, reason: 'muted, per the token set');

    await tester.enterText(find.byType(TextField), 'tagged');
    await tester.pump();
    await _tapSend(tester);
    expect(rec.requests.single['screen_name'], 'HOME');
  });

  testWidgets('the screen tag follows the resolver onto another screen',
      (tester) async {
    // The paired half of the test above. Against HOME alone a hardcoded tag
    // passes; a second screen is what makes §6 actually testable.
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(
      _app(ApiClient(client: _RecordingClient()), home: const CheckoutScreen()),
    );

    await _placePin(tester);

    expect(find.text('CHECKOUT'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('a failed send replaces the screen tag with the error',
      (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient(status: 401, body: '{"error":"invalid_key"}');
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    expect(find.text('HOME'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'keep this text');
    await tester.pump();
    await _tapSend(tester);

    // §4: the error takes the tag's row rather than adding one, and the
    // typed text survives.
    expect(find.text('HOME'), findsNothing);
    expect(find.textContaining('not configured correctly'), findsOneWidget);
    expect(find.text('keep this text'), findsOneWidget);
  });

  testWidgets('one row, three impact chips, Annoying preselected', (
    tester,
  ) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    await tester.pumpWidget(_app(ApiClient(client: _RecordingClient())));

    await _placePin(tester);

    // D51: impact replaces the six type chips. Nine chips over a composer
    // over a keyboard leaves the app itself invisible, and the app is the
    // thing being commented on.
    expect(Impact.values, hasLength(3));
    for (final label in const ['Blocked', 'Annoying', 'Cosmetic']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // The type chips are gone from the overlay entirely.
    for (final label in const [
      'Looks wrong',
      "Doesn't work",
      'Confusing',
      'Crash / freeze',
      'Slow',
      'Idea',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }

    // One row: three chips, never wrapped onto a second line.
    final row = tester.getRect(find.byType(GuidesterImpactChips));
    for (final label in const ['Blocked', 'Annoying', 'Cosmetic']) {
      final chip = tester.getRect(find.text(label));
      expect(chip.top, greaterThanOrEqualTo(row.top));
      expect(chip.bottom, lessThanOrEqualTo(row.bottom));
    }
    expect(row.height, lessThan(48), reason: 'a single row of chips');

    // Never scrolled sideways: a hidden option is an unused one.
    expect(
      find.descendant(
        of: find.byType(GuidesterImpactChips),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
  });

  testWidgets('the default is Annoying and it cannot be cleared', (
    tester,
  ) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);

    bool isSelected(String label) => tester
        .widget<Semantics>(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.selected != null,
            ),
          ),
        )
        .properties
        .selected!;

    expect(isSelected('Annoying'), isTrue, reason: 'the honest modal case');
    expect(isSelected('Blocked'), isFalse);
    expect(isSelected('Cosmetic'), isFalse);

    // Single-select.
    await tester.tap(find.text('Blocked'));
    await tester.pump();
    expect(isSelected('Blocked'), isTrue);
    expect(isSelected('Annoying'), isFalse);

    // Tapping the selected chip does NOT clear it: with a default there is no
    // "none" to return to, and an empty row would put a null back on the wire.
    await tester.tap(find.text('Blocked'));
    await tester.pump();
    expect(isSelected('Blocked'), isTrue);
  });

  testWidgets('impact is always on the payload, default included', (
    tester,
  ) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'no chip touched');
    await tester.pump();
    await _tapSend(tester);

    // Sent even when untouched: relying on the column default would make an
    // older SDK build and a deliberate 'annoying' indistinguishable, and
    // telling those apart is the whole point of tracking the default rate.
    expect(rec.requests.single['impact'], 'annoying');
    expect(
      rec.requests.single.containsKey('issue_type'),
      isFalse,
      reason: 'the SDK stopped asking; the dev sets type at triage',
    );
  });

  testWidgets('a chosen impact reaches the wire', (tester) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'could not continue');
    await tester.pump();
    await tester.tap(find.text('Blocked'));
    await tester.pump();
    await _tapSend(tester);

    expect(rec.requests.single['impact'], 'blocked');
  });

  testWidgets('the chip survives the name prompt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    TesterIdentity.debugReset();
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'first ever comment');
    await tester.pump();
    await tester.tap(find.text('Cosmetic'));
    await tester.pump();
    await _tapSend(tester);

    // The prompt replaces the composer, so an unheld selection is lost here.
    expect(find.text('Your name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(rec.requests.single['impact'], 'cosmetic');
    expect(rec.requests.single['body'], 'first ever comment');
  });

  testWidgets('a sent impact does not leak into the next comment', (
    tester,
  ) async {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump();
    await tester.tap(find.text('Blocked'));
    await tester.pump();
    await _tapSend(tester);

    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump();
    await _tapSend(tester);

    expect(rec.requests, hasLength(2));
    expect(rec.requests[0]['impact'], 'blocked');
    expect(
      rec.requests[1]['impact'],
      'annoying',
      reason: 'the next comment starts at the default, not the last choice',
    );
  });

  test('the SDK wire values match migration 0003 exactly', () {
    // Duplicated in the migration and the ingest function. Nothing at compile
    // time makes them agree — a drift is silent in Dart and surfaces as a
    // rejected send — so pin them literally.
    expect(Impact.values.map((i) => i.wire).toList(), const [
      'blocked',
      'annoying',
      'cosmetic',
    ]);
    expect(Impact.fallback.wire, 'annoying');
  });
}

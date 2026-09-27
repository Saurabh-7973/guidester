import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/theme/tokens.dart';
import 'package:http/http.dart' as http;

/// D42: the overlay chrome renders in the host's accent because
/// `MaterialApp.builder` sits inside the Material context.
///
/// That placement is load-bearing — it is what puts `Directionality`,
/// `MediaQuery` and text selection in scope while staying above the host's
/// `Navigator` — so the fix is a boundary, not a move.
///
/// The CI grep for `Theme.of` passes today and always did: nothing in the SDK
/// calls it. The inheritance happens anyway, through every Material widget's
/// own defaults. That grep tests the wrong thing; this file tests the right
/// one.
class _StubClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      request: request,
    );
  }
}

/// Nothing about this theme resembles ours: Sahaj's amber seed, a light
/// surface, a different font, and a shape scheme that would round our chrome
/// differently. If any of it reaches the overlay, a test here fails.
final ThemeData _hostileHost = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF6D00),
    brightness: Brightness.light,
  ),
  fontFamily: 'HostFont',
  iconTheme: const IconThemeData(color: Color(0xFFFF00FF)),
);

Widget _app() => MaterialApp(
      theme: _hostileHost,
      navigatorObservers: [Guidester.observer],
      builder: (context, child) => GuidesterOverlay(
        client: ApiClient(client: _StubClient()),
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('host content'))),
    );

Future<void> _placePin(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.tapAt(const Offset(200, 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

/// The Theme our chrome resolves against, read from inside the chrome itself.
ThemeData _chromeTheme(WidgetTester tester, Finder inChrome) =>
    Theme.of(tester.element(inChrome));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(
    () => Guidester.init(
      apiKey: 'k',
      endpoint: 'https://e.test',
      enabled: true,
    ),
  );

  testWidgets('the bubble does not resolve against the host theme', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final theme = _chromeTheme(
      tester,
      find.byIcon(Icons.chat_bubble_outline),
    );
    expect(theme.colorScheme.primary, GT.accent);
    expect(theme.brightness, Brightness.dark);
  });

  testWidgets('the composer sheet does not inherit the host accent', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _placePin(tester);

    final theme = _chromeTheme(tester, find.byType(TextField));
    expect(
      theme.colorScheme.primary,
      GT.accent,
      reason: 'the host seed would give an amber primary here',
    );
    // --surface-4, not --surface-1: floating chrome takes the lightest step
    // in the ramp because it sits over a host background nobody knows.
    expect(theme.colorScheme.surface, GT.surface4);
    expect(theme.brightness, Brightness.dark);
  });

  testWidgets('the Send button fills with our accent, not the host\'s', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'text');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final resolved = button.style?.backgroundColor?.resolve({});
    // Either the button carries our colour explicitly, or it resolves it from
    // the boundary Theme. Both are correct; inheriting amber is not.
    final effective = resolved ??
        _chromeTheme(tester, find.byType(FilledButton)).colorScheme.primary;
    expect(effective, GT.accent);
  });

  testWidgets('chrome text does not inherit the host font family', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _placePin(tester);
    final theme = _chromeTheme(tester, find.byType(TextField));
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('HostFont'));
  });

  testWidgets('chrome icons do not inherit the host icon theme', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _placePin(tester);
    final theme = _chromeTheme(tester, find.byType(TextField));
    expect(theme.iconTheme.color, isNot(const Color(0xFFFF00FF)));
  });

  testWidgets('the host app keeps its own theme', (tester) async {
    await tester.pumpWidget(_app());
    // The boundary must not leak the other way: the app under the overlay is
    // still the host's, amber and all.
    final host = Theme.of(tester.element(find.text('host content')));
    expect(host.colorScheme.primary, _hostileHost.colorScheme.primary);
    expect(host.brightness, Brightness.light);
  });
}

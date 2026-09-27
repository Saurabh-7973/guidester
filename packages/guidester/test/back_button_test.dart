import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/router_host.dart';

/// Field test, 25 Sep (emulator): Android back while the sheet was up popped
/// the host's route underneath and left the sheet open, so the comment filed
/// against a screen the tester had already left. Back closes the sheet.
class _Client extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().bytesToString();
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      request: request,
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/checkout'),
            child: const Text('go'),
          ),
        ),
      );
}

class _Checkout extends StatelessWidget {
  const _Checkout();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('checkout screen')));
}

Future<void> _openSheetOnCheckout(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [Guidester.observer],
      builder: (context, child) =>
          GuidesterOverlay(client: ApiClient(client: _Client()), child: child!),
      routes: {
        '/': (_) => const _Home(),
        '/checkout': (_) => const _Checkout(),
      },
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.tapAt(const Offset(200, 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
  expect(find.byType(TextField), findsOneWidget);
}

void main() {
  setUp(() {
    Guidester.debugReset();
    TesterIdentity.debugReset();
    SharedPreferences.setMockInitialValues({'guidester.tester_name': 'T'});
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
  });

  testWidgets('Back closes the sheet and leaves the app where it was', (
    tester,
  ) async {
    await _openSheetOnCheckout(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('checkout screen'), findsOneWidget);
  });

  testWidgets("with no sheet, Back is the app's own", (tester) async {
    await _openSheetOnCheckout(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('in a Router app, Back leaves comment mode first', (
    tester,
  ) async {
    final base = routerConfigFor(initialPath: '/today');
    // go_router and every real Router app hand Back to a dispatcher.
    final config = RouterConfig<Object>(
      routeInformationProvider: base.routeInformationProvider,
      routeInformationParser: base.routeInformationParser,
      routerDelegate: base.routerDelegate,
      backButtonDispatcher: RootBackButtonDispatcher(),
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: config,
        builder: (context, child) => GuidesterOverlay(
          client: ApiClient(client: _Client()),
          child: child!,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    expect(find.text('Tap anywhere to comment'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Tap anywhere to comment'), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });
}

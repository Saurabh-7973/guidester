import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Found recording the demo, 27 Sep: a comment typed on CHECKOUT, then Back,
/// then a pin on HOME, reopened under HOME with no word that it was written
/// somewhere else. A relaunch already said so; staying in the app did not.
class _Client extends http.BaseClient {
  final List<Map<String, dynamic>> sent = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(
      jsonDecode(await request.finalize().bytesToString())
          as Map<String, dynamic>,
    );
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

Future<void> _pin(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.tapAt(const Offset(200, 500));
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
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
  });

  Future<_Client> start(WidgetTester tester) async {
    final client = _Client();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [Guidester.observer],
        builder: (context, child) =>
            GuidesterOverlay(client: ApiClient(client: client), child: child!),
        routes: {
          '/': (_) => const _Home(),
          '/checkout': (_) => const _Checkout(),
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('a draft closed with Back says where it was written',
      (tester) async {
    final client = await start(tester);
    await _pin(tester);
    await tester.enterText(find.byType(TextField), 'pay button hides');
    await tester.pump();

    await tester.binding.handlePopRoute(); // closes the sheet
    await tester.pump();
    await tester.binding.handlePopRoute(); // leaves CHECKOUT
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);

    await _pin(tester);
    expect(find.text('pay button hides'), findsOneWidget);
    expect(find.textContaining('Unsent comment from CHECKOUT'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final comment = client.sent.firstWhere((r) => r['ping'] != true);
    expect(comment['body'], 'pay button hides');
    // Filed where it was pinned now; the note only makes sure the tester knew.
    expect(comment['screen_name'], isNot('CHECKOUT'));
  });

  testWidgets('an empty composer closed with Back carries no note',
      (tester) async {
    await start(tester);
    await _pin(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await _pin(tester);
    expect(find.textContaining('Unsent comment'), findsNothing);
  });
}

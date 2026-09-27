import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/draft_store.dart';
import 'package:guidester/src/impact.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:guidester/src/ui/impact_chips.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// S15 of the 25 Sep field test: a tester killed mid-sentence lost the
/// sentence. Android kills a backgrounded app without warning, so nothing that
/// runs on dispose can be trusted to save it; the draft is written as it is
/// typed, and a force-stop is modelled here as the tree being thrown away and
/// rebuilt against the same preferences store.
class _Client extends http.BaseClient {
  _Client({this.status = 200, this.body = '{"ok":true}'});

  final int status;
  final String body;
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(
      jsonDecode(await request.finalize().bytesToString())
          as Map<String, dynamic>,
    );
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

Widget _app(ApiClient client) => MaterialApp(
      navigatorObservers: [Guidester.observer],
      builder: (context, child) =>
          GuidesterOverlay(client: client, child: child!),
      home: const HomeScreen(),
    );

Future<void> _placePin(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.tapAt(const Offset(200, 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.text('Send'));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
}

/// Throws the whole tree away, the way a force-stop does: no dispose-time
/// save gets a chance to matter, because the next tree reads the store.
Future<void> _relaunch(WidgetTester tester, ApiClient client) async {
  await tester.pumpWidget(const SizedBox());
  Guidester.debugReset();
  Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
  await tester.pumpWidget(_app(client));
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

  testWidgets('a draft typed before a force-stop is there after relaunch',
      (tester) async {
    final client = ApiClient(client: _Client());
    await tester.pumpWidget(_app(client));
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'the total is wrong');
    await tester.pump();

    await _relaunch(tester, client);
    await _placePin(tester);

    expect(find.text('the total is wrong'), findsOneWidget);
    // It may not be about the screen the tester is on now, so say where it
    // was written rather than filing it silently against this one.
    expect(find.textContaining('Unsent comment from HOME'), findsOneWidget);
  });

  testWidgets('the chosen impact survives with the text', (tester) async {
    final client = ApiClient(client: _Client());
    await tester.pumpWidget(_app(client));
    await _placePin(tester);
    await tester.tap(find.text(Impact.blocked.label));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'cannot pay');
    await tester.pump();

    await _relaunch(tester, client);
    await _placePin(tester);

    final chips = tester.widget<GuidesterImpactChips>(
      find.byType(GuidesterImpactChips),
    );
    expect(chips.selected, Impact.blocked);
  });

  testWidgets('a sent comment leaves no draft behind', (tester) async {
    final client = ApiClient(client: _Client());
    await tester.pumpWidget(_app(client));
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'sent already');
    await tester.pump();
    await _tapSend(tester);

    expect(await DraftStore.load(), isNull);
    await _relaunch(tester, client);
    await _placePin(tester);
    expect(find.text('sent already'), findsNothing);
    expect(find.textContaining('Unsent comment'), findsNothing);
  });

  // A refusal, not an outage: an outage is queued instead (outbox_test), and
  // then the draft is the queue's, not the composer's.
  testWidgets('a refused send keeps the draft for the next launch',
      (tester) async {
    final client = ApiClient(
      client: _Client(status: 401, body: '{"error":"invalid_key"}'),
    );
    await tester.pumpWidget(_app(client));
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'try later');
    await tester.pump();
    await _tapSend(tester);

    expect((await DraftStore.load())?.text, 'try later');
  });

  testWidgets('discarding a comment discards the draft', (tester) async {
    final client = ApiClient(client: _Client());
    await tester.pumpWidget(_app(client));
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'never mind');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(await DraftStore.load(), isNull);
  });

  testWidgets('clearing the field clears the draft', (tester) async {
    final client = ApiClient(client: _Client());
    await tester.pumpWidget(_app(client));
    await _placePin(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(await DraftStore.load(), isNull);
  });

  test('an unreadable store is no draft, not a crash', () async {
    SharedPreferences.setMockInitialValues({
      'guidester.draft': 42,
    });
    expect(await DraftStore.load(), isNull);
  });
}

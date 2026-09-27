import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Found recording the demo, 27 Sep, on the emulator. With the composer open,
/// a tap on the app above the sheet reached the app: it navigated to another
/// screen while the composer stayed open with the old screen's name and
/// screenshot, so the comment would file against a screen the tester had
/// left. And the host's AppBar grew a back arrow while the sheet was up,
/// because the Back handling's local history entry reads as "can go back".
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
  const _Home({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Align(
          alignment: Alignment.topCenter,
          child: TextButton(onPressed: onPressed, child: const Text('host')),
        ),
      );
}

Future<void> _openComposer(WidgetTester tester, VoidCallback onPressed) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [Guidester.observer],
      builder: (context, child) =>
          GuidesterOverlay(client: ApiClient(client: _Client()), child: child!),
      home: _Home(onPressed: onPressed),
    ),
  );
  await tester.tap(find.byIcon(Icons.chat_bubble_outline));
  await tester.pump();
  await tester.tapAt(const Offset(400, 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
  expect(find.byType(TextField), findsOneWidget);
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

  testWidgets('with the composer open, a tap on the app does not reach it',
      (tester) async {
    var pressed = 0;
    await _openComposer(tester, () => pressed++);

    await tester.tap(find.text('host'), warnIfMissed: false);
    await tester.pump();

    expect(pressed, 0);
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'the composer stays open',
    );
  });

  testWidgets('the app is reachable again once the composer closes',
      (tester) async {
    var pressed = 0;
    await _openComposer(tester, () => pressed++);

    // Back leaves comment mode entirely; ✕ goes back to "tap to pin" by
    // design, and that tap would place a pin rather than reach the app.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tap(find.text('host'));
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('the app bar does not grow a back arrow while the sheet is up',
      (tester) async {
    await _openComposer(tester, () {});
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('Back still closes the sheet', (tester) async {
    await _openComposer(tester, () {});
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });
}

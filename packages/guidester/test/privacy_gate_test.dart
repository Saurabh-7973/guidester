import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/ui/name_prompt.dart';
import 'package:http/http.dart' as http;

/// §7.1, "non-negotiable, do this first".
///
/// Guidester uploads screenshots and device identifiers off-device. The three
/// requirements before it reaches another human are: off by default, a Play
/// Data-safety declaration on the build testers receive, and a consent line in
/// the name prompt. Two of the three are code and are asserted here.
class _LoudClient extends http.BaseClient {
  final List<String> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url.toString());
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Guidester.debugReset);

  test('the build flag is off unless the dart-define says otherwise', () {
    // The suite runs without --dart-define=GUIDESTER, which is what a
    // production build looks like.
    expect(Guidester.compiledIn, isFalse);
  });

  // THE GATE, RESTATED. Until 0.3.0 there were two switches: a dart-define and
  // a key. The install asked for both, and the flag was the documented one.
  //
  // Now the KEY is the switch. That is what makes the install two lines, and it
  // moves the whole privacy guarantee onto one fact: a production build passes
  // no --dart-define=GUIDESTER_KEY, so the key is empty, so nothing runs.
  // These tests are that guarantee.

  test('an empty key is disabled, which is what production looks like', () {
    // The single most important assertion in this package. A host that ships
    // without the define must get an SDK that does nothing — no bubble, no
    // capture, no network.
    Guidester.init(apiKey: '', endpoint: 'https://e.test');
    expect(Guidester.isEnabled, isFalse);
  });

  test('a key and an endpoint enable it, with no flag', () {
    // The three-line install. If this ever goes false, the documented snippet
    // silently does nothing and every new user sees no bubble.
    Guidester.init(apiKey: 'k', endpoint: 'https://self.hosted/ingest');
    expect(Guidester.isEnabled, isTrue);
  });

  test('an explicit false overrides a present key', () {
    // The override for anyone who hardcodes a key and needs a separate switch.
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: false);
    expect(Guidester.isEnabled, isFalse);
  });

  test('an explicit true still enables it', () {
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
    expect(Guidester.isEnabled, isTrue);
  });

  test('an empty endpoint disables it — there is no default backend', () {
    // D71. There used to be a fallback to the author's project. A build that
    // passes a key but no GUIDESTER_ENDPOINT must send nothing anywhere;
    // diagnostic 1 says why, so this is not silence.
    Guidester.init(apiKey: 'k', endpoint: '');
    expect(Guidester.isEnabled, isFalse);
    expect(Guidester.endpoint, isEmpty);
  });

  test('no backend URL is compiled into the package', () {
    // D71. The published source must not carry anyone's project. Scans lib/
    // rather than trusting the API surface, because a default can come back
    // as a private constant that no test would otherwise see.
    final urlLiteral = RegExp('[\'"]https?://');
    String code(File f) => f
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => urlLiteral.hasMatch(code(f)))
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty, reason: 'URL literal in $hits');
  });

  test('a self-hosted endpoint is kept', () {
    Guidester.init(apiKey: 'k', endpoint: 'https://self.hosted/ingest');
    expect(Guidester.endpoint, 'https://self.hosted/ingest');
  });

  testWidgets('disabled: no chrome, and the host tree is untouched', (
    tester,
  ) async {
    // No key: the production shape.
    Guidester.init(apiKey: '', endpoint: 'https://e.test');

    final client = _LoudClient();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GuidesterOverlay(
          client: ApiClient(client: client),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: Text('host content'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('host content'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

    // build() returns the child on line one, so there is nothing to tap and
    // no capture path to reach.
    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(client.requests, isEmpty);
  });

  testWidgets('the consent line is in the name prompt, uncollapsed', (
    tester,
  ) async {
    // §7.1 item 3, quoted exactly. A tester is told before their first comment
    // leaves the device, and it is not behind a link or a disclosure.
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _PromptHost())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your feedback is sent with a screenshot of this screen and your '
        'device details.',
      ),
      findsOneWidget,
    );
  });
}

class _PromptHost extends StatelessWidget {
  const _PromptHost();

  @override
  Widget build(BuildContext context) => GuidesterNamePrompt(onSubmit: (_) {});
}

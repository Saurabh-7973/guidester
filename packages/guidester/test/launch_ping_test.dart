import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:http/http.dart' as http;

/// Records every request so a ping can be told apart from a comment.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.status = 200, this.body = '{"ok":true}'});

  final int status;
  final String body;
  final List<Map<String, dynamic>> requests = [];

  List<Map<String, dynamic>> get pings =>
      requests.where((r) => r['ping'] == true).toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = await request.finalize().bytesToString();
    requests.add(jsonDecode(payload) as Map<String, dynamic>);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

Widget _app(ApiClient client) => MaterialApp(
      home: const Scaffold(body: Center(child: Text('app content'))),
      builder: (context, child) =>
          GuidesterOverlay(client: client, child: child!),
    );

void main() {
  // Every test in this file is about the ping, so every one of them turns it
  // back on — the package's flutter_test_config switches it off for the rest
  // of the suite.
  setUp(() {
    Guidester.debugReset();
    Guidester.debugLaunchPingEnabled = true;
  });
  tearDown(() {
    Guidester.debugLaunchPingEnabled = false;
    Guidester.debugReset();
  });

  testWidgets('a mounted overlay announces the launch, once', (tester) async {
    Guidester.init(
      apiKey: 'test-key',
      endpoint: 'https://example.test/ingest',
      enabled: true,
    );
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));
    // The device lookup behind the ping is a platform channel with no
    // implementation under test: it answers only when its own 800ms timeout
    // fires, and pumpAndSettle alone advances no clock when nothing animates.
    // Three seconds: the test binding reports Android, so the device lookup
    // waits out its plugin timeout before the ping goes.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(rec.pings, hasLength(1));
    final ping = rec.pings.single;
    expect(ping['api_key'], 'test-key');
    expect(ping['ping'], true);
    // A ping is not a comment and must never be storable as one.
    expect(ping.containsKey('body'), isFalse);
    expect(ping.containsKey('screenshot_b64'), isFalse);
    expect(ping.containsKey('tap_x'), isFalse);
    expect(rec.requests, hasLength(1));
  });

  testWidgets('the kill switch silences the ping too', (tester) async {
    Guidester.init(
      apiKey: 'test-key',
      endpoint: 'https://example.test/ingest',
      enabled: false,
    );
    final rec = _RecordingClient();
    await tester.pumpWidget(_app(ApiClient(client: rec)));
    // The device lookup behind the ping is a platform channel with no
    // implementation under test: it answers only when its own 800ms timeout
    // fires, and pumpAndSettle alone advances no clock when nothing animates.
    // Three seconds: the test binding reports Android, so the device lookup
    // waits out its plugin timeout before the ping goes.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(
      rec.requests,
      isEmpty,
      reason: 'a disabled build reaches the network for nothing at all',
    );
  });

  testWidgets('a rejected ping is invisible to the tester', (tester) async {
    Guidester.init(
      apiKey: 'stale-key',
      endpoint: 'https://example.test/ingest',
      enabled: true,
    );
    final rec = _RecordingClient(status: 401, body: '{"error":"key_revoked"}');
    await tester.pumpWidget(_app(ApiClient(client: rec)));
    // The device lookup behind the ping is a platform channel with no
    // implementation under test: it answers only when its own 800ms timeout
    // fires, and pumpAndSettle alone advances no clock when nothing animates.
    // Three seconds: the test binding reports Android, so the device lookup
    // waits out its plugin timeout before the ping goes.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(rec.pings, hasLength(1));
    expect(tester.takeException(), isNull);
    // Nothing was asked for, so nothing is reported. The developer learns
    // about a revoked key from the dashboard, which is where they are looking.
    expect(find.textContaining('revoked'), findsNothing);
  });

  test('a revoked key says something different to an unconfigured one',
      () async {
    Guidester.init(
      apiKey: 'stale-key',
      endpoint: 'https://example.test/ingest',
      enabled: true,
    );
    final revoked = await ApiClient(
      client: _RecordingClient(status: 401, body: '{"error":"key_revoked"}'),
    ).ping();
    final invalid = await ApiClient(
      client: _RecordingClient(status: 401, body: '{"error":"invalid_key"}'),
    ).ping();

    expect(revoked.success, isFalse);
    expect(invalid.success, isFalse);
    expect(revoked.error, contains('revoked'));
    expect(revoked.error, isNot(invalid.error));
  });

  test('a disabled SDK cannot ping even when asked directly', () async {
    Guidester.init(
      apiKey: 'test-key',
      endpoint: 'https://example.test/ingest',
      enabled: false,
    );
    final rec = _RecordingClient();
    final result = await ApiClient(client: rec).ping();

    expect(result.success, isFalse);
    expect(rec.requests, isEmpty);
  });

  testWidgets('a rejected key is named at launch, from the ping alone', (
    tester,
  ) async {
    // Field test Stage B 7 (25 Sep): the line appeared only once a comment
    // was sent. This is the path a developer takes before any tester does.
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) lines.add(m);
    };
    try {
      Guidester.init(
        apiKey: 'wrong-key',
        endpoint: 'https://example.test/ingest',
        enabled: true,
      );
      final rec =
          _RecordingClient(status: 401, body: '{"error":"invalid_key"}');
      await tester.pumpWidget(_app(ApiClient(client: rec)));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(rec.pings, hasLength(1));
    } finally {
      debugPrint = previous;
    }
    expect(
      lines.any((l) => l.contains('key rejected (401 invalid_key)')),
      isTrue,
      reason: lines.join('\n'),
    );
  });
}

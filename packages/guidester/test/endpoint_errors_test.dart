import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:http/http.dart' as http;

/// Field test Stage B 10 (25 Sep): an endpoint that is wrong produced no
/// `[guidester]` line at all, and the tester was told "No connection" on a
/// working network, or shown a raw "error 405". Every other misconfiguration
/// already ends in one console line; this one has to as well, and it has to
/// be there at launch, from the ping, not only once a tester's report fails.

class _Console {
  final List<String> lines = [];
  DebugPrintCallback? _previous;

  void start() {
    _previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
  }

  void stop() {
    if (_previous == null) return;
    debugPrint = _previous!;
    _previous = null;
  }

  bool has(String fragment) => lines.any((l) => l.contains(fragment));
  String get joined => lines.join('\n');
}

class _Answering extends http.BaseClient {
  _Answering(this.status, this.body);
  final int status;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().bytesToString();
    return http.StreamedResponse(
      Stream.value(body.codeUnits),
      status,
      request: request,
    );
  }
}

class _Throwing extends http.BaseClient {
  _Throwing(this.error);
  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().bytesToString();
    throw error;
  }
}

const _wrongPath = 'https://example.com/nope';
const _wrongHost = 'https://api.guidester-wrong.invalid/functions/v1/ingest';

void main() {
  late _Console console;

  setUp(() {
    Guidester.debugReset();
    console = _Console()..start();
  });

  tearDown(() => console.stop());

  group('a host that answers, but is not the ingest function', () {
    test('405 with an HTML body: the log names the URL and the status',
        () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongPath);
      final api = ApiClient(client: _Answering(405, '<html>nope</html>'));

      final result = await api.send(body: 'x', screenName: 'HOME');

      expect(console.has('[guidester]'), isTrue, reason: console.joined);
      expect(console.has(_wrongPath), isTrue, reason: console.joined);
      expect(console.has('405'), isTrue, reason: console.joined);
      expect(console.has('GUIDESTER_ENDPOINT'), isTrue, reason: console.joined);
      // A tester cannot act on a status code, and retrying will not help.
      expect(result.error, isNot(contains('405')));
      expect(result.error, contains('not configured correctly'));
    });

    test("Supabase's own 404 for a function that does not exist", () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongPath);
      final api = ApiClient(
        client: _Answering(
          404,
          '{"code":"NOT_FOUND","message":"Requested function was not found"}',
        ),
      );

      final result = await api.send(body: 'x', screenName: 'HOME');

      expect(console.has(_wrongPath), isTrue, reason: console.joined);
      expect(result.error, contains('not configured correctly'));
    });

    test('the launch ping says it, before any tester has sent anything',
        () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongPath);
      final api = ApiClient(client: _Answering(405, ''));

      await api.ping();

      expect(console.has(_wrongPath), isTrue, reason: console.joined);
      expect(console.has('405'), isTrue, reason: console.joined);
    });

    test('a 5xx with no code is the server, not the build', () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongPath);
      final api = ApiClient(client: _Answering(503, 'upstream'));

      final result = await api.send(body: 'x', screenName: 'HOME');

      expect(console.has('503'), isTrue, reason: console.joined);
      expect(result.error, isNot(contains('not configured')));
      expect(result.error, contains('try again'));
    });
  });

  group('a host that cannot be reached', () {
    test('the log names the host and says what to check', () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongHost);
      final api = ApiClient(
        client: _Throwing(
          http.ClientException(
            "Failed host lookup: 'api.guidester-wrong.invalid'",
          ),
        ),
      );

      final result = await api.send(body: 'x', screenName: 'HOME');

      expect(console.has('[guidester]'), isTrue, reason: console.joined);
      expect(
        console.has('api.guidester-wrong.invalid'),
        isTrue,
        reason: console.joined,
      );
      expect(console.has('GUIDESTER_ENDPOINT'), isTrue, reason: console.joined);
      // Offline and a wrong host fail the same way on the device, so the
      // tester is told what is known: the server was not reached. Not that
      // their network is down, which on 25 Sep it was not.
      expect(result.error, isNot(startsWith('No connection')));
      expect(result.error, contains('Your comment is still here'));
    });

    // Demo recording, 27 Sep: a release build with no INTERNET permission
    // fails as a host lookup on a device that is online.
    test('on Android, a failed lookup also names the INTERNET permission',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      Guidester.init(apiKey: 'k', endpoint: _wrongHost);
      final api = ApiClient(
        client: _Throwing(http.ClientException('Failed host lookup: x')),
      );

      await api.send(body: 'x', screenName: 'HOME');

      expect(
        console.has('android.permission.INTERNET'),
        isTrue,
        reason: console.joined,
      );
    });

    test('elsewhere, and for a refused connection, it does not', () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongHost);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await ApiClient(
        client: _Throwing(http.ClientException('Failed host lookup: x')),
      ).send(body: 'x', screenName: 'HOME');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await ApiClient(
        client: _Throwing(http.ClientException('Connection refused')),
      ).send(body: 'x', screenName: 'HOME');

      expect(console.has('INTERNET'), isFalse, reason: console.joined);
    });

    test('the launch ping says it too', () async {
      Guidester.init(apiKey: 'k', endpoint: _wrongHost);
      final api = ApiClient(
        client: _Throwing(http.ClientException('Failed host lookup')),
      );

      await api.ping();

      expect(
        console.has('api.guidester-wrong.invalid'),
        isTrue,
        reason: console.joined,
      );
    });
  });

  test('a recognised rejection keeps its own line and no endpoint line',
      () async {
    Guidester.init(apiKey: 'k', endpoint: _wrongPath);
    final api = ApiClient(client: _Answering(401, '{"error":"invalid_key"}'));

    final result = await api.send(body: 'x', screenName: 'HOME');

    expect(
      console.has('key rejected (401 invalid_key)'),
      isTrue,
      reason: console.joined,
    );
    expect(console.has('GUIDESTER_ENDPOINT'), isFalse, reason: console.joined);
    expect(result.error, contains('invalid key'));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/draft_store.dart';
import 'package:guidester/src/outbox.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The offline queue. The deep review's case: testers report from lifts,
/// basements and trains, and one report lost to a spinner is enough for them
/// to stop trusting the button. A send that fails for a reason a retry can fix
/// is kept on the phone and goes later, carrying the same client_id every
/// time so the server (migration 0011) stores it once.

/// Offline until told otherwise, then answers with [status].
class _Network extends http.BaseClient {
  bool online = false;
  int status = 200;
  String body = '{"ok":true}';
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sent = jsonDecode(await request.finalize().bytesToString())
        as Map<String, dynamic>;
    if (!online) {
      throw const SocketException('Network is unreachable');
    }
    requests.add(sent);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }

  List<Map<String, dynamic>> get comments =>
      requests.where((r) => r['ping'] != true).toList();
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

Future<void> _comment(WidgetTester tester, String text) async {
  await _placePin(tester);
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await _tapSend(tester);
}

Map<String, dynamic> _payload(String body, [String? clientId]) =>
    ApiClient.commentPayload(
      body: body,
      screenName: 'HOME',
      clientId: clientId ?? Outbox.newClientId(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryOutboxStore store;

  setUp(() {
    Guidester.debugReset();
    TesterIdentity.debugReset();
    SharedPreferences.setMockInitialValues({
      'guidester.tester_name': 'Test Tester',
    });
    store = MemoryOutboxStore();
    Outbox.debugStore = store;
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
  });

  group('which failures a retry can fix', () {
    Future<SendResult> answer(int status, String body) {
      final net = _Network()
        ..online = true
        ..status = status
        ..body = body;
      return ApiClient(client: net).sendPayload(_payload('x'));
    }

    test('no network at all', () async {
      final r = await ApiClient(client: _Network()).sendPayload(_payload('x'));
      expect(r.success, isFalse);
      expect(r.retryable, isTrue);
    });

    test('a 5xx and a 429 are worth another try', () async {
      expect((await answer(500, 'x')).retryable, isTrue);
      expect(
        (await answer(503, '{"error":"insert_failed"}')).retryable,
        isTrue,
      );
      final limited = await answer(429, '{"error":"rate_limited"}');
      expect(limited.retryable, isTrue);
      expect(limited.error, contains('Too many comments'));
    });

    test('an answer about the request itself is not', () async {
      final revoked = await answer(401, '{"error":"key_revoked"}');
      expect(revoked.retryable, isFalse);
      expect(revoked.status, 401);
      expect(
        (await answer(400, '{"error":"body_too_long"}')).retryable,
        isFalse,
      );
      expect((await answer(405, '<html/>')).retryable, isFalse);
    });

    test('the key is added at send time, the client_id travels', () async {
      final net = _Network()..online = true;
      final payload = _payload('x', 'abcdef0123456789');
      expect(payload.containsKey('api_key'), isFalse);
      await ApiClient(client: net).sendPayload(payload);
      expect(net.requests.single['api_key'], 'k');
      expect(net.requests.single['client_id'], 'abcdef0123456789');
    });
  });

  group('Outbox', () {
    test('keeps what it is given, oldest first, without the key', () async {
      await Outbox.add({..._payload('first'), 'api_key': 'secret'});
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await Outbox.add(_payload('second'));

      final items = await Outbox.load();
      expect(items.map((i) => i.payload['body']), ['first', 'second']);
      expect(items.first.payload.containsKey('api_key'), isFalse);
      expect(store.entries.values.join(), isNot(contains('secret')));
    });

    test('keeps at most twenty, dropping the oldest', () async {
      for (var i = 0; i < Outbox.maxItems + 3; i++) {
        await Outbox.add(_payload('c$i'));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final items = await Outbox.load();
      expect(items, hasLength(Outbox.maxItems));
      expect(items.first.payload['body'], 'c3');
    });

    test('forgets what cannot be read and what is too old', () async {
      store.entries['000000000000001-bad.json'] = 'not json';
      store.entries['000000000000002-old.json'] = jsonEncode({
        'queued_at': DateTime.now()
            .subtract(Outbox.maxAge + const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'payload': _payload('stale'),
      });
      await Outbox.add(_payload('fresh'));

      final items = await Outbox.load();
      expect(items.map((i) => i.payload['body']), ['fresh']);
      expect(store.entries, hasLength(1));
    });

    test('client ids are 32 hex characters and do not repeat', () {
      final ids = {for (var i = 0; i < 200; i++) Outbox.newClientId()};
      expect(ids, hasLength(200));
      expect(ids.every(RegExp(r'^[0-9a-f]{32}$').hasMatch), isTrue);
    });
  });

  test('the file store writes, lists and deletes, and leaves no temp file',
      () async {
    final dir = await Directory.systemTemp.createTemp('outbox_test');
    addTearDown(() => dir.delete(recursive: true));
    final files = FileOutboxStore(Directory('${dir.path}/q'));

    expect(await files.readAll(), isEmpty); // no directory yet
    await files.write('1-a.json', '{"a":1}');
    await files.write('2-b.json', '{"b":2}');
    expect(
      await files.readAll(),
      {'1-a.json': '{"a":1}', '2-b.json': '{"b":2}'},
    );
    expect(
      Directory('${dir.path}/q')
          .listSync()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    await files.delete('1-a.json');
    await files.delete('missing.json'); // not an error
    expect((await files.readAll()).keys, ['2-b.json']);
  });

  group('OutboxSender', () {
    test('sends oldest first with the ids they were queued with', () async {
      await Outbox.add(_payload('one', 'id-one-0000'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await Outbox.add(_payload('two', 'id-two-0000'));
      final net = _Network()..online = true;
      var reported = 0;
      final sender =
          OutboxSender(ApiClient(client: net), onSent: (n) => reported = n);
      addTearDown(sender.dispose);

      await sender.kick();

      expect(
        net.requests.map((r) => r['client_id']),
        ['id-one-0000', 'id-two-0000'],
      );
      expect(reported, 2);
      expect(await Outbox.load(), isEmpty);
    });

    test('still offline: stops at the first and keeps everything', () async {
      await Outbox.add(_payload('one'));
      await Outbox.add(_payload('two'));
      final sender = OutboxSender(ApiClient(client: _Network()));
      addTearDown(sender.dispose);

      await sender.kick();
      expect(await Outbox.length, 2);
    });

    test('a refused key keeps the queue for a newer build', () async {
      await Outbox.add(_payload('one'));
      final net = _Network()
        ..online = true
        ..status = 401
        ..body = '{"error":"key_revoked"}';
      final sender = OutboxSender(ApiClient(client: net));
      addTearDown(sender.dispose);

      await sender.kick();
      expect(await Outbox.length, 1);
    });

    test('a comment the server will never take is dropped, not retried',
        () async {
      await Outbox.add(_payload('too long'));
      await Outbox.add(_payload('fine'));
      var calls = 0;
      final api = ApiClient(
        client: _Scripted((req) {
          calls++;
          return calls == 1
              ? (400, '{"error":"body_too_long"}')
              : (200, '{"ok":true}');
        }),
      );
      final sender = OutboxSender(api);
      addTearDown(sender.dispose);

      await sender.kick();
      expect(calls, 2);
      expect(await Outbox.load(), isEmpty);
    });
  });

  group('in the app', () {
    testWidgets(
        'offline: the comment is kept, the composer closes, and it '
        'goes when the app comes back', (tester) async {
      final net = _Network();
      await tester.pumpWidget(_app(ApiClient(client: net)));
      await tester.pump();

      await _comment(tester, 'the list is empty');

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Saved'), findsOneWidget);
      expect(await DraftStore.load(), isNull);
      final queued = await Outbox.load();
      expect(queued.single.payload['body'], 'the list is empty');
      final id = queued.single.payload['client_id'] as String;
      expect(id, hasLength(32));

      net.online = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(net.comments.single['client_id'], id);
      expect(net.comments.single['body'], 'the list is empty');
      expect(find.text('Saved comment sent'), findsOneWidget);
      expect(await Outbox.load(), isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it retries on its own while the app stays open',
        (tester) async {
      final net = _Network();
      await tester.pumpWidget(_app(ApiClient(client: net)));
      await tester.pump();
      await _comment(tester, 'lift');
      expect(await Outbox.length, 1);

      net.online = true;
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();

      expect(net.comments.single['body'], 'lift');
      expect(await Outbox.load(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a comment queued last launch goes on this one',
        (tester) async {
      await Outbox.add(_payload('from yesterday', 'yesterday-0001'));
      final net = _Network()..online = true;
      await tester.pumpWidget(_app(ApiClient(client: net)));
      await tester.pump();
      await tester.pump();

      expect(net.comments.single['client_id'], 'yesterday-0001');
      expect(await Outbox.load(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a live send carries a client_id and flushes the queue',
        (tester) async {
      await Outbox.add(_payload('queued', 'queued-00001'));
      final net = _Network();
      await tester.pumpWidget(_app(ApiClient(client: net)));
      await tester.pump();

      net.online = true;
      await _comment(tester, 'live');
      await tester.pump();

      final bodies = net.comments.map((r) => r['body']).toList();
      expect(bodies, containsAll(['live', 'queued']));
      final live = net.comments.firstWhere((r) => r['body'] == 'live');
      expect(live['client_id'], hasLength(32));
      expect(await Outbox.load(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a refusal is not queued: the error shows and the text stays',
        (tester) async {
      final net = _Network()
        ..online = true
        ..status = 401
        ..body = '{"error":"invalid_key"}';
      await tester.pumpWidget(_app(ApiClient(client: net)));
      await tester.pump();

      await _comment(tester, 'keep me');

      expect(find.textContaining('not configured correctly'), findsOneWidget);
      expect(find.text('keep me'), findsOneWidget);
      expect(await Outbox.load(), isEmpty);
    });

    testWidgets('a queue that cannot be written shows the error as before',
        (tester) async {
      Outbox.debugStore = _BrokenStore();
      await tester.pumpWidget(_app(ApiClient(client: _Network())));
      await tester.pump();

      await _comment(tester, 'nowhere to put it');

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('nowhere to put it'), findsOneWidget);
    });
  });
}

class _Scripted extends http.BaseClient {
  _Scripted(this.answer);
  final (int, String) Function(Map<String, dynamic>) answer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sent = jsonDecode(await request.finalize().bytesToString())
        as Map<String, dynamic>;
    final (status, body) = answer(sent);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

class _BrokenStore implements OutboxStore {
  @override
  Future<Map<String, String>> readAll() async =>
      throw const FileSystemException();
  @override
  Future<void> write(String name, String contents) async =>
      throw const FileSystemException('disk full');
  @override
  Future<void> delete(String name) async {}
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request with one canned body, and keeps what it was sent.
class _Canned extends http.BaseClient {
  _Canned(this.body, {this.status = 200});

  final String body;
  final int status;
  final List<Map<String, dynamic>> requests = [];

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

String _pingBody(List<Map<String, dynamic>> retests) =>
    jsonEncode({'ok': true, 'ping': true, 'retests': retests});

Map<String, dynamic> _row({
  String id = 'c1',
  String excerpt = 'the share sheet never opens',
  String screen = 'SEND FILE',
  String? fixedIn = '1.0.2 (7)',
}) =>
    {
      'id': id,
      'excerpt': excerpt,
      'screen_name': screen,
      'fixed_in_build': fixedIn,
      'created_at': '2026-09-12T04:15:00.000Z',
    };

void main() {
  setUp(() => Guidester.init(apiKey: 'k', endpoint: 'https://x.test/i'));
  tearDown(Guidester.debugReset);

  group('the ping carries the tester id', () {
    test('sent when the caller has one', () async {
      final rec = _Canned(_pingBody([]));
      await ApiClient(client: rec).ping(testerId: 't-42');
      expect(rec.requests.single['tester_id'], 't-42');
    });

    test('omitted rather than sent empty when there is none', () async {
      final rec = _Canned(_pingBody([]));
      await ApiClient(client: rec).ping();
      expect(rec.requests.single.containsKey('tester_id'), isFalse);
    });
  });

  group('the ping reads what it is answered with', () {
    test('a retest is parsed field by field', () async {
      final rec = _Canned(_pingBody([_row()]));
      final r = await ApiClient(client: rec).ping(testerId: 't-42');

      expect(r.success, isTrue);
      expect(r.retests, hasLength(1));
      final item = r.retests.single;
      expect(item.id, 'c1');
      expect(item.excerpt, 'the share sheet never opens');
      expect(item.screenName, 'SEND FILE');
      expect(item.fixedInBuild, '1.0.2 (7)');
    });

    test('an older backend that answers without the key yields none', () async {
      final rec = _Canned('{"ok":true,"ping":true}');
      final r = await ApiClient(client: rec).ping(testerId: 't-42');
      expect(r.success, isTrue);
      expect(r.retests, isEmpty);
    });

    test('a row with no id is dropped, and the rest of the list survives',
        () async {
      // The response is parsed on a tester's phone. One bad row must not cost
      // them the others, and must never throw into the launch path.
      final rec = _Canned(
        _pingBody([
          {'excerpt': 'no id here'},
          _row(id: 'c2'),
        ]),
      );
      final r = await ApiClient(client: rec).ping(testerId: 't-42');
      expect(r.retests.map((e) => e.id), ['c2']);
    });

    test('a body that is not JSON is not a crash', () async {
      final rec = _Canned('<html>gateway</html>');
      final r = await ApiClient(client: rec).ping(testerId: 't-42');
      expect(r.success, isTrue);
      expect(r.retests, isEmpty);
    });

    test('a rejected key answers with no retests and the failure survives',
        () async {
      final rec = _Canned('{"error":"key_revoked"}', status: 401);
      final r = await ApiClient(client: rec).ping(testerId: 't-42');
      expect(r.success, isFalse);
      expect(r.retests, isEmpty);
    });

    test('a missing fixed_in_build is null, not the string null', () async {
      final rec = _Canned(_pingBody([_row(fixedIn: null)]));
      final r = await ApiClient(client: rec).ping(testerId: 't-42');
      expect(r.retests.single.fixedInBuild, isNull);
    });
  });

  group('a tester answers', () {
    test('works now posts accepted, with both halves of the ownership check',
        () async {
      final rec = _Canned('{"ok":true,"verdict":"accepted"}');
      final r = await ApiClient(client: rec)
          .sendVerdict(commentId: 'c1', testerId: 't-42', accepted: true);

      expect(r.success, isTrue);
      final sent = rec.requests.single;
      expect(sent['verdict'], 'accepted');
      expect(sent['comment_id'], 'c1');
      expect(sent['tester_id'], 't-42');
      expect(sent['api_key'], 'k');
      // A verdict is not a comment and must never be storable as one.
      expect(sent.containsKey('body'), isFalse);
      expect(sent.containsKey('screenshot_b64'), isFalse);
    });

    test('still broken posts rejected', () async {
      final rec = _Canned('{"ok":true,"verdict":"rejected"}');
      await ApiClient(client: rec)
          .sendVerdict(commentId: 'c1', testerId: 't-42', accepted: false);
      expect(rec.requests.single['verdict'], 'rejected');
    });

    test('a report that is not theirs fails in words a tester can read',
        () async {
      // The backend returns the same 404 for "no such comment" and "not
      // yours" on purpose. The SDK must not invent a distinction either.
      final rec = _Canned('{"error":"not_found"}', status: 404);
      final r = await ApiClient(client: rec)
          .sendVerdict(commentId: 'c1', testerId: 't-42', accepted: true);
      expect(r.success, isFalse);
      expect(r.error, isNotNull);
      expect(r.error, isNot(contains('404')));
    });
  });

  group('the overlay, when something is waiting', _overlayTests);
}

/// Everything below is the overlay half: what a tester actually sees when the
/// ping comes back with something waiting on them.
void _overlayTests() {
  Widget app(ApiClient client) => MaterialApp(
        home: const Scaffold(body: Center(child: Text('app content'))),
        builder: (context, child) =>
            GuidesterOverlay(client: client, child: child!),
      );

  /// The launch ping is a real call on a real timer; the package turns it off
  /// by default and these tests are about it.
  setUp(() {
    Guidester.debugReset();
    Guidester.debugLaunchPingEnabled = true;
    TesterIdentity.debugReset();
    SharedPreferences.setMockInitialValues({'guidester.tester_id': 't-42'});
    Guidester.init(
      apiKey: 'k',
      endpoint: 'https://x.test/i',
      enabled: true,
    );
  });
  tearDown(() {
    Guidester.debugLaunchPingEnabled = false;
    Guidester.debugReset();
    TesterIdentity.debugReset();
  });

  testWidgets('the launch ping carries this device tester id', (tester) async {
    final rec = _Canned(_pingBody([]));
    await tester.pumpWidget(app(ApiClient(client: rec)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(rec.requests, isNotEmpty);
    expect(rec.requests.first['tester_id'], 't-42');
  });

  testWidgets('a retest waiting on the tester badges the bubble',
      (tester) async {
    final rec = _Canned(_pingBody([_row(), _row(id: 'c2')]));
    await tester.pumpWidget(app(ApiClient(client: rec)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('nothing waiting means no badge', (tester) async {
    final rec = _Canned(_pingBody([]));
    await tester.pumpWidget(app(ApiClient(client: rec)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guidester.retest.badge')), findsNothing);
  });

  testWidgets('the badge opens a list naming the build with the fix',
      (tester) async {
    final rec = _Canned(_pingBody([_row()]));
    await tester.pumpWidget(app(ApiClient(client: rec)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guidester.retest.badge')));
    await tester.pumpAndSettle();

    expect(find.textContaining('the share sheet never opens'), findsOneWidget);
    // A tester on an older build is told to update, not told they are wrong.
    expect(find.textContaining('1.0.2 (7)'), findsOneWidget);
    expect(find.text('Works now'), findsOneWidget);
    expect(find.text('Still broken'), findsOneWidget);
  });

  testWidgets('Works now posts accepted and the item leaves the list',
      (tester) async {
    final rec = _Canned(_pingBody([_row()]));
    await tester.pumpWidget(app(ApiClient(client: rec)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guidester.retest.badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Works now'));
    await tester.pumpAndSettle();

    final verdicts =
        rec.requests.where((r) => r.containsKey('verdict')).toList();
    expect(verdicts, hasLength(1));
    expect(verdicts.single['verdict'], 'accepted');
    expect(verdicts.single['comment_id'], 'c1');
    expect(verdicts.single['tester_id'], 't-42');
    // Answered, so it is no longer waiting on anybody.
    expect(find.byKey(const Key('guidester.retest.badge')), findsNothing);
  });

  testWidgets('Still broken posts rejected and arms a fresh capture',
      (tester) async {
    // The whole reason this lives in the app rather than behind a link: the
    // answer "no" can carry a new screenshot of the same build.
    final rec = _Canned(_pingBody([_row()]));
    await tester.pumpWidget(app(ApiClient(client: rec)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guidester.retest.badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Still broken'));
    await tester.pumpAndSettle();

    final verdicts =
        rec.requests.where((r) => r.containsKey('verdict')).toList();
    expect(verdicts.single['verdict'], 'rejected');
    // Comment mode, which is the tap-to-pin state the mode bar announces.
    expect(find.text('Tap anywhere to comment'), findsOneWidget);
  });

  testWidgets('a verdict the server refuses keeps the item on the list',
      (tester) async {
    final rec = _Canned(_pingBody([_row()]));
    final client = _SwitchingClient(rec);
    await tester.pumpWidget(app(ApiClient(client: client)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guidester.retest.badge')));
    await tester.pumpAndSettle();
    client.failNext = true;
    await tester.tap(find.text('Works now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Works now'),
      findsOneWidget,
      reason: 'an unanswered report must not disappear',
    );
  });
}

/// Answers the ping normally, then fails the next write on request.
class _SwitchingClient extends http.BaseClient {
  _SwitchingClient(this.inner);

  final _Canned inner;
  bool failNext = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!failNext) return inner.send(request);
    final payload = await request.finalize().bytesToString();
    inner.requests.add(jsonDecode(payload) as Map<String, dynamic>);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"error":"lookup_failed"}')),
      500,
      request: request,
    );
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/error_recorder.dart';
import 'package:guidester/src/tester_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingClient extends http.BaseClient {
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(
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

StackTrace _stackOf(int frames) => StackTrace.fromString(
      List.generate(frames, (i) => '#$i      Something.method (file.dart:$i)')
          .join('\n'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Guidester.debugReset();
    TesterIdentity.debugReset();
  });
  tearDown(Guidester.debugReset);

  void enable() => Guidester.init(
        apiKey: 'k',
        endpoint: 'https://example.test/ingest',
        enabled: true,
      );

  test('a disabled build chains no handlers at all', () {
    final before = FlutterError.onError;
    Guidester.init(
      apiKey: 'k',
      endpoint: 'https://example.test/ingest',
      enabled: false,
    );

    expect(ErrorRecorder.isInstalled, isFalse);
    expect(FlutterError.onError, same(before));
  });

  test('an enabled build records what the framework throws', () {
    final seen = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = seen.add;
    addTearDown(() => FlutterError.onError = previous);

    enable();
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('bad state'),
        stack: _stackOf(3),
        library: 'widgets library',
      ),
    );

    final error = ErrorRecorder.errors.single;
    expect(error.exception, contains('bad state'));
    expect(error.stack, contains('Something.method'));
    expect(error.library, 'widgets library');
    // The host's handler still ran. Taking over Flutter's error path to show
    // an error to ourselves and hide it from the developer would be worse
    // than not capturing it.
    expect(seen, hasLength(1));
  });

  test('a platform error is recorded and still reported as unhandled', () {
    enable();
    final handled = PlatformDispatcher.instance.onError!(
      ArgumentError('no such id'),
      _stackOf(2),
    );

    expect(ErrorRecorder.errors.single.exception, contains('no such id'));
    expect(
      handled,
      isFalse,
      reason: 'claiming to have handled it would silence a real crash',
    );
  });

  test('the buffer keeps the last three, oldest first', () {
    enable();
    for (final n in ['first', 'second', 'third', 'fourth']) {
      ErrorRecorder.record(StateError(n), _stackOf(1));
    }

    final all = ErrorRecorder.errors;
    expect(all, hasLength(ErrorRecorder.maxErrors));
    expect(all.first.exception, contains('second'));
    expect(all.last.exception, contains('fourth'));
    expect(
      all.map((e) => e.exception).join(),
      isNot(contains('first')),
      reason: 'the buffer is a bound, not a log',
    );
  });

  test('a runaway exception and a deep stack are both bounded', () {
    enable();
    ErrorRecorder.record(StateError('x' * 5000), _stackOf(400));

    final error = ErrorRecorder.errors.single;
    expect(error.exception.length, lessThan(600));
    expect(
      '\n'.allMatches(error.stack).length,
      lessThan(ErrorRecorder.maxStackFrames),
    );
    expect(error.stack.length, lessThanOrEqualTo(4001));
  });

  test('an error with no stack is still worth having', () {
    enable();
    ErrorRecorder.record(StateError('channel died'), null);

    expect(ErrorRecorder.errors.single.stack, isEmpty);
    expect(ErrorRecorder.errors.single.exception, contains('channel died'));
  });

  test('the payload is JSON the ingest function will accept', () {
    enable();
    ErrorRecorder.record(
      StateError('bad state'),
      _stackOf(2),
      library: 'widgets library',
    );

    final json = ErrorRecorder.toJson().single;
    expect(json['at'], isA<String>());
    expect(json['at'], endsWith('Z'), reason: 'UTC, so two devices compare');
    expect(json['exception'], isA<String>());
    expect(json['stack'], isA<String>());
    expect(json['library'], 'widgets library');
  });

  test('calling init twice does not double-chain or lose a handler', () {
    final original = FlutterError.onError;
    enable();
    final chained = FlutterError.onError;
    enable();

    expect(FlutterError.onError, same(chained));
    Guidester.debugReset();
    expect(
      FlutterError.onError,
      same(original),
      reason: 'reset gives the host back exactly what it had',
    );
  });

  test('a reset empties the buffer as well as unhooking it', () {
    enable();
    ErrorRecorder.record(StateError('before'), _stackOf(1));
    expect(ErrorRecorder.bufferLength, 1);

    Guidester.debugReset();

    expect(ErrorRecorder.isInstalled, isFalse);
    expect(ErrorRecorder.bufferLength, 0);
    expect(ErrorRecorder.toJson(), isEmpty);
  });

  testWidgets('a comment carries what the app threw before it', (tester) async {
    SharedPreferences.setMockInitialValues({'guidester.tester_name': 'Tester'});
    enable();
    ErrorRecorder.record(
      StateError('RenderFlex overflowed by 42 pixels'),
      _stackOf(3),
      library: 'rendering library',
    );

    final rec = _RecordingClient();
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Center(child: Text('app'))),
        builder: (context, child) =>
            GuidesterOverlay(client: ApiClient(client: rec), child: child!),
      ),
    );
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'the list is empty');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    final sent = rec.requests.single;
    final errors = (sent['errors'] as List).cast<Map<String, dynamic>>();
    expect(errors, hasLength(1));
    expect(errors.single['exception'], contains('RenderFlex overflowed'));
    expect(errors.single['stack'], contains('Something.method'));
    expect(errors.single['library'], 'rendering library');
  });

  testWidgets('a clean session sends no errors key at all', (tester) async {
    SharedPreferences.setMockInitialValues({'guidester.tester_name': 'Tester'});
    enable();

    final rec = _RecordingClient();
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Center(child: Text('app'))),
        builder: (context, child) =>
            GuidesterOverlay(client: ApiClient(client: rec), child: child!),
      ),
    );
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'nothing broke');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(rec.requests.single.containsKey('errors'), isFalse);
  });
}

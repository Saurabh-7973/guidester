import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/guidester.dart';
import 'package:guidester/src/api_client.dart';
import 'package:guidester/src/bubble_position.dart';
import 'package:guidester/src/ui/bubble.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// D44: the bubble lands on Sahaj's "Me" tab, and every host with bottom
/// navigation hits the same overlap. It drags, snaps to the nearer vertical
/// edge, and is remembered — overriding B6's fixed bottom-right.
class _StubClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      request: request,
    );
  }
}

Widget _app() => MaterialApp(
      navigatorObservers: [Guidester.observer],
      builder: (context, child) => GuidesterOverlay(
        client: ApiClient(client: _StubClient()),
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('host content'))),
    );

Finder get _bubble => find.byIcon(Icons.chat_bubble_outline);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BubblePosition.debugReset();
    Guidester.init(apiKey: 'k', endpoint: 'https://e.test', enabled: true);
  });

  testWidgets('it starts bottom-right, where B6 put it', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GuidesterBubble));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(rect.right, closeTo(screen.width - 16, 0.5));
    expect(rect.bottom, closeTo(screen.height - 16, 0.5));
  });

  testWidgets('dragging left snaps it to the left edge', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.drag(_bubble, const Offset(-600, -200));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GuidesterBubble));
    expect(rect.left, closeTo(16, 0.5), reason: 'snapped to the left edge');
  });

  testWidgets('a drag that stays past the midpoint keeps the right edge', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp));
    await tester.drag(_bubble, const Offset(-80, -150));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GuidesterBubble));
    expect(rect.right, closeTo(screen.width - 16, 0.5));
  });

  testWidgets('it moves vertically and stays where it was dropped', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final before = tester.getRect(find.byType(GuidesterBubble));
    await tester.drag(_bubble, const Offset(0, -300));
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(GuidesterBubble));
    expect(after.top, lessThan(before.top - 200));
  });

  testWidgets('the position survives a restart', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.drag(_bubble, const Offset(-600, -250));
    await tester.pumpAndSettle();
    final moved = tester.getRect(find.byType(GuidesterBubble));

    // A fresh overlay, the same prefs store: the cache is cleared so this
    // exercises the stored values, not the in-memory ones.
    BubblePosition.debugReset();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final restored = tester.getRect(find.byType(GuidesterBubble));
    expect(restored.left, closeTo(moved.left, 0.5));
    expect(restored.top, closeTo(moved.top, 0.5));
  });

  testWidgets('it never leaves the screen, however far you throw it', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.drag(_bubble, const Offset(-4000, 4000));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GuidesterBubble));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(screen.width));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));
  });

  testWidgets('tapping it still arms comment mode', (tester) async {
    // Drag must not eat the tap — the bubble's whole job is one tap.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(_bubble);
    await tester.pump();

    expect(find.text('Tap anywhere to comment'), findsOneWidget);
  });

  testWidgets('a moved bubble still arms comment mode', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.drag(_bubble, const Offset(-600, -200));
    await tester.pumpAndSettle();

    await tester.tap(_bubble);
    await tester.pump();

    expect(find.text('Tap anywhere to comment'), findsOneWidget);
  });

  test('the snap midpoint is the screen centre, by the bubble centre', () {
    // 52px bubble on a 400px screen: its centre crosses 200 at x = 174.
    expect(BubblePosition.snapsRight(174, 400), isTrue);
    expect(BubblePosition.snapsRight(173, 400), isFalse);
  });
}

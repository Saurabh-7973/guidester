import 'package:dashboard/src/models/captured_error.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/widgets/error_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _hostStack = '''
#0      RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:900:9)
#1      HomeScreen.build (package:sahaj/screens/home_screen.dart:42:9)
#2      StatelessElement.build (package:flutter/src/widgets/framework.dart:5)
''';

CapturedError _error({
  String exception = 'RenderFlex overflowed by 42 pixels',
  String stack = _hostStack,
  String? library = 'rendering library',
  String? screen = 'HOME',
}) => CapturedError(
  exception: exception,
  stack: stack,
  at: DateTime(2026, 9, 9, 14, 5, 3),
  library: library,
  screen: screen,
);

Future<void> _pump(WidgetTester tester, List<CapturedError> errors) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ErrorPanel(errors: errors)),
        ),
      ),
    );

void main() {
  group('parsing', () {
    test('a row from the wire becomes an error', () {
      final e = CapturedError.fromJson({
        'at': '2026-09-09T08:35:03.000Z',
        'exception': 'Bad state: no element',
        'stack': _hostStack,
        'library': 'widgets library',
        'screen': 'CHECKOUT',
      });

      expect(e.exception, 'Bad state: no element');
      expect(e.screen, 'CHECKOUT');
      expect(e.at?.isUtc, isFalse, reason: 'shown in the reader local time');
    });

    test('the culprit is the first frame outside Flutter', () {
      expect(_error().culprit, 'package:sahaj/screens/home_screen.dart:42:9');
    });

    test('an all-framework stack names no culprit rather than a wrong one', () {
      final e = _error(
        stack:
            '#0      RenderFlex.performLayout '
            '(package:flutter/src/rendering/flex.dart:900:9)',
      );

      expect(e.culprit, isNull);
    });

    test('a paragraph-long assertion still has a one-line headline', () {
      final e = _error(
        exception:
            'A RenderFlex overflowed by 42 pixels on the right.\n'
            'The overflowing RenderFlex has an orientation of Axis.horizontal.',
      );

      expect(e.headline, endsWith('on the right.'));
      expect(e.headline, isNot(contains('orientation')));
    });

    test('a comment row carries its errors, and an old row carries none', () {
      final withErrors = Comment.fromRow({
        'id': '1',
        'body': 'white screen',
        'created_at': '2026-09-09T08:35:03.000Z',
        'errors': [
          {'exception': 'Bad state', 'stack': _hostStack},
        ],
      });
      final withoutErrors = Comment.fromRow({
        'id': '2',
        'body': 'looks fine',
        'created_at': '2026-09-09T08:35:03.000Z',
      });

      expect(withErrors.errors.single.exception, 'Bad state');
      expect(withoutErrors.errors, isEmpty);
    });
  });

  group('panel', () {
    testWidgets('nothing is rendered when nothing went wrong', (tester) async {
      await _pump(tester, const []);

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('the headline and the host frame are visible without a tap', (
      tester,
    ) async {
      await _pump(tester, [_error()]);

      expect(find.text('The app threw this'), findsOneWidget);
      expect(find.text('RenderFlex overflowed by 42 pixels'), findsOneWidget);
      expect(
        find.text('package:sahaj/screens/home_screen.dart:42:9'),
        findsOneWidget,
      );
      // The frames themselves are not, or every error buries the comment.
      expect(find.textContaining('StatelessElement.build'), findsNothing);
    });

    testWidgets('the stack opens and closes', (tester) async {
      await _pump(tester, [_error()]);

      await tester.tap(find.text('Show stack'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatelessElement.build'), findsOneWidget);

      await tester.tap(find.text('Hide stack'));
      await tester.pumpAndSettle();
      expect(find.textContaining('StatelessElement.build'), findsNothing);
    });

    testWidgets('an error with no stack offers no stack controls', (
      tester,
    ) async {
      await _pump(tester, [_error(stack: '')]);

      expect(find.text('NO STACK'), findsOneWidget);
      expect(find.text('Show stack'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('a framework-only stack says so instead of going quiet', (
      tester,
    ) async {
      await _pump(tester, [
        _error(
          stack:
              '#0      RenderFlex.performLayout '
              '(package:flutter/src/rendering/flex.dart:900:9)',
        ),
      ]);

      expect(find.text('FRAMEWORK FRAMES ONLY'), findsOneWidget);
    });

    testWidgets('three errors render newest first', (tester) async {
      await _pump(tester, [
        _error(exception: 'first'),
        _error(exception: 'second'),
        _error(exception: 'third'),
      ]);

      expect(find.text('The app threw these, newest first'), findsOneWidget);
      final third = tester.getTopLeft(find.text('third')).dy;
      final first = tester.getTopLeft(find.text('first')).dy;
      expect(third, lessThan(first));
    });

    testWidgets('copy puts the exception and the stack on the clipboard', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(tester, [_error()]);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied.single, contains('RenderFlex overflowed'));
      expect(copied.single, contains('home_screen.dart'));
      expect(find.text('Copied'), findsOneWidget);
    });
  });
}

import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Spec §5.6 row 17. UNKNOWN is a fixable install problem, not a screen
/// name; the detail says so and says how.
Future<void> _pump(WidgetTester tester, String screen) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(
          repository: FakeRepository({
            CommentStatus.open: [
              testComment(id: 'c1', body: 'a problem', screen: screen),
            ],
          }),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('UNKNOWN says the screen was not detected, and how to fix', (
    tester,
  ) async {
    await _pump(tester, 'UNKNOWN');
    expect(find.text('Screen not detected'), findsOneWidget);
    await tester.tap(find.text('How to name screens'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
    expect(find.textContaining('Guidester.observer'), findsOneWidget);
  });

  testWidgets('a named screen shows no such note', (tester) async {
    await _pump(tester, 'CHECKOUT');
    expect(find.text('Screen not detected'), findsNothing);
  });
}

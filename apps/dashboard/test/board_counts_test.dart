import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Found in the 27 Sep audit: the counts row (fixed not verified, reported
/// today, this week, blocked) appeared only after a verdict change or a
/// refresh tick. A board that had just opened showed none.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  testWidgets('the counts load with the board', (tester) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'one')],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CommentsScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('reported today'), findsOneWidget);
    expect(find.text('blocked'), findsOneWidget);
  });
}

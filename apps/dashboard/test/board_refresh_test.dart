import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Found watching the board during the 27 Sep demo: a tester's comment
/// appeared only after a reload. An open board now looks again on its own,
/// quietly: no skeleton, and the comment being read stays open.
Widget _wrap(FakeRepository repo) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: CommentsScreen(
      repository: repo,
      refreshEvery: const Duration(seconds: 1),
    ),
  ),
);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  testWidgets('a comment that arrives while the board is open appears', (
    tester,
  ) async {
    final open = <Comment>[testComment(id: '1', body: 'being read')];
    final repo = FakeRepository({CommentStatus.open: open});
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    // Listed, and open in the pane.
    expect(find.text('being read'), findsNWidgets(2));

    open.insert(0, testComment(id: '2', body: 'arrived later'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey('board-skeleton')),
      findsNothing,
      reason: 'a refresh never blanks the board',
    );
    await tester.pumpAndSettle();

    expect(find.text('arrived later'), findsOneWidget, reason: 'listed');
    expect(
      find.text('being read'),
      findsNWidgets(2),
      reason: 'the comment being read stays open',
    );
  });

  // Found in the 27 Sep audit: a comment marked Fixed while the In Progress
  // tab was open vanished on the next refresh tick, pane and all, while its
  // note and assignee were being typed.
  testWidgets('the open comment stays until the reader moves on', (
    tester,
  ) async {
    // The only comment in the tab: the case that emptied the board.
    final open = <Comment>[testComment(id: '1', body: 'being read')];
    final repo = FakeRepository({CommentStatus.open: open});
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('being read'), findsNWidgets(2));

    // It left this tab on the server (resolved elsewhere, or by this user).
    open.clear();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      find.text('being read'),
      findsWidgets,
      reason: 'still open in the pane while it is being read',
    );
  });

  testWidgets('a pending delete does not come back during its Undo window', (
    tester,
  ) async {
    final open = <Comment>[
      testComment(id: '1', body: 'to delete'),
      testComment(id: '2', body: 'keeper'),
    ];
    final repo = FakeRepository({CommentStatus.open: open});
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);

    // Two refresh ticks inside the 5 s window; the fake still returns it.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('to delete'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

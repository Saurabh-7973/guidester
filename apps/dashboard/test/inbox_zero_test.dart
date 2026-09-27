import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Spec §5.6 row 11. An empty Open tab in a project that has comments is
/// the goal reached, not a new project: it must not show the first-run help.
Future<FakeRepository> _pump(WidgetTester tester, {int? total}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeRepository({
    CommentStatus.resolved: [
      testComment(
        id: 'r1',
        body: 'fixed thing',
        status: CommentStatus.resolved,
      ),
    ],
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(repository: repo, projectTotal: total),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('nothing open in a busy project is Inbox zero', (tester) async {
    await _pump(tester, total: 12);
    expect(find.text('Inbox zero'), findsOneWidget);
    expect(find.text('No comments left yet'), findsNothing);
  });

  testWidgets('Inbox zero offers the resolved ones', (tester) async {
    final repo = await _pump(tester, total: 12);
    await tester.tap(find.text('See resolved'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'fetch:resolved:all');
    expect(find.text('fixed thing'), findsWidgets);
  });

  testWidgets('a project with no comments at all keeps the first-run help', (
    tester,
  ) async {
    await _pump(tester, total: 0);
    expect(find.text('No comments left yet'), findsOneWidget);
    expect(find.text('Inbox zero'), findsNothing);
  });
}

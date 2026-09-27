import 'dart:async';

import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

void main() {
  testWidgets('loading looks like the list, not a spinner', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'a problem')],
    })..fetchGate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CommentsScreen(repository: repo)),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('board-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading comments'), findsOneWidget);

    repo.fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-skeleton')), findsNothing);
    expect(find.text('a problem'), findsWidgets);
  });

  testWidgets('offline: a banner, no false empty state, and it recovers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo =
        FakeRepository({
            CommentStatus.open: [testComment(id: '1', body: 'a problem')],
          })
          ..failFetchWith =
              'Could not reach the database. Check your connection.'
          ..failFetchOffline = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CommentsScreen(repository: repo)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text("Can't reach the server. Retrying…"), findsOneWidget);
    // Not "No comments left yet": nothing is known about the comments.
    expect(find.text('No comments left yet'), findsNothing);

    repo.failFetchWith = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("Can't reach the server. Retrying…"), findsNothing);
    expect(find.text('a problem'), findsWidgets);
  });

  testWidgets('a database refusal is not retried: it says so, with Try again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository(const {})
      ..failFetchWith = "You do not have access to this project's comments.";
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CommentsScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text("Can't reach the server. Retrying…"), findsNothing);
  });
}

import 'dart:async';

import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Spec §5.6 row 19: a verdict shows at once, and a save that fails puts it
/// back and says so, with Retry.
Future<FakeRepository> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeRepository({
    CommentStatus.open: [testComment(id: 'c1', body: 'a problem')],
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: CommentsScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

bool _selected(WidgetTester tester, String chip) => tester
    .widget<Semantics>(
      find
          .ancestor(
            of: find.text(chip),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.selected != null,
            ),
          )
          .first,
    )
    .properties
    .selected!;

void main() {
  testWidgets('the verdict shows before the server answers', (tester) async {
    final repo = await _pump(tester);
    repo.verdictGate = Completer<void>();
    await tester.tap(find.text('Deferred'));
    await tester.pump();
    expect(_selected(tester, 'Deferred'), isTrue);
    repo.verdictGate!.complete();
    await tester.pumpAndSettle();
    expect(_selected(tester, 'Deferred'), isTrue);
  });

  testWidgets('a failed save puts it back, says so, and Retry works', (
    tester,
  ) async {
    final repo = await _pump(tester);
    repo.failVerdictWith = 'Could not reach the database.';
    await tester.tap(find.text('Deferred'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'Deferred'), isFalse);
    expect(_selected(tester, 'New'), isTrue);
    expect(
      find.textContaining('Could not reach the database.'),
      findsOneWidget,
    );

    repo.failVerdictWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.verdicts.single['dev'], 'deferred');
    expect(_selected(tester, 'Deferred'), isTrue);
  });
}

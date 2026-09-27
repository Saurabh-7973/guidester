import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Field test Stage D 23: j/k were bound and did nothing once the mouse had
/// touched the page. Triage is a keyboard job; every step of it is here.
FakeRepository _repo() => FakeRepository({
  CommentStatus.open: [
    testComment(id: '1', body: 'first problem'),
    testComment(id: '2', body: 'second problem'),
    testComment(id: '3', body: 'third problem'),
  ],
});

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  VoidCallback? onSettings,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(repository: repo, onOpenSettings: onSettings),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The detail pane's title is the selected comment's body.
bool _showing(WidgetTester tester, String body) =>
    find.text(body).evaluate().length > 1;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('j and k move, even after a click on the pane', (tester) async {
    await _pump(tester, _repo());
    expect(_showing(tester, 'first problem'), isTrue);

    // A click on a blank part of the detail pane: the field test's case.
    await tester.tapAt(const Offset(1100, 700));
    await tester.pumpAndSettle();

    await _key(tester, LogicalKeyboardKey.keyJ);
    expect(_showing(tester, 'second problem'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyJ);
    expect(_showing(tester, 'third problem'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyK);
    expect(_showing(tester, 'second problem'), isTrue);
  });

  testWidgets('j and k still move after a click on a row', (tester) async {
    await _pump(tester, _repo());
    await tester.tap(find.text('second problem').first);
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.keyJ);
    expect(_showing(tester, 'third problem'), isTrue);
  });

  testWidgets('r resolves the selected comment', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    await _key(tester, LogicalKeyboardKey.keyR);
    expect(repo.calls, contains('update:1:resolved'));
  });

  testWidgets('p marks the selected comment in progress', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    await _key(tester, LogicalKeyboardKey.keyP);
    expect(repo.calls, contains('update:1:in_progress'));
  });

  testWidgets('? lists the shortcuts, Esc closes it', (tester) async {
    await _pump(tester, _repo());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Next comment'), findsWidgets);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Keyboard shortcuts'), findsNothing);
  });

  testWidgets('typing j in the note field types, and does not move', (
    tester,
  ) async {
    await _pump(tester, _repo());
    final note = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Add a note',
    );
    await tester.tap(note);
    await tester.pumpAndSettle();
    await tester.enterText(note, 'j');
    await _key(tester, LogicalKeyboardKey.keyJ);
    expect(_showing(tester, 'first problem'), isTrue);
  });

  testWidgets('resolving moves on to the next comment, not the first', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await _key(tester, LogicalKeyboardKey.keyJ);
    expect(_showing(tester, 'second problem'), isTrue);
    await _key(tester, LogicalKeyboardKey.keyR);
    expect(_showing(tester, 'third problem'), isTrue);
  });

  testWidgets('g then s opens settings; s alone does nothing', (tester) async {
    var opened = 0;
    await _pump(tester, _repo(), onSettings: () => opened++);
    await _key(tester, LogicalKeyboardKey.keyS);
    expect(opened, 0);
    await _key(tester, LogicalKeyboardKey.keyG);
    await _key(tester, LogicalKeyboardKey.keyS);
    expect(opened, 1);
  });
}

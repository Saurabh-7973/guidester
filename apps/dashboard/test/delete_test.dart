import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// G4. A tester screenshots a screen carrying their own real data and asks for
/// it to be removed. Under the DPDP Act that request is not optional and the
/// project owner is the data fiduciary.
class _Repo implements CommentRepository {
  _Repo(this.rows);

  final List<Comment> rows;
  final List<String> calls = [];
  String? failWith;

  @override
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  }) async {
    calls.add('fetch');
    return rows.where((c) => c.status == status).toList(growable: false);
  }

  @override
  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  }) async => rows.firstWhere((c) => c.id == commentId);

  final List<Map<String, Object?>> verdicts = [];

  @override
  Future<Comment> setVerdict({
    required Comment comment,
    TesterVerdict? tester,
    DevVerdict? dev,
    String? blockedOn,
    bool clearBlockedOn = false,
    String? assignee,
    String? build,
    String? note,
    String? actor,
  }) async {
    verdicts.add({
      'id': comment.id,
      'tester': tester?.wire,
      'dev': dev?.wire,
      'blockedOn': clearBlockedOn ? null : blockedOn,
      'assignee': assignee,
      'build': build,
      'note': note,
    });
    return comment.copyWith(
      testerVerdict: tester,
      devVerdict: dev,
      blockedOn: blockedOn,
      clearBlockedOn: clearBlockedOn,
      assignee: assignee,
      fixedInBuild: dev == DevVerdict.fixed ? build : null,
      verifiedInBuild: tester == TesterVerdict.accepted ? build : null,
    );
  }

  List<CommentEvent> history = const [];

  @override
  Future<List<CommentEvent>> events(String commentId) async => history;

  @override
  Future<Board> board({required String projectId}) async => const Board(
    reportedToday: 0,
    reportedThisWeek: 0,
    fixedNotVerified: 0,
    blocked: 0,
    blockedBy: {},
    openByAssignee: {},
  );

  @override
  Future<String?> signedScreenshotUrl(String path) async => null;

  @override
  Future<void> deleteComment(Comment comment) async {
    calls.add('deleteComment:${comment.id}');
    if (failWith != null) throw RepositoryException(failWith!);
    rows.removeWhere((c) => c.id == comment.id);
  }

  @override
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  }) async {
    calls.add('deleteTester:$testerId');
    if (failWith != null) throw RepositoryException(failWith!);
    final n = rows.where((c) => c.testerId == testerId).length;
    rows.removeWhere((c) => c.testerId == testerId);
    return n;
  }
}

Comment _c(String id, String body, {String? testerId = 't1', String? tester}) =>
    Comment(
      id: id,
      body: body,
      screenName: 'HOME',
      status: CommentStatus.open,
      createdAt: DateTime.now(),
      testerName: tester ?? 'Priya',
      testerId: testerId,
      impact: Impact.annoying,
      screenshotPath: 'proj/$id.png',
    );

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: CommentsScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('delete asks before it does anything', (tester) async {
    final repo = _Repo([_c('1', 'alpha'), _c('2', 'beta')]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // It takes the screenshot with it, so it does not sit one stray click
    // from Resolve, and the confirmation says how long Undo lasts.
    expect(find.textContaining('undo for 5 seconds'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
  });

  testWidgets('cancel leaves the comment alone', (tester) async {
    final repo = _Repo([_c('1', 'alpha')]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
    expect(repo.rows, hasLength(1));
    expect(find.textContaining('undo for 5 seconds'), findsNothing);
  });

  testWidgets('confirming hides the comment, and deletes it after 5 s', (
    tester,
  ) async {
    final repo = _Repo([_c('1', 'alpha'), _c('2', 'beta')]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pump();

    // Gone from the board at once, with Undo on offer; not deleted yet.
    expect(find.text('alpha'), findsNothing);
    expect(find.text('Comment deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('deleteComment:1'));
    expect(repo.rows.map((c) => c.id), ['2']);
  });

  // Found in the 27 Sep audit: after deleting one comment the pane moved to
  // the next, and the confirmation stayed open with the next tester's name in
  // "Delete everything from <them>, no undo" — one click from erasing the
  // wrong person's comments.
  testWidgets('the confirmation closes once a comment is deleted', (
    tester,
  ) async {
    final repo = _Repo([_c('1', 'alpha'), _c('2', 'beta')]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pump();

    expect(find.text('Delete comment'), findsNothing);
    expect(find.textContaining('no undo'), findsNothing);
    expect(
      find.text('Delete'),
      findsOneWidget,
      reason: 'back to the plain button',
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('Undo within 5 s brings it back and deletes nothing', (
    tester,
  ) async {
    final repo = _Repo([_c('1', 'alpha'), _c('2', 'beta')]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    // Let the toast finish arriving before reaching for its button.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
    expect(find.text('alpha'), findsWidgets);
  });

  testWidgets('leaving the board inside the 5 s still deletes', (tester) async {
    final repo = _Repo([_c('1', 'alpha')]);
    await _pump(tester, repo);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repo.calls, contains('deleteComment:1'));
  });

  testWidgets('the whole-tester delete says how many went', (tester) async {
    final repo = _Repo([
      _c('1', 'alpha'),
      _c('2', 'beta'),
      _c('3', 'someone else', testerId: 't2', tester: 'Ravi'),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // "Remove everything of mine" is what a request under the Act looks like.
    await tester.tap(find.textContaining('Delete everything from Priya'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('deleteTester:t1'));
    expect(repo.rows.map((c) => c.id), ['3']);
    expect(find.text('2 comments deleted'), findsOneWidget);
  });

  testWidgets('a comment with no tester id offers no tester delete', (
    tester,
  ) async {
    final repo = _Repo([_c('1', 'alpha', testerId: null)]);
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete comment'), findsOneWidget);
    expect(find.textContaining('Delete everything'), findsNothing);
  });

  testWidgets('a failed delete says so and keeps the comment', (tester) async {
    final repo = _Repo([_c('1', 'alpha')])
      ..failWith = 'That comment belongs to another project.';
    await _pump(tester, repo);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pump();
    // The delete runs when the Undo window closes; the failure shows then,
    // and the comment comes back to the board.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('That comment belongs to another project.'),
      findsOneWidget,
    );
    expect(repo.rows, hasLength(1));
    expect(find.text('alpha'), findsWidgets);
  });
}

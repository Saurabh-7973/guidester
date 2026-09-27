import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:dashboard/src/routing/router.dart';
import 'package:dashboard/src/screens/home_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/comment_detail.dart';
import 'package:dashboard/src/widgets/comment_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The dashboard behind real URLs. Found 25 Sep in Chrome: back left the app,
/// reload dropped to the project list, and a comment could not be linked,
/// because every screen lived at `/`.
class _Comments implements CommentRepository, ReportSource {
  final rows = <CommentStatus, List<Comment>>{
    CommentStatus.open: [
      _c('c1', 'first open', Impact.blocked),
      _c('c2', 'second open', Impact.annoying),
      _c('c3', 'third open', Impact.cosmetic),
    ],
    CommentStatus.resolved: [_c('r1', 'long done', Impact.annoying)],
  };

  @override
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  }) async => [
    for (final c in rows[status] ?? const <Comment>[])
      if (impact == null || c.impact == impact) c,
  ];

  /// Moves the row between tabs, as the database does, so a reload after a
  /// status change sees it.
  @override
  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  }) async {
    final moved = rows.values
        .expand((l) => l)
        .firstWhere((c) => c.id == commentId)
        .copyWith(status: status);
    for (final l in rows.values) {
      l.removeWhere((c) => c.id == commentId);
    }
    (rows[status] ??= []).insert(0, moved);
    return moved;
  }

  @override
  Future<Map<String, List<Comment>>> reportComments({
    String? projectId,
  }) async => {'p1': rows.values.expand((l) => l).toList()};

  @override
  Future<String?> signedScreenshotUrl(String path) async => null;

  @override
  Future<void> deleteComment(Comment comment) async {}

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
  }) async => comment;

  @override
  Future<List<CommentEvent>> events(String commentId) async => const [];

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
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  }) async => 0;
}

Comment _c(String id, String body, Impact impact) => Comment(
  id: id,
  body: body,
  screenName: 'S_$id',
  status: id.startsWith('r') ? CommentStatus.resolved : CommentStatus.open,
  createdAt: DateTime(2026, 9, 25),
  testerName: 'Ana',
  impact: impact,
);

class _Projects implements ProjectRepository {
  @override
  Future<List<Project>> list() async => [
    Project(
      id: 'p1',
      name: 'Snapdrop',
      createdAt: DateTime(2026, 9, 1),
      total: 28,
    ),
    // Two, so arriving at the list stays on the list (with one, §5.6 row 5
    // opens that project's board).
    Project(id: 'p2', name: 'Sahaj', createdAt: DateTime(2026, 9, 2)),
  ];

  @override
  Future<(Project, ProjectKey)> create(String name) =>
      throw UnimplementedError();

  @override
  Future<List<ProjectKey>> keys(String projectId) async => const [];

  @override
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<void> revoke(String keyId) async {}
}

Future<GoRouter> _pumpAt(WidgetTester tester, String at) async {
  tester.view.physicalSize = const Size(1493, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final comments = _Comments();
  final projects = _Projects();
  final router = buildRouter(
    resetPassword: (_) => const SizedBox(),
    initialLocation: at,
    signedIn: () => true,
    refresh: ChangeNotifier(),
    login: (_) => const Text('login'),
    home: (context, location, navigate) => HomeScreen(
      repository: comments,
      projects: projects,
      email: 'dev@example.com',
      location: location,
      onNavigate: navigate,
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

String _where(GoRouter r) =>
    r.routerDelegate.currentConfiguration.uri.toString();

/// The detail pane shows the selected body at 20px.
bool _paneShows(WidgetTester tester, String body) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(CommentDetail),
        matching: find.text(body),
      ),
    )
    .isNotEmpty;

void main() {
  testWidgets('opening a project puts it in the URL', (tester) async {
    final r = await _pumpAt(tester, '/projects');
    await tester.tap(find.text('Snapdrop'));
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1');
    expect(find.byType(CommentRow), findsWidgets);
  });

  testWidgets('a link to a project opens its board with its name', (
    tester,
  ) async {
    await _pumpAt(tester, '/p/p1');
    expect(find.text('Snapdrop'), findsWidgets);
    expect(_paneShows(tester, 'first open'), isTrue);
  });

  testWidgets('a link to a comment opens that comment', (tester) async {
    await _pumpAt(tester, '/p/p1/c/c2');
    expect(_paneShows(tester, 'second open'), isTrue);
    expect(_paneShows(tester, 'first open'), isFalse);
  });

  testWidgets('choosing a comment puts it in the URL', (tester) async {
    final r = await _pumpAt(tester, '/p/p1');
    await tester.tap(find.text('third open').first);
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1/c/c3');
    expect(_paneShows(tester, 'third open'), isTrue);
  });

  testWidgets(
    'the tab and the filter are in the URL, and a link restores them',
    (tester) async {
      final r = await _pumpAt(tester, '/p/p1');
      await tester.tap(find.byKey(const ValueKey('impact-filter-blocked')));
      await tester.pumpAndSettle();
      expect(_where(r), '/p/p1?impact=blocked');
      expect(find.text('second open'), findsNothing);

      final again = await _pumpAt(tester, '/p/p1/c/r1?status=resolved');
      expect(_where(again), '/p/p1/c/r1?status=resolved');
      expect(_paneShows(tester, 'long done'), isTrue);
    },
  );

  testWidgets(
    'a comment link that matches nothing says so and keeps the board',
    (tester) async {
      await _pumpAt(tester, '/p/p1/c/gone');
      expect(
        find.text("This comment doesn't exist or you don't have access."),
        findsOneWidget,
      );
      expect(find.byType(CommentRow), findsWidgets);
    },
  );

  testWidgets('a project link that matches nothing says so', (tester) async {
    await _pumpAt(tester, '/p/nope');
    expect(
      find.text("This project doesn't exist or you don't have access."),
      findsOneWidget,
    );
  });

  testWidgets('back to projects, settings and new project are URLs too', (
    tester,
  ) async {
    final r = await _pumpAt(tester, '/p/p1');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1/settings');

    await tester.tap(find.text('Projects').first);
    await tester.pumpAndSettle();
    expect(_where(r), '/projects');

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    expect(_where(r), '/projects/new');
  });

  testWidgets('resolving the linked comment moves the URL off it', (
    tester,
  ) async {
    final r = await _pumpAt(tester, '/p/p1/c/c1');
    expect(_paneShows(tester, 'first open'), isTrue);

    await tester.tap(find.text('Resolve').first);
    await tester.pumpAndSettle();
    // Rebuild the way any URL change does, to catch a stale comment id.
    await tester.tap(find.byKey(const ValueKey('impact-filter-all')));
    await tester.pumpAndSettle();

    expect(_where(r), '/p/p1', reason: 'url');
    expect(
      find.text("This comment doesn't exist or you don't have access."),
      findsNothing,
      reason: 'missing',
    );
    expect(_paneShows(tester, 'second open'), isTrue, reason: 'pane');
  });

  // Found in Chrome, 26 Sep: opening the project from the list and then
  // choosing a comment changed the pane but left the URL at /p/<id>. The
  // test above starts at /p/p1 directly and never saw it.
  testWidgets(
    'from the project list, choosing a comment still reaches the URL',
    (tester) async {
      final r = await _pumpAt(tester, '/projects');
      await tester.tap(find.text('Snapdrop'));
      await tester.pumpAndSettle();
      expect(_where(r), '/p/p1');

      await tester.tap(find.text('third open').first);
      await tester.pumpAndSettle();
      expect(_where(r), '/p/p1/c/c3');
    },
  );

  // Found in Chrome, 26 Sep: with a comment open, switching the filter showed
  // "This comment doesn't exist". The reload still looked for the comment the
  // old URL named, in a list the new filter had just excluded it from.
  testWidgets(
    'changing the filter with a comment open is not a missing comment',
    (tester) async {
      final r = await _pumpAt(tester, '/p/p1/c/c2');
      await tester.tap(find.byKey(const ValueKey('impact-filter-blocked')));
      await tester.pumpAndSettle();

      expect(_where(r), '/p/p1?impact=blocked');
      expect(
        find.text("This comment doesn't exist or you don't have access."),
        findsNothing,
      );
      expect(_paneShows(tester, 'first open'), isTrue);
    },
  );

  testWidgets('changing the tab with a comment open is not a missing comment', (
    tester,
  ) async {
    final r = await _pumpAt(tester, '/p/p1/c/c2');
    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();

    expect(_where(r), '/p/p1?status=resolved');
    expect(
      find.text("This comment doesn't exist or you don't have access."),
      findsNothing,
    );
    expect(_paneShows(tester, 'long done'), isTrue);
  });

  testWidgets('the Status tab shows every project, then one report', (
    tester,
  ) async {
    final r = await _pumpAt(tester, '/projects');
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(_where(r), '/status');
    expect(find.text('Snapdrop'), findsOneWidget);
    expect(find.text('Sahaj'), findsOneWidget);
    // c1 is open and blocking.
    expect(find.text('Not ready to release'), findsOneWidget);

    await tester.tap(find.text('Snapdrop'));
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1/status');

    await tester.tap(find.text('first open').first);
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1/c/c1');
    expect(_paneShows(tester, 'first open'), isTrue);
  });

  testWidgets('a board links to its own report', (tester) async {
    final r = await _pumpAt(tester, '/p/p1');
    await tester.tap(find.byKey(const ValueKey('open-status-report')));
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1/status');
  });

  testWidgets('Status from inside a project opens that project', (
    tester,
  ) async {
    final r = await _pumpAt(tester, '/p/p1');
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(_where(r), '/p/p1/status');
  });
}

import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/issue_type.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

Widget _wrap(FakeRepository repo, {int? projectTotal}) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: CommentsScreen(repository: repo, projectTotal: projectTotal),
  ),
);

void main() {
  // §6's geometry — a 516 rail, a 24 gap and the pane beside it — is drawn at
  // 1440. The default 800x600 test surface is narrower than the design, and
  // responsive behaviour below 1440 is not specified, so these run at the
  // width the frames were measured at.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  testWidgets('loads the Open tab on first paint', (tester) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'first problem')],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(repo.calls.first, 'fetch:open:all');
    expect(find.text('first problem'), findsWidgets);
    expect(find.text('HOME'), findsWidgets);
  });

  testWidgets('shows an empty state when a tab has nothing', (tester) async {
    await tester.pumpWidget(_wrap(FakeRepository(const {})));
    await tester.pumpAndSettle();
    // §4's empty state replaces the old "Nothing open." copy, and says
    // "tap", not "click" — the tester is on a phone.
    expect(find.text('No comments left yet'), findsOneWidget);
    expect(find.textContaining('Open the app and tap'), findsOneWidget);
  });

  testWidgets('surfaces a load failure with a retry that refetches', (
    tester,
  ) async {
    final repo = FakeRepository(const {})..failFetchWith = 'Database offline.';
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Database offline.'), findsOneWidget);
    repo.failFetchWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Database offline.'), findsNothing);
  });

  testWidgets('switching tabs refetches with the new status', (tester) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'open one')],
      CommentStatus.resolved: [
        testComment(id: '2', body: 'done one', status: CommentStatus.resolved),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Resolved'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('fetch:resolved:all'));
    expect(find.text('done one'), findsWidgets);
  });

  testWidgets('selecting a comment requests a signed URL for its screenshot', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(id: '1', body: 'with shot', shot: 'proj/a.png'),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('sign:proj/a.png'));
  });

  testWidgets('a comment with no screenshot says so instead of failing', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'no shot')],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('No screenshot with this comment'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('sign:')), isEmpty);
  });

  testWidgets('resolving a comment removes it from the Open list', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(id: '1', body: 'alpha'),
        testComment(id: '2', body: 'beta'),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('alpha'), findsWidgets);
    // The actions live on the raised row, and the first comment is selected
    // on load, so its row is already raised.
    await tester.tap(find.text('Resolve').first);
    await tester.pumpAndSettle();

    expect(repo.calls, contains('update:1:resolved'));
    expect(find.text('alpha'), findsNothing);
    expect(find.text('beta'), findsWidgets);
  });

  testWidgets('a failed status change tells the user and keeps the row', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'alpha')],
    })..failUpdateWith = 'That comment belongs to another project.';
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resolve').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('That comment belongs to another project.'),
      findsOneWidget,
    );
    expect(find.text('alpha'), findsWidgets);
  });

  testWidgets('the context panel renders the jsonb long tail', (tester) async {
    // A desktop-sized surface: the dashboard is a web app, and this keeps the
    // whole detail pane on screen so the test does not depend on scrolling.
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(
          id: '1',
          body: 'ctx',
          context: {
            'text_scale_factor': 1.35,
            'platform_brightness': 'dark',
            'is_physical_device': false,
            'route_stack': ['/home', '/cart'],
            'some_future_key': 'still shown',
          },
        ),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // §6: collapsed by default. It is the answer to "which device were you
    // on?", but it is not what you read first.
    expect(find.text('Text size'), findsNothing);
    await tester.tap(find.text('Show device context'));
    await tester.pumpAndSettle();

    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('1.35×'), findsOneWidget);
    expect(find.text('dark'), findsOneWidget);
    expect(find.text('/home → /cart'), findsOneWidget);
    // A key added by a newer SDK must still appear, with no dashboard change.
    expect(find.text('Some future key'), findsOneWidget);
  });

  testWidgets('Next moves the detail selection to the following comment', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(id: '1', body: 'alpha', screen: 'HOME'),
        testComment(id: '2', body: 'beta', screen: 'CHECKOUT'),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // Both bodies appear in the rail, so identify the detail pane's copy by
    // its type size: §6 sets it at 20/600, the rail at 15 or 17.
    bool inDetail(WidgetTester t, String text) =>
        t.widgetList<Text>(find.text(text)).any((w) => w.style?.fontSize == 20);

    expect(inDetail(tester, 'alpha'), isTrue);
    expect(inDetail(tester, 'beta'), isFalse);

    await tester.tap(find.text('Next comment »'));
    await tester.pumpAndSettle();

    expect(inDetail(tester, 'beta'), isTrue);
    expect(inDetail(tester, 'alpha'), isFalse);
  });

  testWidgets('the row shows impact, not issue type', (tester) async {
    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(id: '1', body: 'it froze', issueType: IssueType.crash),
        testComment(id: '2', body: 'minor thing'),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // D51: the SDK stopped asking for a type, so a row never renders one —
    // the developer sets it at triage and it stays a dashboard filter.
    expect(find.byType(IssueTypeChip), findsNothing);
    // Every row carries an impact instead; the column defaults to 'annoying',
    // so a row is never without one.
    expect(find.text('ANNOYING'), findsWidgets);
  });

  // Found 25 Sep: issue_type was null on all 28 live comments, because the
  // SDK asks for impact and never for a type (D51). Every type filter was
  // empty. Impact is what testers actually set, so that is the filter.
  testWidgets('there are no type filters', (tester) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'x')],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    for (final type in IssueType.values) {
      expect(find.byKey(ValueKey('issue-filter-${type.wire}')), findsNothing);
    }
    expect(find.text('All types'), findsNothing);
  });

  testWidgets('filtering by impact refetches with that impact', (tester) async {
    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(id: '1', body: 'cannot log in', impact: Impact.blocked),
        testComment(id: '2', body: 'slightly off', impact: Impact.cosmetic),
        testComment(id: '3', body: 'bit slow'),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('bit slow'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('impact-filter-blocked')));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('fetch:open:blocked'));
    expect(find.text('cannot log in'), findsWidgets);
    expect(find.text('slightly off'), findsNothing);
    expect(find.text('bit slow'), findsNothing);
  });

  testWidgets('the active impact filter clears on a second tap', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [
        testComment(id: '1', body: 'cannot log in', impact: Impact.blocked),
        testComment(id: '2', body: 'bit slow'),
      ],
    });
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    final blocked = find.byKey(const ValueKey('impact-filter-blocked'));
    await tester.tap(blocked);
    await tester.pumpAndSettle();
    expect(find.text('bit slow'), findsNothing);

    await tester.tap(blocked);
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'fetch:open:all');
    expect(find.text('bit slow'), findsWidgets);
  });

  testWidgets(
    'an empty filter says so, offers to clear, and is not onboarding',
    (tester) async {
      final repo = FakeRepository({
        CommentStatus.open: [testComment(id: '1', body: 'bit slow')],
      });
      await tester.pumpWidget(_wrap(repo, projectTotal: 28));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('impact-filter-blocked')));
      await tester.pumpAndSettle();

      expect(find.text('No comments match these filters.'), findsOneWidget);
      // Found 25 Sep: an empty filter on a 28-comment project brought back the
      // new-project help card, which reads as "you have no comments".
      expect(find.text('LEARN HOW TO USE GUIDESTER'), findsNothing);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'fetch:open:all');
      expect(find.text('bit slow'), findsWidgets);
    },
  );

  testWidgets('the help card is for a project with under 3 comments in all', (
    tester,
  ) async {
    final repo = FakeRepository({
      CommentStatus.open: [testComment(id: '1', body: 'first one')],
    });
    await tester.pumpWidget(_wrap(repo, projectTotal: 1));
    await tester.pumpAndSettle();
    expect(find.text('LEARN HOW TO USE GUIDESTER'), findsOneWidget);
  });
}

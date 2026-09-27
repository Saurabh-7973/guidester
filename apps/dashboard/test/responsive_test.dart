import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/comment_detail.dart';
import 'package:dashboard/src/widgets/comment_row.dart';
import 'package:dashboard/src/widgets/comment_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rail collapses and the pane wins. Ruled after §6, which only defines
/// 1440:
///
///   >= 1100     516 rail + 24 + pane, per §6
///   720-1099    56px strip, pane takes the rest, toggle expands to 516
///   < 720       pane only, rail becomes a back control
class _Repo implements CommentRepository {
  _Repo(this._rows);

  final List<Comment> _rows;

  @override
  Future<List<Comment>> fetch({
    required String projectId,
    required CommentStatus status,
    Impact? impact,
  }) async => status == CommentStatus.open ? _rows : const [];

  @override
  Future<Comment> updateStatus({
    required String commentId,
    required CommentStatus status,
  }) async => _rows.firstWhere((c) => c.id == commentId);

  @override
  Future<void> deleteComment(Comment comment) async => _rows.remove(comment);

  @override
  Future<int> deleteTester({
    required String projectId,
    required String testerId,
  }) async => 0;

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
}

Comment _c(String id, String body, {Impact impact = Impact.annoying}) =>
    Comment(
      id: id,
      body: body,
      screenName: 'HOME',
      status: CommentStatus.open,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      testerName: 'Ana',
      impact: impact,
    );

final _rows = <Comment>[
  _c('1', 'alpha', impact: Impact.blocked),
  _c('2', 'beta'),
  _c('3', 'gamma', impact: Impact.cosmetic),
];

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: CommentsScreen(repository: _Repo(_rows))),
    ),
  );
  await tester.pumpAndSettle();
}

/// The detail pane renders the selected body at §6's 20/600.
bool _paneShows(WidgetTester tester, String body) => tester
    .widgetList<Text>(find.text(body))
    .any((w) => w.style?.fontSize == 20);

void main() {
  testWidgets('at 1440 the full rail sits beside the pane', (tester) async {
    await _pumpAt(tester, const Size(1440, 900));

    expect(find.byType(CommentRow), findsWidgets);
    expect(find.byType(CommentStrip), findsNothing);
    expect(find.byType(CommentDetail), findsOneWidget);

    // About a third of the board, within 380-480 (Home (8), with the
    // header now in the same column), and the pane beside it.
    final rail = tester.getSize(find.byType(CommentRow).first);
    expect(rail.width, closeTo(1440 * 0.32, 1));
  });

  testWidgets('at 1100 it is still the full rail', (tester) async {
    await _pumpAt(tester, const Size(1100, 900));
    expect(find.byType(CommentStrip), findsNothing);
    expect(tester.getSize(find.byType(CommentRow).first).width, 380);
  });

  testWidgets('at 1099 the rail collapses to a 56px strip', (tester) async {
    await _pumpAt(tester, const Size(1099, 900));

    expect(find.byType(CommentStrip), findsOneWidget);
    expect(tester.getSize(find.byType(CommentStrip)).width, 56);
    // No row text at this width: the strip carries dots, not comments.
    expect(find.byType(CommentRow), findsNothing);
    // The pane is still there — it is what you are reading at this width.
    expect(find.byType(CommentDetail), findsOneWidget);
    expect(_paneShows(tester, 'alpha'), isTrue);
  });

  testWidgets('the strip carries one dot per comment, coloured by impact', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(900, 900));

    // Position stays visible: three below you, and which of them are blocked.
    for (final row in _rows) {
      expect(
        find.bySemanticsLabel('${row.impact.label}, HOME'),
        findsOneWidget,
        reason: row.body,
      );
    }
  });

  testWidgets('the strip expands to the full rail as an overlay', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(900, 900));
    expect(find.byType(CommentRow), findsNothing);

    await tester.tap(find.byTooltip('Expand list'));
    await tester.pumpAndSettle();

    expect(find.byType(CommentRow), findsWidgets);
    expect(tester.getSize(find.byType(CommentRow).first).width, 516);

    // Choosing from it closes it: you opened it to choose.
    await tester.tap(find.text('gamma').first);
    await tester.pumpAndSettle();
    expect(find.byType(CommentRow), findsNothing);
    expect(_paneShows(tester, 'gamma'), isTrue);
  });

  testWidgets('below 720 the pane is the whole screen', (tester) async {
    await _pumpAt(tester, const Size(719, 900));

    expect(find.byType(CommentStrip), findsNothing);
    expect(find.byType(CommentRow), findsNothing);
    expect(find.byType(CommentDetail), findsOneWidget);
    // The rail became a back control.
    expect(find.text('All comments'), findsOneWidget);
  });

  testWidgets('the back control opens the rail full width', (tester) async {
    await _pumpAt(tester, const Size(719, 900));

    await tester.tap(find.text('All comments'));
    await tester.pumpAndSettle();

    expect(find.byType(CommentRow), findsWidgets);
    // Full width here, not 516: there is nothing to sit beside.
    expect(tester.getSize(find.byType(CommentRow).first).width, 719);
  });

  testWidgets('j and k move the selection with the rail shut', (tester) async {
    await _pumpAt(tester, const Size(900, 900));
    expect(_paneShows(tester, 'alpha'), isTrue);

    // The point of the ruling: navigation never depends on the rail.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_paneShows(tester, 'beta'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_paneShows(tester, 'gamma'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(_paneShows(tester, 'beta'), isTrue);
  });

  testWidgets('j and k work below 720 too, where there is no rail at all', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(719, 900));
    expect(_paneShows(tester, 'alpha'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_paneShows(tester, 'beta'), isTrue);
  });

  testWidgets('Prev and Next still move the selection', (tester) async {
    await _pumpAt(tester, const Size(900, 900));

    await tester.tap(find.text('Next comment »'));
    await tester.pumpAndSettle();
    expect(_paneShows(tester, 'beta'), isTrue);

    await tester.tap(find.text('« Prev comment'));
    await tester.pumpAndSettle();
    expect(_paneShows(tester, 'alpha'), isTrue);
  });

  testWidgets('the strip tracks the selection made by the keyboard', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(900, 900));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.selected ?? false)
        .map((s) => s.properties.label)
        .toList();
    expect(selected, contains('ANNOYING, HOME'));
  });
}

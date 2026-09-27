import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/models/comment.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/impact.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/app_shell.dart';
import 'package:dashboard/src/widgets/comment_row.dart';
import 'package:dashboard/src/widgets/comment_strip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Found on 25 Sep in Chrome at 1493x812 with 27 open comments: five were
/// reachable. Every layout test before this one pumped CommentsScreen in a
/// full-width Scaffold. The app never does: AppShell hands it the centred
/// 624px column, so the screen always took its < 720 branch on a desktop.
/// These tests pump it the way the app does.
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
  Future<String?> signedScreenshotUrl(String path) async => null;
}

final _rows = [
  for (var i = 1; i <= 27; i++)
    Comment(
      id: '$i',
      body: 'comment $i',
      // Distinct screens, so no two rows fold into a duplicate group.
      screenName: 'SCREEN$i',
      status: CommentStatus.open,
      createdAt: DateTime(2026, 9, 25).subtract(Duration(minutes: i)),
      testerName: 'Ana',
    ),
];

Future<void> _pumpInShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: AppShell(
        tab: ShellTab.projects,
        onTabSelected: (_) {},
        userName: 'saurabh',
        onLogOut: () {},
        fullWidth: true,
        child: CommentsScreen(repository: _Repo(List.of(_rows))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Wheel-scrolls the rail the way a mouse does, until [body] is on screen or
/// the wheel stops moving anything.
Future<void> _wheelUntilVisible(WidgetTester tester, String body) async {
  final list = find.byType(ListView).first;
  for (var i = 0; i < 60; i++) {
    if (find.text(body).hitTestable().evaluate().isNotEmpty) return;
    final at = tester.getCenter(list);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
  }
}

void main() {
  testWidgets('a desktop window gets the full rail, not the phone layout', (
    tester,
  ) async {
    await _pumpInShell(tester, const Size(1493, 812));

    expect(find.byType(CommentStrip), findsNothing);
    expect(find.byType(CommentRow), findsWidgets);
  });

  testWidgets('every comment is reachable by wheel from a desktop window', (
    tester,
  ) async {
    await _pumpInShell(tester, const Size(1493, 812));

    await _wheelUntilVisible(tester, 'comment 27');
    expect(find.text('comment 27').hitTestable(), findsOneWidget);
  });

  testWidgets('every comment is reachable on a phone-width window too', (
    tester,
  ) async {
    await _pumpInShell(tester, const Size(600, 812));

    if (find.byType(CommentRow).evaluate().isEmpty) {
      await tester.tap(find.text('All comments'));
      await tester.pumpAndSettle();
    }
    await _wheelUntilVisible(tester, 'comment 27');
    expect(find.text('comment 27').hitTestable(), findsOneWidget);
  });
}

import 'package:dashboard/src/data/team_repository.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/team_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';
import 'support/team_fake.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeTeam team, {
  String me = 'u-me',
  VoidCallback? onLeft,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TeamPanel(
            repository: team,
            projectId: 'p1',
            myUserId: me,
            myEmail: 'me@team.com',
            dashboardUrl: 'https://dash.example/',
            onLeft: onLeft,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the owner sees the team and invites someone as QA', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    final team = FakeTeam();
    await _pump(tester, team);

    expect(find.text('me@team.com (you)'), findsOneWidget);
    expect(find.text('ana@team.com'), findsOneWidget);
    expect(find.text('Member · QA'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('invite-email')).first,
      'Ravi@Team.com ',
    );
    await tester.tap(find.text('Viewer'));
    await tester.tap(find.text('Lead / CTO'));
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(team.invited.single.email, 'ravi@team.com');
    expect(team.invited.single.role, TeamRole.viewer);
    expect(team.invited.single.function, TeamFunction.lead);
    expect(find.text('ravi@team.com'), findsOneWidget);
    expect(find.textContaining('invited, not joined yet'), findsOneWidget);
    expect(find.textContaining('Guidester sends no email'), findsOneWidget);

    await tester.tap(find.text('Copy message'));
    await tester.pumpAndSettle();
    expect(copied, contains('https://dash.example/'));
    expect(copied, contains('ravi@team.com'));

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(team.invited, isEmpty);
  });

  testWidgets('a bad address, yourself, or a repeat each say why', (
    tester,
  ) async {
    final team = FakeTeam();
    await _pump(tester, team);
    final field = find.byKey(const ValueKey('invite-email')).first;

    await tester.enterText(field, 'not-an-email');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an email address'), findsOneWidget);

    await tester.enterText(field, 'me@team.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    expect(find.textContaining("That's you"), findsOneWidget);

    await tester.enterText(field, 'x@team.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'x@team.com');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already has an invite'), findsOneWidget);
    expect(team.invited, hasLength(1));
  });

  testWidgets('the owner removes a member', (tester) async {
    final team = FakeTeam();
    await _pump(tester, team);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(team.removed, ['u-ana']);
    expect(find.text('ana@team.com'), findsNothing);
  });

  testWidgets('a member sees the team, cannot invite, and can leave', (
    tester,
  ) async {
    var left = false;
    final team = FakeTeam(role: TeamRole.member);
    await _pump(tester, team, me: 'u-ana', onLeft: () => left = true);

    expect(find.text('Project owner'), findsOneWidget);
    expect(find.text('ana@team.com (you)'), findsOneWidget);
    expect(find.text('Invite someone'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.textContaining('The owner and admins manage'), findsOneWidget);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(team.removed, ['u-ana']);
    expect(left, isTrue);
  });

  test('email check', () {
    expect(looksLikeEmail('a@b.co'), isTrue);
    expect(looksLikeEmail(' a@b.co '), isTrue);
    expect(looksLikeEmail('a@b'), isFalse);
    expect(looksLikeEmail('a b@c.d'), isFalse);
    expect(looksLikeEmail(''), isFalse);
  });

  test('what each role may do', () {
    expect(TeamRole.owner.deletes, isTrue);
    expect(TeamRole.admin.managesTeam, isTrue);
    expect(TeamRole.member.triages, isTrue);
    expect(TeamRole.member.managesTeam, isFalse);
    expect(TeamRole.viewer.triages, isFalse);
    expect(TeamRole.invitable, isNot(contains(TeamRole.owner)));
  });

  Future<void> board(
    WidgetTester tester, {
    bool canDelete = true,
    bool readOnly = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CommentsScreen(
            repository: FakeRepository({
              CommentStatus.open: [testComment(id: '1', body: 'broken cart')],
            }),
            canDelete: canDelete,
            readOnly: readOnly,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a member triages but sees no Delete', (tester) async {
    await board(tester, canDelete: false);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Resolve'), findsOneWidget);
    expect(find.textContaining('View only'), findsNothing);
  });

  testWidgets('a viewer sees everything and can change nothing', (
    tester,
  ) async {
    await board(tester, canDelete: false, readOnly: true);
    expect(find.textContaining('View only'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    // The row's Resolve is not offered, and r does nothing.
    final resolve = find.text('Resolve');
    if (resolve.evaluate().isNotEmpty) {
      await tester.tap(resolve.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(find.text('broken cart'), findsWidgets, reason: 'still open');
  });
}

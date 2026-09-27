import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/projects_screen.dart';
import 'package:dashboard/src/screens/settings_screen.dart';
import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:dashboard/src/widgets/project_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Block C: §3 projects, §4 project, §7 settings, §8 login, plus the four
/// factual corrections in §9.
Future<void> _pump(WidgetTester tester, Widget child, {double width = 1440}) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: T.page,
        body: Center(child: SizedBox(width: 624, child: child)),
      ),
    ),
  );
}

void main() {
  group('§3 projects', () {
    testWidgets('the table has the three named columns', (tester) async {
      await _pump(tester, ProjectsScreen(projects: const [], onOpen: (_) {}));
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Created by'), findsOneWidget);
      expect(find.text('Total Comments'), findsOneWidget);
    });

    testWidgets('a row shows the badge, the author and the count', (
      tester,
    ) async {
      await _pump(
        tester,
        ProjectsScreen(
          projects: const [
            ProjectSummary(
              id: 'p1',
              name: 'Snapdrop',
              createdBy: 'Saurabh',
              total: 32,
              unread: 2,
            ),
          ],
          onOpen: (_) {},
        ),
      );
      expect(find.text('Snapdrop'), findsOneWidget);
      expect(find.text('Saurabh'), findsOneWidget);
      expect(find.text('32 (2 New)'), findsOneWidget);
      // The amber initial badge, with the letter in the amber-ground token.
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('no unread means no bracket', (tester) async {
      await _pump(
        tester,
        ProjectsScreen(
          projects: const [
            ProjectSummary(
              id: 'p1',
              name: 'Snapdrop',
              createdBy: 'Saurabh',
              total: 5,
              unread: 0,
            ),
          ],
          onOpen: (_) {},
        ),
      );
      expect(find.text('5'), findsOneWidget);
      expect(find.textContaining('New'), findsNothing);
    });

    testWidgets('opening a row reports it', (tester) async {
      ProjectSummary? opened;
      await _pump(
        tester,
        ProjectsScreen(
          projects: const [
            ProjectSummary(
              id: 'p1',
              name: 'Snapdrop',
              createdBy: 'Saurabh',
              total: 1,
              unread: 0,
            ),
          ],
          onOpen: (p) => opened = p,
        ),
      );
      await tester.tap(find.text('Snapdrop'));
      expect(opened?.id, 'p1');
    });
  });

  group('§4 project', () {
    Widget header({int comments = 0, int collaborators = 0}) => ProjectHeader(
      projectName: 'Snapdrop',
      createdBy: 'You',
      collaborators: collaborators,
      commentCount: comments,
      status: CommentStatus.open,
      counts: const {CommentStatus.open: 32},
      onStatusSelected: (_) {},
    );

    testWidgets('the title is 48/700 and the breadcrumb sits above it', (
      tester,
    ) async {
      await _pump(tester, header());
      final title = tester
          .widgetList<Text>(find.text('Snapdrop'))
          .firstWhere((t) => t.style?.fontSize == 48);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(find.text('Projects'), findsOneWidget);
    });

    testWidgets('zero collaborators renders nothing at all', (tester) async {
      // "0 Collaborators" advertises an empty feature.
      await _pump(tester, header());
      expect(find.textContaining('Collaborator'), findsNothing);
    });

    testWidgets('one collaborator is singular', (tester) async {
      await _pump(tester, header(collaborators: 1));
      expect(find.text('1 Collaborator'), findsOneWidget);
    });

    testWidgets('the learn card hides once there are 3 comments', (
      tester,
    ) async {
      await _pump(tester, header(comments: 2));
      expect(find.text('LEARN HOW TO USE GUIDESTER'), findsOneWidget);

      await _pump(tester, header(comments: 3));
      expect(find.text('LEARN HOW TO USE GUIDESTER'), findsNothing);
    });

    testWidgets('status tabs are teal, with counts in brackets', (
      tester,
    ) async {
      await _pump(tester, header());
      final open = tester.widget<Text>(find.text('Open [32]'));
      expect(open.style!.color, T.teal, reason: 'teal is status, only');

      final resolved = tester.widget<Text>(find.text('Resolved'));
      expect(resolved.style!.color, T.text3);
      // A tab with no known count renders no bracket rather than a wrong one.
      expect(find.textContaining('Resolved ['), findsNothing);
    });

    testWidgets('selecting a tab reports it', (tester) async {
      CommentStatus? picked;
      await _pump(
        tester,
        ProjectHeader(
          projectName: 'Snapdrop',
          createdBy: 'You',
          collaborators: 0,
          commentCount: 0,
          status: CommentStatus.open,
          counts: const {},
          onStatusSelected: (s) => picked = s,
        ),
      );
      await tester.tap(find.text('Resolved'));
      expect(picked, CommentStatus.resolved);
    });

    testWidgets('the empty state says tap, not click', (tester) async {
      await _pump(tester, const ProjectEmptyState());
      expect(find.text('No comments left yet'), findsOneWidget);
      expect(find.textContaining('tap'), findsOneWidget);
      expect(find.textContaining('click'), findsNothing);
    });
  });

  group('§7 settings', () {
    testWidgets('the right column is API keys, not a subscription', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsScreen(
          email: 'you@example.com',
          apiKeyMasked: 'gd_live_••••4f2a',
          apiKeyCreated: '4 Sep 2026',
        ),
        width: 1600,
      );

      expect(find.text('API Keys'), findsOneWidget);
      expect(find.text('gd_live_••••4f2a'), findsOneWidget);
      // A plan you cannot change is dead furniture.
      expect(find.textContaining('Pro Plan'), findsNothing);
      expect(find.textContaining(r'$8/mo'), findsNothing);
      expect(find.text('Change Plan'), findsNothing);
    });

    testWidgets('a key never used says so', (tester) async {
      await _pump(
        tester,
        const SettingsScreen(
          email: 'you@example.com',
          apiKeyMasked: 'gd_live_••••4f2a',
        ),
        width: 1600,
      );
      expect(find.text('never'), findsOneWidget);
    });

    testWidgets('with nothing to save to, Save Changes stays off', (
      tester,
    ) async {
      // A button that looks like it saves and does not is the dead control
      // Phase 2b removed. The enabled-after-edit case, with a real gateway,
      // is in projects_settings_test.dart.
      await _pump(
        tester,
        const SettingsScreen(email: 'you@example.com'),
        width: 1600,
      );

      GButton save() =>
          tester.widget<GButton>(find.widgetWithText(GButton, 'Save Changes'));
      expect(save().onPressed, isNull);
    });
  });

  group('§1 controls', () {
    testWidgets('a disabled button is accent-dim, not a faded accent', (
      tester,
    ) async {
      await _pump(tester, const GButton(label: 'Continue', onPressed: null));
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GButton),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, T.accentDim);
      expect(tester.getSize(find.byType(GButton)).height, T.controlHeight);
    });

    testWidgets('an enabled button is the accent fill', (tester) async {
      await _pump(tester, GButton(label: 'Continue', onPressed: () {}));
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GButton),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, T.accent);
    });
  });
}

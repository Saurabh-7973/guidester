import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/screens/home_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/comment_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Stage D 22: triage from a phone. Every screen at 390 x 844 must lay out
/// without overflow, and a comment must be reachable and leavable.
class _Projects implements ProjectRepository {
  @override
  Future<List<Project>> list() async => [
    Project(
      id: 'p1',
      name: 'Snapdrop field test build for the closed test on Play',
      createdAt: DateTime(2026, 9, 1),
      total: 3,
    ),
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

Future<List<DashboardLocation>> _pump(
  WidgetTester tester,
  DashboardLocation at, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final went = <DashboardLocation>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: HomeScreen(
        repository: FakeRepository({
          CommentStatus.open: [
            testComment(
              id: 'c1',
              body: 'The pay button sits under the keyboard on small phones',
              screen: 'CHECKOUT_PAYMENT',
            ),
            testComment(id: 'c2', body: 'Tabs too small'),
          ],
        }),
        projects: _Projects(),
        email: 'someone.with.a.long.address@example.com',
        location: at,
        onNavigate: went.add,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return went;
}

void main() {
  for (final (name, at) in [
    ('projects', const DashboardLocation.projects()),
    ('settings', const DashboardLocation.settings()),
    ('board', const DashboardLocation.board('p1')),
    ('comment', const DashboardLocation.board('p1', commentId: 'c1')),
  ]) {
    // 610: wider than the compact breakpoint, still narrower than the 624px
    // column plus its gutters.
    for (final width in const [390.0, 360.0, 610.0]) {
      testWidgets('$name fits a ${width.toInt()} px phone', (tester) async {
        await _pump(tester, at, width: width);
        expect(tester.takeException(), isNull);
      });

      // The nav row takes the content's 16 px gutter, so "Projects" does
      // not touch the screen edge (23 Oct).
      testWidgets('$name nav has a 16 px gutter at ${width.toInt()} px', (
        tester,
      ) async {
        await _pump(tester, at, width: width);
        expect(tester.getTopLeft(find.text('Projects').first).dx, 16);
        expect(
          tester.getTopRight(find.text('Settings').first).dx,
          lessThanOrEqualTo(width - 16),
        );
      });
    }
  }

  for (final width in const [390.0, 360.0, 610.0]) {
    testWidgets('the projects list sits inside the gutter at '
        '${width.toInt()} px', (tester) async {
      await _pump(tester, const DashboardLocation.projects(), width: width);
      expect(tester.getTopLeft(find.text('Name').first).dx, 16);
      expect(
        tester.getTopLeft(find.textContaining('Snapdrop field test')).dx,
        greaterThanOrEqualTo(16),
      );
    });
  }

  testWidgets('a phone board scrolls, and the card takes its own height', (
    tester,
  ) async {
    await _pump(tester, const DashboardLocation.board('p1', commentId: 'c1'));
    expect(find.byKey(const ValueKey('phone-board')), findsOneWidget);
    // Squeezed under the header it was about 100px tall (23 Oct).
    expect(tester.getSize(find.byType(CommentDetail)).height, greaterThan(300));
    // The list is on the page, above the card.
    expect(find.text('Tabs too small'), findsWidgets);
  });
}

import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/screens/home_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
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
  DashboardLocation at,
) async {
  tester.view.physicalSize = const Size(390, 844);
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
    testWidgets('$name fits a 390 px phone', (tester) async {
      await _pump(tester, at);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/screens/home_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Home (8): with a comment open, the project header, tabs and list are one
/// left panel, and the comment takes the rest at full height. Nothing on the
/// page scrolls but the list: the author's 26 Sep screenshot of a detail pane
/// that scrolled at 2556 x 1196 is what this prevents.
class _Projects implements ProjectRepository {
  @override
  Future<List<Project>> list() async => [
    Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026), total: 2),
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

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  DashboardLocation at = const DashboardLocation.board('p1', commentId: 'c1'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: HomeScreen(
        repository: FakeRepository({
          CommentStatus.open: [
            testComment(
              id: 'c1',
              body: 'The pay button hides',
              shot: 'p/a.png',
            ),
            testComment(id: 'c2', body: 'Tabs too small', shot: 'p/b.png'),
          ],
        }),
        projects: _Projects(),
        email: 'dev@example.com',
        location: at,
        onNavigate: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(1280, 800),
    Size(1440, 800),
    Size(1440, 900),
    Size(1440, 1196),
  ]) {
    testWidgets('at ${size.width.toInt()}x${size.height.toInt()} only the '
        'list scrolls', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      final scrolling = <String>[];
      for (final e in find.byType(Scrollable).evaluate()) {
        final state = (e as StatefulElement).state as ScrollableState;
        final pos = state.position;
        final inRail =
            e.findAncestorWidgetOfExactType<ListView>()?.key ==
            const ValueKey('rail');
        if (pos.axis == Axis.vertical && pos.maxScrollExtent > 0 && !inRail) {
          final keyed = e
              .findAncestorWidgetOfExactType<SingleChildScrollView>()
              ?.key;
          scrolling.add(
            '${keyed ?? e.widget.runtimeType} by ${pos.maxScrollExtent.round()}',
          );
        }
      }
      expect(scrolling, isEmpty);
    });
  }

  testWidgets('the project title lives in the left panel', (tester) async {
    await _pump(tester, const Size(1440, 900));
    final title = tester.getRect(find.text('Snapdrop').last);
    final comment = tester.getRect(find.text('The pay button hides').last);
    expect(title.right, lessThan(comment.left));
    // The comment starts near the top, not under a 330 px project header.
    expect(comment.top, lessThan(200));
  });

  testWidgets('off the board, the chip sits bottom-left at any height', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1440, 1196),
      at: const DashboardLocation.projects(),
    );
    final chip = tester.getRect(find.text('Log Out'));
    // "Log Out" sits after the avatar.
    expect(chip.left, lessThan(120));
    expect(1196 - chip.bottom, lessThan(48));
  });

  testWidgets('on the board, the chip is top-right, over nothing', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 900));
    final chip = tester.getRect(find.text('Log Out'));
    expect(chip.right, greaterThan(1300));
    expect(chip.top, lessThan(80));
  });

  testWidgets('golden: the board at 1440x900', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/board_1440x900.png'),
    );
  }, tags: ['golden']);
}

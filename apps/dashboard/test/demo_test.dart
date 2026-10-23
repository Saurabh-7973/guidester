import 'package:dashboard/demo_main.dart';
import 'package:dashboard/src/demo/demo_data.dart';
import 'package:dashboard/src/demo/demo_repositories.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/models/workflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The demo build: the real app on [DemoBackend], with no Supabase anywhere.
Future<DemoDashboard> _boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = DemoDashboard();
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('boots signed in, without Supabase, under the banner', (
    tester,
  ) async {
    // Supabase.instance throws when nothing initialised it; any code path
    // that reached for it would fail this test.
    await _boot(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(DemoBanner.text), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    // One project: the list opens its board.
    expect(find.text('Checkout app (demo)'), findsWidgets);
  });

  testWidgets('the board lists the seeded comments', (tester) async {
    await _boot(tester);
    expect(
      find.textContaining('Go to an unnamed route" and nothing happened'),
      findsWidgets,
    );
    expect(find.textContaining('Switch router style" is for'), findsWidgets);
  });

  testWidgets('a verdict change lands in memory', (tester) async {
    final app = await _boot(tester);
    final repo = app.backend.comments;
    await tester.tap(
      find.textContaining('Go to an unnamed route" and nothing happened').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();

    final moved = await repo.fetch(
      projectId: DemoData.projectId,
      status: CommentStatus.inProgress,
    );
    final c = moved.singleWhere((c) => c.id == 'demo-1');
    expect(c.devVerdict, DevVerdict.inProgress);
    final history = await repo.events('demo-1');
    expect(history.last.summary, 'Dev new → in progress');
  });

  test('status follows the dev verdict, as migration 0009 makes it', () {
    expect(statusForVerdict(DevVerdict.fixed), CommentStatus.resolved);
    expect(statusForVerdict(DevVerdict.wontFix), CommentStatus.resolved);
    expect(statusForVerdict(DevVerdict.deferred), CommentStatus.resolved);
    expect(statusForVerdict(DevVerdict.inProgress), CommentStatus.inProgress);
    expect(statusForVerdict(DevVerdict.blocked), CommentStatus.open);
    expect(statusForVerdict(DevVerdict.isNew), CommentStatus.open);
  });

  test('the seed covers every state the board shows', () {
    final seed = DemoData.seed(DateTime(2026, 10, 1)).comments;
    expect(seed.map((c) => c.status).toSet(), CommentStatus.values.toSet());
    expect(seed.map((c) => c.impact).toSet(), hasLength(3));
    expect(seed.where((c) => c.fixedNotVerified), isNotEmpty);
    expect(
      seed.where((c) => c.testerVerdict == TesterVerdict.accepted),
      isNotEmpty,
    );
    expect(
      seed.where((c) => c.testerVerdict == TesterVerdict.rejected),
      isNotEmpty,
    );
    expect(seed.where((c) => c.errors.isNotEmpty), hasLength(3));
  });

  testWidgets('a server-only action says so instead of pretending', (
    tester,
  ) async {
    final app = await _boot(tester);
    final key = (await app.backend.projects.keys(DemoData.projectId)).single;
    final same = await app.backend.projects.rotate(
      projectId: DemoData.projectId,
      replacing: key.id,
    );
    await tester.pump();
    expect(same.key, key.key);
    expect(find.text(notInDemo), findsOneWidget);
  });
}

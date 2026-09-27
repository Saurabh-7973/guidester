import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/screens/onboarding_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/onboarding_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repository whose key can be "used" from the test, which is the only way
/// to exercise a screen whose job is waiting for something to happen.
class _FakeProjects implements ProjectRepository {
  _FakeProjects();

  final List<String> created = [];
  int keyReads = 0;
  bool used = false;

  Project? _project;
  ProjectKey _key = ProjectKey(
    id: 'key-1',
    key: 'gd_live_abc123def456abc123def456abc123def456abc123def4f2a',
    label: 'default',
    createdAt: DateTime(2026, 9, 9),
  );

  @override
  Future<(Project, ProjectKey)> create(String name) async {
    created.add(name);
    _project = Project(id: 'p1', name: name, createdAt: DateTime(2026, 9, 9));
    return (_project!, _key);
  }

  @override
  Future<List<ProjectKey>> keys(String projectId) async {
    keyReads++;
    if (used) {
      _key = ProjectKey(
        id: _key.id,
        key: _key.key,
        label: _key.label,
        createdAt: _key.createdAt,
        lastUsedAt: DateTime.now().subtract(const Duration(seconds: 2)),
        lastUsedDevice: 'Pixel 7',
        lastUsedOs: 'Android 15',
      );
    }
    return [_key];
  }

  @override
  Future<List<Project>> list() async => [?_project];

  @override
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  }) async => _key;

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<void> revoke(String keyId) async {}
}

class _FailingProjects extends _FakeProjects {
  @override
  Future<(Project, ProjectKey)> create(String name) async =>
      throw Exception('duplicate key value violates unique constraint');
}

Future<void> _pump(
  WidgetTester tester,
  _FakeProjects repo, {
  ValueChanged<Project>? onFinished,
  VoidCallback? onCancel,
}) {
  // The frames are 1440 × 752 and §2's geometry is measured there. At the test
  // default of 800 × 600 the buttons sit below the fold and cannot be tapped.
  tester.view.physicalSize = const Size(1440, 752);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: OnboardingScreen(
          repository: repo,
          endpoint: 'https://example.supabase.co/functions/v1/ingest',
          pollInterval: const Duration(milliseconds: 50),
          onFinished: onFinished ?? (_) {},
          onCancel: onCancel ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
}

Future<void> _nameAndContinue(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('step 01 cannot continue without a name', (tester) async {
    final repo = _FakeProjects();
    await _pump(tester, repo);

    expect(find.text('Enter project name'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      repo.created,
      isEmpty,
      reason: 'a nameless project is not a project',
    );
    expect(find.text('Enter project name'), findsOneWidget);
  });

  testWidgets('the preview takes the name as it is typed', (tester) async {
    await _pump(tester, _FakeProjects());

    expect(find.text('Your project'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Snapdrop');
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ProjectPreview),
        matching: find.text('Snapdrop'),
      ),
      findsOneWidget,
    );
    expect(find.text('Your project'), findsNothing);
  });

  testWidgets('naming the project creates it and moves to the install step', (
    tester,
  ) async {
    final repo = _FakeProjects();
    await _pump(tester, repo);
    await _nameAndContinue(tester, 'Snapdrop');

    expect(repo.created, ['Snapdrop']);
    expect(find.text('Install SDK'), findsOneWidget);
    // §9's first correction: the frame's package belongs to another company.
    expect(find.textContaining('flutter pub add guidester'), findsOneWidget);
    expect(find.textContaining('codestage'), findsNothing);
  });

  testWidgets('a failed create keeps you on step 01 and says why', (
    tester,
  ) async {
    final repo = _FailingProjects();
    await _pump(tester, repo);
    await _nameAndContinue(tester, 'Snapdrop');

    expect(find.text('Enter project name'), findsOneWidget);
    expect(find.textContaining('unique constraint'), findsOneWidget);
  });

  testWidgets('step 03 carries this project real key and endpoint', (
    tester,
  ) async {
    final repo = _FakeProjects();
    await _pump(tester, repo);
    await _nameAndContinue(tester, 'Snapdrop');
    await tester.tap(find.text('Yes, I have installed'));
    // Not pumpAndSettle: step 03 waits on a spinner that never stops until
    // the SDK reports, which is the entire point of the screen.
    await tester.pump();
    await tester.pump();

    expect(find.text('Add Guidester to your app'), findsOneWidget);
    expect(find.textContaining('gd_live_abc123'), findsOneWidget);

    // D71: the endpoint is a required argument (the package ships no
    // backend URL), so a snippet without it does not compile. The enabled
    // flag stays gone (the key is the kill switch), and the observer stays
    // out: MaterialApp.router has no navigatorObservers, so the line would
    // break every go_router app, and the SDK's console diagnostic names it
    // for the Navigator 1.0 apps that need it.
    expect(
      find.textContaining(
        "endpoint: 'https://example.supabase.co/functions/v1/ingest'",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('enabled:'), findsNothing);
    expect(find.textContaining('navigatorObservers'), findsNothing);
    expect(
      find.textContaining('GuidesterOverlay(child: child!)'),
      findsOneWidget,
    );
    // §9's second correction.
    expect(find.textContaining('CdsService'), findsNothing);
  });

  testWidgets('step 03 waits, then states the fact when the SDK reports', (
    tester,
  ) async {
    final repo = _FakeProjects();
    var finished = 0;
    await _pump(tester, repo, onFinished: (_) => finished++);
    await _nameAndContinue(tester, 'Snapdrop');
    await tester.tap(find.text('Yes, I have installed'));
    await tester.pump();

    expect(find.text('Waiting for your first launch…'), findsOneWidget);
    // Nothing has reported, so there is nothing to open yet.
    await _tap(tester, 'Open project');
    await tester.pump();
    expect(finished, 0);

    repo.used = true;
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(
      find.textContaining('Connected — Pixel 7, Android 15'),
      findsOneWidget,
    );
    expect(find.text('Waiting for your first launch…'), findsNothing);

    await _tap(tester, 'Open project');
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('the poll stops once the answer is yes', (tester) async {
    final repo = _FakeProjects();
    await _pump(tester, repo);
    await _nameAndContinue(tester, 'Snapdrop');
    await tester.tap(find.text('Yes, I have installed'));
    await tester.pump();

    repo.used = true;
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    final readsWhenConnected = repo.keyReads;

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(
      repo.keyReads,
      readsWhenConnected,
      reason: 'a screen that has its answer keeps asking for nothing',
    );
  });

  testWidgets('the stepper marks what is done, in progress and pending', (
    tester,
  ) async {
    final repo = _FakeProjects();
    await _pump(tester, repo);

    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await _nameAndContinue(tester, 'Snapdrop');

    // Step 01 became a check; 02 and 03 still carry their numbers.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('01'), findsNothing);
  });

  testWidgets('leaving is always possible', (tester) async {
    var cancelled = 0;
    await _pump(tester, _FakeProjects(), onCancel: () => cancelled++);
    await _nameAndContinue(tester, 'Snapdrop');
    await tester.tap(find.text('Yes, I have installed'));
    await tester.pump();
    await tester.pump();

    await _tap(tester, 'Do this later');
    await tester.pump();

    expect(cancelled, 1);
  });

  testWidgets('the help link opens a real guide, not a missing video', (
    tester,
  ) async {
    await _pump(tester, _FakeProjects());
    expect(find.text('Watch this installation video'), findsNothing);
    await tester.tap(find.text('How testers leave a comment'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
  });
}

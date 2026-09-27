import 'dart:async';

import 'package:dashboard/src/data/auth_gateway.dart';
import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/screens/home_screen.dart';
import 'package:dashboard/src/screens/projects_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

class _Projects implements ProjectRepository {
  _Projects({this.failures = 0, this.rows = const []});
  int failures;
  final List<Project> rows;
  Completer<void>? gate;
  int lists = 0;

  @override
  Future<List<Project>> list() async {
    lists++;
    if (gate != null) await gate!.future;
    if (failures > 0) {
      failures--;
      throw const RepositoryException('Could not load projects.');
    }
    return rows;
  }

  @override
  Future<(Project, ProjectKey)> create(String name) =>
      throw UnimplementedError();
  List<ProjectKey> keyRows = const [];

  @override
  Future<List<ProjectKey>> keys(String projectId) async => keyRows;
  @override
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  }) => throw UnimplementedError();
  @override
  Future<void> revoke(String keyId) async {}

  final deleted = <String>[];

  @override
  Future<void> deleteProject(String projectId) async => deleted.add(projectId);
}

class _Auth implements AuthGateway {
  final names = <String>[];

  @override
  Future<AuthOutcome> saveName(String name) async {
    names.add(name);
    return const SignedIn();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<List<DashboardLocation>> _home(
  WidgetTester tester,
  _Projects projects, {
  DashboardLocation at = const DashboardLocation.projects(),
  _Auth? auth,
  String? displayName,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final went = <DashboardLocation>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: HomeScreen(
        repository: FakeRepository(const {}),
        projects: projects,
        email: 'dev@example.com',
        displayName: displayName,
        auth: auth,
        location: at,
        onNavigate: went.add,
      ),
    ),
  );
  return went;
}

void main() {
  testWidgets('no projects: one button to create the first', (tester) async {
    var created = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ProjectsScreen(
            projects: const [],
            onOpen: (_) {},
            onNew: () => created++,
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(GButton, 'Create your first project'));
    expect(created, 1);
  });

  testWidgets('projects load as a skeleton, not a spinner', (tester) async {
    final projects = _Projects()..gate = Completer<void>();
    await _home(tester, projects);
    await tester.pump();
    expect(find.byKey(const ValueKey('projects-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    projects.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed load offers Try again, and it works', (tester) async {
    final projects = _Projects(
      failures: 1,
      rows: [Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026))],
    );
    await _home(tester, projects);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load projects.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Snapdrop'), findsOneWidget);
  });

  testWidgets('Save Changes saves the name and says so', (tester) async {
    final auth = _Auth();
    await _home(
      tester,
      _Projects(),
      at: const DashboardLocation.settings(),
      auth: auth,
      displayName: 'Sau',
    );
    await tester.pumpAndSettle();

    Finder field(String hint) => find.descendant(
      of: find.byWidgetPredicate((w) => w is GField && w.hint == hint),
      matching: find.byType(TextField),
    );
    GButton save() =>
        tester.widget<GButton>(find.widgetWithText(GButton, 'Save Changes'));

    expect(tester.widget<TextField>(field('Name')).controller!.text, 'Sau');
    // Changing the address needs a confirmation flow that does not exist.
    expect(tester.widget<TextField>(field('Email')).enabled, isFalse);
    expect(save().onPressed, isNull);

    await tester.enterText(field('Name'), '  Saurabh ');
    await tester.pump();
    await tester.tap(find.widgetWithText(GButton, 'Save Changes'));
    await tester.pumpAndSettle();
    expect(auth.names, ['Saurabh']);
    expect(find.text('Saved'), findsOneWidget);
    // The shell's user chip follows.
    expect(find.text('Saurabh'), findsWidgets);
  });

  testWidgets('one project: arriving opens its board', (tester) async {
    final went = await _home(
      tester,
      _Projects(
        rows: [Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026))],
      ),
    );
    await tester.pumpAndSettle();
    expect(went.map((l) => l.path), ['/p/p1']);
  });

  testWidgets('two projects: the list, as asked', (tester) async {
    final went = await _home(
      tester,
      _Projects(
        rows: [
          Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026)),
          Project(id: 'p2', name: 'Sahaj', createdAt: DateTime(2026)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(went, isEmpty);
  });

  testWidgets('one project, arriving somewhere else: no jump', (tester) async {
    final went = await _home(
      tester,
      _Projects(
        rows: [Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026))],
      ),
      at: const DashboardLocation.settings(),
    );
    await tester.pumpAndSettle();
    expect(went, isEmpty);
  });

  testWidgets('delete project: typed name, then gone, then the list', (
    tester,
  ) async {
    final projects = _Projects(
      rows: [
        Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026)),
        Project(id: 'p2', name: 'Sahaj', createdAt: DateTime(2026)),
      ],
    );
    final went = await _home(
      tester,
      projects,
      at: const DashboardLocation.settings(projectId: 'p1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GButton, 'Delete project'));
    await tester.pumpAndSettle();

    GButton confirm() =>
        tester.widget<GButton>(find.widgetWithText(GButton, 'Delete forever'));
    expect(find.textContaining('Type Snapdrop'), findsOneWidget);
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'Snapdro');
    await tester.pump();
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'Snapdrop');
    await tester.pump();
    await tester.tap(find.widgetWithText(GButton, 'Delete forever'));
    await tester.pumpAndSettle();

    expect(projects.deleted, ['p1']);
    expect(went.last.path, '/projects');
  });

  testWidgets('a project row has Open, Settings and Copy project ID', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final opened = <String>[];
    final settings = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ProjectsScreen(
            projects: const [
              ProjectSummary(
                id: 'p1',
                name: 'Snapdrop',
                createdBy: 'Sau',
                total: 3,
                unread: 1,
              ),
            ],
            onOpen: (p) => opened.add(p.id),
            onSettings: (p) => settings.add(p.id),
          ),
        ),
      ),
    );
    Future<void> choose(String item) async {
      await tester.tap(find.byTooltip('More for Snapdrop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await choose('Open');
    await choose('Settings');
    await choose('Copy project ID');
    expect(opened, ['p1']);
    expect(settings, ['p1']);
    expect(copied, 'p1');
  });

  testWidgets('settings shows the install, masked, and copies it whole', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const full = 'gd_live_0123456789abcdef0123456789abcdef';
    final projects =
        _Projects(
            rows: [
              Project(id: 'p1', name: 'Snapdrop', createdAt: DateTime(2026)),
            ],
          )
          ..keyRows = [
            ProjectKey(
              id: 'k1',
              key: full,
              label: 'default',
              createdAt: DateTime(2026),
            ),
          ];
    await _home(
      tester,
      projects,
      at: const DashboardLocation.settings(projectId: 'p1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Install'), findsOneWidget);
    expect(find.textContaining(full), findsNothing);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, contains(full));
    expect(copied, contains('endpoint:'));
  });
}

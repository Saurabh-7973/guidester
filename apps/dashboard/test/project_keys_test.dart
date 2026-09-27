import 'package:dashboard/src/data/comment_repository.dart';
import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/screens/home_screen.dart';
import 'package:dashboard/src/screens/settings_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectKey _key({
  String id = 'key-1',
  String value = 'gd_live_0123456789abcdef0123456789abcdef0123456789ab4f2a',
  DateTime? revokedAt,
  DateTime? lastUsedAt,
  String? device,
  String? os,
}) => ProjectKey(
  id: id,
  key: value,
  label: 'default',
  createdAt: DateTime(2026, 9, 1),
  revokedAt: revokedAt,
  lastUsedAt: lastUsedAt,
  lastUsedDevice: device,
  lastUsedOs: os,
);

class _FakeProjects implements ProjectRepository {
  _FakeProjects({List<ProjectKey>? keys, List<Project>? projects})
    : _keys = keys ?? [_key()],
      _projects =
          projects ??
          [Project(id: 'p1', name: 'Sahaj', createdAt: DateTime(2026, 9, 1))];

  List<ProjectKey> _keys;
  final List<Project> _projects;

  int rotations = 0;
  final List<String> revoked = [];

  @override
  Future<(Project, ProjectKey)> create(String name) async =>
      (_projects.first, _keys.first);

  @override
  Future<List<ProjectKey>> keys(String projectId) async => _keys;

  @override
  Future<List<Project>> list() async => _projects;

  @override
  Future<ProjectKey> rotate({
    required String projectId,
    required String replacing,
  }) async {
    rotations++;
    final fresh = _key(id: 'key-2', value: 'gd_live_ffffffffffffffffffff9999');
    _keys = [fresh, _key(id: replacing, revokedAt: DateTime.now())];
    return fresh;
  }

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<void> revoke(String keyId) async {
    revoked.add(keyId);
    _keys = [_key(id: keyId, revokedAt: DateTime.now())];
  }
}

Future<void> _pumpSettings(WidgetTester tester, _FakeProjects repo) async {
  tester.view.physicalSize = const Size(1440, 752);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SettingsScreen(
          email: 'dev@example.com',
          projects: repo,
          projectId: 'p1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the key itself', () {
    test('is masked to a prefix and four characters', () {
      expect(_key().masked, 'gd_live_••••4f2a');
    });

    test('a pre-0006 bare-hex key is masked too', () {
      expect(
        _key(value: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d49999').masked,
        'a1b2••••9999',
      );
    });

    test('device and OS read as one line, and absence reads as nothing', () {
      expect(
        _key(device: 'Pixel 7', os: 'Android 15').lastUsedDescription,
        'Pixel 7, Android 15',
      );
      expect(_key().lastUsedDescription, isNull);
    });
  });

  group('settings', () {
    testWidgets('shows the live key, masked, with when it last reported', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        _FakeProjects(
          keys: [
            _key(
              lastUsedAt: DateTime(2026, 9, 9),
              device: 'Pixel 7',
              os: 'Android 15',
            ),
          ],
        ),
      );

      expect(find.text('gd_live_••••4f2a'), findsOneWidget);
      expect(find.textContaining('Pixel 7, Android 15'), findsOneWidget);
      // Never the whole key. A key readable off a screen is a key in a
      // screenshot.
      expect(find.textContaining('0123456789abcdef'), findsNothing);
    });

    testWidgets('a key nothing has used says never', (tester) async {
      await _pumpSettings(tester, _FakeProjects());

      expect(find.text('never'), findsOneWidget);
    });

    testWidgets('the live key is preferred over a revoked one', (tester) async {
      await _pumpSettings(
        tester,
        _FakeProjects(
          keys: [
            _key(id: 'old', revokedAt: DateTime(2026, 9, 2)),
            _key(id: 'live', value: 'gd_live_aaaaaaaaaaaaaaaaaaaaaaaa1234'),
          ],
        ),
      );

      expect(find.text('gd_live_••••1234'), findsOneWidget);
    });

    testWidgets('rotate asks first, and says what it breaks', (tester) async {
      final repo = _FakeProjects();
      await _pumpSettings(tester, repo);

      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('stops reporting'), findsOneWidget);
      expect(repo.rotations, 0, reason: 'nothing happens before you answer');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.rotations, 0);

      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GButton, 'Rotate').last);
      await tester.pumpAndSettle();

      expect(repo.rotations, 1);
      expect(find.text('gd_live_••••9999'), findsOneWidget);
    });

    testWidgets('revoke asks first, and the revoked key says so', (
      tester,
    ) async {
      final repo = _FakeProjects();
      await _pumpSettings(tester, repo);

      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no new key is created'), findsOneWidget);

      await tester.tap(find.widgetWithText(GButton, 'Revoke').last);
      await tester.pumpAndSettle();

      expect(repo.revoked, ['key-1']);
      expect(find.text('revoked'), findsOneWidget);
    });

    testWidgets('with no project selected the key column has nothing to show', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 752);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SettingsScreen(email: 'dev@example.com')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No key yet'), findsOneWidget);
    });
  });

  group('projects list', () {
    testWidgets('reads the projects rather than assuming one', (tester) async {
      tester.view.physicalSize = const Size(1440, 752);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeProjects(
        projects: [
          Project(
            id: 'p1',
            name: 'Sahaj',
            createdAt: DateTime(2026, 9, 1),
            total: 32,
            unread: 2,
          ),
          Project(id: 'p2', name: 'Snapdrop', createdAt: DateTime(2026, 9, 2)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: HomeScreen(
            repository: _UnusedComments(),
            projects: repo,
            email: 'dev@example.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sahaj'), findsOneWidget);
      expect(find.text('Snapdrop'), findsOneWidget);
      expect(find.textContaining('32'), findsOneWidget);
    });
  });
}

/// The comments repository is never reached in these tests: nothing opens a
/// project. Every method throws rather than returning something empty, so a
/// test that starts using it fails loudly instead of quietly passing.
class _UnusedComments implements CommentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the comments repository is not part of this');
}

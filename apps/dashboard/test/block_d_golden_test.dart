@Tags(['golden'])
library;

import 'package:dashboard/src/data/project_repository.dart';
import 'package:dashboard/src/screens/onboarding_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// §2's three steps at the frames' 1440 × 752.
///
///   flutter test --update-goldens test/block_d_golden_test.dart
///
/// The right preview panel runs off the right edge on purpose, so these
/// goldens are also the check that it is clipped rather than squeezed.
class _StubProjects implements ProjectRepository {
  _StubProjects({this.used = false});

  final bool used;

  ProjectKey get _key => ProjectKey(
    id: 'key-1',
    key: 'gd_live_0123456789abcdef0123456789abcdef0123456789ab4f2a',
    label: 'default',
    createdAt: DateTime.utc(2026, 9, 1),
    lastUsedAt: used
        ? DateTime.now().subtract(const Duration(seconds: 2))
        : null,
    lastUsedDevice: used ? 'Pixel 7' : null,
    lastUsedOs: used ? 'Android 15' : null,
  );

  @override
  Future<(Project, ProjectKey)> create(String name) async => (
    Project(id: 'p1', name: name, createdAt: DateTime.utc(2026, 9, 1)),
    _key,
  );

  @override
  Future<List<ProjectKey>> keys(String projectId) async => [_key];

  @override
  Future<List<Project>> list() async => const [];

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

void main() {
  Future<void> pump(WidgetTester tester, {bool used = false}) async {
    tester.view.physicalSize = const Size(1440, 752);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: Scaffold(
          backgroundColor: T.page,
          body: OnboardingScreen(
            repository: _StubProjects(used: used),
            endpoint:
                'https://abcdefghijklmnopqrst.supabase.co'
                '/functions/v1/ingest',
            pollInterval: const Duration(milliseconds: 50),
            onFinished: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('step 01 — name', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Snapdrop');
    await tester.pump();

    await expectLater(
      find.byType(OnboardingScreen),
      matchesGoldenFile('goldens/onboarding_01_1440.png'),
    );
  });

  testWidgets('step 02 — install', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Snapdrop');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(OnboardingScreen),
      matchesGoldenFile('goldens/onboarding_02_1440.png'),
    );
  });

  testWidgets('step 03 — wire up, connected', (tester) async {
    await pump(tester, used: true);
    await tester.enterText(find.byType(TextField), 'Snapdrop');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, I have installed'));
    await tester.pump();
    await tester.pump();

    await expectLater(
      find.byType(OnboardingScreen),
      matchesGoldenFile('goldens/onboarding_03_1440.png'),
    );
  });
}

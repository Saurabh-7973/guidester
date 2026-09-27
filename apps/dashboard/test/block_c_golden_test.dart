@Tags(['golden'])
library;

import 'dart:async';

import 'package:dashboard/src/data/auth_gateway.dart';
import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/screens/login_screen.dart';
import 'package:dashboard/src/screens/projects_screen.dart';
import 'package:dashboard/src/screens/settings_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/app_shell.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:dashboard/src/widgets/project_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Block C screens at the frames' 1440.
///
///   flutter test --update-goldens test/block_c_golden_test.dart
void main() {
  Future<void> shell(WidgetTester tester, ShellTab tab, Widget child) async {
    tester.view.physicalSize = const Size(1440, 752);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AppShell(
          tab: tab,
          onTabSelected: (_) {},
          userName: 'sampledeveloper1',
          onLogOut: () {},
          trailing: tab == ShellTab.projects
              ? GButton(
                  label: 'New project',
                  icon: Icons.add,
                  // Enabled, as in the app: a null here renders disabled.
                  onPressed: () {},
                )
              : null,
          child: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('projects list', (tester) async {
    await shell(
      tester,
      ShellTab.projects,
      ProjectsScreen(
        projects: const [
          ProjectSummary(
            id: 'p1',
            name: 'Sahaj',
            createdBy: 'Saurabh',
            total: 32,
            unread: 2,
          ),
        ],
        onOpen: (_) {},
      ),
    );
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/projects_1440.png'),
    );
  });

  testWidgets('project, empty', (tester) async {
    await shell(
      tester,
      ShellTab.projects,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProjectHeader(
            projectName: 'Sahaj',
            createdBy: 'You',
            collaborators: 0,
            commentCount: 0,
            status: CommentStatus.open,
            counts: const {},
            onStatusSelected: (_) {},
          ),
          const ProjectEmptyState(),
        ],
      ),
    );
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/project_empty_1440.png'),
    );
  });

  testWidgets('settings', (tester) async {
    await shell(
      tester,
      ShellTab.settings,
      const SettingsScreen(
        email: 'you@example.com',
        apiKeyMasked: 'gd_live_••••4f2a',
        apiKeyCreated: '4 Sep 2026',
        apiKeyLastUsed: '2 minutes ago',
      ),
    );
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/settings_1440.png'),
    );
  });

  testWidgets('login', (tester) async {
    tester.view.physicalSize = const Size(1440, 752);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: LoginScreen(auth: _NeverAuth()),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/login_1440.png'),
    );
  });
}

/// The golden renders the real screen, which never submits here.
class _NeverAuth implements AuthGateway {
  @override
  Future<AuthOutcome> logIn({
    required String email,
    required String password,
  }) => Completer<AuthOutcome>().future;

  @override
  Future<AuthOutcome> createAccount({
    required String email,
    required String password,
  }) => Completer<AuthOutcome>().future;

  @override
  Future<AuthOutcome> sendPasswordReset({required String email}) =>
      Completer<AuthOutcome>().future;

  @override
  Future<AuthOutcome> setNewPassword({required String password}) =>
      Completer<AuthOutcome>().future;

  @override
  Future<AuthOutcome> saveName(String name) async => const SignedIn();
}

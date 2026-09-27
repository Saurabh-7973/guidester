import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../data/auth_gateway.dart';
import '../data/comment_repository.dart';
import '../data/project_repository.dart';
import '../routing/location.dart';
import '../theme/tokens.dart';
import '../widgets/app_shell.dart';
import '../widgets/controls.dart';
import '../widgets/project_header.dart';
import '../widgets/skeleton.dart';
import 'comments_screen.dart';
import 'onboarding_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'status_screen.dart';

/// Everything behind the login: the shell, and what sits inside it.
///
/// Where it is comes from [location], which the router parses from the URL,
/// and every move goes out through [onNavigate] so the URL changes with it.
/// Without a router (a widget test) it keeps its own location instead.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.projects,
    this.email,
    this.displayName,
    this.auth,
    this.onboardingPollInterval = const Duration(seconds: 3),
    this.location,
    this.onNavigate,
    this.onLogOut,
  });

  final CommentRepository repository;
  final ProjectRepository projects;

  /// Who is signed in. Read from the Supabase session when omitted, which is
  /// every case but a test — a widget test has no initialised client and
  /// should not need one to render a list of projects.
  final String? email;

  /// The name the account chose in Settings, if any.
  final String? displayName;

  /// Saves the account name from Settings. Null hides the save.
  final AuthGateway? auth;

  /// Passed through to onboarding's connection check so a test does not wait.
  final Duration onboardingPollInterval;

  /// Where the URL says we are. Null keeps the location in local state.
  final DashboardLocation? location;

  /// Moves to [DashboardLocation] by changing the URL.
  final void Function(DashboardLocation)? onNavigate;

  /// Log out, as the app tracks it (so it is not mistaken for an expiry).
  final Future<void> Function()? onLogOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DashboardLocation _local = const DashboardLocation.projects();

  DashboardLocation get _loc => widget.location ?? _local;

  void _go(DashboardLocation to) {
    if (to == _loc) return;
    final navigate = widget.onNavigate;
    if (navigate != null) {
      navigate(to);
    } else {
      setState(() => _local = to);
    }
  }

  ShellTab get _tab => _loc.tab;
  bool get _onboarding => _loc.onboarding;

  /// The open project, looked up by the id in the URL. Null while the list
  /// loads, and when the id matches nothing the user can see.
  Project? get _openProject {
    final id = _loc.tab == ShellTab.projects ? _loc.projectId : null;
    if (id == null) return null;
    return _projects?.where((p) => p.id == id).firstOrNull;
  }

  List<Project>? _projects;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  bool _firstLoad = true;

  Future<void> _load() async {
    final first = _firstLoad;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await widget.projects.list();
      if (!mounted) return;
      setState(() => _projects = projects);
      // §5.6 row 5: with exactly one project, arriving at the list opens its
      // board. First arrival only: the Projects tab must still show the list
      // when someone asks for it.
      if (_firstLoad &&
          projects.length == 1 &&
          _loc == const DashboardLocation.projects()) {
        _go(DashboardLocation.board(projects.single.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (first) _firstLoad = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The project Settings shows a key for when nothing is open: the only one,
  /// when there is one. With several and none open, Settings shows the account
  /// half alone rather than picking a project on the user's behalf.
  Project? get _first =>
      (_projects?.length ?? 0) == 1 ? _projects!.first : null;

  String get _email =>
      widget.email ??
      Supabase.instance.client.auth.currentUser?.email ??
      'Signed in';

  /// Saved in Settings during this visit, ahead of [HomeScreen.displayName].
  String? _savedName;

  String get _name {
    final chosen = _savedName ?? widget.displayName;
    if (chosen != null && chosen.trim().isNotEmpty) return chosen;
    final email = _email;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  Future<void> _signOut() =>
      widget.onLogOut?.call() ?? Supabase.instance.client.auth.signOut();

  Widget _board() {
    final project = _openProject;
    if (project == null) {
      if (_projects == null && _error == null) {
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: T.text3),
          ),
        );
      }
      return _Missing(
        message:
            _error ?? "This project doesn't exist or you don't have access.",
        onBack: () => _go(const DashboardLocation.projects()),
      );
    }
    final loc = _loc;
    return CommentsScreen(
      // A different project is a different board, not an update to this one.
      key: ValueKey(project.id),
      repository: widget.repository,
      projectId: project.id,
      projectName: project.name,
      createdBy: _name,
      projectTotal: project.total,
      commentId: loc.commentId,
      status: loc.status,
      impact: loc.impact,
      screen: loc.screen,
      // Hash URLs: everything after # is the route, so the link is this page
      // with the comment's own route in the fragment.
      linkFor: (id) => '${pageUrl()}#${loc.withComment(id).path}',
      lastLaunch: () async {
        final keys = await widget.projects.keys(project.id);
        final live = keys.where((k) => !k.isRevoked).firstOrNull;
        final at = live?.lastUsedAt;
        if (at == null) return null;
        final device = [
          live!.lastUsedDevice,
          live.lastUsedOs,
        ].whereType<String>().join(', ');
        return LastLaunch(at: at, device: device.isEmpty ? null : device);
      },
      onSetup: () => _go(DashboardLocation.settings(projectId: project.id)),
      onOpenSettings: () =>
          _go(DashboardLocation.settings(projectId: project.id)),
      onChanged: (commentId, status, impact, screen) => _go(
        DashboardLocation.board(
          project.id,
          commentId: commentId,
          status: status,
          impact: impact,
          screen: screen,
        ),
      ),
      onBackToProjects: () => _go(const DashboardLocation.projects()),
      onOpenReport: widget.repository is ReportSource
          ? () => _go(DashboardLocation.status(projectId: project.id))
          : null,
    );
  }

  Widget _status() {
    final source = widget.repository;
    final projects = _projects;
    if (source is! ReportSource) {
      return const _Missing(
        message: 'Status reports need the live database.',
        onBack: null,
      );
    }
    if (projects == null) {
      return _error == null
          ? const StatusSkeleton()
          : _Missing(
              message: _error!,
              onBack: () => _go(const DashboardLocation.projects()),
            );
    }
    return StatusScreen(
      source: source as ReportSource,
      projects: [for (final p in projects) (id: p.id, name: p.name)],
      projectId: _loc.projectId,
      onOpenReport: (id) => _go(DashboardLocation.status(projectId: id)),
      onOpenBoard: (projectId, commentId) =>
          _go(DashboardLocation.board(projectId, commentId: commentId)),
      linkFor: (id) =>
          '${pageUrl()}#${DashboardLocation.status(projectId: id).path}',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Onboarding replaces the shell rather than sitting inside it. §2's frames
    // carry no nav tabs and no user chip, and its geometry is measured from
    // the page edge — x=80 for the left panel, x=860 for the preview — which
    // is not where the shell's content area starts.
    if (_onboarding) {
      return Scaffold(
        backgroundColor: T.page,
        body: OnboardingScreen(
          repository: widget.projects,
          endpoint: Env.ingestEndpoint,
          pollInterval: widget.onboardingPollInterval,
          onCancel: () {
            _go(const DashboardLocation.projects());
            unawaited(_load());
          },
          onFinished: (project) {
            _go(DashboardLocation.board(project.id));
            unawaited(_load());
          },
        ),
      );
    }

    return AppShell(
      tab: _tab,
      // Projects goes back to the list. Settings keeps the project you were
      // in, so its key is the one shown.
      onTabSelected: (t) => _go(switch (t) {
        ShellTab.settings => DashboardLocation.settings(
          projectId: _loc.projectId,
        ),
        // From inside a project, its own report; from anywhere else, all.
        ShellTab.status => DashboardLocation.status(projectId: _loc.projectId),
        ShellTab.projects => const DashboardLocation.projects(),
      }),
      userName: _name,
      onLogOut: _signOut,
      fullWidth: _loc.isBoard || _tab == ShellTab.status,
      trailing: _tab == ShellTab.projects && !_loc.isBoard && !_onboarding
          ? GButton(
              label: 'New project',
              icon: Icons.add,
              // §3 renames the frame's "Add Projects". It opens §2's flow,
              // which is where a project and its key are actually made.
              onPressed: () => _go(const DashboardLocation.newProject()),
            )
          : null,
      child: switch (_tab) {
        ShellTab.settings => SettingsScreen(
          email: _email,
          name: _savedName ?? widget.displayName,
          auth: widget.auth,
          onNameSaved: (n) => setState(() => _savedName = n),
          projectName: _projects
              ?.where((p) => p.id == (_loc.projectId ?? _first?.id))
              .firstOrNull
              ?.name,
          onProjectDeleted: () {
            _go(const DashboardLocation.projects());
            unawaited(_load());
          },
          projects: widget.projects,
          projectId: _loc.projectId ?? _first?.id,
        ),
        ShellTab.projects when !_loc.isBoard => _Projects(
          projects: _projects,
          loading: _loading,
          error: _error,
          createdBy: _name,
          onOpen: (p) => _go(DashboardLocation.board(p.id)),
          onRetry: _load,
          onNew: () => _go(const DashboardLocation.newProject()),
          onSettings: (p) => _go(DashboardLocation.settings(projectId: p.id)),
        ),
        ShellTab.projects => _board(),
        ShellTab.status => _status(),
      },
    );
  }
}

/// §3's table, from the database.
class _Projects extends StatelessWidget {
  const _Projects({
    required this.projects,
    required this.loading,
    required this.error,
    required this.createdBy,
    required this.onOpen,
    required this.onRetry,
    required this.onNew,
    required this.onSettings,
  });

  final ValueChanged<ProjectSummary> onSettings;

  final VoidCallback onRetry;
  final VoidCallback onNew;
  final List<Project>? projects;
  final bool loading;
  final String? error;
  final String createdBy;
  final ValueChanged<ProjectSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error!.replaceFirst('RepositoryException: ', ''),
              style: T.body.copyWith(color: T.text3),
            ),
            const SizedBox(height: 16),
            GButton(
              label: 'Try again',
              kind: GButtonKind.secondary,
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }
    // An empty table while the first read is in flight reads as "you have no
    // projects", which is a different and much worse sentence.
    if (loading && projects == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: BoardSkeleton(key: ValueKey('projects-skeleton'), rows: 3),
      );
    }
    return ProjectsScreen(
      projects: [
        for (final p in projects ?? const <Project>[])
          ProjectSummary(
            id: p.id,
            name: p.name,
            createdBy: createdBy,
            total: p.total,
            unread: p.unread,
          ),
      ],
      onOpen: onOpen,
      onNew: onNew,
      onSettings: onSettings,
    );
  }
}

/// A URL that names a project the user cannot see.
class _Missing extends StatelessWidget {
  const _Missing({required this.message, required this.onBack});

  final String message;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Column(
      children: [
        Text(message, style: T.body.copyWith(color: T.text3)),
        if (onBack != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onBack, child: const Text('Back to Projects')),
        ],
      ],
    ),
  );
}

/// Shown when the dart-defines are missing. Kept here so `main.dart` stays a
/// wiring file.
class SetupRequired extends StatelessWidget {
  const SetupRequired({super.key, required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.page,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: T.surface1,
              borderRadius: BorderRadius.circular(T.rCard),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configuration missing', style: T.heading),
                const SizedBox(height: 8),
                Text(
                  'Not set: ${missing.join(', ')}',
                  style: T.supporting.copyWith(color: T.text3),
                ),
                const SizedBox(height: 16),
                const SelectableText(
                  'flutter run -d chrome \\\n'
                  '  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=<anon key> \\\n'
                  '  --dart-define=PROJECT_ID=<project uuid>',
                  style: T.code,
                ),
                const SizedBox(height: 12),
                Text(
                  'These are build-time values, not secrets in a vault — but '
                  'they stay out of the repository so a fork never carries '
                  "one project's identifiers.",
                  style: T.supporting.copyWith(color: T.text3, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

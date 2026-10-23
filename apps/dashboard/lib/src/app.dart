import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'data/auth_gateway.dart';
import 'data/comment_repository.dart';
import 'data/project_repository.dart';
import 'data/session_state.dart';
import 'data/team_repository.dart';
import 'routing/router.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/session_expired.dart';

/// Who is signed in, as far as the dashboard needs to know.
class DashboardUser {
  const DashboardUser({required this.id, this.email, this.name});

  final String id;
  final String? email;

  /// The name the account chose in Settings, if any.
  final String? name;
}

/// The whole dashboard, with everything it talks to passed in.
///
/// `main.dart` passes the Supabase implementations; `demo_main.dart` passes
/// in-memory ones. The app itself never reaches for a client, so the same
/// screens run against either.
class DashboardApp extends StatefulWidget {
  const DashboardApp({
    super.key,
    required this.comments,
    required this.projects,
    required this.auth,
    required this.signedIn,
    required this.currentUser,
    required this.signOut,
    this.team,
    this.authChanges = const Stream.empty(),
    this.scaffoldMessengerKey,
    this.frame,
  });

  /// Comments, and the Status page when it is also a [ReportSource].
  final CommentRepository comments;
  final ProjectRepository projects;

  /// Teams (0013). Null: a solo dashboard.
  final TeamRepository? team;
  final AuthGateway auth;

  /// Whether a session exists right now. Read on every route change, not
  /// once: the stream has emitted nothing yet on a cold load with a restored
  /// session.
  final bool Function() signedIn;
  final DashboardUser? Function() currentUser;
  final Future<void> Function() signOut;

  /// Auth events, with the email they carry.
  final Stream<(AuthChangeEvent, String?)> authChanges;

  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Wraps every page, outside the session overlay. The demo's banner.
  final TransitionBuilder? frame;

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  final _auth = SessionState();
  late final StreamSubscription<(AuthChangeEvent, String?)> _authSub = widget
      .authChanges
      .listen((s) => _auth.onEvent(s.$1, s.$2));

  // Hash URLs (`/#/p/...`), not path URLs: a self-hoster serves this from any
  // static host, and only the hash survives a reload there without a rewrite
  // rule sending every path back to index.html.
  late final _router = buildRouter(
    // An expired session keeps its page (the overlay asks to log in over
    // it), so it still counts as signed in for the guard.
    signedIn: () => widget.signedIn() || _auth.expired,
    refresh: _auth,
    login: (_) => LoginScreen(auth: widget.auth),
    recovering: () => _auth.recovering,
    resetPassword: (_) =>
        ResetPasswordScreen(auth: widget.auth, onDone: _auth.recoveryFinished),
    home: (context, location, navigate) {
      final user = widget.currentUser();
      return HomeScreen(
        auth: widget.auth,
        email: user?.email,
        displayName: user?.name,
        repository: widget.comments,
        projects: widget.projects,
        team: widget.team,
        userId: user?.id,
        location: location,
        onNavigate: navigate,
        onLogOut: _logOut,
      );
    },
  );

  Future<void> _logOut() {
    _auth.loggingOut();
    return widget.signOut();
  }

  @override
  void initState() {
    super.initState();
    _auth.lastEmail = widget.currentUser()?.email;
    if (widget.signedIn()) {
      _auth.onEvent(AuthChangeEvent.initialSession, _auth.lastEmail);
    }
    _authSub; // start listening
  }

  @override
  void dispose() {
    _router.dispose();
    _authSub.cancel();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Guidester',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      builder: (context, child) {
        final page = ListenableBuilder(
          listenable: _auth,
          builder: (context, _) => SessionExpiredOverlay(
            expired: _auth.expired,
            email: _auth.lastEmail,
            auth: widget.auth,
            // The auth listener sees the new session and clears `expired`.
            onRestored: () {},
            onLogOut: _logOut,
            child: child!,
          ),
        );
        return widget.frame?.call(context, page) ?? page;
      },
    );
  }
}

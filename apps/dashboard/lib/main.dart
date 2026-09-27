import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/config/accessibility.dart';
import 'src/config/env.dart';
import 'src/data/auth_gateway.dart';
import 'src/data/comment_repository.dart';
import 'src/data/project_repository.dart';
import 'src/data/session_state.dart';
import 'src/data/team_repository.dart';
import 'src/routing/location.dart';
import 'src/routing/router.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/reset_password_screen.dart';
import 'src/theme/app_theme.dart';
import 'src/widgets/session_expired.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Held for the life of the app; never disposed.
  enableAccessibility();

  // Fail visibly rather than crashing on a null client: a build with no
  // dart-defines is the single most likely first-run mistake.
  if (!Env.isConfigured) {
    runApp(const _SetupRequiredApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // `anonKey` is deprecated in supabase_flutter; `publishableKey` is the
    // current name for the same value, and accepts the anon key that older
    // projects were issued.
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const DashboardApp());
}

class DashboardApp extends StatefulWidget {
  const DashboardApp({super.key});

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  final _client = Supabase.instance.client;
  final _auth = SessionState();
  late final StreamSubscription<AuthState> _authSub = _client
      .auth
      .onAuthStateChange
      .listen((s) => _auth.onEvent(s.event, s.session?.user.email));
  late final _comments = SupabaseCommentRepository(_client);
  late final _projects = SupabaseProjectRepository(_client);
  late final _team = SupabaseTeamRepository(_client);

  // The reset link comes back to wherever this dashboard is served, minus
  // any route: the router puts the user on the reset screen itself.
  late final _gateway = SupabaseAuthGateway(
    _client.auth,
    redirectTo: pageUrl(),
  );

  // Hash URLs (`/#/p/...`), not path URLs: a self-hoster serves this from any
  // static host, and only the hash survives a reload there without a rewrite
  // rule sending every path back to index.html.
  late final _router = buildRouter(
    // currentSession, not the stream event: the stream has emitted nothing
    // yet on a cold load with a restored session.
    // An expired session keeps its page (the overlay asks to log in over
    // it), so it still counts as signed in for the guard.
    signedIn: () => _client.auth.currentSession != null || _auth.expired,
    refresh: _auth,
    login: (_) => LoginScreen(auth: _gateway),
    recovering: () => _auth.recovering,
    resetPassword: (_) =>
        ResetPasswordScreen(auth: _gateway, onDone: _auth.recoveryFinished),
    home: (context, location, navigate) => HomeScreen(
      auth: _gateway,
      displayName: _client.auth.currentUser?.userMetadata?['name'] as String?,
      repository: _comments,
      projects: _projects,
      team: _team,
      userId: _client.auth.currentUser?.id,
      location: location,
      onNavigate: navigate,
      onLogOut: _logOut,
    ),
  );

  Future<void> _logOut() {
    _auth.loggingOut();
    return _client.auth.signOut();
  }

  @override
  void initState() {
    super.initState();
    _auth.lastEmail = _client.auth.currentUser?.email;
    if (_client.auth.currentSession != null) {
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
      builder: (context, child) => ListenableBuilder(
        listenable: _auth,
        builder: (context, _) => SessionExpiredOverlay(
          expired: _auth.expired,
          email: _auth.lastEmail,
          auth: _gateway,
          // The auth listener sees the new session and clears `expired`.
          onRestored: () {},
          onLogOut: _logOut,
          child: child!,
        ),
      ),
    );
  }
}

class _SetupRequiredApp extends StatelessWidget {
  const _SetupRequiredApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Guidester — setup',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: SetupRequired(missing: Env.missing),
  );
}

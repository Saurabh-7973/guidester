import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/accessibility.dart';
import 'src/config/env.dart';
import 'src/data/auth_gateway.dart';
import 'src/data/comment_repository.dart';
import 'src/data/project_repository.dart';
import 'src/data/team_repository.dart';
import 'src/routing/location.dart';
import 'src/screens/home_screen.dart' show SetupRequired;
import 'src/theme/app_theme.dart';

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

  final client = Supabase.instance.client;
  runApp(
    DashboardApp(
      comments: SupabaseCommentRepository(client),
      projects: SupabaseProjectRepository(client),
      team: SupabaseTeamRepository(client),
      // The reset link comes back to wherever this dashboard is served, minus
      // any route: the router puts the user on the reset screen itself.
      auth: SupabaseAuthGateway(client.auth, redirectTo: pageUrl()),
      signedIn: () => client.auth.currentSession != null,
      currentUser: () {
        final user = client.auth.currentUser;
        if (user == null) return null;
        return DashboardUser(
          id: user.id,
          email: user.email,
          name: user.userMetadata?['name'] as String?,
        );
      },
      signOut: client.auth.signOut,
      authChanges: client.auth.onAuthStateChange.map(
        (s) => (s.event, s.session?.user.email),
      ),
    ),
  );
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

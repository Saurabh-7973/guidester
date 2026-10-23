// The dashboard on sample data, for the "Try it" page.
//
// The real app, every screen of it, with in-memory repositories in place of
// Supabase. There is no Supabase.initialize and no login: the demo opens
// signed in, every write lands in memory, and a reload starts over. Nothing a
// visitor does leaves their browser.
//
// Build:
//   flutter build web --release -t lib/demo_main.dart \
//     --base-href /guidester/dashboard/ --no-web-resources-cdn
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/config/accessibility.dart';
import 'src/demo/demo_data.dart';
import 'src/demo/demo_repositories.dart';
import 'src/theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Held for the life of the app; never disposed.
  enableAccessibility();
  runApp(DemoDashboard());
}

/// The dashboard, wired to a [DemoBackend].
class DemoDashboard extends StatelessWidget {
  DemoDashboard({super.key, DateTime? now}) : _now = now;

  final DateTime? _now;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  late final DemoBackend backend = DemoBackend(notice: _say, now: _now);

  void _say(String message) {
    final m = _messenger.currentState;
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => DashboardApp(
    comments: backend.comments,
    projects: backend.projects,
    team: backend.team,
    auth: backend.auth,
    signedIn: () => true,
    currentUser: () => DemoData.you,
    // There is no account to leave.
    signOut: () async => _say(notInDemo),
    scaffoldMessengerKey: _messenger,
    frame: (context, child) => Column(
      children: [
        const DemoBanner(),
        Expanded(child: child!),
      ],
    ),
  );
}

/// One line across the top of every page, so nobody mistakes the demo for
/// their own data.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  static const String text = 'Demo: sample data, changes reset on reload.';

  @override
  Widget build(BuildContext context) => Material(
    color: T.accentDim,
    child: SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: T.supporting.copyWith(color: T.text1),
        ),
      ),
    ),
  );
}

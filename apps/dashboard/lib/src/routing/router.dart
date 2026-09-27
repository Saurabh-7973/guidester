import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import 'location.dart';

typedef HomeBuilder =
    Widget Function(
      BuildContext context,
      DashboardLocation location,
      void Function(DashboardLocation) navigate,
    );

/// Every dashboard URL builds the same page, keyed the same way.
///
/// Navigator treats a page with an unchanged key as the same route and
/// updates it in place, so going from `/p/x` to `/p/x/c/y` changes the URL
/// without rebuilding the board: the list, its scroll and the loaded rows
/// survive. A fresh key per URL would reload the board on every j/k.
const _homeKey = ValueKey('dashboard');

/// The app's routes, with the auth guard in front of them.
///
/// Signed out, any dashboard URL goes to `/login?next=<it>`, and signing in
/// comes back to it. [refresh] re-runs the guard; the app passes the auth
/// state stream, a test passes a notifier.
GoRouter buildRouter({
  required bool Function() signedIn,
  required Listenable refresh,
  required WidgetBuilder login,
  required HomeBuilder home,
  required WidgetBuilder resetPassword,

  /// True between opening a password-reset link and saving the new
  /// password. The link signs the user in; until they have chosen a
  /// password, nothing else in the dashboard is where they should be.
  bool Function()? recovering,
  String initialLocation = '/projects',
}) {
  Page<void> homePage(BuildContext context, GoRouterState state) {
    final location = DashboardLocation.parse(state.uri);
    if (location == null) {
      return MaterialPage(key: state.pageKey, child: const _NotFound());
    }
    return NoTransitionPage(
      key: _homeKey,
      child: home(context, location, (to) => GoRouter.of(context).go(to.path)),
    );
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refresh,
    redirect: (context, state) {
      final atLogin = state.uri.path == '/login';
      if (!signedIn()) {
        if (atLogin) return null;
        final here = state.uri.toString();
        return Uri(
          path: '/login',
          queryParameters: here == '/' ? null : {'next': here},
        ).toString();
      }
      final atReset = state.uri.path == '/reset-password';
      if (recovering?.call() ?? false) {
        return atReset ? null : '/reset-password';
      }
      if (atReset) return '/projects';
      if (atLogin) return _safeNext(state.uri.queryParameters['next']);
      if (state.uri.path == '/' || state.uri.path.isEmpty) return '/projects';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: login(context)),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: resetPassword(context)),
      ),
      GoRoute(path: '/', redirect: (_, _) => '/projects'),
      for (final path in const [
        '/projects',
        '/projects/new',
        '/settings',
        '/status',
        '/p/:projectId',
        '/p/:projectId/status',
        '/p/:projectId/settings',
        '/p/:projectId/c/:commentId',
      ])
        GoRoute(path: path, pageBuilder: homePage),
    ],
    errorPageBuilder: (context, state) =>
        MaterialPage(key: state.pageKey, child: const _NotFound()),
  );
}

/// Only a path inside the dashboard. `next` arrives in a URL anyone can
/// craft, so an absolute URL or a protocol-relative one is dropped.
String _safeNext(String? next) {
  if (next == null) return '/projects';
  final uri = Uri.tryParse(next);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return '/projects';
  if (!next.startsWith('/') || next.startsWith('//')) return '/projects';
  if (uri.path == '/login') return '/projects';
  return DashboardLocation.parse(uri) == null ? '/projects' : next;
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.page,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Page not found', style: T.heading),
            const SizedBox(height: 8),
            Text(
              'Nothing lives at this address.',
              style: T.supporting.copyWith(color: T.text3),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => GoRouter.of(context).go('/projects'),
              child: const Text('Go to Projects'),
            ),
          ],
        ),
      ),
    );
  }
}

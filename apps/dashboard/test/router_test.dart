import 'package:dashboard/src/routing/location.dart';
import 'package:dashboard/src/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Stands in for HomeScreen: shows where it is, and counts how often it was
/// created, which is how the tests see that a URL change kept its state.
class _Probe extends StatefulWidget {
  const _Probe({required this.location, required this.navigate});
  final DashboardLocation location;
  final void Function(DashboardLocation) navigate;

  static int created = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created++;
  }

  @override
  Widget build(BuildContext context) => Text('at ${widget.location.path}');
}

class _Auth extends ChangeNotifier {
  bool signedIn = false;
  bool recovering = false;
  void set(bool v) {
    signedIn = v;
    notifyListeners();
  }
}

Future<(GoRouter, _Auth)> _pump(
  WidgetTester tester, {
  required String at,
  bool signedIn = true,
}) async {
  _Probe.created = 0;
  final auth = _Auth()..signedIn = signedIn;
  final router = buildRouter(
    initialLocation: at,
    signedIn: () => auth.signedIn,
    recovering: () => auth.recovering,
    refresh: auth,
    login: (_) => const Text('login page'),
    resetPassword: (_) => const Text('reset page'),
    home: (context, location, navigate) =>
        _Probe(location: location, navigate: navigate),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return (router, auth);
}

String _where(GoRouter r) =>
    r.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('/ opens the project list', (tester) async {
    final (r, _) = await _pump(tester, at: '/');
    expect(_where(r), '/projects');
    expect(find.text('at /projects'), findsOneWidget);
  });

  testWidgets('a deep link opens that comment', (tester) async {
    final (r, _) = await _pump(tester, at: '/p/abc/c/42?status=resolved');
    expect(find.text('at /p/abc/c/42?status=resolved'), findsOneWidget);
    expect(_where(r), '/p/abc/c/42?status=resolved');
  });

  testWidgets('signed out, a deep link goes to login and comes back after', (
    tester,
  ) async {
    final (r, auth) = await _pump(tester, at: '/p/abc/c/42', signedIn: false);
    expect(find.text('login page'), findsOneWidget);
    expect(Uri.parse(_where(r)).path, '/login');
    expect(Uri.parse(_where(r)).queryParameters['next'], '/p/abc/c/42');

    auth.set(true);
    await tester.pumpAndSettle();
    expect(find.text('at /p/abc/c/42'), findsOneWidget);
  });

  testWidgets('signing out from anywhere lands on login', (tester) async {
    final (r, auth) = await _pump(tester, at: '/p/abc');
    auth.set(false);
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
    expect(find.text('at /p/abc'), findsNothing);
    expect(Uri.parse(_where(r)).path, '/login');
  });

  testWidgets('signed in, /login goes on to the dashboard', (tester) async {
    final (r, _) = await _pump(tester, at: '/login?next=%2Fp%2Fabc');
    expect(_where(r), '/p/abc');
  });

  testWidgets('a next that leaves the dashboard is ignored', (tester) async {
    final (r, _) = await _pump(
      tester,
      at: '/login?next=https%3A%2F%2Fevil.example',
    );
    expect(_where(r), '/projects');
  });

  testWidgets('a path that is no place shows a 404 with a way back', (
    tester,
  ) async {
    await _pump(tester, at: '/nowhere/at/all');
    expect(find.text('Page not found'), findsOneWidget);
    await tester.tap(find.text('Go to Projects'));
    await tester.pumpAndSettle();
    expect(find.text('at /projects'), findsOneWidget);
  });

  testWidgets('moving between dashboard URLs keeps the same screen state', (
    tester,
  ) async {
    final (r, _) = await _pump(tester, at: '/p/abc');
    expect(_Probe.created, 1);

    final probe = tester.widget<_Probe>(find.byType(_Probe));
    probe.navigate(const DashboardLocation.board('abc', commentId: '7'));
    await tester.pumpAndSettle();
    probe.navigate(const DashboardLocation.settings(projectId: 'abc'));
    await tester.pumpAndSettle();

    expect(find.text('at /p/abc/settings'), findsOneWidget);
    expect(_where(r), '/p/abc/settings');
    expect(_Probe.created, 1, reason: 'the list and its scroll survive');
  });

  testWidgets('a reset link lands on the new-password screen, from anywhere', (
    tester,
  ) async {
    final (r, auth) = await _pump(tester, at: '/p/abc');
    auth
      ..recovering = true
      ..set(true);
    await tester.pumpAndSettle();
    expect(_where(r), '/reset-password');
    expect(find.text('reset page'), findsOneWidget);
  });

  testWidgets('while recovering, no other page is reachable', (tester) async {
    final (r, auth) = await _pump(tester, at: '/projects');
    auth
      ..recovering = true
      ..set(true);
    await tester.pumpAndSettle();
    r.go('/settings');
    await tester.pumpAndSettle();
    expect(_where(r), '/reset-password');
  });

  testWidgets('once the password is set, the reset page is left', (
    tester,
  ) async {
    final (r, auth) = await _pump(tester, at: '/projects');
    auth
      ..recovering = true
      ..set(true);
    await tester.pumpAndSettle();
    auth
      ..recovering = false
      ..set(true);
    await tester.pumpAndSettle();
    expect(_where(r), '/projects');
  });

  testWidgets('signed out, the reset page is not a way in', (tester) async {
    final (r, _) = await _pump(tester, at: '/reset-password', signedIn: false);
    expect(_where(r), startsWith('/login'));
  });
}

import 'package:dashboard/src/data/auth_gateway.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:dashboard/src/widgets/session_expired.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec §5.6 row 14: a session that expires mid-triage asks to log in over
/// the page, so what was on it (an open comment, a half-typed note) is still
/// there afterwards. A redirect to /login threw that away.
class _Auth implements AuthGateway {
  _Auth(this.answer);
  final AuthOutcome answer;
  final logins = <(String, String)>[];

  @override
  Future<AuthOutcome> logIn({
    required String email,
    required String password,
  }) async {
    logins.add((email, password));
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Page extends StatefulWidget {
  const _Page();
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final note = TextEditingController(text: 'half-typed note');
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: TextField(controller: note)),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required bool expired,
  required _Auth auth,
  VoidCallback? onRestored,
  VoidCallback? onLogOut,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => SessionExpiredOverlay(
        expired: expired,
        email: 'dev@example.com',
        auth: auth,
        onRestored: onRestored ?? () {},
        onLogOut: onLogOut ?? () {},
        child: child!,
      ),
      home: const _Page(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('not expired: nothing over the page', (tester) async {
    await _pump(tester, expired: false, auth: _Auth(const SignedIn()));
    expect(find.text('Your session expired'), findsNothing);
  });

  testWidgets('expired: asks over the page, and the page is still there', (
    tester,
  ) async {
    await _pump(tester, expired: true, auth: _Auth(const SignedIn()));
    expect(find.text('Your session expired'), findsOneWidget);
    expect(find.text('half-typed note'), findsOneWidget);
    expect(find.text('dev@example.com'), findsWidgets);
  });

  testWidgets('logging back in restores, with the same email', (tester) async {
    var restored = 0;
    final auth = _Auth(const SignedIn());
    await _pump(
      tester,
      expired: true,
      auth: auth,
      onRestored: () => restored++,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(GPasswordField),
        matching: find.byType(TextField),
      ),
      'hunter22',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(GButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(auth.logins.single, ('dev@example.com', 'hunter22'));
    expect(restored, 1);
  });

  testWidgets('a wrong password says so and stays', (tester) async {
    var restored = 0;
    await _pump(
      tester,
      expired: true,
      auth: _Auth(const WrongCredentials()),
      onRestored: () => restored++,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(GPasswordField),
        matching: find.byType(TextField),
      ),
      'nope',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(GButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is wrong.'), findsOneWidget);
    expect(restored, 0);
  });

  testWidgets('Log out instead is offered', (tester) async {
    var out = 0;
    await _pump(
      tester,
      expired: true,
      auth: _Auth(const SignedIn()),
      onLogOut: () => out++,
    );
    await tester.tap(find.text('Log out instead'));
    expect(out, 1);
  });
}

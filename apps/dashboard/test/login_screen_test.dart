import 'dart:async';

import 'package:dashboard/src/data/auth_gateway.dart';
import 'package:dashboard/src/screens/login_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Figma login frame (Downloads/Cashflow/Home.png, D75): one form,
/// "Login or sign up", Continue. Sign-up happens from the same form.
class _FakeAuth implements AuthGateway {
  _FakeAuth({this.login = const SignedIn(), this.create = const SignedIn()});
  AuthOutcome login;
  AuthOutcome create;
  Completer<void>? gate;
  final calls = <(String, String, String)>[];

  @override
  Future<AuthOutcome> logIn({
    required String email,
    required String password,
  }) async {
    calls.add(('login', email, password));
    if (gate != null) await gate!.future;
    return login;
  }

  @override
  Future<AuthOutcome> createAccount({
    required String email,
    required String password,
  }) async {
    calls.add(('create', email, password));
    return create;
  }

  @override
  Future<AuthOutcome> sendPasswordReset({required String email}) async {
    calls.add(('reset', email, ''));
    return ResetSent(email);
  }

  @override
  Future<AuthOutcome> setNewPassword({required String password}) async {
    calls.add(('set', '', password));
    return const SignedIn();
  }

  @override
  Future<AuthOutcome> saveName(String name) async => const SignedIn();
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAuth auth, {
  Size size = const Size(1440, 752),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: LoginScreen(auth: auth),
    ),
  );
}

Finder _input(String hint) => find.descendant(
  of: find.byWidgetPredicate((w) => w is GField && w.hint == hint),
  matching: find.byType(TextField),
);

Finder get _continue => find.widgetWithText(GButton, 'Continue');

GButton _button(WidgetTester tester) => tester.widget<GButton>(_continue);

Future<void> _fill(WidgetTester tester, String email, String password) async {
  await tester.enterText(_input('Email'), email);
  await tester.enterText(_input('Password'), password);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(_continue);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the frame: domain, heading, two fields, Continue, watermark', (
    tester,
  ) async {
    await _pump(tester, _FakeAuth());
    expect(find.text('guidester.in'), findsOneWidget);
    expect(find.text('Login or sign up'), findsOneWidget);
    expect(_input('Email'), findsOneWidget);
    expect(_input('Password'), findsOneWidget);
    expect(_continue, findsOneWidget);
    expect(find.text('Where tester feedback lands.'), findsOneWidget);
  });

  testWidgets('Continue stays disabled until both fields have something', (
    tester,
  ) async {
    await _pump(tester, _FakeAuth());
    expect(_button(tester).onPressed, isNull);
    await tester.enterText(_input('Email'), 'a@b.co');
    await tester.pump();
    expect(_button(tester).onPressed, isNull);
    await tester.enterText(_input('Password'), 'x');
    await tester.pump();
    expect(_button(tester).onPressed, isNotNull);
  });

  testWidgets('a malformed email is caught before sending', (tester) async {
    final auth = _FakeAuth();
    await _pump(tester, auth);
    await _fill(tester, 'dev@', 'hunter22');
    await _submit(tester);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('email is trimmed; Enter in the password field submits', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await _pump(tester, auth);
    await _fill(tester, '  Dev@Example.com ', 'hunter22');
    await tester.showKeyboard(_input('Password'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(auth.calls.single, ('login', 'Dev@Example.com', 'hunter22'));
  });

  testWidgets('Enter then click while in flight sends once', (tester) async {
    final auth = _FakeAuth()..gate = Completer<void>();
    await _pump(tester, auth);
    await _fill(tester, 'a@b.co', 'hunter22');
    await tester.showKeyboard(_input('Password'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // Busy swaps the label for a spinner, so find the button itself.
    await tester.tap(find.byWidgetPredicate((w) => w is GButton && w.expand));
    await tester.pump();
    expect(auth.calls, hasLength(1));
    auth.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('wrong credentials say so', (tester) async {
    final auth = _FakeAuth(login: const WrongCredentials());
    await _pump(tester, auth);
    await _fill(tester, 'a@b.co', 'hunter22');
    await _submit(tester);
    expect(find.text('Email or password is wrong.'), findsOneWidget);
  });

  testWidgets('create account is always one tap away, and back', (
    tester,
  ) async {
    final auth = _FakeAuth(create: const ConfirmEmail('a@b.co'));
    await _pump(tester, auth);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    expect(find.widgetWithText(GButton, 'Create account'), findsOneWidget);
    await _fill(tester, 'a@b.co', 'hunter22');
    await tester.tap(find.widgetWithText(GButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(auth.calls.single, ('create', 'a@b.co', 'hunter22'));
    expect(find.textContaining('Check a@b.co'), findsOneWidget);
    await tester.tap(find.text('Have an account? Log in'));
    await tester.pump();
    expect(_continue, findsOneWidget);
  });

  testWidgets('create account refuses a short password before sending', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await _pump(tester, auth);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await _fill(tester, 'a@b.co', '123');
    await tester.tap(find.widgetWithText(GButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 6 characters.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('create account for an existing address says so', (tester) async {
    final auth = _FakeAuth(create: const AlreadyRegistered());
    await _pump(tester, auth);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await _fill(tester, 'a@b.co', 'hunter22');
    await tester.tap(find.widgetWithText(GButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already has an account'), findsOneWidget);
  });

  testWidgets('the eye shows and hides the password', (tester) async {
    await _pump(tester, _FakeAuth());
    bool obscured() => tester.widget<TextField>(_input('Password')).obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.bySemanticsLabel('Show password'));
    await tester.pump();
    expect(obscured(), isFalse);
    await tester.tap(find.bySemanticsLabel('Hide password'));
    await tester.pump();
    expect(obscured(), isTrue);
  });

  testWidgets('forgot password needs an email first', (tester) async {
    final auth = _FakeAuth();
    await _pump(tester, auth);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.text('Enter your email to get a reset link.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('forgot password sends a link to the typed email', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await _pump(tester, auth);
    await tester.enterText(_input('Email'), ' a@b.co ');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(auth.calls.single, ('reset', 'a@b.co', ''));
    // Supabase does not say whether the address has an account, and neither
    // does this sentence.
    expect(
      find.text('If a@b.co has an account, a reset link is on its way.'),
      findsOneWidget,
    );
  });

  testWidgets('a field-level failure lands under its field', (tester) async {
    final auth = _FakeAuth(
      login: const AuthFailed(
        'Confirm your email first. The link is in your inbox.',
        field: AuthField.email,
      ),
    );
    await _pump(tester, auth);
    await _fill(tester, 'a@b.co', 'hunter22');
    await _submit(tester);
    final field = tester.widget<GField>(
      find.byWidgetPredicate((w) => w is GField && w.hint == 'Email'),
    );
    expect(field.error, contains('Confirm your email'));
  });

  testWidgets('no network is said plainly', (tester) async {
    final auth = _FakeAuth(
      login: const AuthFailed("Can't reach the server. Check your connection."),
    );
    await _pump(tester, auth);
    await _fill(tester, 'a@b.co', 'hunter22');
    await _submit(tester);
    expect(
      find.text("Can't reach the server. Check your connection."),
      findsOneWidget,
    );
  });

  testWidgets('360 px phone: no overflow, 44 px controls', (tester) async {
    await _pump(tester, _FakeAuth(), size: const Size(360, 740));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(_continue).height, greaterThanOrEqualTo(44));
  });
}

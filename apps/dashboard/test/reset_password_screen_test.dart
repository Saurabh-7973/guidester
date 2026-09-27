import 'package:dashboard/src/data/auth_gateway.dart';
import 'package:dashboard/src/screens/reset_password_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth implements AuthGateway {
  _Auth(this.answer);
  final AuthOutcome answer;
  final set = <String>[];

  @override
  Future<AuthOutcome> setNewPassword({required String password}) async {
    set.add(password);
    return answer;
  }

  @override
  Future<AuthOutcome> logIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<AuthOutcome> createAccount({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<AuthOutcome> sendPasswordReset({required String email}) =>
      throw UnimplementedError();

  @override
  Future<AuthOutcome> saveName(String name) async => const SignedIn();
}

Future<void> _pump(WidgetTester tester, _Auth auth, VoidCallback onDone) {
  tester.view.physicalSize = const Size(1440, 752);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ResetPasswordScreen(auth: auth, onDone: onDone),
    ),
  );
}

Finder get _field => find.byType(TextField);
Finder get _save => find.widgetWithText(GButton, 'Save password');

void main() {
  testWidgets('a short password is refused before sending', (tester) async {
    final auth = _Auth(const SignedIn());
    await _pump(tester, auth, () {});
    await tester.enterText(_field, '123');
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    expect(find.text('Use at least 6 characters.'), findsOneWidget);
    expect(auth.set, isEmpty);
  });

  testWidgets('saving hands over to the app', (tester) async {
    var done = 0;
    final auth = _Auth(const SignedIn());
    await _pump(tester, auth, () => done++);
    await tester.enterText(_field, 'hunter22');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(auth.set, ['hunter22']);
    expect(done, 1);
  });

  testWidgets('a failure is said, and the screen stays', (tester) async {
    var done = 0;
    final auth = _Auth(
      const AuthFailed(
        'Password should be at least 6 characters.',
        field: AuthField.password,
      ),
    );
    await _pump(tester, auth, () => done++);
    await tester.enterText(_field, 'hunter22');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 6'), findsOneWidget);
    expect(done, 0);
  });

  testWidgets('it has the eye too', (tester) async {
    await _pump(tester, _Auth(const SignedIn()), () {});
    expect(find.bySemanticsLabel('Show password'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';

import '../data/auth_gateway.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';

/// The Figma login frame (D75): one form, "Login or sign up", Continue.
///
/// Where the user lands after signing in is the router's job
/// (`/login?next=`); this screen only has to succeed. The same form creates
/// an account ("New here?") and asks for a reset link ("Forgot password?").
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthGateway auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _creating = false;
  String? _emailError;
  String? _passwordError;
  AuthOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    // Continue is disabled until both fields are non-empty, as in the frame,
    // which needs the button to rebuild as they are typed into.
    // Only an edit clears a field's error: the controller also notifies when
    // the selection moves, and a tap elsewhere moves it.
    _clearOnEdit(_email, () => _emailError = null);
    _clearOnEdit(_password, () => _passwordError = null);
  }

  void _clearOnEdit(TextEditingController c, VoidCallback clear) {
    var last = c.text;
    c.addListener(() {
      if (c.text == last) return;
      last = c.text;
      setState(clear);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  void _toggleMode() => setState(() {
    _creating = !_creating;
    _outcome = null;
    _emailError = null;
    _passwordError = null;
  });

  Future<void> _forgot() async {
    if (_busy) return;
    final email = _email.text.trim();
    final at = email.indexOf('@');
    if (at < 1 || at == email.length - 1) {
      setState(() => _emailError = 'Enter your email to get a reset link.');
      return;
    }
    setState(() {
      _busy = true;
      _outcome = null;
    });
    final outcome = await widget.auth.sendPasswordReset(email: email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  bool _validate({required bool creating}) {
    final email = _email.text.trim();
    final at = email.indexOf('@');
    String? e;
    String? p;
    if (at < 1 || at == email.length - 1) e = 'Enter a valid email address.';
    if (creating && _password.text.length < 6) {
      p = 'Use at least 6 characters.';
    }
    setState(() {
      _emailError = e;
      _passwordError = p;
    });
    return e == null && p == null;
  }

  Future<void> _run({required bool creating}) async {
    if (!_canSubmit || !_validate(creating: creating)) return;
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    final outcome = creating
        ? await widget.auth.createAccount(email: email, password: password)
        : await widget.auth.logIn(email: email, password: password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome case AuthFailed(:final message, field: final field?)) {
        if (field == AuthField.email) _emailError = message;
        if (field == AuthField.password) _passwordError = message;
      } else {
        _outcome = outcome;
      }
    });
    // SignedIn needs nothing here: the auth listener re-runs the router guard.
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: T.page,
      body: Stack(
        children: [
          const _Watermark(),
          Positioned(
            left: 40,
            top: 40,
            // §8: text, not a link. The domain does not resolve.
            child: Text(
              'guidester.in',
              style: T.supporting.copyWith(color: T.text3),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: (width - 32).clamp(0.0, 250.0),
                child: AutofillGroup(child: _form()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Login or sign up',
          textAlign: TextAlign.center,
          style: T.heading,
        ),
        const SizedBox(height: 42),
        GField(
          controller: _email,
          hint: 'Email',
          error: _emailError,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        GPasswordField(
          controller: _password,
          focusNode: _passwordFocus,
          error: _passwordError,
          enabled: !_busy,
          newPassword: _creating,
          onSubmitted: (_) => _run(creating: _creating),
        ),
        if (!_creating)
          Align(
            alignment: Alignment.centerRight,
            child: _TextLink(
              label: 'Forgot password?',
              onTap: _busy ? null : _forgot,
            ),
          ),
        SizedBox(height: _creating ? 24 : 12),
        GButton(
          label: _creating ? 'Create account' : 'Continue',
          onPressed: _canSubmit ? () => _run(creating: _creating) : null,
          busy: _busy,
          expand: true,
        ),
        ..._afterContinue(),
        const SizedBox(height: 16),
        Center(
          child: _TextLink(
            label: _creating
                ? 'Have an account? Log in'
                : 'New here? Create an account',
            onTap: _busy ? null : _toggleMode,
          ),
        ),
      ],
    );
  }

  List<Widget> _afterContinue() {
    final outcome = _outcome;
    Widget line(String text, Color colour) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: T.supporting.copyWith(color: colour),
        ),
      ),
    );
    return switch (outcome) {
      WrongCredentials() => [line('Email or password is wrong.', T.red)],
      ResetSent(:final email) => [
        line('If $email has an account, a reset link is on its way.', T.text2),
      ],
      ConfirmEmail(:final email) => [
        line('Check $email for a confirmation link, then log in.', T.text2),
      ],
      AlreadyRegistered() => [
        line('This email already has an account. Check the password.', T.red),
      ],
      AuthFailed(:final message) => [line(message, T.red)],
      _ => const [],
    };
  }
}

/// A quiet text button: the frame's secondary links are text, not buttons.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Text(label, style: T.supporting.copyWith(color: T.text2)),
        ),
      ),
    );
  }
}

/// §8, and §9 correction 3: the frame's "Better Feedback" is the first line
/// of the `feedback` package's own pub.dev description, so the wordmark says
/// something of ours instead.
class _Watermark extends StatelessWidget {
  const _Watermark();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: -20,
      // FittedBox with BoxFit.none lays the text out at its natural size and
      // lets the ClipRect trim it off both edges, as in the frame.
      child: ExcludeSemantics(
        child: ClipRect(
          child: SizedBox(
            height: 150,
            child: FittedBox(
              fit: BoxFit.none,
              alignment: Alignment.center,
              child: Text(
                'Where tester feedback lands.',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: T.family,
                  fontSize: 120,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  // Barely there: it must never compete with the form.
                  color: T.text1.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

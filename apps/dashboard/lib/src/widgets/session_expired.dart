import 'package:flutter/material.dart';

import '../data/auth_gateway.dart';
import '../theme/tokens.dart';
import 'controls.dart';

/// Spec §5.6 row 14. When a session expires on its own (not a Log out), the
/// page stays where it is and a small login sits over it; logging back in
/// removes it and nothing on the page was lost. A redirect to /login threw
/// away the open comment and anything half-typed.
class SessionExpiredOverlay extends StatelessWidget {
  const SessionExpiredOverlay({
    super.key,
    required this.expired,
    required this.email,
    required this.auth,
    required this.onRestored,
    required this.onLogOut,
    required this.child,
  });

  final bool expired;
  final String? email;
  final AuthGateway auth;
  final VoidCallback onRestored;
  final VoidCallback onLogOut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Kept in the tree either way, so its state survives.
        ExcludeSemantics(
          excluding: expired,
          child: AbsorbPointer(absorbing: expired, child: child),
        ),
        if (expired) ...[
          ModalBarrier(color: T.page.withValues(alpha: 0.7)),
          // This sits in MaterialApp.builder, above the Navigator and so
          // above its Overlay; text fields need one for their selection
          // handles and toolbar, so the dialog brings its own.
          Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Center(
                  child: Material(
                    type: MaterialType.transparency,
                    child: _Reauth(
                      email: email,
                      auth: auth,
                      onRestored: onRestored,
                      onLogOut: onLogOut,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Reauth extends StatefulWidget {
  const _Reauth({
    required this.email,
    required this.auth,
    required this.onRestored,
    required this.onLogOut,
  });

  final String? email;
  final AuthGateway auth;
  final VoidCallback onRestored;
  final VoidCallback onLogOut;

  @override
  State<_Reauth> createState() => _ReauthState();
}

class _ReauthState extends State<_Reauth> {
  late final _email = TextEditingController(text: widget.email ?? '');
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.auth.logIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case SignedIn():
        widget.onRestored();
      case WrongCredentials():
        setState(() => _error = 'Email or password is wrong.');
      case AuthFailed(:final message):
        setState(() => _error = message);
      default:
        setState(() => _error = 'Something went wrong. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: T.surface1,
        borderRadius: BorderRadius.circular(T.rDialog),
        border: Border.all(color: T.borderDefault),
      ),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Your session expired', style: T.heading),
            const SizedBox(height: 8),
            Text(
              'Log in again to carry on. Everything on the page is kept.',
              style: T.supporting.copyWith(color: T.text2),
            ),
            const SizedBox(height: 20),
            GField(
              controller: _email,
              hint: 'Email',
              enabled: !_busy,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 12),
            GPasswordField(
              controller: _password,
              autofocus: true,
              enabled: !_busy,
              error: _error,
              onSubmitted: (_) => _logIn(),
            ),
            const SizedBox(height: 20),
            GButton(
              label: 'Log in',
              busy: _busy,
              expand: true,
              onPressed: _password.text.isEmpty ? null : _logIn,
            ),
            const SizedBox(height: 8),
            Center(
              child: GButton(
                label: 'Log out instead',
                kind: GButtonKind.ghost,
                onPressed: _busy ? null : widget.onLogOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

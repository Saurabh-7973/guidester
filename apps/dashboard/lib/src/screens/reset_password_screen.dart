import 'package:flutter/material.dart';

import '../data/auth_gateway.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';

/// Where a password-reset link lands. Drawn like the login frame (D75).
///
/// The link has already signed the user in; [onDone] tells the app the
/// password is set, and the router moves on.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.auth,
    required this.onDone,
  });

  final AuthGateway auth;
  final VoidCallback onDone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Only an edit clears the error. The controller also notifies when the
    // selection moves, which a tap on Save does, and that wiped the error
    // Save had just set.
    var last = _password.text;
    _password.addListener(() {
      if (_password.text == last) return;
      last = _password.text;
      setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_password.text.length < 6) {
      setState(() => _error = 'Use at least 6 characters.');
      return;
    }
    setState(() => _busy = true);
    final outcome = await widget.auth.setNewPassword(password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case SignedIn():
        widget.onDone();
      case AuthFailed(:final message):
        setState(() => _error = message);
      default:
        setState(() => _error = 'Something went wrong. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: T.page,
      body: Stack(
        children: [
          Positioned(
            left: 40,
            top: 40,
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
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Set a new password',
                        textAlign: TextAlign.center,
                        style: T.heading,
                      ),
                      const SizedBox(height: 42),
                      GPasswordField(
                        controller: _password,
                        hint: 'New password',
                        error: _error,
                        enabled: !_busy,
                        autofocus: true,
                        newPassword: true,
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 24),
                      GButton(
                        label: 'Save password',
                        onPressed: _password.text.isEmpty ? null : _save,
                        busy: _busy,
                        expand: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

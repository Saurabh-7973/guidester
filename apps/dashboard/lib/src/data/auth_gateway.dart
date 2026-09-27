import 'package:supabase_flutter/supabase_flutter.dart';

/// What a login or signup attempt came to, in words a person can act on.
sealed class AuthOutcome {
  const AuthOutcome();
}

class SignedIn extends AuthOutcome {
  const SignedIn();
}

/// The self-hoster's project requires email confirmation.
class ConfirmEmail extends AuthOutcome {
  const ConfirmEmail(this.email);
  final String email;
}

class AlreadyRegistered extends AuthOutcome {
  const AlreadyRegistered();
}

/// No account with this email, or the wrong password. Supabase answers both
/// the same way on purpose, so the screen offers both next steps.
class WrongCredentials extends AuthOutcome {
  const WrongCredentials();
}

/// A reset link was requested. Supabase does not say whether the address has
/// an account, so neither does anything that shows this.
class ResetSent extends AuthOutcome {
  const ResetSent(this.email);
  final String email;
}

enum AuthField { email, password }

class AuthFailed extends AuthOutcome {
  const AuthFailed(this.message, {this.field});
  final String message;

  /// The field the message belongs under, or null for the form as a whole.
  final AuthField? field;
}

/// The one seam between the login screen and Supabase, so the screen's tests
/// and golden render the real widget rather than a copy of it.
abstract interface class AuthGateway {
  Future<AuthOutcome> logIn({required String email, required String password});
  Future<AuthOutcome> createAccount({
    required String email,
    required String password,
  });

  /// Mails a link that signs the user in for one purpose: choosing a new
  /// password on the reset screen.
  Future<AuthOutcome> sendPasswordReset({required String email});

  /// Sets the password of the user the reset link signed in.
  Future<AuthOutcome> setNewPassword({required String password});

  /// The name shown on the user chip, kept in the account's metadata.
  Future<AuthOutcome> saveName(String name);
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth, {required this.redirectTo});
  final GoTrueClient _auth;

  /// Where the reset link lands: this dashboard, wherever it is served. The
  /// address must also be in the Supabase project's allowed redirect URLs.
  final String redirectTo;

  @override
  Future<AuthOutcome> sendPasswordReset({required String email}) async {
    try {
      await _auth.resetPasswordForEmail(email, redirectTo: redirectTo);
      return ResetSent(email);
    } catch (e) {
      return describeAuthError(e);
    }
  }

  @override
  Future<AuthOutcome> saveName(String name) async {
    try {
      await _auth.updateUser(UserAttributes(data: {'name': name}));
      return const SignedIn();
    } catch (e) {
      return describeAuthError(e);
    }
  }

  @override
  Future<AuthOutcome> setNewPassword({required String password}) async {
    try {
      await _auth.updateUser(UserAttributes(password: password));
      return const SignedIn();
    } catch (e) {
      return describeAuthError(e);
    }
  }

  @override
  Future<AuthOutcome> logIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
      return const SignedIn();
    } catch (e) {
      return describeAuthError(e);
    }
  }

  @override
  Future<AuthOutcome> createAccount({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signUp(email: email, password: password);
      return describeSignUp(response, email);
    } catch (e) {
      return describeAuthError(e);
    }
  }
}

/// With confirmations on, Supabase answers a signup for an address that
/// already has an account with a user and no error, so that the endpoint
/// cannot be used to test which addresses exist. The tell is an empty
/// identities list. Telling the person who typed the address is fine; the
/// alternative sends them to an inbox that will never get a mail.
AuthOutcome describeSignUp(AuthResponse response, String email) {
  if (response.session != null) return const SignedIn();
  final identities = response.user?.identities;
  if (identities != null && identities.isEmpty) {
    return const AlreadyRegistered();
  }
  return ConfirmEmail(email);
}

AuthOutcome describeAuthError(Object error) {
  if (error is AuthRetryableFetchException) {
    return const AuthFailed("Can't reach the server. Check your connection.");
  }
  if (error is AuthWeakPasswordException) {
    return AuthFailed(error.message, field: AuthField.password);
  }
  if (error is AuthException) {
    return switch (error.code) {
      'invalid_credentials' => const WrongCredentials(),
      'email_not_confirmed' => const AuthFailed(
        'Confirm your email first. The link is in your inbox.',
        field: AuthField.email,
      ),
      'user_already_exists' || 'email_exists' => const AlreadyRegistered(),
      'signup_disabled' || 'email_provider_disabled' => const AuthFailed(
        'Creating accounts is turned off on this server. Ask whoever runs it.',
      ),
      'validation_failed' => const AuthFailed(
        'Enter a valid email address.',
        field: AuthField.email,
      ),
      'same_password' => const AuthFailed(
        'That is the current password. Choose a different one.',
        field: AuthField.password,
      ),
      'over_request_rate_limit' || 'over_email_send_rate_limit' =>
        const AuthFailed('Too many attempts. Wait a minute and try again.'),
      _ => AuthFailed(
        error.message.isEmpty
            ? 'Something went wrong. Try again.'
            : error.message,
      ),
    };
  }
  return const AuthFailed('Something went wrong. Try again.');
}

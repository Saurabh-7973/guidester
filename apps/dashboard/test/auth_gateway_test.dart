import 'package:dashboard/src/data/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user({List<UserIdentity>? identities}) => User(
  id: 'u',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-09-26T00:00:00Z',
  identities: identities,
);

UserIdentity _identity() => const UserIdentity(
  id: 'i',
  userId: 'u',
  identityData: {},
  identityId: 'i',
  provider: 'email',
  createdAt: null,
  lastSignInAt: null,
);

Session _session() => Session(
  accessToken: 'a',
  tokenType: 'bearer',
  user: _user(identities: [_identity()]),
);

AuthFailed _failed(Object error) => describeAuthError(error) as AuthFailed;

void main() {
  group('describeAuthError', () {
    test('wrong credentials are their own outcome', () {
      // Supabase answers "no such account" and "wrong password" alike, so the
      // screen offers both next steps, and needs to know this was the case.
      expect(
        describeAuthError(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        isA<WrongCredentials>(),
      );
    });

    test('unconfirmed email says what to do, under the email', () {
      final o = _failed(
        const AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
      );
      expect(o.message, contains('Confirm'));
      expect(o.field, AuthField.email);
    });

    test('weak password is attached to the password field', () {
      final o = _failed(
        AuthWeakPasswordException(
          message: 'Password should be at least 6 characters.',
          statusCode: '422',
          reasons: const ['length'],
        ),
      );
      expect(o.field, AuthField.password);
      expect(o.message, contains('6'));
    });

    test('existing user on create account', () {
      expect(
        describeAuthError(
          const AuthApiException(
            'User already registered',
            statusCode: '422',
            code: 'user_already_exists',
          ),
        ),
        isA<AlreadyRegistered>(),
      );
    });

    test('signups turned off by the self-hoster', () {
      final o = _failed(
        const AuthApiException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_disabled',
        ),
      );
      expect(o.message, contains('turned off'));
    });

    test('rate limit', () {
      final o = _failed(
        const AuthApiException(
          'Email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      );
      expect(o.message, contains('Too many'));
    });

    test('no network is the server, not the user', () {
      final o = _failed(
        AuthRetryableFetchException(message: 'ClientException'),
      );
      expect(o.message, "Can't reach the server. Check your connection.");
    });

    test('anything else gets a plain sentence, never a stack', () {
      expect(
        _failed(StateError('boom')).message,
        'Something went wrong. Try again.',
      );
    });
  });

  group('describeSignUp', () {
    test('a session means signed in', () {
      expect(
        describeSignUp(AuthResponse(session: _session()), 'a@b.co'),
        isA<SignedIn>(),
      );
    });

    test('no session means confirm the email', () {
      final o = describeSignUp(
        AuthResponse(user: _user(identities: [_identity()])),
        'a@b.co',
      );
      expect(o, isA<ConfirmEmail>());
      expect((o as ConfirmEmail).email, 'a@b.co');
    });

    test('empty identities is an existing account in disguise', () {
      expect(
        describeSignUp(
          AuthResponse(user: _user(identities: const [])),
          'a@b.co',
        ),
        isA<AlreadyRegistered>(),
      );
    });
  });
}

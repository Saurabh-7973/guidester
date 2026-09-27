import 'package:dashboard/src/data/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a sign-out nobody asked for is an expiry, and keeps the email', () {
    final s = SessionState()
      ..onEvent(AuthChangeEvent.signedIn, 'dev@example.com')
      ..onEvent(AuthChangeEvent.signedOut, null);
    expect(s.expired, isTrue);
    expect(s.lastEmail, 'dev@example.com');
  });

  test('Log out is not an expiry', () {
    final s = SessionState()
      ..onEvent(AuthChangeEvent.signedIn, 'dev@example.com')
      ..loggingOut();
    s.onEvent(AuthChangeEvent.signedOut, null);
    expect(s.expired, isFalse);
  });

  test('signing back in clears it', () {
    final s = SessionState()
      ..onEvent(AuthChangeEvent.signedIn, 'dev@example.com')
      ..onEvent(AuthChangeEvent.signedOut, null)
      ..onEvent(AuthChangeEvent.signedIn, 'dev@example.com');
    expect(s.expired, isFalse);
  });

  test('a first visit, never signed in, is not an expiry', () {
    final s = SessionState()..onEvent(AuthChangeEvent.signedOut, null);
    expect(s.expired, isFalse);
  });

  test('a password reset link still means recovering', () {
    final s = SessionState()
      ..onEvent(AuthChangeEvent.passwordRecovery, 'dev@example.com');
    expect(s.recovering, isTrue);
    s.recoveryFinished();
    expect(s.recovering, isFalse);
  });
}

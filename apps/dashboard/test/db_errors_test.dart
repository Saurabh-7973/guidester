import 'package:dashboard/src/data/db_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Field-test code reading (24, 26 Sep): an expired session told the user
/// "You do not have access to this project's comments", which reads as a
/// permissions problem nobody can fix.
void main() {
  const expired = 'Your session expired. Log in again.';

  test('an expired JWT is an expired session', () {
    for (final code in ['PGRST301', 'PGRST303', '401']) {
      expect(
        describeDbError(PostgrestException(message: 'JWT expired', code: code)),
        expired,
        reason: code,
      );
    }
  });

  test('a refused row is still no access', () {
    expect(
      describeDbError(
        const PostgrestException(message: 'denied', code: '42501'),
      ),
      "You do not have access to this project's comments.",
    );
  });

  test('anything else is the connection, in plain words', () {
    expect(
      describeDbError(const PostgrestException(message: 'boom', code: '500')),
      'Could not reach the database. Check your connection.',
    );
  });

  test('a prefix names what was being done', () {
    expect(
      describeDbError(
        const PostgrestException(message: 'JWT expired', code: 'PGRST303'),
        doing: 'Could not load projects.',
      ),
      'Could not load projects. $expired',
    );
  });
}

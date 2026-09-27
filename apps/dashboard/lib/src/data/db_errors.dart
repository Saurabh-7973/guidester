import 'package:supabase_flutter/supabase_flutter.dart';

/// A database failure in words the person at the dashboard can act on.
///
/// [doing] names what was being attempted ("Could not load projects."), and
/// goes first.
String describeDbError(PostgrestException e, {String? doing}) {
  final why = switch (e.code) {
    // PostgREST's codes for a JWT that is missing, malformed or expired, and
    // the bare status a gateway sends when the body is not PostgREST's. An
    // expired session is by far the common case: a tab left open overnight.
    'PGRST301' ||
    'PGRST302' ||
    'PGRST303' ||
    '401' => 'Your session expired. Log in again.',
    '42501' => "You do not have access to this project's comments.",
    _ => 'Could not reach the database. Check your connection.',
  };
  return doing == null ? why : '$doing $why';
}

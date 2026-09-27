/// Build-time configuration.
///
/// Nothing here is a secret in the strict sense — the anon key is designed to
/// be shipped to browsers and is useless without a logged-in session, because
/// every table is behind row-level security. It is still passed at build time
/// rather than committed, so a fork or a screenshot of the repo never carries
/// one project's identifiers.
///
/// ```bash
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<anon key> \
///   --dart-define=PROJECT_ID=<project uuid>
/// ```
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Single project for v0. A projects list is v1.
  static const String projectId = String.fromEnvironment('PROJECT_ID');

  /// Where the SDK posts. Derived rather than configured: it is this same
  /// project's edge function, and a second dart-define for a value that can
  /// only ever be one thing is a way to get them out of step.
  static String get ingestEndpoint => '$supabaseUrl/functions/v1/ingest';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Human-readable list of what is missing, for the setup screen.
  ///
  /// `PROJECT_ID` is not in it any more. Since onboarding creates projects and
  /// the list reads them back, a build with no PROJECT_ID is a new account
  /// rather than a misconfiguration — and turning a first-run user away at a
  /// setup screen is the opposite of what onboarding is for.
  static List<String> get missing => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
  ];
}

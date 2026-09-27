/// What the problem cost the tester — the one question a tester can answer
/// accurately about their own report.
///
/// Not severity. "How bad is this" asks a tester to guess at a developer's
/// priorities; "could you keep using the app?" is a fact they were just living
/// through. It maps straight to triage order, which is what makes it worth the
/// only chip row the composer has.
///
/// Replaces the six issue-type chips (D51). Nine chips over a composer over a
/// keyboard leaves the app itself invisible, and the app is the thing being
/// commented on. `issue_type` stays in the schema and stays in the dashboard's
/// filters; the SDK simply stops asking, and the developer sets it at triage.
///
/// These three values are duplicated in `supabase/migrations/0003_impact.sql`
/// and `supabase/functions/ingest/index.ts`. Nothing at compile time makes
/// them agree — a drift is silent here and surfaces as a rejected send — so a
/// test pins them literally.
enum Impact {
  /// Could not continue. Owns `--red` in the dashboard's meta row.
  blocked('blocked', 'Blocked'),

  /// Kept going, but it cost something. The honest modal case, and the
  /// default.
  annoying('annoying', 'Annoying'),

  /// Noticed it; carried on regardless.
  cosmetic('cosmetic', 'Cosmetic');

  const Impact(this.wire, this.label);

  /// The value sent on the payload and stored in the column.
  final String wire;

  /// The chip label.
  final String label;

  /// What a comment carries when the tester never touches the row.
  ///
  /// Never null and never required: there is nothing to skip and nothing to
  /// validate, so the field costs no friction. Whether it earns its place is
  /// measurable — if every comment after fourteen days is still `annoying`,
  /// the field is dead and the data says so.
  static const Impact fallback = Impact.annoying;

  static Impact? fromWire(String? value) {
    if (value == null) return null;
    for (final impact in Impact.values) {
      if (impact.wire == value) return impact;
    }
    return null;
  }
}

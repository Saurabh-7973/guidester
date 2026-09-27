/// Mirrors the `issue_type` CHECK constraint added in migration 0002.
///
/// [wire] is the exact stored value; never send [name] to the API — a rename
/// in Dart would silently stop matching. These six are duplicated in
/// `supabase/migrations/0002_issue_type.sql`, `supabase/functions/ingest/
/// index.ts` and the SDK's own enum; all four must agree.
///
/// Deliberately not shared with the SDK: the dashboard would then depend on a
/// Flutter package built for phones, for the sake of six strings.
enum IssueType {
  looksWrong('looks_wrong', 'Looks wrong'),
  doesntWork('doesnt_work', "Doesn't work"),
  confusing('confusing', 'Confusing'),
  crash('crash', 'Crash / freeze'),
  slow('slow', 'Slow'),
  idea('idea', 'Idea');

  const IssueType(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for an untyped comment — rows predating 0002, and any comment whose
  /// tester skipped the chips (§5.2). An unrecognised value is also null: a
  /// value the dashboard cannot name must not blank the row.
  static IssueType? fromWire(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final t in IssueType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

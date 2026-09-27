-- Quick-select issue type (overlay UX spec §5).
--
-- A real column, not a jsonb key, so the dashboard can filter and group on it
-- with an index. Nullable on purpose: existing rows predate the column, and an
-- older SDK build in a tester's hands never sends one. Both stay valid.
--
-- These six values are duplicated in three other places, and all four must
-- agree: supabase/functions/ingest/index.ts (server-side validation),
-- packages/guidester/lib/src/issue_type.dart (the chips), and
-- apps/dashboard/lib/src/models/issue_type.dart (the filter).

alter table public.comments
  add column if not exists issue_type text
  check (issue_type is null or issue_type in
    ('looks_wrong','doesnt_work','confusing','crash','slow','idea'));

create index if not exists comments_issue_type_idx
  on public.comments (project_id, issue_type);

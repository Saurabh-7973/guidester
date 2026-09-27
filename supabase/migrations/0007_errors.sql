-- The stack, on the comment.
--
-- A tester writes "the screen went white". The exception that made it white is
-- already on their device, in a log nobody will ever open, and by the time the
-- report is triaged the build has moved on. The SDK chains Flutter's two error
-- handlers and carries the last three errors of the session with the comment,
-- so the report arrives with the line that caused it.
--
-- jsonb rather than a table: an error has no life of its own here. It is never
-- queried across comments, never edited, and never outlives the row it
-- explains — the loop is triage, not crash analytics. A column that travels
-- with the comment matches how it is read.

alter table public.comments
  add column if not exists errors jsonb not null default '[]'::jsonb;

-- The only question asked across comments: which of these carry a stack. A
-- partial index because most comments carry none, and an index over the
-- majority that answers nothing costs writes for nothing.
create index if not exists comments_with_errors_idx
  on public.comments (project_id, created_at desc)
  where jsonb_array_length(errors) > 0;

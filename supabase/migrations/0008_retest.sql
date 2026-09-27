-- The return leg of the loop.
--
-- 0005 modelled two verdicts that move independently, and then left
-- tester_verdict with no way to move except a developer changing it on the
-- tester's behalf. That made the bugsheet row this project exists to prevent —
-- `Dev: Closed, QA never retested` — the only reachable state rather than a
-- failure mode. See analysis/deep-review.md §1.
--
-- Nothing here is a new table. The loop was already modelled; it needed one
-- event kind and one index.

-- --------------------------------------------------------------------------
-- The ask, as an event
-- --------------------------------------------------------------------------
--
-- A developer marking something fixed is a question to a specific person, not
-- just a state change. Without this the timeline can show the answer and never
-- the ask, which is precisely the ambiguity the spreadsheet had: a QA Remark
-- reading "Pls Recheck" with nothing recording when it was requested.

alter table public.comment_events
  drop constraint if exists comment_events_kind_check;

alter table public.comment_events
  add constraint comment_events_kind_check check (kind in (
    'commented',
    'verdict_changed',
    'assigned',
    'blocked',
    'build_marked',
    'reopened',
    'attachment_added',
    'retest_requested'   -- new: the developer asked this tester to re-check
  ));

-- --------------------------------------------------------------------------
-- The query the device makes on every launch
-- --------------------------------------------------------------------------
--
-- "What is waiting on THIS tester in THIS project" runs once per app launch,
-- from every installed build, so it must never be a table scan. tester_id is
-- the device-local random id the SDK already sends with each comment.
--
-- Partial rather than total: the only rows this query ever wants are the ones a
-- developer has marked fixed and the tester has not accepted. Everything else
-- in the table is dead weight in this index.
create index if not exists comments_pending_retest_idx
  on public.comments (project_id, tester_id, created_at desc)
  where dev_verdict = 'fixed' and tester_verdict <> 'accepted';

-- --------------------------------------------------------------------------
-- What the ping is allowed to answer with
-- --------------------------------------------------------------------------
--
-- Deliberately a view rather than trusting the edge function to remember the
-- shape. The response leaves the system to a caller holding only an api_key
-- that is extractable from any APK, so the columns it can carry are worth
-- writing down once, in the schema, rather than in a select list that will be
-- edited later by somebody who does not know why it is short.
--
-- NOT included, on purpose: screenshot_path, context, errors, tester_name,
-- assignee, anything about any other tester, and any project-level count.
--
-- `security_invoker` is load-bearing, not a flourish. A normal Postgres view
-- runs with its OWNER's privileges and therefore reads straight past the row
-- level security on `comments`. Supabase grants select on public objects to
-- anon by default, so a plain view here would have handed the anon key —
-- extractable from every shipped APK — a readable list of other people's bug
-- reports, through a table whose RLS was verified under direct attack. The
-- harness caught it, because rls_test.sql deliberately re-grants everything so
-- that RLS is the only thing left standing. With security_invoker the view
-- executes as the caller, so anon reaches exactly what anon reaches on
-- `comments`: nothing.
create or replace view public.pending_retests
  with (security_invoker = true) as
  select
    c.id,
    c.project_id,
    c.tester_id,
    -- An excerpt, not the body. Enough to recognise which report this is.
    left(c.body, 120) as excerpt,
    c.screen_name,
    c.fixed_in_build,
    c.found_in_build,
    c.created_at
  from public.comments c
  where c.dev_verdict = 'fixed'
    and c.tester_verdict <> 'accepted';

-- The view is read by the edge function under the service role, which bypasses
-- RLS legitimately. The revoke is belt to security_invoker's braces: Supabase's
-- default grants would otherwise put it within reach of a role that must never
-- see another tester's report.
revoke all on public.pending_retests from anon, authenticated;

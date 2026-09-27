-- 0009's backfill, checked against rows that already disagree.
--
-- run.sh applies 0001..0008, loads the rows below, then applies 0009 and runs
-- the assertions at the bottom of this file. The rows mirror what the live
-- board held on 25 Sep.
\set ON_ERROR_STOP on

create or replace function assert(cond boolean, label text) returns void
language plpgsql as $$
begin
  if not cond then raise exception 'ASSERTION FAILED: %', label; end if;
end $$;

\if :{?phase_assert}
do $$
declare
  n int;
  v text;
begin
  select dev_verdict into v from public.comments where body = 'list resolve';
  perform assert(v = 'fixed', 'resolved with verdict new becomes fixed');

  select status::text into v from public.comments where body = 'wont fix left open';
  perform assert(v = 'resolved', 'wont_fix left open becomes resolved');

  select status::text into v from public.comments where body = 'in progress by list';
  perform assert(v = 'in_progress', 'in_progress status is kept');
  select dev_verdict into v from public.comments where body = 'in progress by list';
  perform assert(v = 'in_progress', 'and the verdict catches up');

  select status::text into v from public.comments where body = 'untouched';
  perform assert(v = 'open', 'a new, open comment is unchanged');

  select count(*) into n from public.comments
    where status::text <> public.status_for_verdict(dev_verdict)::text;
  perform assert(n = 0, 'after backfill no row disagrees');

  raise notice '--- backfill assertions passed ---';
end $$;
\else
insert into auth.users (id, email)
  values ('33333333-3333-3333-3333-333333333333', 'backfill@test');
insert into public.projects (id, owner_id, name)
  values ('cccccccc-0000-0000-0000-000000000003',
          '33333333-3333-3333-3333-333333333333', 'Backfill');
insert into public.comments (project_id, body, status, dev_verdict) values
  ('cccccccc-0000-0000-0000-000000000003', 'list resolve', 'resolved', 'new'),
  ('cccccccc-0000-0000-0000-000000000003', 'wont fix left open', 'open', 'wont_fix'),
  ('cccccccc-0000-0000-0000-000000000003', 'in progress by list', 'in_progress', 'new'),
  ('cccccccc-0000-0000-0000-000000000003', 'untouched', 'open', 'new');
\endif

-- Behavioural verification of the §4.2 security model.
-- Every assertion raises an exception on failure, so psql -v ON_ERROR_STOP=1
-- exits non-zero if any invariant breaks.
\set ON_ERROR_STOP on

-- Supabase grants these to anon/authenticated on public tables by default.
-- Granting them makes the test harder: RLS becomes the only thing standing.
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant select on all tables in schema storage to anon, authenticated;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111','owner-a@test'),
  ('22222222-2222-2222-2222-222222222222','owner-b@test');
insert into public.projects (id, owner_id, name) values
  ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','Project A'),
  ('bbbbbbbb-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222','Project B');
insert into public.comments (project_id, body, screen_name) values
  ('aaaaaaaa-0000-0000-0000-000000000001','comment on A','HOME'),
  ('bbbbbbbb-0000-0000-0000-000000000002','comment on B','CHECKOUT');
insert into storage.objects (bucket_id, name) values
  ('screenshots','aaaaaaaa-0000-0000-0000-000000000001/shot-a.png'),
  ('screenshots','bbbbbbbb-0000-0000-0000-000000000002/shot-b.png');

create function assert(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond then raise notice 'PASS  %', label;
  else raise exception 'FAIL  %', label; end if;
end $$;

create function as_user(u text) returns void language plpgsql as $$
begin
  execute format('set local role authenticated');
  execute format('set local request.jwt.claim.sub = %L', u);
end $$;

do $$
declare n int; ok boolean; cid uuid;
begin
  -- 1. the anon role, which the SDK would hold, sees nothing
  set local role anon;
  select count(*) into n from public.projects;  perform assert(n = 0, 'anon reads 0 projects');
  select count(*) into n from public.comments;  perform assert(n = 0, 'anon reads 0 comments');
  reset role;

  -- 2. anon cannot write
  set local role anon;
  begin
    insert into public.comments (project_id, body)
      values ('aaaaaaaa-0000-0000-0000-000000000001','anon injection');
    perform assert(false, 'anon insert must be denied');
  exception when insufficient_privilege or check_violation then
    perform assert(true, 'anon insert denied by RLS');
  end;
  reset role;

  -- 3/4. tenant isolation, both directions
  perform as_user('11111111-1111-1111-1111-111111111111');
  select count(*) into n from public.projects; perform assert(n = 1, 'owner A sees exactly 1 project');
  select count(*) into n from public.comments; perform assert(n = 1, 'owner A sees exactly 1 comment');
  select count(*) into n from storage.objects; perform assert(n = 1, 'owner A sees only their screenshot folder');
  select bool_and(name like 'aaaaaaaa%') into ok from storage.objects;
  perform assert(ok, 'owner A screenshot is scoped to their project folder');
  reset role;

  perform as_user('22222222-2222-2222-2222-222222222222');
  select count(*) into n from public.comments; perform assert(n = 1, 'owner B sees exactly 1 comment');
  select bool_and(body = 'comment on B') into ok from public.comments;
  perform assert(ok, 'owner B sees only their own comment');
  reset role;

  -- 5. cross-tenant update is a no-op, not an error
  perform as_user('11111111-1111-1111-1111-111111111111');
  with u as (update public.comments set status='resolved' where body='comment on B' returning 1)
    select count(*) into n from u;
  perform assert(n = 0, 'owner A cannot update owner B comment');
  reset role;

  -- 6. body length check, 1..2000
  begin
    insert into public.comments (project_id, body) values ('aaaaaaaa-0000-0000-0000-000000000001','');
    perform assert(false, 'empty body must be rejected');
  exception when check_violation then perform assert(true, 'empty body rejected'); end;
  begin
    insert into public.comments (project_id, body)
      values ('aaaaaaaa-0000-0000-0000-000000000001', repeat('x',2001));
    perform assert(false, '2001-char body must be rejected');
  exception when check_violation then perform assert(true, '2001-char body rejected'); end;
  insert into public.comments (project_id, body)
    values ('aaaaaaaa-0000-0000-0000-000000000001', repeat('x',2000));
  perform assert(true, '2000-char body accepted');

  -- 7. defaults and enum
  select bool_and(status='open' and context='{}'::jsonb) into ok
    from public.comments where body='comment on A';
  perform assert(ok, 'status defaults open, context defaults {}');
  select bool_and(screen_name='UNKNOWN') into ok
    from public.comments where body=repeat('x',2000);
  perform assert(ok, 'screen_name defaults UNKNOWN');
  select bool_and(api_key ~ '^[0-9a-f]{48}$') into ok from public.projects;
  perform assert(ok, 'api_key auto-generates as 48 hex chars');
  begin
    update public.comments set status='wontfix' where body='comment on A';
    perform assert(false, 'invalid enum must be rejected');
  exception when invalid_text_representation then perform assert(true, 'invalid enum rejected'); end;

  -- 8. structural invariants the brief called non-negotiable
  select count(*) into n from pg_policies
    where schemaname in ('public','storage') and 'anon' = any(roles);
  perform assert(n = 0, 'NO policy grants the anon role anything');
  select bool_and(not public) into ok from storage.buckets where id='screenshots';
  perform assert(ok, 'screenshots bucket is private');
  select bool_and(relrowsecurity) into ok from pg_class
    where relname in ('projects','comments');
  perform assert(ok, 'RLS enabled on projects and comments');
  select count(*) into n from information_schema.columns
    where table_name='comments' and column_name='context' and data_type='jsonb';
  perform assert(n = 1, 'comments.context exists and is jsonb');

  -- 8b. keys are rows now (0006). The connection check in onboarding reads
  -- last_used_at through this table, so it has to be as closed as the rest.
  select count(*) into n from public.project_keys;
  perform assert(n = 2, 'every project has exactly one key');

  -- The backfill is the half of 0006 this harness cannot reach by applying it:
  -- these projects were created AFTER the migration, so the trigger keyed them
  -- and the backfill matched nothing. The live project is the other way round,
  -- and its testers' builds hold the pre-0006 key. Reproduce that project here
  -- and run the same statement over it.
  alter table public.projects disable trigger projects_default_key;
  insert into public.projects (id, owner_id, name)
    values ('dddddddd-0000-0000-0000-000000000004',
            '11111111-1111-1111-1111-111111111111','Pre-0006 project');
  alter table public.projects enable trigger projects_default_key;
  insert into public.project_keys (project_id, label, key, created_at)
  select p.id, 'default', p.api_key, p.created_at
  from public.projects p
  where not exists (select 1 from public.project_keys k where k.project_id = p.id);
  select bool_and(k.key = p.api_key) into ok
    from public.project_keys k join public.projects p on p.id = k.project_id
    where p.id = 'dddddddd-0000-0000-0000-000000000004';
  perform assert(ok, 'the backfilled key is the key already inside shipped builds');
  select count(*) into n from public.project_keys;
  perform assert(n = 3, 'the backfill claims each key once, not once per run');
  delete from public.projects where id='dddddddd-0000-0000-0000-000000000004';

  insert into public.projects (id, owner_id, name)
    values ('cccccccc-0000-0000-0000-000000000003',
            '11111111-1111-1111-1111-111111111111','Project C');
  select count(*) into n from public.project_keys
    where project_id='cccccccc-0000-0000-0000-000000000003';
  perform assert(n = 1, 'a new project gets a key without the client asking');
  select bool_and(label='default' and key ~ '^gd_live_[0-9a-f]{48}$'
                  and revoked_at is null and last_used_at is null) into ok
    from public.project_keys where project_id='cccccccc-0000-0000-0000-000000000003';
  perform assert(ok, 'the new key is labelled, prefixed, live and never used');

  set local role anon;
  select count(*) into n from public.project_keys;
  perform assert(n = 0, 'anon reads 0 project keys');
  begin
    insert into public.project_keys (project_id, label)
      values ('aaaaaaaa-0000-0000-0000-000000000001','anon key');
    perform assert(false, 'anon insert of a key must be denied');
  exception when insufficient_privilege or check_violation then
    perform assert(true, 'anon cannot mint itself a key');
  end;
  reset role;

  perform as_user('11111111-1111-1111-1111-111111111111');
  select count(*) into n from public.project_keys;
  perform assert(n = 2, 'owner A sees only their own projects keys');
  with u as (update public.project_keys set revoked_at=now()
             where project_id='bbbbbbbb-0000-0000-0000-000000000002' returning 1)
    select count(*) into n from u;
  perform assert(n = 0, 'owner A cannot revoke owner B key');
  reset role;

  select bool_and(relrowsecurity) into ok from pg_class where relname='project_keys';
  perform assert(ok, 'RLS enabled on project_keys');
  select count(*) into n from information_schema.columns
    where table_name='comments' and column_name='project_key_id'
      and is_nullable='YES';
  perform assert(n = 1, 'comments record which key let them in, nullable for pre-0006 rows');

  delete from public.projects where id='cccccccc-0000-0000-0000-000000000003';
  select count(*) into n from public.project_keys
    where project_id='cccccccc-0000-0000-0000-000000000003';
  perform assert(n = 0, 'deleting a project takes its keys with it');

  -- Errors (0007). The default is what lets the dashboard render "no errors"
  -- without a null check on every row written before this migration.
  select count(*) into n from information_schema.columns
    where table_name='comments' and column_name='errors'
      and data_type='jsonb' and is_nullable='NO' and column_default like '%[]%';
  perform assert(n = 1, 'comments.errors is jsonb, NOT NULL, defaulting to []');
  select bool_and(jsonb_array_length(errors) = 0) into ok from public.comments;
  perform assert(ok, 'a comment written without errors has an empty list, not null');
  insert into public.comments (project_id, body, errors) values
    ('aaaaaaaa-0000-0000-0000-000000000001','white screen',
     '[{"at":"2026-09-09T05:00:00Z","exception":"RenderFlex overflowed",
        "stack":"#0 Foo.build (foo.dart:12)","library":"rendering library"}]'::jsonb);
  select count(*) into n from public.comments where jsonb_array_length(errors) > 0;
  perform assert(n = 1, 'a comment can carry the stack that explains it');
  select count(*) into n from pg_indexes
    where schemaname='public' and indexname='comments_with_errors_idx';
  perform assert(n = 1, 'finding the comments that carry a stack is an index scan');

  -- 9. cascade
  delete from auth.users where id='22222222-2222-2222-2222-222222222222';
  select count(*) into n from public.comments
    where project_id='bbbbbbbb-0000-0000-0000-000000000002';
  perform assert(n = 0, 'deleting a user cascades to projects and comments');

  -- Deletion (0004, G4). The policies matter more than the UI: without them a
  -- data-erasure request cannot be honoured at all.
  -- By name: 0013 adds an admin's delete beside the owner's.
  select count(*) into n from pg_policies
    where schemaname = 'public' and tablename = 'comments' and cmd = 'DELETE'
      and policyname = 'owner deletes comments';
  perform assert(n = 1, 'owners can delete comments');

  select count(*) into n from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and cmd = 'DELETE'
      and policyname = 'owner deletes own screenshots';
  perform assert(n = 1, 'owners can delete their screenshot objects');

  -- The delete policies must not have opened anything to anon on the way in.
  select count(*) into n from pg_policies
    where schemaname in ('public','storage') and 'anon' = any(roles);
  perform assert(n = 0, 'delete policies grant the anon role nothing');

  select count(*) into n from pg_indexes
    where schemaname = 'public' and indexname = 'comments_tester_idx';
  perform assert(n = 1, 'deleting by tester is an index scan, not a table scan');

  -- Impact (0003): NOT NULL with a default is what lets the dashboard give it
  -- a colour without ever rendering an empty one.
  select count(*) into n from information_schema.columns
    where table_name = 'comments' and column_name = 'impact'
      and is_nullable = 'NO' and column_default like '%annoying%';
  perform assert(n = 1, 'impact is NOT NULL and defaults to annoying');

  select count(*) into n from information_schema.columns
    where table_name = 'comments' and column_name = 'priority'
      and is_nullable = 'YES';
  perform assert(n = 1, 'priority exists, nullable, awaiting its UI');

  -- ------------------------------------------------------------------
  -- 0008 — the return leg
  -- ------------------------------------------------------------------

  -- The ask has to be recordable, or the timeline shows only the answer.
  select id into cid from public.comments limit 1;

  begin
    insert into public.comment_events (comment_id, kind, actor, body)
    values (cid, 'retest_requested', 'a developer', 'fixed in 1.0.46');
    perform assert(true, 'retest_requested is an accepted event kind');
  exception when check_violation then
    perform assert(false, 'retest_requested is an accepted event kind');
  end;

  -- And the constraint must still refuse anything not on the list, or it is
  -- free text wearing a check.
  begin
    insert into public.comment_events (comment_id, kind) values (cid, 'nonsense');
    perform assert(false, 'an unknown event kind is still refused');
  exception when check_violation then
    perform assert(true, 'an unknown event kind is still refused');
  end;

  -- Every installed build runs the pending-retest query on every launch.
  select count(*) into n from pg_indexes
    where schemaname = 'public' and indexname = 'comments_pending_retest_idx';
  perform assert(n = 1, 'pending retests are an index scan, not a table scan');

  -- The view exists, and carries none of the columns that must not leave the
  -- system on a key that is extractable from any APK.
  select count(*) into n from information_schema.views
    where table_schema = 'public' and table_name = 'pending_retests';
  perform assert(n = 1, 'the pending_retests view exists');

  select count(*) into n from information_schema.columns
    where table_schema = 'public' and table_name = 'pending_retests'
      and column_name in
        ('screenshot_path','context','errors','tester_name','assignee','body');
  perform assert(n = 0, 'the view carries no screenshot, context, errors or body');

  -- The one that matters, and it is behavioural rather than a grant check.
  --
  -- A plain view runs with its OWNER's privileges and reads straight past RLS.
  -- This suite re-grants everything to anon on purpose, so without
  -- security_invoker the anon key shipped in every APK would read other
  -- testers' reports out of a table whose RLS is otherwise airtight.
  -- Seed a row the view actually selects, or the assertion below is
  -- decoration: with nothing marked fixed, an unprotected view returns zero
  -- too and the test passes for the wrong reason. Found by mutation-testing it.
  insert into public.comments (project_id, body, tester_id, dev_verdict)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'a fix nobody has retested', 'tester-abc', 'fixed');

  select count(*) into n from public.pending_retests;
  perform assert(n = 1, 'the view does select a fixed, unaccepted comment');

  set local role anon;
  select count(*) into n from public.pending_retests;
  reset role;
  perform assert(n = 0, 'anon reads nothing through the pending_retests view');

  select count(*) into n from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relname = 'pending_retests'
      and c.reloptions @> array['security_invoker=true'];
  perform assert(n = 1, 'the view is security_invoker, so RLS is the caller''s');

  -- 0009: dev_verdict is the only status a developer sets; status follows it.
  --
  -- Found on 25 Sep: dev verdict Won't Fix left status=open (still in the Open
  -- tab), and the list's Resolve left dev_verdict=new. Two columns, two answers.
  declare
    v_id uuid;
    v_status text;
    v_verdict text;
  begin
    insert into public.comments (project_id, body)
      values ('aaaaaaaa-0000-0000-0000-000000000001', 'verdict drives status')
      returning id into v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'open', 'a new comment is open');

    update public.comments set dev_verdict = 'wont_fix' where id = v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'resolved', 'wont_fix resolves');

    update public.comments set dev_verdict = 'deferred' where id = v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'resolved', 'deferred resolves');

    update public.comments set dev_verdict = 'blocked' where id = v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'open', 'blocked stays open');

    update public.comments set dev_verdict = 'in_progress' where id = v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'in_progress', 'in_progress is in progress');

    update public.comments set dev_verdict = 'fixed' where id = v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'resolved', 'fixed resolves');

    -- A client that still writes only status (the old list buttons) moves the
    -- verdict with it instead of drifting.
    update public.comments set status = 'open' where id = v_id;
    select dev_verdict into v_verdict from public.comments where id = v_id;
    perform assert(v_verdict = 'new', 'status open alone reopens as new');

    update public.comments set status = 'resolved' where id = v_id;
    select dev_verdict into v_verdict from public.comments where id = v_id;
    perform assert(v_verdict = 'fixed', 'status resolved alone means fixed');

    update public.comments set status = 'in_progress' where id = v_id;
    select dev_verdict into v_verdict from public.comments where id = v_id;
    perform assert(v_verdict = 'in_progress', 'status in_progress alone moves the verdict');

    -- Both written and disagreeing: the verdict wins.
    update public.comments set dev_verdict = 'wont_fix', status = 'open'
      where id = v_id;
    select status::text, dev_verdict into v_status, v_verdict
      from public.comments where id = v_id;
    perform assert(v_status = 'resolved' and v_verdict = 'wont_fix',
      'when both are written, dev_verdict decides');

    -- An insert that names a verdict gets the matching status.
    insert into public.comments (project_id, body, dev_verdict)
      values ('aaaaaaaa-0000-0000-0000-000000000001', 'born fixed', 'fixed')
      returning id into v_id;
    select status::text into v_status from public.comments where id = v_id;
    perform assert(v_status = 'resolved', 'an insert with a verdict gets its status');

    select count(*) into n from public.comments
      where status::text <> public.status_for_verdict(dev_verdict)::text;
    perform assert(n = 0, 'no row disagrees');
  end;

  -- 0011: a comment retried by the offline queue is stored once.
  insert into public.comments (project_id, body, client_id)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 'first try', 'dev-abcdef012345');
  begin
    insert into public.comments (project_id, body, client_id)
      values ('aaaaaaaa-0000-0000-0000-000000000001', 'retry', 'dev-abcdef012345');
    raise exception 'a second comment with the same client_id was stored';
  exception when unique_violation then
    perform assert(true, 'a retried client_id is stored once');
  end;
  -- Another project's id space is its own.
  insert into public.projects (id, owner_id, name) values
    ('eeeeeeee-0000-0000-0000-000000000011','11111111-1111-1111-1111-111111111111','Project E');
  insert into public.comments (project_id, body, client_id)
    values ('eeeeeeee-0000-0000-0000-000000000011', 'other project', 'dev-abcdef012345');
  get diagnostics n = row_count;
  perform assert(n = 1, 'another project may use the same client_id');
  -- Rows without one, every comment before 0011, never collide.
  insert into public.comments (project_id, body)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 'no id'),
           ('aaaaaaaa-0000-0000-0000-000000000001', 'no id either');
  begin
    insert into public.comments (project_id, body, client_id)
      values ('aaaaaaaa-0000-0000-0000-000000000001', 'short', 'abc');
    raise exception 'a client_id shorter than 8 characters was stored';
  exception when check_violation then
    perform assert(true, 'a client_id under 8 characters is refused');
  end;

  -- 0012: the ingest limiter.
  declare
    v_key uuid;
    ok boolean;
  begin
    insert into public.project_keys (project_id, label)
      values ('aaaaaaaa-0000-0000-0000-000000000001', 'rate test')
      returning id into v_key;

    for i in 1..3 loop
      ok := public.ingest_allow(v_key, 'comment', 3, 60);
      perform assert(ok, 'request ' || i || ' of 3 is allowed');
    end loop;
    ok := public.ingest_allow(v_key, 'comment', 3, 60);
    perform assert(not ok, 'the fourth in the window is refused');

    ok := public.ingest_allow(v_key, 'ping', 3, 60);
    perform assert(ok, 'another bucket counts on its own');

    -- An old window is cleared when the key is next counted.
    insert into public.ingest_hits (key_id, bucket, window_start, hits)
      values (v_key, 'comment', now() - interval '1 hour', 99);
    perform public.ingest_allow(v_key, 'comment', 3, 60);
    select count(*) into n from public.ingest_hits
      where key_id = v_key and bucket = 'comment';
    perform assert(n = 1, 'old windows are cleared as the key is counted');

    begin
      set local role anon;
      perform public.ingest_allow(v_key, 'comment', 1000, 60);
      reset role;
      raise exception 'anon could call ingest_allow';
    exception when insufficient_privilege then
      reset role;
      perform assert(true, 'anon cannot call the limiter');
    end;

    set local role anon;
    select count(*) into n from public.ingest_hits;
    reset role;
    perform assert(n = 0, 'anon reads no ingest_hits rows');

    delete from public.project_keys where id = v_key;
    select count(*) into n from public.ingest_hits where key_id = v_key;
    perform assert(n = 0, 'a deleted key takes its counts with it');
  end;

  -- 0013: teams. A member of A's project sees and triages it; a viewer only
  -- reads; nobody joins without an invite to their own confirmed email; the
  -- owner loses nothing; anon still reaches nothing.
  declare
    v_a    constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
    v_b    constant uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
    v_own  constant text := '11111111-1111-1111-1111-111111111111';
    v_mem  constant text := '33333333-3333-3333-3333-333333333333';
    v_view constant text := '44444444-4444-4444-4444-444444444444';
    v_adm  constant text := '55555555-5555-5555-5555-555555555555';
    v_unc  constant text := '66666666-6666-6666-6666-666666666666';
    v_str  constant text := '77777777-7777-7777-7777-777777777777';
    v_cid  uuid;
    v_spare uuid;
    v_n    int;
    v_role text;
    v_all  int;
  begin
    reset role;
    insert into auth.users (id, email, email_confirmed_at) values
      (v_mem::uuid,  'member@test',   now()),
      (v_view::uuid, 'viewer@test',   now()),
      (v_adm::uuid,  'admin@test',    now()),
      (v_unc::uuid,  'unconfirmed@test', null),
      (v_str::uuid,  'stranger@test', now());
    select id into v_cid from public.comments where project_id = v_a limit 1;
    insert into public.comments (project_id, body, screen_name)
      values (v_a, 'spare comment on A', 'HOME') returning id into v_spare;
    select count(*) into v_all from public.comments where project_id = v_a;

    -- Before any invite, a signed-in stranger to the project sees none of it.
    perform as_user(v_mem);
    select count(*) into n from public.comments where project_id = v_a;
    perform assert(n = 0, 'team: no invite, no comments');
    select public.accept_project_invites() into v_n;
    perform assert(v_n = 0, 'team: accepting with no invite joins nothing');

    -- Nobody adds themselves.
    begin
      insert into public.project_members (project_id, user_id, role)
        values (v_a, v_mem::uuid, 'admin');
      perform assert(false, 'team: self-insert into members must be denied');
    exception when insufficient_privilege or check_violation then
      perform assert(true, 'team: a user cannot add themselves to a project');
    end;
    begin
      insert into public.project_invites (project_id, email, role)
        values (v_a, 'member@test', 'admin');
      perform assert(false, 'team: self-invite must be denied');
    exception when insufficient_privilege or check_violation then
      perform assert(true, 'team: a non-member cannot invite');
    end;

    -- The owner invites.
    perform as_user(v_own);
    insert into public.project_invites (project_id, email, role, team) values
      (v_a, 'member@test', 'member', 'qa'),
      (v_a, 'viewer@test', 'viewer', 'lead'),
      (v_a, 'admin@test', 'admin', 'developer'),
      (v_a, 'unconfirmed@test', 'member', null),
      (v_a, 'owner-a@test', 'viewer', null);
    begin
      insert into public.project_invites (project_id, email, role)
        values (v_a, 'x@test', 'owner');
      perform assert(false, 'team: owner role must be rejected');
    exception when check_violation then
      perform assert(true, 'team: nobody can be invited as owner');
    end;

    -- Owner B cannot see or add invites on A.
    perform as_user('22222222-2222-2222-2222-222222222222');
    select count(*) into n from public.project_invites;
    perform assert(n = 0, 'team: another owner sees no invites on A');
    begin
      insert into public.project_invites (project_id, email, role)
        values (v_a, 'stranger@test', 'admin');
      perform assert(false, 'team: owner B inviting onto A must be denied');
    exception when insufficient_privilege or check_violation then
      perform assert(true, 'team: owner B cannot invite onto A');
    end;

    -- An unconfirmed address joins nothing.
    perform as_user(v_unc);
    select public.accept_project_invites() into v_n;
    perform assert(v_n = 0, 'team: an unconfirmed email joins nothing');
    select count(*) into n from public.comments;
    perform assert(n = 0, 'team: and sees nothing');

    -- The owner's own invite is a no-op.
    perform as_user(v_own);
    select public.accept_project_invites() into v_n;
    perform assert(v_n = 0, 'team: the owner does not join their own project');

    -- The member accepts and triages.
    perform as_user(v_mem);
    select public.accept_project_invites() into v_n;
    perform assert(v_n = 1, 'team: member joins by their confirmed email');
    select public.project_role(v_a) into v_role;
    perform assert(v_role = 'member', 'team: project_role says member');
    select count(*) into n from public.projects;
    perform assert(n = 1, 'team: member sees A and only A');
    select count(*) into n from public.comments where project_id = v_b;
    perform assert(n = 0, 'team: member sees nothing of B');
    select count(*) into n from storage.objects;
    perform assert(n = 1, 'team: member reads A''s screenshots, not B''s');
    update public.comments set dev_verdict = 'in_progress' where id = v_cid;
    get diagnostics v_n = row_count;
    perform assert(v_n = 1, 'team: member moves a verdict');
    insert into public.comment_events (comment_id, kind, body)
      values (v_cid, 'commented', 'member note');
    perform assert(true, 'team: member adds a note');
    delete from public.comments where id = v_spare;
    get diagnostics v_n = row_count;
    perform assert(v_n = 0, 'team: member cannot delete a comment');
    select count(*) into n from public.project_invites;
    perform assert(n = 0, 'team: member cannot see invites');
    select count(*) into n from public.project_members where project_id = v_a;
    perform assert(n = 1, 'team: member sees the team');
    update public.project_members set role = 'admin'
      where project_id = v_a and user_id = v_mem::uuid;
    get diagnostics v_n = row_count;
    perform assert(v_n = 0, 'team: member cannot promote themselves');
    begin
      insert into public.project_keys (project_id, label) values (v_a, 'mine');
      perform assert(false, 'team: member making a key must be denied');
    exception when insufficient_privilege or check_violation then
      perform assert(true, 'team: member cannot make keys');
    end;
    select count(*) into n from public.project_keys where project_id = v_a;
    perform assert(n >= 1, 'team: member sees the key for the install snippet');
    delete from public.projects where id = v_a;
    get diagnostics v_n = row_count;
    perform assert(v_n = 0, 'team: member cannot delete the project');

    -- The viewer reads, and only reads.
    perform as_user(v_view);
    perform public.accept_project_invites();
    select count(*) into n from public.comments where project_id = v_a;
    perform assert(n = v_all, 'team: viewer reads every comment on A');
    update public.comments set dev_verdict = 'fixed' where id = v_cid;
    get diagnostics v_n = row_count;
    perform assert(v_n = 0, 'team: viewer cannot move a verdict');
    begin
      insert into public.comment_events (comment_id, kind, body)
        values (v_cid, 'commented', 'viewer note');
      perform assert(false, 'team: viewer note must be denied');
    exception when insufficient_privilege or check_violation then
      perform assert(true, 'team: viewer cannot add notes');
    end;
    select count(*) into n from public.project_keys where project_id = v_a;
    perform assert(n = 0, 'team: viewer does not see keys');
    reset role;
    select count(*) into n from public.projects p
      join public.project_keys k on k.key = p.api_key
      where p.id = v_a;
    perform assert(n = 0, 'team: the projects row a viewer reads holds no live key');
    perform as_user(v_view);

    -- A revoked invite is dead.
    perform as_user(v_own);
    update public.project_invites set revoked_at = now()
      where email = 'admin@test';
    perform as_user(v_adm);
    select public.accept_project_invites() into v_n;
    perform assert(v_n = 0, 'team: a revoked invite joins nothing');
    perform as_user(v_own);
    insert into public.project_invites (project_id, email, role, team)
      values (v_a, 'admin@test', 'admin', 'developer');

    -- The admin deletes, invites and removes.
    perform as_user(v_adm);
    select public.accept_project_invites() into v_n;
    perform assert(v_n = 1, 'team: a fresh invite after a revoked one works');
    delete from public.comments where id = v_spare;
    get diagnostics v_n = row_count;
    perform assert(v_n = 1, 'team: admin deletes a comment');
    insert into public.project_invites (project_id, email, role)
      values (v_a, 'stranger@test', 'viewer');
    perform assert(true, 'team: admin invites');
    delete from public.project_members
      where project_id = v_a and user_id = v_view::uuid;
    get diagnostics v_n = row_count;
    perform assert(v_n = 1, 'team: admin removes a member');
    delete from public.projects where id = v_a;
    get diagnostics v_n = row_count;
    perform assert(v_n = 0, 'team: admin cannot delete the project');

    perform as_user(v_view);
    select count(*) into n from public.comments where project_id = v_a;
    perform assert(n = 0, 'team: a removed member sees nothing');

    -- Anyone leaves.
    perform as_user(v_mem);
    delete from public.project_members
      where project_id = v_a and user_id = v_mem::uuid;
    get diagnostics v_n = row_count;
    perform assert(v_n = 1, 'team: a member leaves');
    select count(*) into n from public.comments where project_id = v_a;
    perform assert(n = 0, 'team: and sees nothing after');

    -- The owner kept everything.
    perform as_user(v_own);
    select count(*) into n from public.comments where project_id = v_a;
    perform assert(n = v_all - 1, 'team: owner still reads A (less the deleted one)');
    select public.project_role(v_a) into v_role;
    perform assert(v_role = 'owner', 'team: project_role says owner');

    -- anon, still nothing.
    reset role;
    set local role anon;
    select count(*) into n from public.project_members;
    perform assert(n = 0, 'team: anon reads no members');
    select count(*) into n from public.project_invites;
    perform assert(n = 0, 'team: anon reads no invites');
    begin
      perform public.accept_project_invites();
      perform assert(false, 'team: anon must not call accept');
    exception when insufficient_privilege then
      perform assert(true, 'team: anon cannot call accept_project_invites');
    end;
    reset role;
  end;

  -- 0010: an owner deletes their own project, and its comments go with it;
  -- nobody deletes someone else's.
  declare v_left int;
  begin
    perform as_user('22222222-2222-2222-2222-222222222222');
    delete from public.projects where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    perform as_user('11111111-1111-1111-1111-111111111111');
    select count(*) into v_left from public.projects
      where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    perform assert(v_left = 1, 'owner B cannot delete owner A project');

    delete from public.projects where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    select count(*) into v_left from public.projects
      where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    perform assert(v_left = 0, 'owner A deletes their own project');
    select count(*) into v_left from public.comments
      where project_id = 'aaaaaaaa-0000-0000-0000-000000000001';
    perform assert(v_left = 0, 'its comments go with it');
  end;

  raise notice '--- all assertions passed ---';
end $$;

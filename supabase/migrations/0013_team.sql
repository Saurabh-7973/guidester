-- Teams. A project had one reader, its owner; a company has a lead, developers,
-- QA, designers, product people and support, and every one of them had to use
-- the owner's login or not see the board at all.
--
-- Two ideas, kept apart:
--
--   * role, what someone may DO: admin (manage the team and keys, delete),
--     member (triage: verdicts, notes, assignees), viewer (read only: the CTO,
--     a client, a stakeholder). The owner stays projects.owner_id and is not a
--     row here, so nothing in this file can take a project away from its owner.
--   * team, what someone WORKS ON: developer, qa, design, product, backend,
--     frontend, support, lead. It changes nothing about access; the dashboard
--     uses it to open each person on their own list.
--
-- Every policy below is ADDED beside the owner policies of 0001-0010, which
-- are left exactly as they were. Postgres ORs permissive policies, so an owner
-- keeps every right they had, and a member gains only what is written here.
-- anon still reaches nothing: every policy here is `to authenticated`.
--
-- Invites are by email. There is no mail server in Guidester; the owner sends
-- the dashboard link themselves. An invite turns into membership only when a
-- signed-in user whose CONFIRMED email matches it calls
-- accept_project_invites(). Knowing an invite's id or email gets nobody in.

set search_path to public, extensions;

create table if not exists public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in ('admin', 'member', 'viewer')),
  team       text check (team in ('developer', 'qa', 'design', 'product',
                                  'backend', 'frontend', 'support', 'lead')),
  email      text,
  added_by   uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create index if not exists project_members_user_idx
  on public.project_members (user_id);

create table if not exists public.project_invites (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  email       text not null check (email = lower(email) and email like '%_@_%'),
  role        text not null check (role in ('admin', 'member', 'viewer')),
  team        text check (team in ('developer', 'qa', 'design', 'product',
                                   'backend', 'frontend', 'support', 'lead')),
  invited_by  uuid references auth.users(id) on delete set null
                default auth.uid(),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at  timestamptz
);

-- One live invite per person per project; a revoked or accepted one may be
-- followed by a new one.
create unique index if not exists project_invites_live_idx
  on public.project_invites (project_id, email)
  where accepted_at is null and revoked_at is null;

-- --------------------------------------------------------------------------
-- The one question every policy asks
-- --------------------------------------------------------------------------
--
-- SECURITY DEFINER so a policy on project_members can ask about
-- project_members without recursing into itself. It answers only for the
-- caller (auth.uid()), never for a user named by argument, and returns a role
-- name or null: nothing a caller could not learn by reading what RLS already
-- shows them.
create or replace function public.project_role(p_project uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from public.projects p
                 where p.id = p_project and p.owner_id = auth.uid())
      then 'owner'
    else (select m.role from public.project_members m
          where m.project_id = p_project and m.user_id = auth.uid())
  end
$$;

revoke all on function public.project_role(uuid) from public;
grant execute on function public.project_role(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- Members: what each role may do, beside the owner policies
-- --------------------------------------------------------------------------

create policy "members select projects" on public.projects
  for select to authenticated using (public.project_role(id) is not null);

create policy "members select comments" on public.comments
  for select to authenticated using (
    public.project_role(project_id) is not null
  );

create policy "triagers update comments" on public.comments
  for update to authenticated
  using (public.project_role(project_id) in ('admin', 'member'))
  with check (public.project_role(project_id) in ('admin', 'member'));

-- Deleting, including erasing a tester, is an admin's call.
create policy "admins delete comments" on public.comments
  for delete to authenticated using (
    public.project_role(project_id) = 'admin'
  );

create policy "members read comment events" on public.comment_events
  for select to authenticated using (
    exists (select 1 from public.comments c
            where c.id = comment_events.comment_id
              and public.project_role(c.project_id) is not null)
  );

create policy "triagers write comment events" on public.comment_events
  for insert to authenticated with check (
    exists (select 1 from public.comments c
            where c.id = comment_events.comment_id
              and public.project_role(c.project_id) in ('admin', 'member'))
  );

create policy "admins delete comment events" on public.comment_events
  for delete to authenticated using (
    exists (select 1 from public.comments c
            where c.id = comment_events.comment_id
              and public.project_role(c.project_id) = 'admin')
  );

create policy "members read attachments" on public.attachments
  for select to authenticated using (
    exists (select 1 from public.comments c
            where c.id = attachments.comment_id
              and public.project_role(c.project_id) is not null)
  );

create policy "admins delete attachments" on public.attachments
  for delete to authenticated using (
    exists (select 1 from public.comments c
            where c.id = attachments.comment_id
              and public.project_role(c.project_id) = 'admin')
  );

-- A key is compiled into every test build, so members may see it (Settings
-- shows the install snippet). Making, rotating and revoking is an admin's.
create policy "triagers select project keys" on public.project_keys
  for select to authenticated using (
    public.project_role(project_id) in ('admin', 'member')
  );

create policy "admins insert project keys" on public.project_keys
  for insert to authenticated with check (
    public.project_role(project_id) = 'admin'
  );

create policy "admins update project keys" on public.project_keys
  for update to authenticated
  using (public.project_role(project_id) = 'admin')
  with check (public.project_role(project_id) = 'admin');

-- Matched as text, like 0001's policy: a folder that is not a uuid must fail
-- the check, not fail the query. `objects.name`, qualified: inside the
-- subquery a bare `name` is the PROJECT's name, and the check silently fails
-- (caught by the RLS suite).
create policy "members read screenshots" on storage.objects
  for select to authenticated using (
    bucket_id = 'screenshots'
    and exists (select 1 from public.projects p
                where p.id::text = (storage.foldername(objects.name))[1]
                  and public.project_role(p.id) is not null)
  );

create policy "admins delete screenshots" on storage.objects
  for delete to authenticated using (
    bucket_id = 'screenshots'
    and exists (select 1 from public.projects p
                where p.id::text = (storage.foldername(objects.name))[1]
                  and public.project_role(p.id) = 'admin')
  );

-- --------------------------------------------------------------------------
-- The team itself
-- --------------------------------------------------------------------------

alter table public.project_members enable row level security;
alter table public.project_invites enable row level security;

-- Everyone on a project sees who else is on it.
create policy "members see the team" on public.project_members
  for select to authenticated using (
    public.project_role(project_id) is not null
  );

-- Only the owner and admins change the team. The role column cannot say
-- 'owner' (check constraint), so nobody can be made owner through here.
create policy "admins add members" on public.project_members
  for insert to authenticated with check (
    public.project_role(project_id) in ('owner', 'admin')
  );

create policy "admins change members" on public.project_members
  for update to authenticated
  using (public.project_role(project_id) in ('owner', 'admin'))
  with check (public.project_role(project_id) in ('owner', 'admin'));

-- Admins remove people; anyone may leave.
create policy "admins remove members, anyone leaves" on public.project_members
  for delete to authenticated using (
    public.project_role(project_id) in ('owner', 'admin')
    or user_id = auth.uid()
  );

create policy "admins see invites" on public.project_invites
  for select to authenticated using (
    public.project_role(project_id) in ('owner', 'admin')
  );

create policy "admins invite" on public.project_invites
  for insert to authenticated with check (
    public.project_role(project_id) in ('owner', 'admin')
  );

-- Revoking is an update, so the team can see what was offered.
create policy "admins revoke invites" on public.project_invites
  for update to authenticated
  using (public.project_role(project_id) in ('owner', 'admin'))
  with check (public.project_role(project_id) in ('owner', 'admin'));

create policy "admins delete invites" on public.project_invites
  for delete to authenticated using (
    public.project_role(project_id) in ('owner', 'admin')
  );

-- --------------------------------------------------------------------------
-- Accepting: the caller's own confirmed email, nothing else
-- --------------------------------------------------------------------------
--
-- SECURITY DEFINER because the invitee cannot read project_invites (they are
-- not a member yet). It takes no arguments on purpose: the email comes from
-- auth.users for auth.uid(), and only once Supabase has confirmed it, so
-- signing up with someone else's address and not confirming gets nothing.
-- Returns how many projects were joined.
create or replace function public.accept_project_invites()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_n     integer;
begin
  if v_uid is null then
    return 0;
  end if;

  select lower(u.email) into v_email
  from auth.users u
  where u.id = v_uid and u.email_confirmed_at is not null;

  if v_email is null then
    return 0;
  end if;

  with live as (
    update public.project_invites i
       set accepted_at = now()
     where i.email = v_email
       and i.accepted_at is null
       and i.revoked_at is null
       -- The owner needs no membership, and inviting yourself is a no-op.
       and not exists (select 1 from public.projects p
                       where p.id = i.project_id and p.owner_id = v_uid)
    returning i.project_id, i.role, i.team, i.invited_by
  ), joined as (
    insert into public.project_members
      (project_id, user_id, role, team, email, added_by)
    select project_id, v_uid, role, team, v_email, invited_by from live
    on conflict (project_id, user_id)
      do update set role = excluded.role, team = excluded.team
    returning 1
  )
  select count(*) into v_n from joined;

  return v_n;
end $$;

revoke all on function public.accept_project_invites() from public;
grant execute on function public.accept_project_invites() to authenticated;

-- --------------------------------------------------------------------------
-- The pre-0006 key column
-- --------------------------------------------------------------------------
--
-- 0006 copied every projects.api_key into project_keys, where that value is a
-- LIVE key. Until now only the owner could read a projects row; from here a
-- viewer can, and a viewer must not hold a write key. Nothing reads this
-- column (0006), so each value is replaced with a fresh random one that opens
-- nothing. The live copy in project_keys, and every build carrying it, is
-- untouched.
update public.projects
   set api_key = encode(gen_random_bytes(24), 'hex')
 where exists (select 1 from public.project_keys k
               where k.project_id = projects.id and k.key = projects.api_key);

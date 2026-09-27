-- Keys become rows. Product spec §2.2, and the thing §3.2's connection check
-- reads from.
--
-- Until now a project had exactly one key, stored on the project itself, with
-- no label, no revocation and no record of whether anything had ever used it.
-- Three things needed that record:
--
--   * Onboarding cannot verify an install without it. "Do you see the bubble?
--     Yes / No" is self-reported and people click Yes to get past it; the SDK
--     already talks to the backend, so the backend can answer instead.
--   * A key that leaks is rotated, not replaced by deleting the project. That
--     needs a second key to exist alongside the first while builds age out.
--   * When a leaked key starts producing junk, the comments have to say which
--     key let them in.
--
-- The key stays PER PROJECT and never becomes per-organisation: it is a write
-- credential compiled into a distributed APK, so it is assumed to leak. One
-- that leaks costs one project's rotation.

set search_path to public, extensions;

create table if not exists public.project_keys (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects(id) on delete cascade,
  label        text not null,
  key          text not null unique
                 default 'gd_live_' || encode(gen_random_bytes(24), 'hex'),
  revoked_at   timestamptz,
  last_used_at timestamptz,
  -- What answered, not just when. §3.2 shows "Connected — Pixel 7, Android 15,
  -- 2 seconds ago": a timestamp alone cannot tell a developer whether the
  -- device that reported is the one in their hand, which is the whole question
  -- being asked at minute one of an install.
  last_used_device text,
  last_used_os     text,
  created_at   timestamptz not null default now()
);

create index if not exists project_keys_project_idx
  on public.project_keys (project_id);

-- The prefix is not decoration. `gd_live_` makes a leaked key greppable in a
-- repo scan and identifiable on sight in a support message. Existing keys keep
-- their bare-hex value — rewriting them would brick every installed build — so
-- the format is a default for new keys, not a constraint on the column.

-- Every existing project gets its current key as a row, so builds already in
-- testers' hands keep reporting across this migration.
insert into public.project_keys (project_id, label, key, created_at)
select p.id, 'default', p.api_key, p.created_at
from public.projects p
-- Keyed by project, not by key value: a project that already has a key of any
-- kind is not missing one, and matching on the value instead would hand a
-- second, redundant key to every project whose key came from somewhere else.
where not exists (
  select 1 from public.project_keys k where k.project_id = p.id
);

comment on column public.projects.api_key is
  'DEPRECATED as of 0006. project_keys is the source of truth and what ingest '
  'looks up; this column is the pre-0006 key, kept because dropping it would '
  'invalidate nothing but would also tell us nothing. Do not read it.';

-- Which key ingested a comment. Nullable: rows written before 0006 have no
-- answer, and inventing one would be a lie about provenance.
alter table public.comments
  add column if not exists project_key_id uuid
  references public.project_keys(id) on delete set null;

-- --------------------------------------------------------------------------
-- RLS — the same shape as everything else: owners only, anon nothing
-- --------------------------------------------------------------------------
--
-- The SDK holds a key; it does not read this table. No anon policy exists here
-- for the same reason none exists anywhere else — that absence is what makes
-- an extracted APK key useless for reading.

alter table public.project_keys enable row level security;

create policy "owner selects project keys" on public.project_keys
  for select to authenticated using (
    exists (select 1 from public.projects p
            where p.id = project_keys.project_id and p.owner_id = auth.uid())
  );

create policy "owner inserts project keys" on public.project_keys
  for insert to authenticated with check (
    exists (select 1 from public.projects p
            where p.id = project_keys.project_id and p.owner_id = auth.uid())
  );

-- Rotation revokes rather than deletes: a revoked key still has to be able to
-- say which comments arrived on it.
create policy "owner updates project keys" on public.project_keys
  for update to authenticated
  using (
    exists (select 1 from public.projects p
            where p.id = project_keys.project_id and p.owner_id = auth.uid())
  )
  with check (
    exists (select 1 from public.projects p
            where p.id = project_keys.project_id and p.owner_id = auth.uid())
  );

create policy "owner deletes project keys" on public.project_keys
  for delete to authenticated using (
    exists (select 1 from public.projects p
            where p.id = project_keys.project_id and p.owner_id = auth.uid())
  );

-- --------------------------------------------------------------------------
-- Every project gets a key the moment it exists
-- --------------------------------------------------------------------------
--
-- Onboarding step 01 creates the project and step 02 shows the key. Doing that
-- as two client writes leaves a window where a project exists with no way to
-- report into it, and a client that dies between them leaves it there forever.
-- The trigger closes the window: there is no such thing as a keyless project.
--
-- SECURITY INVOKER, deliberately. The insert is checked against the same
-- policy the owner's own insert would be, so this cannot become a way to
-- attach a key to someone else's project.
create or replace function public.create_default_project_key()
returns trigger language plpgsql as $$
begin
  insert into public.project_keys (project_id, label) values (new.id, 'default');
  return new;
end $$;

drop trigger if exists projects_default_key on public.projects;
create trigger projects_default_key
  after insert on public.projects
  for each row execute function public.create_default_project_key();

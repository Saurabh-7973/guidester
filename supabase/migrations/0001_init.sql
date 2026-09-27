create extension if not exists pgcrypto;

-- DEVIATION FROM §4.2 — required, see DECISIONS.md D36.
-- Supabase pre-installs pgcrypto into the `extensions` schema, which is not on
-- the default search_path, so the unqualified gen_random_bytes() below fails
-- with "function gen_random_bytes(integer) does not exist" on a real project.
-- Postgres resolves a column DEFAULT at DDL time and stores the resolved
-- function, so setting the path here is enough and nothing depends on it later.
-- Naming a schema that does not exist is not an error, so this is also correct
-- on a plain Postgres where pgcrypto lands in public.
set search_path to public, extensions;

create table public.projects (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  api_key    text not null unique default encode(gen_random_bytes(24), 'hex'),
  created_at timestamptz not null default now()
);

create type comment_status as enum ('open', 'in_progress', 'resolved');

create table public.comments (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  body            text not null check (char_length(body) between 1 and 2000),
  screen_name     text not null default 'UNKNOWN',
  tap_x           real,                 -- normalized 0..1
  tap_y           real,                 -- normalized 0..1
  screenshot_path text,
  tester_name     text,
  tester_id       text,                 -- device-local id, not an account
  device_model    text,
  os_version      text,
  app_version     text,
  context         jsonb not null default '{}'::jsonb,   -- everything else, §5.7
  status          comment_status not null default 'open',
  created_at      timestamptz not null default now()
);

create index comments_project_status_idx
  on public.comments (project_id, status, created_at desc);

alter table public.projects enable row level security;
alter table public.comments enable row level security;

create policy "owner selects projects" on public.projects
  for select to authenticated using (owner_id = auth.uid());

create policy "owner inserts projects" on public.projects
  for insert to authenticated with check (owner_id = auth.uid());

create policy "owner selects comments" on public.comments
  for select to authenticated using (
    exists (select 1 from public.projects p
            where p.id = comments.project_id and p.owner_id = auth.uid())
  );

create policy "owner updates comments" on public.comments
  for update to authenticated
  using (
    exists (select 1 from public.projects p
            where p.id = comments.project_id and p.owner_id = auth.uid())
  )
  with check (
    exists (select 1 from public.projects p
            where p.id = comments.project_id and p.owner_id = auth.uid())
  );

-- PRIVATE bucket. Screenshots are read via signed URLs only.
insert into storage.buckets (id, name, public)
values ('screenshots', 'screenshots', false)
on conflict (id) do nothing;

create policy "owner reads own screenshots" on storage.objects
  for select to authenticated using (
    bucket_id = 'screenshots'
    and (storage.foldername(name))[1] in (
      select p.id::text from public.projects p where p.owner_id = auth.uid()
    )
  );

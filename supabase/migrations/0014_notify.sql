-- Notifications. A comment used to wait on the board until someone looked;
-- now a project can post each one to its Slack, Discord or Microsoft Teams
-- channel as it arrives.
--
-- One webhook per project, kept out of `projects` on purpose: since 0013 a
-- viewer reads project rows, and a webhook URL is a credential (anyone who
-- holds it posts to the channel). Only the owner and admins read or change
-- it. Ingest reads it with the service role and checks the host again before
-- calling it (functions/ingest/notify.ts); the check below only keeps
-- obvious mistakes out of the table.

set search_path to public, extensions;

create table if not exists public.project_webhooks (
  project_id uuid primary key references public.projects(id) on delete cascade,
  url        text not null check (url like 'https://%' and length(url) <= 500),
  created_by uuid references auth.users(id) on delete set null
               default auth.uid(),
  updated_at timestamptz not null default now()
);

alter table public.project_webhooks enable row level security;

create policy "admins read the webhook" on public.project_webhooks
  for select to authenticated using (
    public.project_role(project_id) in ('owner', 'admin')
  );

create policy "admins set the webhook" on public.project_webhooks
  for insert to authenticated with check (
    public.project_role(project_id) in ('owner', 'admin')
  );

create policy "admins change the webhook" on public.project_webhooks
  for update to authenticated
  using (public.project_role(project_id) in ('owner', 'admin'))
  with check (public.project_role(project_id) in ('owner', 'admin'));

create policy "admins remove the webhook" on public.project_webhooks
  for delete to authenticated using (
    public.project_role(project_id) in ('owner', 'admin')
  );

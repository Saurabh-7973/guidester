-- The loop, modelled. Derived from a real 1,130-row bugsheet, not invented.
--
-- Everything here replaces something a team was doing by hand in a spreadsheet:
-- two status columns that drift, an owner encoded inside a status value, and a
-- timestamped history typed into a cell.

-- --------------------------------------------------------------------------
-- Two verdicts, because the sheet already has two status columns
-- --------------------------------------------------------------------------
--
-- QA Status and Dev Status disagree constantly in the real data, and the
-- disagreement is the useful part: `dev=fixed, tester!=accepted` is a fix
-- nobody verified, which is invisible today because it takes reading two
-- columns side by side.

alter table public.comments
  add column if not exists tester_verdict text not null default 'open'
  check (tester_verdict in ('open','verifying','accepted','rejected'));

alter table public.comments
  add column if not exists dev_verdict text not null default 'new'
  check (dev_verdict in
    ('new','in_progress','fixed','wont_fix','deferred','blocked'));

-- --------------------------------------------------------------------------
-- Routing, which the sheet had crushed into the status column
-- --------------------------------------------------------------------------
--
-- `Open Backend`, `Open BA`, `Open Thence`, `Open Master` are not states, they
-- are whoever owes the next move. Keeping them inside the status is why "how
-- many are open?" could not be answered without a judgement call.

-- Deliberately NOT a CHECK constraint, and deliberately not a fixed list.
--
-- The team this was modelled on blocks on `exchange`, `master data` and a named
-- design vendor. None of those generalise, and a constraint carrying them would
-- make every other team's real blocker invalid. A shipped taxonomy that does not
-- fit is worse than free text: people either pick the wrong value or stop using
-- the field.
--
-- So: free text on the row, and a per-project list of suggestions below. The
-- list is what the UI offers; the column is what it accepts.
alter table public.comments
  add column if not exists blocked_on text;

-- The suggestions a project offers, editable by the project owner.
--
-- The default six are the ones that hold for any software team. Anything
-- domain-specific — exchange, master data, a vendor's name — is added by the
-- team that needs it, not shipped to everyone who doesn't.
alter table public.projects
  add column if not exists blocked_on_options text[] not null
  default array['backend','frontend','design','product','qa','third-party'];

-- Free text on purpose. There are no member accounts yet, and a foreign key to
-- a table that does not exist would block the useful 90% for the sake of the
-- last 10%. It becomes a reference when members land.
alter table public.comments
  add column if not exists assignee text;

-- --------------------------------------------------------------------------
-- Builds. The sheet records where a bug was FOUND and loses where it was FIXED.
-- --------------------------------------------------------------------------
--
-- found_in_build is filled by the SDK from app_version, so it is never typed
-- and never wrong. The other two are set by whoever moves the verdict.

alter table public.comments
  add column if not exists found_in_build text;

alter table public.comments
  add column if not exists fixed_in_build text;

alter table public.comments
  add column if not exists verified_in_build text;

-- Backfill from the context payload the SDK has been sending all along. G5:
-- app_version was captured and never used.
update public.comments
   set found_in_build = context->>'app_version'
 where found_in_build is null
   and context ? 'app_version';

-- --------------------------------------------------------------------------
-- Environment. Only the WhatsApp thread reveals this one.
-- --------------------------------------------------------------------------
--
-- The Excel has no environment column, and the group is full of the cost:
--   "Issue in Live envoirnment"
--   "27/07 working in uat not in live"
--   "please specify Env"
--   "25 Jun - check in prod"
--   "Checked in Live"
--   "I'm checking in live environment"
--
-- A bug that reproduces in UAT and not in Live, or the reverse, is a different
-- bug. Testers say which one in prose, developers ask when they forget, and
-- neither is filterable. The SDK already knows — it is a dart-define at build
-- time — so this is never typed and never wrong.

alter table public.comments
  add column if not exists environment text;

create index if not exists comments_environment_idx
  on public.comments (project_id, environment, created_at desc);

-- --------------------------------------------------------------------------
-- The history, which was being typed into a spreadsheet cell
-- --------------------------------------------------------------------------
--
-- Real cell contents from the sheet:
--   "19/03: closed
--    19/06: Closed"
--   "24/06 : Fixed
--    30/07 : Pls Recheck"
--
-- Date-prefixed, newline-separated, append-only, unsortable, and the reason the
-- status column silently lags the remark: a person updates one cell, not both.
-- Here the verdict IS the last event.

create table if not exists public.comment_events (
  id          uuid primary key default gen_random_uuid(),
  comment_id  uuid not null references public.comments(id) on delete cascade,
  at          timestamptz not null default now(),

  -- Free text for the same reason as assignee. A tester has no account.
  actor       text,

  kind        text not null check (kind in (
                'commented',       -- a remark, either side
                'verdict_changed', -- dev or tester moved
                'assigned',
                'blocked',
                'build_marked',    -- fixed_in / verified_in set
                'reopened',
                'attachment_added'
              )),

  -- What the remark said. Nullable: a pure verdict change carries no prose.
  body        text,

  -- For verdict_changed / assigned / blocked, so the timeline reads
  -- "in_progress → fixed" rather than just "fixed".
  field       text,
  from_value  text,
  to_value    text,

  build       text
);

create index if not exists comment_events_comment_idx
  on public.comment_events (comment_id, at desc);

-- --------------------------------------------------------------------------
-- Attachments, plural, and not only images
-- --------------------------------------------------------------------------
--
-- The group shares videos as often as screenshots, because half the reports are
-- behavioural — flickering, a broadcast that stalls, a ticker that stutters.
-- A still frame cannot show any of them.
--
-- comments.screenshot_path stays as the primary capture; this is everything
-- else, including the recordings and network logs the SDK does not send yet.

create table if not exists public.attachments (
  id          uuid primary key default gen_random_uuid(),
  comment_id  uuid not null references public.comments(id) on delete cascade,
  kind        text not null check (kind in
                ('screenshot','recording','log','network')),
  path        text not null,
  bytes       bigint,
  duration_ms integer,
  created_at  timestamptz not null default now()
);

create index if not exists attachments_comment_idx
  on public.attachments (comment_id);

-- --------------------------------------------------------------------------
-- The boards this exists to make possible
-- --------------------------------------------------------------------------
--
-- Matches how the list is actually read: what is blocked, what is waiting on
-- me, and what was fixed but never checked.
create index if not exists comments_dev_verdict_idx
  on public.comments (project_id, dev_verdict, created_at desc);

create index if not exists comments_tester_verdict_idx
  on public.comments (project_id, tester_verdict, created_at desc);

create index if not exists comments_assignee_idx
  on public.comments (project_id, assignee);

-- --------------------------------------------------------------------------
-- RLS. Same ownership test as everything else.
-- --------------------------------------------------------------------------

alter table public.comment_events enable row level security;
alter table public.attachments enable row level security;

create policy "owner reads comment events" on public.comment_events
  for select to authenticated using (
    exists (select 1 from public.comments c
            join public.projects p on p.id = c.project_id
            where c.id = comment_events.comment_id and p.owner_id = auth.uid())
  );

create policy "owner writes comment events" on public.comment_events
  for insert to authenticated with check (
    exists (select 1 from public.comments c
            join public.projects p on p.id = c.project_id
            where c.id = comment_events.comment_id and p.owner_id = auth.uid())
  );

-- Events are the history. They are deliberately NOT updatable: correcting the
-- past by editing it is the failure the spreadsheet already has.
create policy "owner deletes comment events" on public.comment_events
  for delete to authenticated using (
    exists (select 1 from public.comments c
            join public.projects p on p.id = c.project_id
            where c.id = comment_events.comment_id and p.owner_id = auth.uid())
  );

create policy "owner reads attachments" on public.attachments
  for select to authenticated using (
    exists (select 1 from public.comments c
            join public.projects p on p.id = c.project_id
            where c.id = attachments.comment_id and p.owner_id = auth.uid())
  );

create policy "owner deletes attachments" on public.attachments
  for delete to authenticated using (
    exists (select 1 from public.comments c
            join public.projects p on p.id = c.project_id
            where c.id = attachments.comment_id and p.owner_id = auth.uid())
  );

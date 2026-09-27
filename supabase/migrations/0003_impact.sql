-- Impact, and the priority column that has no UI yet.
--
-- Impact is what the tester answers: "could you keep using the app?" It is not
-- severity — a tester cannot judge severity, but they can report what the
-- problem cost them, and that maps straight onto triage order.
--
-- These three values are duplicated in two other places, and all three must
-- agree: supabase/functions/ingest/index.ts (server-side validation) and
-- packages/guidester/lib/src/impact.dart (the chips). A drift is silent on
-- both sides and surfaces as a rejected send.
--
-- NOT NULL with a default, unlike issue_type. Every row has an impact: rows
-- that predate the column take the default, and an older SDK build in a
-- tester's hands sends nothing and gets the same. The dashboard therefore
-- never renders an empty impact, which is what lets it own colour in the meta
-- row.

alter table public.comments
  add column if not exists impact text not null default 'annoying'
  check (impact in ('blocked','annoying','cosmetic'));

-- The list is ordered by impact then recency, so the filter wants both.
create index if not exists comments_impact_idx
  on public.comments (project_id, impact, created_at desc);

-- Priority is the developer's override on top of the tester's impact. It ships
-- with no UI (D51): one developer and thirty comments is ordered well enough by
-- impact alone, and a second dimension nobody sets is furniture. The column
-- exists now so that adding the UI later is not a migration.
--
-- Nullable on purpose — null means "not triaged", which is different from any
-- value it could take. Design-system Rule 1 gives colour to priority; until
-- this is populated, impact holds it.
--
-- Deliberately unconstrained. The value domain has not been ruled, and a check
-- constraint invented here would force exactly the migration this column
-- exists to avoid. The constraint lands with the UI, when the values are known.
alter table public.comments
  add column if not exists priority text;

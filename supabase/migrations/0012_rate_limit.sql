-- Rate limiting for the ingest function.
--
-- The api key is compiled into every tester build and is assumed to leak
-- (0006). Anyone holding it could post comments and screenshots as fast as
-- the network allows; twenty requests a second met no resistance in the deep
-- review. The function is stateless between requests, so the count lives
-- here: one row per key, per kind of request, per fixed window.
--
-- Per key, not per tester: tester_id is chosen by the caller and an attacker
-- would simply vary it. One key is one project's build, so its limit is the
-- whole team's, and the numbers in the function are set with that in mind.

set search_path to public, extensions;

create table if not exists public.ingest_hits (
  key_id       uuid not null references public.project_keys(id) on delete cascade,
  bucket       text not null,
  window_start timestamptz not null,
  hits         integer not null default 0,
  primary key (key_id, bucket, window_start)
);

-- Nobody reads this but the function below. RLS with no policies, and the
-- function is security definer, so no role reaches the rows directly.
alter table public.ingest_hits enable row level security;
revoke all on public.ingest_hits from anon, authenticated;

-- Counts one request and says whether it is inside the limit.
--
-- One statement does the count, so two requests arriving together cannot
-- both read the old number. Old windows for this key are cleared as it goes,
-- which bounds the table at a few rows per active key without a cron job.
create or replace function public.ingest_allow(
  p_key uuid,
  p_bucket text,
  p_limit integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  w timestamptz := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  n integer;
begin
  insert into public.ingest_hits as h (key_id, bucket, window_start, hits)
    values (p_key, p_bucket, w, 1)
  on conflict (key_id, bucket, window_start)
    do update set hits = h.hits + 1
  returning h.hits into n;

  delete from public.ingest_hits
    where key_id = p_key and bucket = p_bucket and window_start < w;

  return n <= p_limit;
end
$$;

revoke all on function public.ingest_allow(uuid, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.ingest_allow(uuid, text, integer, integer)
  to service_role;

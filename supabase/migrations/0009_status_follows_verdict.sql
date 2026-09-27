-- One status. dev_verdict is what a developer sets; status follows it.
--
-- 0005 kept two verdicts on purpose (dev and tester disagree usefully), but
-- the older `status` column stayed writable beside dev_verdict and the two
-- drifted. Found on the live board, 25 Sep: dev verdict Won't Fix left
-- status=open, so the comment stayed in the Open tab and its count; the list's
-- Resolve button set status=resolved and left dev_verdict=new. Every count
-- built on either column was wrong in a different direction.
--
-- status is kept, not dropped: the SDK, the RLS tests and the list tabs read
-- it, and a generated column cannot be written by old clients at all. A
-- trigger keeps it derived instead, and maps an old client's status-only write
-- back onto the verdict so nothing drifts in either direction.

create or replace function public.status_for_verdict(verdict text)
returns comment_status
language sql immutable
as $$
  select case verdict
    when 'in_progress' then 'in_progress'::comment_status
    when 'fixed'       then 'resolved'::comment_status
    when 'wont_fix'    then 'resolved'::comment_status
    when 'deferred'    then 'resolved'::comment_status
    else                    'open'::comment_status      -- new, blocked
  end
$$;

create or replace function public.comments_status_follows_verdict()
returns trigger
language plpgsql
as $$
begin
  -- A status-only write (dev_verdict untouched) comes from a client that
  -- predates this migration. Move the verdict to match, then derive as usual.
  if tg_op = 'UPDATE'
     and new.status is distinct from old.status
     and new.dev_verdict is not distinct from old.dev_verdict then
    new.dev_verdict := case new.status
      when 'resolved'    then 'fixed'
      when 'in_progress' then 'in_progress'
      else case when old.dev_verdict = 'blocked' then 'blocked' else 'new' end
    end;
  end if;

  new.status := public.status_for_verdict(new.dev_verdict);
  return new;
end
$$;

drop trigger if exists comments_status_follows_verdict on public.comments;
create trigger comments_status_follows_verdict
  before insert or update of status, dev_verdict on public.comments
  for each row execute function public.comments_status_follows_verdict();

-- Backfill. A row resolved from the list with verdict still `new` meant
-- "done", so it becomes fixed; an in-progress status with verdict `new` moves
-- the verdict. Everything else takes its status from the verdict it already has.
-- Disabled trigger: these rows are being reconciled, not edited.
alter table public.comments disable trigger comments_status_follows_verdict;

update public.comments
   set dev_verdict = case status
         when 'resolved'    then 'fixed'
         when 'in_progress' then 'in_progress'
       end
 where dev_verdict = 'new' and status in ('resolved', 'in_progress');

update public.comments
   set status = public.status_for_verdict(dev_verdict)
 where status is distinct from public.status_for_verdict(dev_verdict);

alter table public.comments enable trigger comments_status_follows_verdict;

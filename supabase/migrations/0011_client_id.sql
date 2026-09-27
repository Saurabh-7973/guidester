-- The SDK's offline queue retries a comment until the server answers. A retry
-- after a timeout can reach a server that already stored the first attempt, so
-- every comment carries an id the device made once, and the second arrival is
-- recognised instead of stored twice.
--
-- Nullable: every comment before this, and every SDK build before 0.5.0, has
-- none. Unique per project rather than globally, so the id is only ever
-- compared against rows the same key could have written.

alter table public.comments
  add column if not exists client_id text
    check (client_id is null or length(client_id) between 8 and 64);

create unique index if not exists comments_client_id_key
  on public.comments (project_id, client_id)
  where client_id is not null;

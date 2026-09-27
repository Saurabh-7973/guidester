-- Deletion. G4 in the developer field test: there is no delete in the schema,
-- the UI or the storage path.
--
-- A tester screenshots a screen carrying their own real data and asks for it to
-- be removed. Under the DPDP Act that request is not optional and the project
-- owner is the data fiduciary, so this ships before twelve strangers use the
-- product, not after one of them asks.
--
-- Two shapes are needed and both are covered by the same policies: delete one
-- comment, and delete everything from one tester_id.

-- Same ownership test as select and update: you may delete a comment only in a
-- project you own. Nothing here lets a tester delete anything — testers have no
-- account, and `anon` still reaches the API and receives nothing.
create policy "owner deletes comments" on public.comments
  for delete to authenticated using (
    exists (select 1 from public.projects p
            where p.id = comments.project_id and p.owner_id = auth.uid())
  );

-- The row is only half of it. A deleted comment whose screenshot survives in
-- storage is exactly the failure the request was about, so the object must be
-- deletable by the same owner. Screenshots are keyed by project id as the first
-- path segment, which is what makes this checkable.
create policy "owner deletes own screenshots" on storage.objects
  for delete to authenticated using (
    bucket_id = 'screenshots'
    and (storage.foldername(name))[1] in (
      select p.id::text from public.projects p where p.owner_id = auth.uid()
    )
  );

-- Deleting by tester wants an index: without one, "everything from this tester"
-- is a sequential scan of the whole project's comments.
create index if not exists comments_tester_idx
  on public.comments (project_id, tester_id);

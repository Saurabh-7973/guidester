-- An owner can delete their own project (redesign spec §5.6 row 8).
--
-- The rows under it already cascade: comments, their events and verdict
-- history, and project keys all reference projects(id) on delete cascade.
-- Screenshots do not: they live in storage, keyed by project id, and the
-- storage policy that lets an owner delete them checks project ownership. So
-- the dashboard removes the project's screenshots FIRST and the row second;
-- after the row is gone nobody could.

create policy "owner deletes projects" on public.projects
  for delete to authenticated using (owner_id = auth.uid());

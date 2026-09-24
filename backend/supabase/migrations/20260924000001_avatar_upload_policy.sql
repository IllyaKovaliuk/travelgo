-- `route-covers` had a SELECT policy (public) and an INSERT policy
-- (any authenticated user) but no UPDATE policy. Cover photos never
-- needed one — every publish writes a brand-new random path. Avatars
-- reuse a *fixed* path per user (`avatars/<id>/avatar.jpg`, upserted) so
-- changing your photo replaces the old file instead of piling up
-- orphans — but an upsert onto an existing object is an UPDATE under
-- RLS, which had nothing granting it, so the second time anyone changed
-- their avatar the upload would have failed.
create policy "Authenticated users can update cover photos"
  on storage.objects for update
  using (bucket_id = 'route-covers' and auth.role() = 'authenticated')
  with check (bucket_id = 'route-covers' and auth.role() = 'authenticated');

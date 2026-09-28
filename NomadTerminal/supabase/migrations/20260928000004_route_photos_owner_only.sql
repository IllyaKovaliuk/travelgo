-- Correction to 20260928000002: photos are NOT open to "any authenticated
-- user" the way comments are — only the route's own author can add photos
-- to their route (mid-recording, or after the fact from Route Detail).
-- Replaces "Authenticated users can add photos" with an author check.
drop policy if exists "Authenticated users can add photos" on public.route_photos;

create policy "Only the route's author can add photos"
    on public.route_photos for insert
    with check (
        auth.uid() = uploader_id
        and exists (
            select 1 from public.routes r
            where r.id = route_photos.route_id and r.author_id = auth.uid()
        )
    );

-- Same tightening on the storage side: the route-photos bucket previously
-- accepted an upload from anyone signed in; a route_photos row can now
-- only ever be inserted by the route's author anyway, but this keeps the
-- storage layer from being a looser gate than the table it's for.
drop policy if exists "Authenticated users can upload route photos" on storage.objects;

create policy "Authenticated users can upload to their own folder"
    on storage.objects for insert
    with check (bucket_id = 'route-photos' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);

-- Account deletion must also remove the user's uploaded files.
--
-- Why this is NOT `delete from storage.objects where owner = uid` inside
-- delete_my_account(): Supabase guards that table with a
-- `protect_objects_delete` trigger that raises 42501 ("Direct deletion from
-- storage tables is not allowed. Use the Storage API instead.") unless
-- `storage.allow_delete_query` is set — a direct DELETE would make account
-- deletion fail outright. And even with the bypass, a SQL delete only drops
-- the metadata row: the file itself stays in object storage and, because
-- every bucket here is public, stays reachable by its URL.
--
-- So files are removed through the Storage API by the client, right before
-- it calls delete_my_account() (while the session is still valid). This
-- migration provides the two server-side pieces that makes possible:
--   1. a way to enumerate everything the caller owns, in any bucket
--      (avatars live in route-covers under `avatars/<uid>/`; there is no
--      separate avatars bucket), and
--   2. the missing DELETE policy on route-covers (route-photos and
--      hazard-photos already have owner-based ones).

create or replace function public.my_storage_objects()
returns table (bucket_id text, name text)
language sql
stable
security definer
set search_path = public, storage
as $$
  select o.bucket_id, o.name
  from storage.objects o
  where o.owner = auth.uid()
    and auth.uid() is not null;
$$;

revoke all on function public.my_storage_objects() from public, anon;
grant execute on function public.my_storage_objects() to authenticated;

create policy "Uploaders can delete their own cover files"
    on storage.objects for delete
    using (bucket_id = 'route-covers' and owner = auth.uid());

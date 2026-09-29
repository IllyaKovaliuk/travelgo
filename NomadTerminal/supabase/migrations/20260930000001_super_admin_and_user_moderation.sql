-- Super admin (can appoint/revoke other admins) + real user-level
-- moderation: ban/unban, direct hide/delete of content (not just
-- reinstate-after-3-reports), and browsing a specific user's own
-- content. Founder's real account becomes the one and only super admin.
alter table public.profiles add column if not exists is_super_admin boolean not null default false;
alter table public.profiles add column if not exists is_banned boolean not null default false;

update public.profiles set is_super_admin = true, is_admin = true
where id = '0e74178a-a229-435e-8dee-901ba8fbc205';

-- Only a super admin can grant/revoke the admin role itself.
create or replace function public.admin_set_admin_role(target_user_id uuid, make_admin boolean)
returns void as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_super_admin) then
    raise exception 'not authorized';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'cannot change your own admin role';
  end if;
  update public.profiles set is_admin = make_admin where id = target_user_id;
end;
$$ language plpgsql security definer set search_path = public;

-- Real ban: blocks future sign-ins/token refresh at the auth layer
-- (auth.users.banned_until — the actual mechanism Supabase Auth itself
-- checks) *and* immediately blocks new routes/comments/photos via the
-- is_banned checks added to those tables' write policies below, so a
-- still-valid existing session can't keep posting in the meantime.
create or replace function public.admin_set_user_banned(target_user_id uuid, banned boolean)
returns void as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'not authorized';
  end if;
  if exists (select 1 from public.profiles where id = target_user_id and is_super_admin) then
    raise exception 'cannot ban a super admin';
  end if;
  update public.profiles set is_banned = banned where id = target_user_id;
  update auth.users
    set banned_until = case when banned then timestamptz '2099-01-01T00:00:00Z' else null end
    where id = target_user_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.admin_search_users(query text)
returns table (
    id uuid, username text, display_name text,
    is_admin boolean, is_super_admin boolean, is_banned boolean, created_at timestamptz
) as $$
  select p.id, p.username, p.display_name, p.is_admin, p.is_super_admin, p.is_banned, p.created_at
  from public.profiles p
  where exists (select 1 from public.profiles ap where ap.id = auth.uid() and ap.is_admin)
    and (query = '' or p.username ilike '%' || query || '%' or p.display_name ilike '%' || query || '%')
  order by p.created_at desc
  limit 50;
$$ language sql security definer set search_path = public;

-- Real, permanent delete — separate from the existing reinstate-only
-- flow, for content that should just be gone, not just hidden.
create or replace function public.admin_delete_route(target_id uuid)
returns void as $$
  delete from public.routes where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

create or replace function public.admin_delete_comment(target_id uuid)
returns void as $$
  delete from public.route_comments where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

create or replace function public.admin_delete_photo(target_id uuid)
returns void as $$
  delete from public.route_photos where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

-- Direct hide — an admin acting proactively, not waiting on 3 reports.
create or replace function public.admin_hide_route(target_id uuid)
returns void as $$
  update public.routes set status = 'hidden' where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

create or replace function public.admin_hide_comment(target_id uuid)
returns void as $$
  update public.route_comments set hidden = true where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

create or replace function public.admin_hide_photo(target_id uuid)
returns void as $$
  update public.route_photos set hidden = true where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

-- Browse one specific user's real content — the actual "block photos"
-- workflow: find the user, see what they've posted, hide/delete inline,
-- not only ever react to something that already collected 3 reports.
create or replace function public.admin_list_user_photos(target_user_id uuid)
returns table (id uuid, image_url text, route_id uuid, route_title text, hidden boolean, created_at timestamptz)
as $$
  select ph.id, ph.image_url, ph.route_id, r.title, ph.hidden, ph.created_at
  from public.route_photos ph
  join public.routes r on r.id = ph.route_id
  where ph.uploader_id = target_user_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin)
  order by ph.created_at desc;
$$ language sql security definer set search_path = public;

create or replace function public.admin_list_user_routes(target_user_id uuid)
returns table (id uuid, title text, status text, created_at timestamptz)
as $$
  select r.id, r.title, r.status::text, r.created_at
  from public.routes r
  where r.author_id = target_user_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin)
  order by r.created_at desc;
$$ language sql security definer set search_path = public;

-- Block a banned user from posting new content immediately, rather than
-- waiting on their session to actually expire/refresh.
drop policy if exists "Owners manage their own routes" on public.routes;
create policy "Owners manage their own routes"
    on public.routes for all
    using (auth.uid() = author_id)
    with check (
        auth.uid() = author_id
        and not coalesce((select is_banned from public.profiles where id = auth.uid()), false)
    );

drop policy if exists "Authenticated users can comment" on public.route_comments;
create policy "Authenticated users can comment"
    on public.route_comments for insert
    with check (
        auth.uid() = author_id
        and not coalesce((select is_banned from public.profiles where id = auth.uid()), false)
    );

drop policy if exists "Only the route's author can add photos" on public.route_photos;
create policy "Only the route's author can add photos"
    on public.route_photos for insert
    with check (
        auth.uid() = uploader_id
        and not coalesce((select is_banned from public.profiles where id = auth.uid()), false)
        and exists (
            select 1 from public.routes r
            where r.id = route_photos.route_id and r.author_id = auth.uid()
        )
    );

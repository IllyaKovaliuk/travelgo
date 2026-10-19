-- Real admin role — until now, admin_list_hidden_*/admin_reinstate_* were
-- `security definer` + granted to `authenticated`, reachable by literally
-- any signed-in user (a documented, accepted trade-off "at this scale" —
-- fine with zero real users, a real hole once there are some). Adds a
-- genuine is_admin flag and gates every admin RPC on it server-side, not
-- just hiding the button client-side.
alter table public.profiles add column if not exists is_admin boolean not null default false;

-- The founder's real account — the only one that should start as admin.
update public.profiles set is_admin = true where id = '0e74178a-a229-435e-8dee-901ba8fbc205';

create or replace function public.admin_list_hidden_routes()
returns table (
    id uuid, title text, place text, author_id uuid, author_name text,
    report_count int, reasons text[], created_at timestamptz
) as $$
  select
    r.id, r.title, r.place, r.author_id, p.display_name,
    (select count(distinct cr.reporter_id)::int from content_reports cr
      where cr.target_type = 'route' and cr.target_id = r.id),
    (select array_agg(distinct cr.reason) from content_reports cr
      where cr.target_type = 'route' and cr.target_id = r.id),
    r.created_at
  from routes r
  join profiles p on p.id = r.author_id
  where r.status = 'hidden'
    and exists (select 1 from public.profiles ap where ap.id = auth.uid() and ap.is_admin)
  order by r.created_at desc;
$$ language sql security definer set search_path = public;

create or replace function public.admin_list_hidden_comments()
returns table (
    id uuid, body text, route_id uuid, route_title text, author_id uuid, author_name text,
    report_count int, reasons text[], created_at timestamptz
) as $$
  select
    c.id, c.body, c.route_id, r.title, c.author_id, p.display_name,
    (select count(distinct cr.reporter_id)::int from content_reports cr
      where cr.target_type = 'comment' and cr.target_id = c.id),
    (select array_agg(distinct cr.reason) from content_reports cr
      where cr.target_type = 'comment' and cr.target_id = c.id),
    c.created_at
  from route_comments c
  join routes r on r.id = c.route_id
  join profiles p on p.id = c.author_id
  where c.hidden = true
    and exists (select 1 from public.profiles ap where ap.id = auth.uid() and ap.is_admin)
  order by c.created_at desc;
$$ language sql security definer set search_path = public;

create or replace function public.admin_list_hidden_photos()
returns table (
    id uuid, image_url text, caption text, route_id uuid, route_title text,
    uploader_id uuid, uploader_name text, report_count int, reasons text[], created_at timestamptz
) as $$
  select
    ph.id, ph.image_url, ph.caption, ph.route_id, r.title, ph.uploader_id, p.display_name,
    (select count(distinct cr.reporter_id)::int from content_reports cr
      where cr.target_type = 'photo' and cr.target_id = ph.id),
    (select array_agg(distinct cr.reason) from content_reports cr
      where cr.target_type = 'photo' and cr.target_id = ph.id),
    ph.created_at
  from route_photos ph
  join routes r on r.id = ph.route_id
  join profiles p on p.id = ph.uploader_id
  where ph.hidden = true
    and exists (select 1 from public.profiles ap where ap.id = auth.uid() and ap.is_admin)
  order by ph.created_at desc;
$$ language sql security definer set search_path = public;

create or replace function public.admin_reinstate_route(target_id uuid)
returns void as $$
  update routes set status = 'published'
  where id = target_id and status = 'hidden'
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

create or replace function public.admin_reinstate_comment(target_id uuid)
returns void as $$
  update route_comments set hidden = false
  where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

create or replace function public.admin_reinstate_photo(target_id uuid)
returns void as $$
  update route_photos set hidden = false
  where id = target_id
    and exists (select 1 from public.profiles where id = auth.uid() and is_admin);
$$ language sql security definer set search_path = public;

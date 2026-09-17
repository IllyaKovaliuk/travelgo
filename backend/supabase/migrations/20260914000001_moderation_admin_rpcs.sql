-- Real admin review/reinstate for auto-hidden content — the original
-- moderation migration (20260901000002) shipped auto-hide with "reviewing/
-- reinstating wrongly-hidden content is a manual SQL job for now, which is
-- an acceptable trade-off at this scale but should become a real admin
-- tool once there's enough volume for false positives to matter." This is
-- that tool.
--
-- Known, deliberate limitation: there is no admin-role/auth-tier system in
-- this app (out of scope here — would need real user roles). These RPCs
-- are `security definer` (bypass RLS) and granted to any `authenticated`
-- user, not just a designated admin, matching the trust model the
-- original moderation migration already accepted ("acceptable trade-off
-- at this scale"). Fine while the founder is the only real user of this
-- screen; worth real role-gating before this matters for abuse.

create or replace function public.admin_list_hidden_routes()
returns table (
  id uuid,
  title text,
  place text,
  author_id uuid,
  author_name text,
  report_count integer,
  reasons text[],
  created_at timestamptz
)
language sql
security definer set search_path = public
as $$
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
  order by r.created_at desc;
$$;

create or replace function public.admin_list_hidden_comments()
returns table (
  id uuid,
  body text,
  route_id uuid,
  route_title text,
  author_id uuid,
  author_name text,
  report_count integer,
  reasons text[],
  created_at timestamptz
)
language sql
security definer set search_path = public
as $$
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
  order by c.created_at desc;
$$;

create or replace function public.admin_reinstate_route(target_id uuid)
returns void
language sql
security definer set search_path = public
as $$
  update routes set status = 'published' where id = target_id and status = 'hidden';
$$;

create or replace function public.admin_reinstate_comment(target_id uuid)
returns void
language sql
security definer set search_path = public
as $$
  update route_comments set hidden = false where id = target_id;
$$;

grant execute on function public.admin_list_hidden_routes() to authenticated;
grant execute on function public.admin_list_hidden_comments() to authenticated;
grant execute on function public.admin_reinstate_route(uuid) to authenticated;
grant execute on function public.admin_reinstate_comment(uuid) to authenticated;

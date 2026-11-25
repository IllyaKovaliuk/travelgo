-- Crews (private groups of friends) and Expeditions (shared trips).
--
-- All state changes go through SECURITY DEFINER RPCs — the client reads
-- (RLS-scoped to members) and calls RPCs, nothing else, so the rules live in
-- one place and an Android client can reuse them as-is. A user only ever sees
-- crews / expeditions they belong to.
--
-- No realtime and no money here: v1 is plain fetch + pull-to-refresh, and the
-- shared budget / expense ledger is a later phase.

-- ── Types ───────────────────────────────────────────────────────────────
create type public.crew_role as enum ('owner', 'organizer', 'member');
create type public.expedition_role as enum ('organizer', 'member');
create type public.trip_type as enum ('road_trip', 'hiking', 'camping', 'city', 'ski');
create type public.expedition_status as enum ('planning', 'active', 'completed', 'cancelled');
create type public.stop_kind as enum ('accommodation', 'food', 'activity', 'poi');

-- ── Tables ──────────────────────────────────────────────────────────────
-- owner_id / organizer_id are ON DELETE RESTRICT on purpose: deleting an
-- account must hand the crew / trip to someone else first (see
-- delete_my_account below), never silently cascade a group's history away.
create table public.crews (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(btrim(name)) between 1 and 60),
    cover_image_url text,
    owner_id uuid not null references public.profiles(id) on delete restrict,
    created_at timestamptz not null default now()
);

create table public.crew_members (
    crew_id uuid not null references public.crews(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    role public.crew_role not null default 'member',
    joined_at timestamptz not null default now(),
    primary key (crew_id, user_id)
);
create index crew_members_user_id_idx on public.crew_members(user_id);
-- Exactly one owner per crew.
create unique index crew_members_one_owner_idx on public.crew_members(crew_id) where role = 'owner';

create table public.crew_invites (
    id uuid primary key default gen_random_uuid(),
    crew_id uuid not null references public.crews(id) on delete cascade,
    code text not null unique,
    created_by uuid not null references public.profiles(id) on delete cascade,
    expires_at timestamptz not null default (now() + interval '14 days'),
    max_uses integer check (max_uses is null or max_uses > 0),
    uses integer not null default 0,
    revoked boolean not null default false,
    created_at timestamptz not null default now()
);
create index crew_invites_crew_id_idx on public.crew_invites(crew_id);

create table public.expeditions (
    id uuid primary key default gen_random_uuid(),
    crew_id uuid references public.crews(id) on delete cascade,
    name text not null check (char_length(btrim(name)) between 1 and 80),
    cover_image_url text,
    trip_type public.trip_type not null default 'road_trip',
    start_date date,
    end_date date,
    status public.expedition_status not null default 'planning',
    organizer_id uuid not null references public.profiles(id) on delete restrict,
    created_at timestamptz not null default now(),
    constraint expeditions_dates_ordered check (end_date is null or start_date is null or end_date >= start_date)
);
create index expeditions_crew_id_idx on public.expeditions(crew_id);

create table public.expedition_members (
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    role public.expedition_role not null default 'member',
    joined_at timestamptz not null default now(),
    primary key (expedition_id, user_id)
);
create index expedition_members_user_id_idx on public.expedition_members(user_id);

-- added_by is SET NULL, not CASCADE: someone leaving Nomad shouldn't delete
-- the stops and routes the rest of the group is relying on.
create table public.expedition_routes (
    id uuid primary key default gen_random_uuid(),
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    route_id uuid not null references public.routes(id) on delete cascade,
    day_index integer check (day_index is null or day_index >= 1),
    position integer not null default 0,
    added_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    unique (expedition_id, route_id)
);

create table public.expedition_stops (
    id uuid primary key default gen_random_uuid(),
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    kind public.stop_kind not null default 'poi',
    title text not null check (char_length(btrim(title)) between 1 and 120),
    notes text check (notes is null or char_length(notes) <= 2000),
    lat double precision check (lat is null or lat between -90 and 90),
    lng double precision check (lng is null or lng between -180 and 180),
    day_index integer check (day_index is null or day_index >= 1),
    position integer not null default 0,
    added_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);
create index expedition_stops_expedition_idx on public.expedition_stops(expedition_id);

-- ── Membership helpers ──────────────────────────────────────────────────
-- SECURITY DEFINER so policies can ask "is the viewer in this crew?" without
-- recursing into the very table's own RLS.
create or replace function public.is_crew_member(p_crew_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.crew_members
                 where crew_id = p_crew_id and user_id = auth.uid());
$$;

create or replace function public.is_crew_manager(p_crew_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.crew_members
                 where crew_id = p_crew_id and user_id = auth.uid()
                   and role in ('owner', 'organizer'));
$$;

-- Everyone in the crew sees its expeditions; ad-hoc trips (no crew) are
-- visible to their explicit participants.
create or replace function public.can_see_expedition(p_expedition_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.expeditions e
    where e.id = p_expedition_id
      and (
        exists (select 1 from public.expedition_members m
                where m.expedition_id = e.id and m.user_id = auth.uid())
        or (e.crew_id is not null and exists (
              select 1 from public.crew_members c
              where c.crew_id = e.crew_id and c.user_id = auth.uid()))
      )
  );
$$;

create or replace function public.can_manage_expedition(p_expedition_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.expeditions e
    where e.id = p_expedition_id
      and (
        e.organizer_id = auth.uid()
        or exists (select 1 from public.expedition_members m
                   where m.expedition_id = e.id and m.user_id = auth.uid() and m.role = 'organizer')
        or (e.crew_id is not null and exists (
              select 1 from public.crew_members c
              where c.crew_id = e.crew_id and c.user_id = auth.uid() and c.role in ('owner','organizer')))
      )
  );
$$;

revoke all on function public.is_crew_member(uuid), public.is_crew_manager(uuid),
  public.can_see_expedition(uuid), public.can_manage_expedition(uuid) from public, anon;
grant execute on function public.is_crew_member(uuid), public.is_crew_manager(uuid),
  public.can_see_expedition(uuid), public.can_manage_expedition(uuid) to authenticated;

-- ── Row Level Security ──────────────────────────────────────────────────
alter table public.crews enable row level security;
alter table public.crew_members enable row level security;
alter table public.crew_invites enable row level security;
alter table public.expeditions enable row level security;
alter table public.expedition_members enable row level security;
alter table public.expedition_routes enable row level security;
alter table public.expedition_stops enable row level security;

-- Crews: members read; managers rename. Creating / deleting / membership
-- changes are RPC-only.
create policy "Members read their crews" on public.crews
    for select using (public.is_crew_member(id));
create policy "Managers edit their crew" on public.crews
    for update using (public.is_crew_manager(id)) with check (public.is_crew_manager(id));

create policy "Members read their crew's roster" on public.crew_members
    for select using (public.is_crew_member(crew_id));
-- A block hides the blocked person from the blocker's roster view
-- (Guideline 1.2), same RESTRICTIVE pattern as the route policies.
create policy "Hide blocked users in rosters" on public.crew_members
    as restrictive for select
    using (user_id = auth.uid() or not public.is_blocked_by_viewer(user_id));

-- Invites: managers see the codes for their crew; everything else is RPC.
create policy "Managers read their crew's invites" on public.crew_invites
    for select using (public.is_crew_manager(crew_id));

create policy "Members read expeditions" on public.expeditions
    for select using (public.can_see_expedition(id));
create policy "Managers edit expeditions" on public.expeditions
    for update using (public.can_manage_expedition(id)) with check (public.can_manage_expedition(id));
create policy "Managers delete expeditions" on public.expeditions
    for delete using (public.can_manage_expedition(id));

create policy "Members read expedition roster" on public.expedition_members
    for select using (public.can_see_expedition(expedition_id));
create policy "Hide blocked users in expedition rosters" on public.expedition_members
    as restrictive for select
    using (user_id = auth.uid() or not public.is_blocked_by_viewer(user_id));

create policy "Members read expedition routes" on public.expedition_routes
    for select using (public.can_see_expedition(expedition_id));
create policy "Members remove expedition routes" on public.expedition_routes
    for delete using (public.can_see_expedition(expedition_id));
create policy "Members reorder expedition routes" on public.expedition_routes
    for update using (public.can_see_expedition(expedition_id))
    with check (public.can_see_expedition(expedition_id));

create policy "Members read expedition stops" on public.expedition_stops
    for select using (public.can_see_expedition(expedition_id));
create policy "Members edit expedition stops" on public.expedition_stops
    for update using (public.can_see_expedition(expedition_id))
    with check (public.can_see_expedition(expedition_id));
create policy "Members remove expedition stops" on public.expedition_stops
    for delete using (public.can_see_expedition(expedition_id));

-- Explicit grants (no default-privilege reliance). No INSERT anywhere: every
-- row is created by an RPC.
revoke all on public.crews, public.crew_members, public.crew_invites, public.expeditions,
  public.expedition_members, public.expedition_routes, public.expedition_stops from anon, authenticated;
grant select, update on public.crews to authenticated;
grant select on public.crew_members, public.crew_invites, public.expedition_members to authenticated;
grant select, update, delete on public.expeditions to authenticated;
grant select, update, delete on public.expedition_routes, public.expedition_stops to authenticated;
-- Column-level: a manager may rename/re-cover a crew but never re-assign
-- its owner or id from the client.
revoke update on public.crews from authenticated;
grant update (name, cover_image_url) on public.crews to authenticated;
revoke update on public.expeditions from authenticated;
grant update (name, cover_image_url, trip_type, start_date, end_date, status) on public.expeditions to authenticated;
revoke update on public.expedition_routes from authenticated;
grant update (day_index, position) on public.expedition_routes to authenticated;
revoke update on public.expedition_stops from authenticated;
grant update (kind, title, notes, lat, lng, day_index, position) on public.expedition_stops to authenticated;

-- ── RPCs ────────────────────────────────────────────────────────────────
-- Inserts the crew AND the owner's membership atomically, so the creator can
-- read their own crew the moment this returns.
create or replace function public.create_crew(p_name text, p_cover text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_id uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if (select count(*) from crews where owner_id = uid) >= 20 then
    raise exception 'crew limit reached';
  end if;
  insert into crews (name, cover_image_url, owner_id)
    values (btrim(p_name), p_cover, uid) returning id into v_id;
  insert into crew_members (crew_id, user_id, role) values (v_id, uid, 'owner');
  return v_id;
end;
$$;

-- Random URL-safe code; any crew member can make one (the invite loop is how a
-- crew grows, so it isn't limited to managers), anyone with it can join.
create or replace function public.create_crew_invite(
  p_crew_id uuid, p_max_uses integer default null, p_ttl_days integer default 14)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_code text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_crew_member(p_crew_id) then raise exception 'not allowed'; end if;
  loop
    -- gen_random_uuid() is core Postgres (pgcrypto's gen_random_bytes lives in
    -- the `extensions` schema on Supabase, outside our search_path).
    v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
    exit when not exists (select 1 from crew_invites where code = v_code);
  end loop;
  insert into crew_invites (crew_id, code, created_by, expires_at, max_uses)
    values (p_crew_id, v_code, auth.uid(),
            now() + make_interval(days => greatest(1, least(coalesce(p_ttl_days, 14), 60))),
            p_max_uses);
  return v_code;
end;
$$;

create or replace function public.revoke_crew_invite(p_code text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update crew_invites set revoked = true
   where code = p_code and is_crew_manager(crew_id);
end;
$$;

-- What the join screen shows before someone commits. Safe for any signed-in
-- user: only name / cover / member count, and only for a live code.
create or replace function public.preview_crew_by_code(p_code text)
returns table (crew_id uuid, name text, cover_image_url text, member_count bigint, already_member boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.cover_image_url,
         (select count(*) from crew_members m where m.crew_id = c.id),
         exists (select 1 from crew_members m where m.crew_id = c.id and m.user_id = auth.uid())
  from crew_invites i join crews c on c.id = i.crew_id
  where i.code = p_code and not i.revoked and i.expires_at > now()
    and (i.max_uses is null or i.uses < i.max_uses)
    and auth.uid() is not null;
$$;

create or replace function public.join_crew_by_code(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_inv crew_invites%rowtype;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into v_inv from crew_invites
   where code = p_code and not revoked and expires_at > now()
     and (max_uses is null or uses < max_uses)
   for update;
  if not found then raise exception 'invite invalid or expired'; end if;
  if exists (select 1 from user_blocks b
              where (b.blocker_id = v_inv.created_by and b.blocked_id = uid)) then
    raise exception 'invite invalid or expired';
  end if;
  if (select count(*) from crew_members where crew_id = v_inv.crew_id) >= 50 then
    raise exception 'crew is full';
  end if;
  insert into crew_members (crew_id, user_id, role) values (v_inv.crew_id, uid, 'member')
    on conflict do nothing;
  if found then
    update crew_invites set uses = uses + 1 where id = v_inv.id;
    -- Join the crew's open trips too, so "my trips" is complete.
    insert into expedition_members (expedition_id, user_id, role)
      select e.id, uid, 'member' from expeditions e
       where e.crew_id = v_inv.crew_id and e.status in ('planning', 'active')
    on conflict do nothing;
  end if;
  return v_inv.crew_id;
end;
$$;

create or replace function public.leave_crew(p_crew_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_role crew_role;
begin
  select role into v_role from crew_members where crew_id = p_crew_id and user_id = uid;
  if not found then return; end if;
  if v_role = 'owner' then
    raise exception 'transfer ownership before leaving';
  end if;
  delete from expedition_members
   where user_id = uid and expedition_id in (select id from expeditions where crew_id = p_crew_id);
  delete from crew_members where crew_id = p_crew_id and user_id = uid;
end;
$$;

create or replace function public.set_crew_member_role(p_crew_id uuid, p_user_id uuid, p_role crew_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if p_user_id = uid then raise exception 'cannot change your own role'; end if;
  if p_role = 'owner' then
    -- Ownership transfer: owner only; the old owner becomes an organizer.
    if not exists (select 1 from crew_members where crew_id = p_crew_id and user_id = uid and role = 'owner') then
      raise exception 'not allowed';
    end if;
    update crew_members set role = 'organizer' where crew_id = p_crew_id and user_id = uid;
    update crew_members set role = 'owner' where crew_id = p_crew_id and user_id = p_user_id;
    update crews set owner_id = p_user_id where id = p_crew_id;
  else
    if not exists (select 1 from crew_members where crew_id = p_crew_id and user_id = uid and role = 'owner') then
      raise exception 'not allowed';
    end if;
    update crew_members set role = p_role
     where crew_id = p_crew_id and user_id = p_user_id and role <> 'owner';
  end if;
end;
$$;

create or replace function public.remove_crew_member(p_crew_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_target crew_role;
begin
  if not is_crew_manager(p_crew_id) then raise exception 'not allowed'; end if;
  select role into v_target from crew_members where crew_id = p_crew_id and user_id = p_user_id;
  if not found or v_target = 'owner' then raise exception 'not allowed'; end if;
  -- Organizers can't remove other organizers; only the owner can.
  if v_target = 'organizer' and not exists (
       select 1 from crew_members where crew_id = p_crew_id and user_id = auth.uid() and role = 'owner') then
    raise exception 'not allowed';
  end if;
  delete from expedition_members
   where user_id = p_user_id and expedition_id in (select id from expeditions where crew_id = p_crew_id);
  delete from crew_members where crew_id = p_crew_id and user_id = p_user_id;
end;
$$;

create or replace function public.delete_crew(p_crew_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_members where crew_id = p_crew_id and user_id = auth.uid() and role = 'owner') then
    raise exception 'not allowed';
  end if;
  delete from crews where id = p_crew_id;
end;
$$;

-- A trip inside a crew (any crew member can start one) or ad hoc (p_crew_id
-- null). Crew trips enrol everyone currently in the crew.
create or replace function public.create_expedition(
  p_name text, p_crew_id uuid default null, p_trip_type public.trip_type default 'road_trip',
  p_start date default null, p_end date default null, p_cover text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_id uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_crew_id is not null and not is_crew_member(p_crew_id) then raise exception 'not allowed'; end if;
  insert into expeditions (crew_id, name, cover_image_url, trip_type, start_date, end_date, organizer_id)
    values (p_crew_id, btrim(p_name), p_cover, p_trip_type, p_start, p_end, uid)
    returning id into v_id;
  insert into expedition_members (expedition_id, user_id, role) values (v_id, uid, 'organizer');
  if p_crew_id is not null then
    insert into expedition_members (expedition_id, user_id, role)
      select v_id, user_id, 'member' from crew_members where crew_id = p_crew_id and user_id <> uid;
  end if;
  return v_id;
end;
$$;

-- Only published, public routes — a member who can't open the route would
-- just see a dead row, and a private route must never leak through a trip.
create or replace function public.add_route_to_expedition(
  p_expedition_id uuid, p_route_id uuid, p_day integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not can_see_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from routes r where r.id = p_route_id
                  and r.status = 'published' and r.visibility = 'public') then
    raise exception 'route not available';
  end if;
  insert into expedition_routes (expedition_id, route_id, day_index, position, added_by)
    values (p_expedition_id, p_route_id, p_day,
            coalesce((select max(position) + 1 from expedition_routes where expedition_id = p_expedition_id), 0),
            auth.uid())
    on conflict (expedition_id, route_id) do update set day_index = excluded.day_index
    returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.add_expedition_stop(
  p_expedition_id uuid, p_kind public.stop_kind, p_title text,
  p_notes text default null, p_lat double precision default null,
  p_lng double precision default null, p_day integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not can_see_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  insert into expedition_stops (expedition_id, kind, title, notes, lat, lng, day_index, position, added_by)
    values (p_expedition_id, p_kind, btrim(p_title), p_notes, p_lat, p_lng, p_day,
            coalesce((select max(position) + 1 from expedition_stops where expedition_id = p_expedition_id), 0),
            auth.uid())
    returning id into v_id;
  return v_id;
end;
$$;

revoke all on function
  public.create_crew(text, text), public.create_crew_invite(uuid, integer, integer),
  public.revoke_crew_invite(text), public.preview_crew_by_code(text),
  public.join_crew_by_code(text), public.leave_crew(uuid),
  public.set_crew_member_role(uuid, uuid, crew_role), public.remove_crew_member(uuid, uuid),
  public.delete_crew(uuid),
  public.create_expedition(text, uuid, trip_type, date, date, text),
  public.add_route_to_expedition(uuid, uuid, integer),
  public.add_expedition_stop(uuid, stop_kind, text, text, double precision, double precision, integer)
  from public, anon;
grant execute on function
  public.create_crew(text, text), public.create_crew_invite(uuid, integer, integer),
  public.revoke_crew_invite(text), public.preview_crew_by_code(text),
  public.join_crew_by_code(text), public.leave_crew(uuid),
  public.set_crew_member_role(uuid, uuid, crew_role), public.remove_crew_member(uuid, uuid),
  public.delete_crew(uuid),
  public.create_expedition(text, uuid, trip_type, date, date, text),
  public.add_route_to_expedition(uuid, uuid, integer),
  public.add_expedition_stop(uuid, stop_kind, text, text, double precision, double precision, integer)
  to authenticated;

-- ── Account deletion (App Store 5.1.1(v)) ───────────────────────────────
-- crews.owner_id / expeditions.organizer_id are RESTRICT, so a leaving owner
-- hands the group over first: the oldest organizer, else the oldest member.
-- A crew where they were the only member (and trips nobody else is on) is
-- deleted with them. crew_members / expedition_members rows cascade.
create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r record;
  v_next uuid;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  for r in select id from crews where owner_id = uid loop
    select user_id into v_next from crew_members
     where crew_id = r.id and user_id <> uid
     order by (role = 'organizer') desc, joined_at asc, user_id asc
     limit 1;
    if v_next is null then
      delete from crews where id = r.id;
    else
      -- Drop the leaving owner's row first: only one owner row may exist.
      delete from crew_members where crew_id = r.id and user_id = uid;
      update crew_members set role = 'owner' where crew_id = r.id and user_id = v_next;
      update crews set owner_id = v_next where id = r.id;
    end if;
  end loop;

  for r in select id from expeditions where organizer_id = uid loop
    select user_id into v_next from expedition_members
     where expedition_id = r.id and user_id <> uid
     order by (role = 'organizer') desc, joined_at asc, user_id asc
     limit 1;
    if v_next is null then
      delete from expeditions where id = r.id;
    else
      update expedition_members set role = 'organizer' where expedition_id = r.id and user_id = v_next;
      update expeditions set organizer_id = v_next where id = r.id;
    end if;
  end loop;

  delete from profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

grant execute on function delete_my_account() to authenticated;

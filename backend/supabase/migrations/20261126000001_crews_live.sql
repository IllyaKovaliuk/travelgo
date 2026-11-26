-- Crews, part 2: decisions (polls), trip day (start / ready check / convoy),
-- live location, crew awareness alerts.
--
-- Same rules as part 1: clients only READ these tables; every write is an RPC
-- that checks who the caller is. Live location is the sensitive one, so:
--   * sharing is opt-in per expedition and has an end time;
--   * only the latest fix is kept (no location history);
--   * only people who are *going* on the expedition can read it, and only
--     while the sharer's share is active.

-- ── Expedition: start / finish, roles, car ──────────────────────────────
alter table public.expeditions
  add column if not exists started_at timestamptz,
  add column if not exists start_mode text check (start_mode is null or start_mode in ('convoy', 'foot'));

alter table public.expedition_members
  add column if not exists awareness_role text check (awareness_role is null or awareness_role in ('lead', 'sweep')),
  -- the driver whose car this person rides in (own id = driving). Null = not set.
  add column if not exists car_driver_id uuid references public.profiles(id) on delete set null;

-- "Going" = in expedition_members. Crew members can see the trip without going.
create or replace function public.is_expedition_participant(p_expedition_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.expedition_members
                 where expedition_id = p_expedition_id and user_id = auth.uid());
$$;

create or replace function public.join_expedition(p_expedition_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not can_see_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  insert into expedition_members (expedition_id, user_id, role)
    values (p_expedition_id, auth.uid(), 'member') on conflict do nothing;
end;
$$;

create or replace function public.set_expedition_role(p_expedition_id uuid, p_user_id uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  if p_role is not null and p_role not in ('lead', 'sweep') then raise exception 'bad role'; end if;
  -- one lead and one sweep at a time
  if p_role is not null then
    update expedition_members set awareness_role = null
     where expedition_id = p_expedition_id and awareness_role = p_role;
  end if;
  update expedition_members set awareness_role = p_role
   where expedition_id = p_expedition_id and user_id = p_user_id;
end;
$$;

create or replace function public.set_my_car(p_expedition_id uuid, p_driver_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_expedition_participant(p_expedition_id) then raise exception 'not allowed'; end if;
  if p_driver_id is not null and not exists (
       select 1 from expedition_members where expedition_id = p_expedition_id and user_id = p_driver_id) then
    raise exception 'driver is not on the trip';
  end if;
  update expedition_members set car_driver_id = p_driver_id
   where expedition_id = p_expedition_id and user_id = auth.uid();
end;
$$;

-- Ready check before start.
create table public.expedition_readiness (
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    offline_pct integer not null default 0 check (offline_pct between 0 and 100),
    gps_on boolean not null default false,
    battery integer check (battery is null or battery between 0 and 100),
    ready boolean not null default false,
    updated_at timestamptz not null default now(),
    primary key (expedition_id, user_id)
);

create or replace function public.set_readiness(
  p_expedition_id uuid, p_offline_pct integer, p_gps_on boolean, p_battery integer, p_ready boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_expedition_participant(p_expedition_id) then raise exception 'not allowed'; end if;
  insert into expedition_readiness (expedition_id, user_id, offline_pct, gps_on, battery, ready)
    values (p_expedition_id, auth.uid(), greatest(0, least(100, coalesce(p_offline_pct, 0))),
            coalesce(p_gps_on, false), p_battery, coalesce(p_ready, false))
  on conflict (expedition_id, user_id) do update
    set offline_pct = excluded.offline_pct, gps_on = excluded.gps_on,
        battery = excluded.battery, ready = excluded.ready, updated_at = now();
end;
$$;

create or replace function public.start_expedition(p_expedition_id uuid, p_mode text default 'foot')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  if p_mode not in ('convoy', 'foot') then raise exception 'bad mode'; end if;
  update expeditions set status = 'active', started_at = now(), start_mode = p_mode
   where id = p_expedition_id and status = 'planning';
  if not found then raise exception 'already started'; end if;
end;
$$;

create or replace function public.finish_expedition(p_expedition_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  update expeditions set status = 'completed' where id = p_expedition_id;
  -- Location sharing ends with the trip — nothing is left behind.
  delete from live_fixes where expedition_id = p_expedition_id;
  delete from live_shares where expedition_id = p_expedition_id;
end;
$$;

-- ── Polls ───────────────────────────────────────────────────────────────
create table public.polls (
    id uuid primary key default gen_random_uuid(),
    crew_id uuid not null references public.crews(id) on delete cascade,
    expedition_id uuid references public.expeditions(id) on delete cascade,
    day_index integer check (day_index is null or day_index >= 1),
    kind text not null check (kind in ('where', 'route', 'when', 'other')),
    question text not null check (char_length(btrim(question)) between 1 and 200),
    created_by uuid references public.profiles(id) on delete set null,
    closes_at timestamptz,
    allow_member_options boolean not null default true,
    close_when_all_voted boolean not null default true,
    status text not null default 'open' check (status in ('open', 'closed')),
    winner_option_id uuid,
    created_at timestamptz not null default now()
);
create index polls_crew_idx on public.polls(crew_id);
create index polls_expedition_idx on public.polls(expedition_id);

create table public.poll_options (
    id uuid primary key default gen_random_uuid(),
    poll_id uuid not null references public.polls(id) on delete cascade,
    label text not null check (char_length(btrim(label)) between 1 and 120),
    -- place {name, lat?, lng?} | route {route_id} | dates {start, end} | free text {}
    payload jsonb not null default '{}'::jsonb,
    added_by uuid references public.profiles(id) on delete set null,
    position integer not null default 0,
    created_at timestamptz not null default now()
);
create index poll_options_poll_idx on public.poll_options(poll_id);

alter table public.polls
  add constraint polls_winner_fk foreign key (winner_option_id)
  references public.poll_options(id) on delete set null;

create table public.poll_votes (
    poll_id uuid not null references public.polls(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    option_id uuid not null references public.poll_options(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (poll_id, user_id)
);

create or replace function public.can_see_poll(p_poll_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.polls p
    where p.id = p_poll_id
      and (case when p.expedition_id is not null then public.can_see_expedition(p.expedition_id)
                else public.is_crew_member(p.crew_id) end));
$$;

-- Who is expected to vote (for "close when everyone voted").
create or replace function public._poll_electorate(p_poll_id uuid)
returns table(user_id uuid) language sql stable security definer set search_path = public as $$
  select m.user_id from polls p
    join expedition_members m on m.expedition_id = p.expedition_id
   where p.id = p_poll_id and p.expedition_id is not null
  union
  select c.user_id from polls p
    join crew_members c on c.crew_id = p.crew_id
   where p.id = p_poll_id and p.expedition_id is null;
$$;

-- Closes a poll. Winner = the explicit pick, else the single leader; a tie
-- closes with no winner until an organizer picks one. A winning route option
-- on an expedition poll is placed into that day.
create or replace function public._finish_poll(p_poll_id uuid, p_winner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_poll polls%rowtype;
  v_win uuid := p_winner;
  v_top integer;
  v_leaders integer;
  v_route uuid;
begin
  select * into v_poll from polls where id = p_poll_id for update;
  if v_win is null then
    select max(cnt) into v_top from (
      select count(v.user_id) as cnt from poll_options o
        left join poll_votes v on v.option_id = o.id where o.poll_id = p_poll_id group by o.id) t;
    select count(*) into v_leaders from (
      select o.id from poll_options o left join poll_votes v on v.option_id = o.id
       where o.poll_id = p_poll_id group by o.id having count(v.user_id) = v_top) t;
    if coalesce(v_top, 0) > 0 and v_leaders = 1 then
      select o.id into v_win from poll_options o left join poll_votes v on v.option_id = o.id
       where o.poll_id = p_poll_id group by o.id having count(v.user_id) = v_top;
    end if;
  end if;
  update polls set status = 'closed', winner_option_id = v_win where id = p_poll_id;

  if v_win is not null and v_poll.kind = 'route' and v_poll.expedition_id is not null then
    begin
      v_route := nullif(
        (select payload ->> 'route_id' from poll_options where id = v_win), '')::uuid;
      if v_route is not null and exists (select 1 from routes r where r.id = v_route
                                          and r.status = 'published' and r.visibility = 'public') then
        insert into expedition_routes (expedition_id, route_id, day_index, position, added_by)
          values (v_poll.expedition_id, v_route, v_poll.day_index,
                  coalesce((select max(position) + 1 from expedition_routes
                             where expedition_id = v_poll.expedition_id), 0), v_poll.created_by)
        on conflict (expedition_id, route_id) do update set day_index = excluded.day_index;
      end if;
    exception when others then null;  -- a bad payload never blocks closing the poll
    end;
  end if;
end;
$$;

create or replace function public.create_poll(
  p_crew_id uuid, p_expedition_id uuid, p_day integer, p_kind text, p_question text,
  p_options jsonb, p_closes_at timestamptz default null,
  p_allow_member_options boolean default true, p_close_when_all_voted boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_id uuid;
  v_crew uuid := p_crew_id;
  o jsonb;
  n integer := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_expedition_id is not null then
    if not can_see_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
    select crew_id into v_crew from expeditions where id = p_expedition_id;
    if v_crew is null then raise exception 'polls need a crew'; end if;
  elsif not is_crew_member(v_crew) then
    raise exception 'not allowed';
  end if;
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) not between 2 and 6 then
    raise exception 'a poll needs 2 to 6 options';
  end if;

  insert into polls (crew_id, expedition_id, day_index, kind, question, created_by, closes_at,
                     allow_member_options, close_when_all_voted)
    values (v_crew, p_expedition_id, p_day, p_kind, btrim(p_question), uid, p_closes_at,
            coalesce(p_allow_member_options, true), coalesce(p_close_when_all_voted, true))
    returning id into v_id;
  for o in select * from jsonb_array_elements(p_options) loop
    insert into poll_options (poll_id, label, payload, added_by, position)
      values (v_id, btrim(o ->> 'label'), coalesce(o -> 'payload', '{}'::jsonb), uid, n);
    n := n + 1;
  end loop;
  return v_id;
end;
$$;

create or replace function public.add_poll_option(p_poll_id uuid, p_label text, p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_poll polls%rowtype;
  v_id uuid;
begin
  select * into v_poll from polls where id = p_poll_id;
  if not found or not can_see_poll(p_poll_id) then raise exception 'not allowed'; end if;
  if v_poll.status <> 'open' then raise exception 'poll is closed'; end if;
  if not v_poll.allow_member_options and v_poll.created_by is distinct from auth.uid() then
    raise exception 'only the author can add options';
  end if;
  if (select count(*) from poll_options where poll_id = p_poll_id) >= 6 then raise exception 'too many options'; end if;
  insert into poll_options (poll_id, label, payload, added_by, position)
    values (p_poll_id, btrim(p_label), coalesce(p_payload, '{}'::jsonb), auth.uid(),
            coalesce((select max(position) + 1 from poll_options where poll_id = p_poll_id), 0))
    returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.vote_poll(p_poll_id uuid, p_option_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_poll polls%rowtype;
begin
  select * into v_poll from polls where id = p_poll_id;
  if not found or not can_see_poll(p_poll_id) then raise exception 'not allowed'; end if;
  if v_poll.status <> 'open' or (v_poll.closes_at is not null and v_poll.closes_at < now()) then
    raise exception 'poll is closed';
  end if;
  if not exists (select 1 from poll_options where id = p_option_id and poll_id = p_poll_id) then
    raise exception 'unknown option';
  end if;
  insert into poll_votes (poll_id, user_id, option_id) values (p_poll_id, auth.uid(), p_option_id)
    on conflict (poll_id, user_id) do update set option_id = excluded.option_id, created_at = now();

  if v_poll.close_when_all_voted and not exists (
       select 1 from _poll_electorate(p_poll_id) e
        where not exists (select 1 from poll_votes v where v.poll_id = p_poll_id and v.user_id = e.user_id)) then
    perform _finish_poll(p_poll_id, null);
  end if;
end;
$$;

-- Organizer (or the author) closes early / picks the winner of a tie.
create or replace function public.close_poll(p_poll_id uuid, p_winner uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_poll polls%rowtype;
  v_ok boolean;
begin
  select * into v_poll from polls where id = p_poll_id;
  if not found then raise exception 'not found'; end if;
  v_ok := v_poll.created_by = auth.uid()
          or is_crew_manager(v_poll.crew_id)
          or (v_poll.expedition_id is not null and can_manage_expedition(v_poll.expedition_id));
  if not v_ok then raise exception 'not allowed'; end if;
  if v_poll.status = 'closed' and v_poll.winner_option_id is not null then raise exception 'poll is closed'; end if;
  if p_winner is not null and not exists (select 1 from poll_options where id = p_winner and poll_id = p_poll_id) then
    raise exception 'unknown option';
  end if;
  perform _finish_poll(p_poll_id, p_winner);
end;
$$;

-- Deadlines are enforced lazily: whoever opens the list closes what expired.
create or replace function public.settle_polls(p_crew_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if not is_crew_member(p_crew_id) then raise exception 'not allowed'; end if;
  for r in select id from polls
            where crew_id = p_crew_id and status = 'open' and closes_at is not null and closes_at < now() loop
    perform _finish_poll(r.id, null);
  end loop;
end;
$$;

-- ── Live location ───────────────────────────────────────────────────────
create table public.live_shares (
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    mode text not null default 'trip_end' check (mode in ('trip_end', 'recording')),
    until timestamptz not null,
    low_power boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (expedition_id, user_id)
);

-- One row per person: the latest fix only. No history is stored.
create table public.live_fixes (
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    lat double precision not null check (lat between -90 and 90),
    lng double precision not null check (lng between -180 and 180),
    altitude double precision,
    accuracy double precision,
    speed double precision,
    heading double precision,
    battery integer check (battery is null or battery between 0 and 100),
    recorded_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (expedition_id, user_id)
);

create or replace function public.start_live_share(
  p_expedition_id uuid, p_mode text, p_until timestamptz, p_low_power boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_expedition_participant(p_expedition_id) then raise exception 'not allowed'; end if;
  if p_mode not in ('trip_end', 'recording') then raise exception 'bad mode'; end if;
  insert into live_shares (expedition_id, user_id, mode, until, low_power)
    values (p_expedition_id, auth.uid(),  p_mode, least(p_until, now() + interval '14 days'), coalesce(p_low_power, false))
  on conflict (expedition_id, user_id) do update
    set mode = excluded.mode, until = excluded.until, low_power = excluded.low_power;
end;
$$;

create or replace function public.stop_live_share(p_expedition_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from live_fixes where expedition_id = p_expedition_id and user_id = auth.uid();
  delete from live_shares where expedition_id = p_expedition_id and user_id = auth.uid();
end;
$$;

create or replace function public.upsert_live_fix(
  p_expedition_id uuid, p_lat double precision, p_lng double precision,
  p_altitude double precision default null, p_accuracy double precision default null,
  p_speed double precision default null, p_heading double precision default null,
  p_battery integer default null, p_recorded_at timestamptz default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from live_shares s
                  where s.expedition_id = p_expedition_id and s.user_id = auth.uid() and s.until > now()) then
    delete from live_fixes where expedition_id = p_expedition_id and user_id = auth.uid();
    raise exception 'not sharing';
  end if;
  insert into live_fixes (expedition_id, user_id, lat, lng, altitude, accuracy, speed, heading, battery, recorded_at)
    values (p_expedition_id, auth.uid(), p_lat, p_lng, p_altitude, p_accuracy, p_speed, p_heading, p_battery,
            least(coalesce(p_recorded_at, now()), now()))
  on conflict (expedition_id, user_id) do update
    set lat = excluded.lat, lng = excluded.lng, altitude = excluded.altitude, accuracy = excluded.accuracy,
        speed = excluded.speed, heading = excluded.heading, battery = excluded.battery,
        recorded_at = excluded.recorded_at, updated_at = now();
end;
$$;

-- ── Convoy + awareness events ───────────────────────────────────────────
create table public.convoy_events (
    id uuid primary key default gen_random_uuid(),
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    driver_id uuid not null references public.profiles(id) on delete cascade,
    kind text not null check (kind in ('stopped', 'resumed', 'status', 'help')),
    status text check (status is null or status in ('flat_tire', 'fuel', 'short_break', 'lost_convoy')),
    eta_min integer check (eta_min is null or eta_min between 0 and 600),
    ask_others text check (ask_others is null or ask_others in ('keep_going', 'wait')),
    lat double precision,
    lng double precision,
    created_at timestamptz not null default now()
);
create index convoy_events_exp_idx on public.convoy_events(expedition_id, created_at desc);

create or replace function public.post_convoy_event(
  p_expedition_id uuid, p_kind text, p_status text default null, p_eta_min integer default null,
  p_ask_others text default null, p_lat double precision default null, p_lng double precision default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not is_expedition_participant(p_expedition_id) then raise exception 'not allowed'; end if;
  -- a stop is reported once until the car moves again
  if p_kind = 'stopped' then
    select id into v_id from convoy_events
     where expedition_id = p_expedition_id and driver_id = auth.uid()
       and created_at > now() - interval '10 minutes'
     order by created_at desc limit 1;
    if found and (select kind from convoy_events where id = v_id) = 'stopped' then return v_id; end if;
  end if;
  insert into convoy_events (expedition_id, driver_id, kind, status, eta_min, ask_others, lat, lng)
    values (p_expedition_id, auth.uid(), p_kind, p_status, p_eta_min, p_ask_others, p_lat, p_lng)
    returning id into v_id;
  return v_id;
end;
$$;

create table public.alert_rules (
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    kind text not null check (kind in ('stopped_off_plan', 'falling_behind', 'group_spread', 'off_route',
                                       'low_battery', 'no_signal', 'turnaround')),
    mode text not null check (mode in ('road', 'trail', 'ascent')),
    threshold numeric,
    enabled boolean not null default true,
    primary key (expedition_id, kind, mode)
);

create or replace function public.set_alert_rule(
  p_expedition_id uuid, p_kind text, p_mode text, p_threshold numeric, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  insert into alert_rules (expedition_id, kind, mode, threshold, enabled)
    values (p_expedition_id, p_kind, p_mode, p_threshold, coalesce(p_enabled, true))
  on conflict (expedition_id, kind, mode) do update
    set threshold = excluded.threshold, enabled = excluded.enabled;
end;
$$;

create table public.awareness_events (
    id uuid primary key default gen_random_uuid(),
    expedition_id uuid not null references public.expeditions(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    kind text not null check (kind in ('stopped_off_plan', 'falling_behind', 'group_spread', 'off_route',
                                       'low_battery', 'no_signal', 'turnaround', 'regroup', 'ping')),
    value numeric,
    target_user_id uuid references public.profiles(id) on delete cascade,
    lat double precision,
    lng double precision,
    created_at timestamptz not null default now()
);
create index awareness_events_exp_idx on public.awareness_events(expedition_id, created_at desc);

create or replace function public.post_awareness_event(
  p_expedition_id uuid, p_kind text, p_value numeric default null,
  p_lat double precision default null, p_lng double precision default null,
  p_target uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not is_expedition_participant(p_expedition_id) then raise exception 'not allowed'; end if;
  -- one alert per person and kind per 5 minutes (devices compute alerts independently)
  if p_kind not in ('regroup', 'ping') then
    select id into v_id from awareness_events
     where expedition_id = p_expedition_id and user_id = auth.uid() and kind = p_kind
       and created_at > now() - interval '5 minutes' limit 1;
    if found then return v_id; end if;
  end if;
  insert into awareness_events (expedition_id, user_id, kind, value, target_user_id, lat, lng)
    values (p_expedition_id, auth.uid(), p_kind, p_value, p_target, p_lat, p_lng)
    returning id into v_id;
  return v_id;
end;
$$;

-- ── Row Level Security ──────────────────────────────────────────────────
alter table public.expedition_readiness enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.live_shares enable row level security;
alter table public.live_fixes enable row level security;
alter table public.convoy_events enable row level security;
alter table public.alert_rules enable row level security;
alter table public.awareness_events enable row level security;

create policy "Participants read readiness" on public.expedition_readiness
    for select using (public.is_expedition_participant(expedition_id));
create policy "Members read polls" on public.polls
    for select using (public.can_see_poll(id));
create policy "Members read poll options" on public.poll_options
    for select using (public.can_see_poll(poll_id));
create policy "Members read poll votes" on public.poll_votes
    for select using (public.can_see_poll(poll_id));
create policy "Hide blocked users' votes" on public.poll_votes
    as restrictive for select using (user_id = auth.uid() or not public.is_blocked_by_viewer(user_id));
create policy "Participants read shares" on public.live_shares
    for select using (public.is_expedition_participant(expedition_id));
-- A fix is readable only while its owner's share is active.
create policy "Participants read live fixes" on public.live_fixes
    for select using (
      public.is_expedition_participant(expedition_id)
      and exists (select 1 from public.live_shares s
                   where s.expedition_id = live_fixes.expedition_id
                     and s.user_id = live_fixes.user_id and s.until > now()));
create policy "Hide blocked users' fixes" on public.live_fixes
    as restrictive for select using (user_id = auth.uid() or not public.is_blocked_by_viewer(user_id));
create policy "Participants read convoy events" on public.convoy_events
    for select using (public.is_expedition_participant(expedition_id));
create policy "Participants read alert rules" on public.alert_rules
    for select using (public.is_expedition_participant(expedition_id));
create policy "Participants read awareness events" on public.awareness_events
    for select using (public.is_expedition_participant(expedition_id));

revoke all on public.expedition_readiness, public.polls, public.poll_options, public.poll_votes,
  public.live_shares, public.live_fixes, public.convoy_events, public.alert_rules,
  public.awareness_events from anon, authenticated;
grant select on public.expedition_readiness, public.polls, public.poll_options, public.poll_votes,
  public.live_shares, public.live_fixes, public.convoy_events, public.alert_rules,
  public.awareness_events to authenticated;
-- expedition_members gained columns; keep it read-only for clients.
grant select on public.expedition_members to authenticated;

-- ── Function privileges ─────────────────────────────────────────────────
revoke all on function
  public.is_expedition_participant(uuid), public.can_see_poll(uuid), public._poll_electorate(uuid),
  public._finish_poll(uuid, uuid), public.join_expedition(uuid), public.set_expedition_role(uuid, uuid, text),
  public.set_my_car(uuid, uuid), public.set_readiness(uuid, integer, boolean, integer, boolean),
  public.start_expedition(uuid, text), public.finish_expedition(uuid),
  public.create_poll(uuid, uuid, integer, text, text, jsonb, timestamptz, boolean, boolean),
  public.add_poll_option(uuid, text, jsonb), public.vote_poll(uuid, uuid), public.close_poll(uuid, uuid),
  public.settle_polls(uuid), public.start_live_share(uuid, text, timestamptz, boolean),
  public.stop_live_share(uuid),
  public.upsert_live_fix(uuid, double precision, double precision, double precision, double precision,
                         double precision, double precision, integer, timestamptz),
  public.post_convoy_event(uuid, text, text, integer, text, double precision, double precision),
  public.set_alert_rule(uuid, text, text, numeric, boolean),
  public.post_awareness_event(uuid, text, numeric, double precision, double precision, uuid)
  from public, anon;
grant execute on function
  public.is_expedition_participant(uuid), public.can_see_poll(uuid),
  public.join_expedition(uuid), public.set_expedition_role(uuid, uuid, text),
  public.set_my_car(uuid, uuid), public.set_readiness(uuid, integer, boolean, integer, boolean),
  public.start_expedition(uuid, text), public.finish_expedition(uuid),
  public.create_poll(uuid, uuid, integer, text, text, jsonb, timestamptz, boolean, boolean),
  public.add_poll_option(uuid, text, jsonb), public.vote_poll(uuid, uuid), public.close_poll(uuid, uuid),
  public.settle_polls(uuid), public.start_live_share(uuid, text, timestamptz, boolean),
  public.stop_live_share(uuid),
  public.upsert_live_fix(uuid, double precision, double precision, double precision, double precision,
                         double precision, double precision, integer, timestamptz),
  public.post_convoy_event(uuid, text, text, integer, text, double precision, double precision),
  public.set_alert_rule(uuid, text, text, numeric, boolean),
  public.post_awareness_event(uuid, text, numeric, double precision, double precision, uuid)
  to authenticated;
-- _finish_poll is internal: never callable from the API.

-- NomadPoints — server-verified loyalty ledger.
--
-- Deliberately NOT a blockchain token: no wallet, no on-chain anything.
-- This is the honest, low-risk first step toward the "tokenize the app"
-- idea — award points for real, hard-to-fake activity (GPS-recorded
-- distance, genuine likes/saves from *other* people, real followers),
-- keep a full append-only audit trail, and redeem points for real
-- in-app value today (bonus Pro time, exclusive badges).
--
-- Why the ledger matters beyond bookkeeping: if this project ever does
-- issue a real token later (with actual legal review — do not skip
-- that step), this table is exactly the historical-activity snapshot
-- real projects (Uniswap, Arbitrum, dYdX) used for their retroactive
-- airdrops — rewarding people who were genuinely active before the
-- token existed, not people who show up after an announcement to farm
-- it. Keep this ledger accurate and unforgeable now; it's the asset
-- that makes a future token credible instead of a rug.

-- ── Balance + bonus-Pro columns on profiles ────────────────────────────
alter table public.profiles add column points_balance integer not null default 0;
alter table public.profiles add column bonus_pro_until timestamptz;

-- These must never be client-writable directly — only via the
-- security-definer functions below, which run as the function owner
-- and bypass this column-level grant entirely. Without this, the
-- existing "Users manage their own profile" update policy would let
-- anyone POST points_balance = 999999999 straight through PostgREST.
revoke update (points_balance, bonus_pro_until) on public.profiles from authenticated;

-- ── Ledger — append-only, no client write access at all ───────────────
create table public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  delta integer not null,
  reason text not null,
  ref_id uuid,
  created_at timestamptz not null default now()
);

create index points_ledger_user_idx on public.points_ledger (user_id, created_at desc);

alter table public.points_ledger enable row level security;

create policy "Users read their own points ledger"
  on public.points_ledger for select
  using (auth.uid() = user_id);

-- No insert/update/delete policy on purpose — the table is only ever
-- written by award_points() below, which runs as the (trusted) function
-- owner and so isn't subject to RLS at all.

-- ── The one place points ever get created ──────────────────────────────
create function public.award_points(p_user_id uuid, p_delta integer, p_reason text, p_ref_id uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.points_ledger (user_id, delta, reason, ref_id)
  values (p_user_id, p_delta, p_reason, p_ref_id);

  update public.profiles
  set points_balance = points_balance + p_delta
  where id = p_user_id;
end;
$$;

-- Nobody gets to call this directly — only the triggers/functions in
-- this file (which run as the table owner) invoke it.
revoke all on function public.award_points(uuid, integer, text, uuid) from public;

-- ── Earning: route published ────────────────────────────────────────────
-- Distance-weighted, capped, floored — rewards real recorded routes
-- (distance comes from live CLLocation tracking, not a text field) over
-- spammy one-line entries, without letting one mega-route dominate.
create function public.handle_route_published()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  pts integer;
begin
  if new.status = 'published' then
    pts := least(150, greatest(20, round(20 + new.distance_km * 0.5)));
    perform public.award_points(new.author_id, pts, 'route_published', new.id);
  end if;
  return new;
end;
$$;

create trigger on_route_published
  after insert on public.routes
  for each row execute procedure public.handle_route_published();

-- ── Earning: route enrichment (segments / requirements / POIs / cover) ─
-- Small per-item bonuses so a route with real segments/gear/pins/photo
-- earns more than a bare title — rewards the same "quality over volume"
-- signal the app already cares about.
create function public.handle_segment_added()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = new.route_id;
  if v_author is not null then
    perform public.award_points(v_author, 5, 'segment_added', new.route_id);
  end if;
  return new;
end;
$$;

create trigger on_segment_added
  after insert on public.route_segments
  for each row execute procedure public.handle_segment_added();

create function public.handle_requirement_added()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = new.route_id;
  if v_author is not null then
    perform public.award_points(v_author, 5, 'requirement_added', new.route_id);
  end if;
  return new;
end;
$$;

create trigger on_requirement_added
  after insert on public.route_requirements
  for each row execute procedure public.handle_requirement_added();

create function public.handle_poi_added()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = new.route_id;
  if v_author is not null then
    perform public.award_points(v_author, 5, 'poi_added', new.route_id);
  end if;
  return new;
end;
$$;

create trigger on_poi_added
  after insert on public.route_points_of_interest
  for each row execute procedure public.handle_poi_added();

create function public.handle_cover_added()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if old.cover_image_url is null and new.cover_image_url is not null then
    perform public.award_points(new.author_id, 10, 'cover_photo_added', new.id);
  end if;
  return new;
end;
$$;

create trigger on_cover_added
  after update of cover_image_url on public.routes
  for each row execute procedure public.handle_cover_added();

-- ── Earning: social signal from *other* people ─────────────────────────
-- Symmetric award/deduct on insert/delete (not just insert) so
-- like → unlike → like farming nets to zero instead of paying out —
-- the balance always reflects genuinely current engagement, not the
-- number of times someone toggled a button.
create function public.handle_route_liked()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = new.route_id;
  if v_author is not null and v_author <> new.user_id then
    perform public.award_points(v_author, 2, 'route_liked', new.route_id);
  end if;
  return new;
end;
$$;

create function public.handle_route_unliked()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = old.route_id;
  if v_author is not null and v_author <> old.user_id then
    perform public.award_points(v_author, -2, 'route_unliked', old.route_id);
  end if;
  return old;
end;
$$;

create trigger on_route_liked after insert on public.route_likes
  for each row execute procedure public.handle_route_liked();
create trigger on_route_unliked after delete on public.route_likes
  for each row execute procedure public.handle_route_unliked();

create function public.handle_route_saved()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = new.route_id;
  if v_author is not null and v_author <> new.user_id then
    perform public.award_points(v_author, 3, 'route_saved', new.route_id);
  end if;
  return new;
end;
$$;

create function public.handle_route_unsaved()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_author uuid;
begin
  select author_id into v_author from public.routes where id = old.route_id;
  if v_author is not null and v_author <> old.user_id then
    perform public.award_points(v_author, -3, 'route_unsaved', old.route_id);
  end if;
  return old;
end;
$$;

create trigger on_route_saved after insert on public.route_saves
  for each row execute procedure public.handle_route_saved();
create trigger on_route_unsaved after delete on public.route_saves
  for each row execute procedure public.handle_route_unsaved();

create function public.handle_followed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform public.award_points(new.followee_id, 5, 'new_follower', new.follower_id);
  return new;
end;
$$;

create function public.handle_unfollowed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform public.award_points(old.followee_id, -5, 'unfollowed', old.follower_id);
  return old;
end;
$$;

create trigger on_followed after insert on public.follows
  for each row execute procedure public.handle_followed();
create trigger on_unfollowed after delete on public.follows
  for each row execute procedure public.handle_unfollowed();

-- ── Reward catalog + redemption ─────────────────────────────────────────
create table public.point_rewards (
  key text primary key,
  title text not null,
  description text not null,
  cost integer not null,
  kind text not null check (kind in ('badge', 'pro_days')),
  badge_key text references public.badges (key),
  pro_days integer,
  sort_order integer not null default 0
);

alter table public.point_rewards enable row level security;

create policy "Reward catalog is publicly readable"
  on public.point_rewards for select using (true);

create function public.redeem_reward(p_reward_key text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reward record;
  v_balance integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_reward from public.point_rewards where key = p_reward_key;
  if not found then
    raise exception 'unknown reward';
  end if;

  select points_balance into v_balance from public.profiles where id = v_uid;
  if v_balance is null or v_balance < v_reward.cost then
    raise exception 'insufficient points';
  end if;

  perform public.award_points(v_uid, -v_reward.cost, 'redeemed_' || p_reward_key, null);

  if v_reward.kind = 'badge' then
    insert into public.user_badges (user_id, badge_id)
    select v_uid, b.id from public.badges b where b.key = v_reward.badge_key
    on conflict do nothing;
  elsif v_reward.kind = 'pro_days' then
    update public.profiles
    set bonus_pro_until = greatest(coalesce(bonus_pro_until, now()), now()) + (v_reward.pro_days || ' days')::interval
    where id = v_uid;
  end if;
end;
$$;

grant execute on function public.redeem_reward(text) to authenticated;

insert into public.badges (key, title, subtitle, icon, color_start, color_end) values
  ('early_nomad', 'Early Nomad', 'POINTS SHOP', 'star.circle.fill', '#E8743B', '#B33A2B')
on conflict (key) do nothing;

insert into public.point_rewards (key, title, description, cost, kind, badge_key, pro_days, sort_order) values
  ('pro_week', '1 week of Pro', 'Unlock a full week of Pro features, on the house.', 150, 'pro_days', null, 7, 0),
  ('pro_month', '1 month of Pro', 'A full month of Pro, no card needed.', 500, 'pro_days', null, 30, 1),
  ('badge_early_nomad', 'Early Nomad badge', 'Show it off on your profile — proof you were here early.', 80, 'badge', 'early_nomad', null, 2)
on conflict (key) do nothing;

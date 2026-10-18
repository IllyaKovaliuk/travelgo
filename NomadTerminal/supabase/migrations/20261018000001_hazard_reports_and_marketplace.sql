-- Proof of Exploration (community hazard reports + validation) and the
-- NomadPoints partner marketplace (rewards → QR vouchers).
--
-- Design notes:
--   * Points keep flowing through the existing append-only ledger
--     (`points_ledger` + `award_points`) — no second balance anywhere.
--   * Every write that moves points or trust is a security-definer
--     function / trigger. Clients get no direct INSERT-able points,
--     trust, stock, or voucher state.
--   * Trust lives in its own table (`user_trust`) instead of a `profiles`
--     column, so it is read-only to clients by construction (no write
--     policy at all) rather than relying on a column-level REVOKE.

-- ── Hazard reports ──────────────────────────────────────────────────────
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  hazard_type text not null check (hazard_type in ('tree_fall', 'bridge_broken', 'deep_ford', 'other')),
  description text check (description is null or char_length(description) <= 280),
  image_url text,
  status text not null default 'active' check (status in ('active', 'resolved')),
  points_awarded integer not null default 50,
  confirmations integer not null default 0,
  dismissals integer not null default 0,
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now()
);

create index reports_active_geo_idx on public.reports (latitude, longitude) where status = 'active';
create index reports_user_day_idx on public.reports (user_id, created_at desc);

alter table public.reports enable row level security;

-- Everyone signed in sees live hazards. Expired rows disappear from reads
-- immediately; the cleanup function below only reclaims the space.
create policy "Active hazards are readable"
  on public.reports for select
  using (
    auth.role() = 'authenticated'
    and ((status = 'active' and expires_at > now()) or user_id = auth.uid())
  );

create policy "Users file their own hazards"
  on public.reports for insert
  with check (auth.uid() = user_id);

create policy "Users delete their own hazards"
  on public.reports for delete
  using (auth.uid() = user_id);
-- No UPDATE policy: status/counters change only via vote_on_report().

-- ── Trust score (server-written, owner-readable) ────────────────────────
create table public.user_trust (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  score integer not null default 0
);
alter table public.user_trust enable row level security;
create policy "Users read their own trust"
  on public.user_trust for select using (auth.uid() = user_id);

create function public.adjust_trust(p_user_id uuid, p_delta integer)
returns void
language sql
security definer set search_path = public
as $$
  insert into public.user_trust (user_id, score) values (p_user_id, p_delta)
  on conflict (user_id) do update set score = public.user_trust.score + excluded.score;
$$;
revoke all on function public.adjust_trust(uuid, integer) from public;

-- ── Anti-cheat on insert: rate limit, trust gate, fixed reward ──────────
create function public.before_report_insert()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_today integer;
  v_trust integer;
begin
  select count(*) into v_today
  from public.reports
  where user_id = new.user_id and created_at > now() - interval '24 hours';
  if v_today >= 5 then
    raise exception 'rate limit: max 5 reports per day';
  end if;

  select coalesce(score, 0) into v_trust from public.user_trust where user_id = new.user_id;
  if coalesce(v_trust, 0) <= -6 then
    raise exception 'reporting disabled: low trust score';
  end if;

  -- Client-supplied bookkeeping is never trusted.
  new.status := 'active';
  new.points_awarded := 50;
  new.confirmations := 0;
  new.dismissals := 0;
  new.expires_at := now() + interval '14 days';
  new.created_at := now();
  return new;
end;
$$;

create trigger reports_before_insert
  before insert on public.reports
  for each row execute procedure public.before_report_insert();

create function public.after_report_insert()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform public.award_points(new.user_id, new.points_awarded, 'hazard_reported', new.id);
  return new;
end;
$$;

create trigger reports_after_insert
  after insert on public.reports
  for each row execute procedure public.after_report_insert();

-- ── Validation: confirm / dismiss from someone actually nearby ──────────
create table public.report_votes (
  report_id uuid not null references public.reports (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  vote text not null check (vote in ('confirm', 'dismiss')),
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);
alter table public.report_votes enable row level security;
create policy "Users read their own votes"
  on public.report_votes for select using (auth.uid() = user_id);
-- Writes only via vote_on_report().

create function public.vote_on_report(
  p_report_id uuid, p_vote text, p_lat double precision, p_lng double precision
)
returns public.reports
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.reports;
  v_dist double precision;
  v_votes_today integer;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_vote not in ('confirm', 'dismiss') then raise exception 'invalid vote'; end if;

  select * into r from public.reports where id = p_report_id for update;
  if not found or r.status <> 'active' or r.expires_at <= now() then
    raise exception 'report not active';
  end if;
  if r.user_id = uid then raise exception 'cannot vote on your own report'; end if;

  -- "Passing by" check: haversine distance in meters from the voter's
  -- current position to the hazard. Must be within 300 m.
  v_dist := 2 * 6371000 * asin(sqrt(
    power(sin(radians(p_lat - r.latitude) / 2), 2)
    + cos(radians(r.latitude)) * cos(radians(p_lat))
      * power(sin(radians(p_lng - r.longitude) / 2), 2)
  ));
  if v_dist > 300 then raise exception 'too far from hazard'; end if;

  select count(*) into v_votes_today
  from public.report_votes where user_id = uid and created_at > now() - interval '24 hours';
  if v_votes_today >= 20 then raise exception 'rate limit: too many votes today'; end if;

  begin
    insert into public.report_votes (report_id, user_id, vote) values (p_report_id, uid, p_vote);
  exception when unique_violation then
    raise exception 'already voted';
  end;

  if p_vote = 'confirm' then
    update public.reports
    set confirmations = confirmations + 1,
        expires_at = greatest(expires_at, now() + interval '7 days')
    where id = p_report_id returning * into r;
    perform public.adjust_trust(r.user_id, 1);
    if r.confirmations = 3 then
      -- Community-verified: small extra payout, once.
      perform public.award_points(r.user_id, 10, 'hazard_verified', r.id);
    end if;
    perform public.award_points(uid, 5, 'hazard_validated', r.id);
  else
    update public.reports set dismissals = dismissals + 1 where id = p_report_id returning * into r;
    if r.dismissals >= 3 and r.dismissals > r.confirmations then
      update public.reports set status = 'resolved' where id = p_report_id returning * into r;
      perform public.adjust_trust(r.user_id, -3);
    end if;
    perform public.award_points(uid, 5, 'hazard_validated', r.id);
  end if;

  return r;
end;
$$;
grant execute on function public.vote_on_report(uuid, text, double precision, double precision) to authenticated;

-- Cleanup: expired reports are already invisible to reads; this reclaims
-- them. Scheduled below when pg_cron is available, otherwise callable.
create function public.expire_old_reports()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare n integer;
begin
  with gone as (
    delete from public.reports
    where expires_at < now() - interval '7 days' or (status = 'resolved' and created_at < now() - interval '7 days')
    returning 1
  ) select count(*) into n from gone;
  return n;
end;
$$;
revoke all on function public.expire_old_reports() from public;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('expire-old-hazard-reports', '17 * * * *', 'select public.expire_old_reports()');
  end if;
end $$;

-- ── Hazard photos ───────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('hazard-photos', 'hazard-photos', true)
on conflict (id) do nothing;

create policy "Hazard photos are publicly readable"
  on storage.objects for select using (bucket_id = 'hazard-photos');
create policy "Authenticated users can upload hazard photos"
  on storage.objects for insert
  with check (bucket_id = 'hazard-photos' and auth.role() = 'authenticated');
create policy "Uploaders can delete their own hazard photos"
  on storage.objects for delete
  using (bucket_id = 'hazard-photos' and owner = auth.uid());

-- ── Partners / rewards / vouchers ───────────────────────────────────────
create table public.partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null check (category in ('quad_rental', 'hotel', 'equipment', 'cafe')),
  latitude double precision not null,
  longitude double precision not null,
  logo_url text,
  is_verified boolean not null default false
);
alter table public.partners enable row level security;
create policy "Verified partners are readable"
  on public.partners for select using (auth.role() = 'authenticated' and is_verified);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners (id) on delete cascade,
  title text not null,
  description text not null default '',
  points_cost integer not null check (points_cost > 0),
  stock integer not null default 0 check (stock >= 0),
  expires_at timestamptz
);
alter table public.rewards enable row level security;
create policy "Live rewards are readable"
  on public.rewards for select
  using (
    auth.role() = 'authenticated'
    and (expires_at is null or expires_at > now())
    and exists (select 1 from public.partners p where p.id = partner_id and p.is_verified)
  );

create table public.user_vouchers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  reward_id uuid not null references public.rewards (id),
  qr_code_hash text not null unique,
  is_redeemed boolean not null default false,
  redeemed_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index user_vouchers_user_idx on public.user_vouchers (user_id, created_at desc);
alter table public.user_vouchers enable row level security;
create policy "Users read their own vouchers"
  on public.user_vouchers for select using (auth.uid() = user_id);
-- No client writes: created by redeem_partner_reward(), marked used by
-- mark_voucher_redeemed() (admin/partner tooling).

-- Atomic: lock the reward and the buyer's balance, check, deduct (through
-- the ledger), decrement stock, mint the voucher — all or nothing.
create function public.redeem_partner_reward(p_reward_id uuid)
returns public.user_vouchers
language plpgsql
security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rw public.rewards;
  v_balance integer;
  v public.user_vouchers;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into rw from public.rewards where id = p_reward_id for update;
  if not found or (rw.expires_at is not null and rw.expires_at <= now()) then
    raise exception 'reward unavailable';
  end if;
  if not exists (select 1 from public.partners where id = rw.partner_id and is_verified) then
    raise exception 'reward unavailable';
  end if;
  if rw.stock <= 0 then raise exception 'out of stock'; end if;

  select points_balance into v_balance from public.profiles where id = uid for update;
  if coalesce(v_balance, 0) < rw.points_cost then raise exception 'insufficient points'; end if;

  perform public.award_points(uid, -rw.points_cost, 'redeemed_partner_reward', rw.id);
  update public.rewards set stock = stock - 1 where id = rw.id;

  insert into public.user_vouchers (user_id, reward_id, qr_code_hash, expires_at)
  values (
    uid, rw.id,
    replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
    least(coalesce(rw.expires_at, now() + interval '7 days'), now() + interval '7 days')
  )
  returning * into v;
  return v;
end;
$$;
grant execute on function public.redeem_partner_reward(uuid) to authenticated;

-- Partner-side scan. No partner app exists yet, so for now only admins
-- can mark a voucher used.
create function public.mark_voucher_redeemed(p_qr_code_hash text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'not authorized';
  end if;
  update public.user_vouchers
  set is_redeemed = true, redeemed_at = now()
  where qr_code_hash = p_qr_code_hash and not is_redeemed and expires_at > now();
  if not found then raise exception 'voucher invalid, used, or expired'; end if;
end;
$$;
grant execute on function public.mark_voucher_redeemed(text) to authenticated;

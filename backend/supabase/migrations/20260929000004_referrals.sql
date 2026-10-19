-- Real referral system — "Invite a friend" was a ShareLink with plain
-- static text and a fake "you both unlock early access" promise nothing
-- backed. Every profile gets a real short code (generated at signup,
-- backfilled for existing ones); redeeming someone else's code once,
-- right after signing up, links the two accounts and pays out through
-- the *existing* points economy (see award_points/points_ledger) rather
-- than inventing a second reward currency or a promise ("early access to
-- the next region") this app has no actual mechanism to grant.
alter table public.profiles add column if not exists referral_code text unique;

create or replace function public.generate_referral_code()
returns text as $$
declare
  candidate text;
begin
  loop
    candidate := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where referral_code = candidate);
  end loop;
  return candidate;
end;
$$ language plpgsql;

-- Backfill every existing profile that predates this column.
update public.profiles set referral_code = public.generate_referral_code() where referral_code is null;

alter table public.profiles alter column referral_code set not null;

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, display_name, referral_code)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'nomad_' || substr(new.id::text, 1, 8)),
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    public.generate_referral_code()
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create table public.referrals (
    id uuid primary key default gen_random_uuid(),
    referrer_id uuid not null references public.profiles(id) on delete cascade,
    referred_id uuid not null references public.profiles(id) on delete cascade unique,
    created_at timestamptz not null default now(),
    constraint referrals_no_self_referral check (referrer_id <> referred_id)
);

create index referrals_referrer_id_idx on public.referrals(referrer_id);

alter table public.referrals enable row level security;

create policy "Users can see referrals they're part of"
    on public.referrals for select
    using (auth.uid() = referrer_id or auth.uid() = referred_id);

-- Called once, right after a fresh sign-up, if the person entered someone
-- else's code. +30 to the referrer, +15 to the new joiner — meaningfully
-- more than a like/follow, less than actually publishing a route,
-- matching how the rest of this points economy is already scaled (see
-- handle_route_liked/handle_followed/handle_route_published).
create or replace function public.redeem_referral_code(p_code text)
returns void as $$
declare
  v_uid uuid := auth.uid();
  v_referrer_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if exists (select 1 from public.referrals where referred_id = v_uid) then
    raise exception 'already redeemed a referral code';
  end if;

  select id into v_referrer_id from public.profiles where referral_code = upper(trim(p_code));
  if v_referrer_id is null then
    raise exception 'invalid code';
  end if;
  if v_referrer_id = v_uid then
    raise exception 'cannot refer yourself';
  end if;

  insert into public.referrals (referrer_id, referred_id) values (v_referrer_id, v_uid);
  perform public.award_points(v_referrer_id, 30, 'referral_referrer', v_uid);
  perform public.award_points(v_uid, 15, 'referral_new_user', v_referrer_id);
end;
$$ language plpgsql security definer set search_path = public;

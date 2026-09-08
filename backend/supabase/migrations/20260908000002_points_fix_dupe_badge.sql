-- Fix: redeem_reward() deducted points for a badge reward even when the
-- user already owned that badge (the user_badges insert just silently
-- no-op'd on the unique conflict, but the points were already spent).
-- Caught in manual verification: redeeming "Early Nomad badge" a second
-- time would burn another 80 points for literally nothing. Now checks
-- ownership first and rejects the redemption before any points move.
create or replace function public.redeem_reward(p_reward_key text)
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

  if v_reward.kind = 'badge' then
    if exists (
      select 1 from public.user_badges ub
      join public.badges b on b.id = ub.badge_id
      where ub.user_id = v_uid and b.key = v_reward.badge_key
    ) then
      raise exception 'already owned';
    end if;
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

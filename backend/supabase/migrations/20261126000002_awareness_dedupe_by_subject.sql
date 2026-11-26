-- Devices report alerts about a *subject* (target_user_id, defaulting to the
-- reporter). The 5-minute dedupe must be per subject, otherwise one person
-- falling behind would hide the next person's alert of the same kind.
create or replace function public.post_awareness_event(
  p_expedition_id uuid, p_kind text, p_value numeric default null,
  p_lat double precision default null, p_lng double precision default null,
  p_target uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_subject uuid := coalesce(p_target, auth.uid());
begin
  if not is_expedition_participant(p_expedition_id) then raise exception 'not allowed'; end if;
  if p_target is not null and not exists (
       select 1 from expedition_members where expedition_id = p_expedition_id and user_id = p_target) then
    raise exception 'target is not on the trip';
  end if;
  if p_kind not in ('regroup', 'ping') then
    select id into v_id from awareness_events
     where expedition_id = p_expedition_id and kind = p_kind
       and coalesce(target_user_id, user_id) = v_subject
       and created_at > now() - interval '5 minutes' limit 1;
    if found then return v_id; end if;
  end if;
  insert into awareness_events (expedition_id, user_id, kind, value, target_user_id, lat, lng)
    values (p_expedition_id, auth.uid(), p_kind, p_value, v_subject, p_lat, p_lng)
    returning id into v_id;
  return v_id;
end;
$$;

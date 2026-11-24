-- The invite loop is the success metric for Crews, so the admin summary gets
-- its funnel: invites sent -> invite links opened -> people who joined, plus
-- how many invites each inviter sends. Events come from the client
-- (`crew_invite_sent`, `crew_invite_opened`, `crew_join`) via the existing
-- analytics_events table; nothing new is stored.
create or replace function public.admin_analytics_summary()
returns json as $$
declare
  v_is_admin boolean;
  result json;
begin
  select is_admin into v_is_admin from public.profiles where id = auth.uid();
  if not coalesce(v_is_admin, false) then
    raise exception 'not authorized';
  end if;

  select json_build_object(
    'total_users', (select count(*) from public.profiles),
    'total_routes_published', (select count(*) from public.routes where status = 'published'),
    'signups_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'routes_published_7d', (select count(*) from public.routes where status = 'published' and created_at > now() - interval '7 days'),
    'dau', (select count(distinct user_id) from public.analytics_events where created_at > now() - interval '1 day'),
    'wau', (select count(distinct user_id) from public.analytics_events where created_at > now() - interval '7 days'),
    'sos_triggers_7d', (select count(*) from public.analytics_events where event_name = 'sos_triggered' and created_at > now() - interval '7 days'),
    'top_events_7d', (
      select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
        select event_name, count(*) as count from public.analytics_events
        where created_at > now() - interval '7 days'
        group by event_name order by count desc limit 10
      ) t
    ),
    'crew_funnel', (
      select json_build_object(
        'crews_total', (select count(*) from public.crews),
        'invites_sent_7d', count(*) filter (where event_name = 'crew_invite_sent'),
        'invites_opened_7d', count(*) filter (where event_name = 'crew_invite_opened'),
        'joins_7d', count(*) filter (where event_name = 'crew_join'),
        'inviters_7d', count(distinct user_id) filter (where event_name = 'crew_invite_sent'),
        'invites_per_inviter_7d', coalesce(round(
            count(*) filter (where event_name = 'crew_invite_sent')::numeric
            / nullif(count(distinct user_id) filter (where event_name = 'crew_invite_sent'), 0), 2), 0)
      )
      from public.analytics_events
      where created_at > now() - interval '7 days'
        and event_name in ('crew_invite_sent', 'crew_invite_opened', 'crew_join')
    )
  ) into result;
  return result;
end;
$$ language plpgsql security definer set search_path = public;

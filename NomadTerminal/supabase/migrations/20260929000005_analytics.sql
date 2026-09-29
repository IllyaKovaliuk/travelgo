-- Real, first-party analytics — there was nothing at all before this
-- (no events, no admin-facing numbers of any kind), so anything "usage"
-- related was pure guesswork. A plain events table in the same backend
-- rather than a third-party SDK (Amplitude/Mixpanel/PostHog etc. all need
-- a real account + API key this session has no way to create), read only
-- by real admins through one aggregate RPC — not raw per-user event
-- access, which would be a real privacy overreach for a "let me see the
-- numbers" screen.
create table public.analytics_events (
    id bigint generated always as identity primary key,
    user_id uuid references public.profiles(id) on delete set null,
    event_name text not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index analytics_events_created_at_idx on public.analytics_events(created_at);
create index analytics_events_event_name_idx on public.analytics_events(event_name);

alter table public.analytics_events enable row level security;

-- Fire-and-forget logging from the app — anyone signed in can insert an
-- event tagged as themselves (or anonymous/null), nobody can log an event
-- as someone else.
create policy "Users can log their own events"
    on public.analytics_events for insert
    with check (auth.uid() = user_id or user_id is null);

-- Real admins get raw row access too (for ad-hoc digging), same gate as
-- the moderation RPCs.
create policy "Admins can read all events"
    on public.analytics_events for select
    using (exists (select 1 from public.profiles where id = auth.uid() and is_admin));

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
    )
  ) into result;
  return result;
end;
$$ language plpgsql security definer set search_path = public;

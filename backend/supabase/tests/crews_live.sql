-- Behaviour / RLS test for 20261126000001_crews_live.sql. Throwaway Postgres only.
-- Order: crews_rls_stub.sql, every migration, then this file.
\set ON_ERROR_STOP off
\pset pager off
\set a '11111111-1111-1111-1111-111111111111'
\set b '22222222-2222-2222-2222-222222222222'
\set c '33333333-3333-3333-3333-333333333333'
insert into auth.users(id,email) values (:'a','a@x'),(:'b','b@x'),(:'c','c@x');
update profiles set display_name='Real Person';
create table ctx(k text primary key, v text); grant all on ctx to authenticated;

\echo === setup: A makes crew, B and C join, trip with A+B going (C only in crew)
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'crew', create_crew('Nomads')::text;
insert into ctx select 'code', create_crew_invite((select v::uuid from ctx where k='crew'))::text;
reset role;
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select join_crew_by_code((select v from ctx where k='code'));
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select join_crew_by_code((select v from ctx where k='code'));
reset role;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'exp', create_expedition('Ridge', (select v::uuid from ctx where k='crew'), 'hiking')::text;
reset role;
-- create_expedition adds every crew member; drop C from "going" as superuser to model "not going"
delete from expedition_members where user_id = :'c' and expedition_id=(select v::uuid from ctx where k='exp');

\echo === polls: create, vote, tie, close
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'poll', create_poll((select v::uuid from ctx where k='crew'), null, null, 'where', 'Where?',
  '[{"label":"Svydovets"},{"label":"Kolochava"}]'::jsonb, now()+interval '1 day')::text;
select create_poll((select v::uuid from ctx where k='crew'), null, null, 'where', 'x', '[{"label":"only one"}]'::jsonb) as one_option_EXPECT_ERROR;
select count(*) as a_sees_options_EXPECT_2 from poll_options;
select vote_poll((select v::uuid from ctx where k='poll'), (select id from poll_options where label='Svydovets'));
reset role;
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select vote_poll((select v::uuid from ctx where k='poll'), (select id from poll_options where label='Kolochava'));
select count(*) as votes_visible_EXPECT_2 from poll_votes;
-- 3 members in crew, only 2 voted: still open
select status as still_open_EXPECT_open from polls;
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select vote_poll((select v::uuid from ctx where k='poll'), (select id from poll_options where label='Kolochava'));
select status as closed_EXPECT_closed, (select label from poll_options o where o.id=winner_option_id) as winner_EXPECT_Kolochava from polls;
select vote_poll((select v::uuid from ctx where k='poll'), (select id from poll_options where label='Svydovets')) as vote_after_close_EXPECT_ERROR;
reset role;

\echo === outsider cannot see
insert into auth.users(id,email) values ('44444444-4444-4444-4444-444444444444','d@x');
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false); set role authenticated;
select count(*) as outsider_polls_EXPECT_0 from polls;
select vote_poll((select v::uuid from ctx where k='poll'), (select id from poll_options limit 1)) as outsider_vote_EXPECT_ERROR;
reset role;

\echo === route poll winner lands in the day
insert into routes(author_id,title,place,difficulty,transport,transport_label,distance_km,status,visibility)
 select :'a','Pub','P',(enum_range(null::difficulty))[1],(enum_range(null::transport_mode))[1],'x',1,'published','public';
insert into ctx select 'route', id::text from routes limit 1;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'rpoll', create_poll(null, (select v::uuid from ctx where k='exp'), 2, 'route', 'Which way?',
  jsonb_build_array(jsonb_build_object('label','Pub','payload',jsonb_build_object('route_id',(select v from ctx where k='route'))),
                    jsonb_build_object('label','Other')), null, true, false)::text;
select vote_poll((select v::uuid from ctx where k='rpoll'), (select id from poll_options where label='Pub'));
select close_poll((select v::uuid from ctx where k='rpoll'));
select count(*) as route_in_day2_EXPECT_1 from expedition_routes where day_index=2;
reset role;

\echo === start / finish
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select start_expedition((select v::uuid from ctx where k='exp'), 'convoy') as member_cannot_start_EXPECT_ERROR;
reset role;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select start_expedition((select v::uuid from ctx where k='exp'), 'convoy');
select start_expedition((select v::uuid from ctx where k='exp'), 'convoy') as double_start_EXPECT_ERROR;
select status, start_mode from expeditions;
reset role;

\echo === live location: consent, visibility, expiry, outsiders
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select upsert_live_fix((select v::uuid from ctx where k='exp'), 48.1, 24.5) as no_share_EXPECT_ERROR;
select start_live_share((select v::uuid from ctx where k='exp'), 'trip_end', now()+interval '2 hours');
select upsert_live_fix((select v::uuid from ctx where k='exp'), 48.1, 24.5, 1800, 10, 1.2, 90, 80);
reset role;
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select count(*) as b_sees_a_fix_EXPECT_1 from live_fixes;
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select count(*) as c_not_going_EXPECT_0 from live_fixes;
select count(*) as c_shares_EXPECT_0 from live_shares;
reset role;
-- expired share hides the fix
update live_shares set until = now() - interval '1 minute';
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select count(*) as expired_EXPECT_0 from live_fixes;
reset role;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select start_live_share((select v::uuid from ctx where k='exp'), 'trip_end', now()+interval '2 hours');
select upsert_live_fix((select v::uuid from ctx where k='exp'), 48.2, 24.6);
select stop_live_share((select v::uuid from ctx where k='exp'));
select count(*) as after_stop_EXPECT_0 from live_fixes;
insert into live_fixes(expedition_id,user_id,lat,lng) values ((select v::uuid from ctx where k='exp'), :'a', 1, 1);
reset role;

\echo === blocked user fix hidden
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select start_live_share((select v::uuid from ctx where k='exp'), 'trip_end', now()+interval '2 hours');
select upsert_live_fix((select v::uuid from ctx where k='exp'), 48.2, 24.6);
reset role;
insert into user_blocks(blocker_id, blocked_id) values (:'b', :'a');
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select count(*) as blocked_EXPECT_0 from live_fixes;
reset role;
delete from user_blocks;

\echo === convoy, alerts, roles, ping
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select post_convoy_event((select v::uuid from ctx where k='exp'), 'stopped') is not null as stopped;
select post_convoy_event((select v::uuid from ctx where k='exp'), 'stopped') = (select id from convoy_events limit 1) as dedup_EXPECT_t;
select post_convoy_event((select v::uuid from ctx where k='exp'), 'status', 'flat_tire', 20, 'wait') is not null as status;
select set_alert_rule((select v::uuid from ctx where k='exp'), 'low_battery', 'trail', 20, true) as member_cannot_EXPECT_ERROR;
select post_awareness_event((select v::uuid from ctx where k='exp'), 'low_battery', 15) is not null as ev1;
select post_awareness_event((select v::uuid from ctx where k='exp'), 'low_battery', 14) = (select id from awareness_events where kind='low_battery' limit 1) as dedup2_EXPECT_t;
select post_awareness_event((select v::uuid from ctx where k='exp'), 'ping', null, null, null, :'a') is not null as ping;
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select count(*) as c_events_EXPECT_0 from awareness_events;
select post_convoy_event((select v::uuid from ctx where k='exp'), 'stopped') as c_post_EXPECT_ERROR;
reset role;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select set_alert_rule((select v::uuid from ctx where k='exp'), 'low_battery', 'trail', 25, true);
select set_expedition_role((select v::uuid from ctx where k='exp'), :'a', 'lead');
select set_expedition_role((select v::uuid from ctx where k='exp'), :'b', 'lead');
select string_agg(user_id::text || ':' || coalesce(awareness_role,'-'), ' ') as one_lead_only from expedition_members;
-- direct writes are not possible
insert into polls(crew_id,kind,question) values ((select v::uuid from ctx where k='crew'),'where','hack');
update live_fixes set lat = 0;
reset role;

\echo === finish wipes location, account deletion works
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select finish_expedition((select v::uuid from ctx where k='exp'));
reset role;
select (select count(*) from live_fixes) as fixes_EXPECT_0, (select count(*) from live_shares) as shares_EXPECT_0;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select delete_my_account();
reset role;
select count(*) as a_gone_EXPECT_0 from profiles where id=:'a';

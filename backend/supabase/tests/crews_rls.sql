-- RLS / behaviour test for crews + expeditions (migration 20261123000002).
-- Run against a THROWAWAY Postgres, never prod: it creates users and calls
-- delete_my_account(). Needs the Supabase stubs in crews_rls_stub.sql first,
-- then every migration in order, then this file.
\set ON_ERROR_STOP off
\pset pager off
\set a '11111111-1111-1111-1111-111111111111'
\set b '22222222-2222-2222-2222-222222222222'
\set c '33333333-3333-3333-3333-333333333333'
insert into auth.users(id,email) values (:'a','a@x'),(:'b','b@x'),(:'c','c@x');
update profiles set display_name='Real Person';
insert into routes(author_id,title,place,difficulty,transport,transport_label,distance_km,status,visibility)
 select :'a','Pub','P',(enum_range(null::difficulty))[1],(enum_range(null::transport_mode))[1],'x',1,'published','public';
insert into routes(author_id,title,place,difficulty,transport,transport_label,distance_km,status,visibility)
 select :'a','Priv','P',(enum_range(null::difficulty))[1],(enum_range(null::transport_mode))[1],'x',1,'published','private';
create table ctx(k text primary key, v text); grant all on ctx to authenticated;
insert into ctx select 'pub', id::text from routes where title='Pub';
insert into ctx select 'priv', id::text from routes where title='Priv';

\echo === 1. A creates crew; isolation
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'crew', create_crew('Weekend Nomads')::text;
select count(*) as a_sees_crews from crews;
select count(*) as a_members from crew_members;
reset role;
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select count(*) as b_sees_crews_EXPECT_0 from crews;
select count(*) as b_sees_members_EXPECT_0 from crew_members;
insert into crews(name, owner_id) values ('hack', :'b');
insert into crew_members(crew_id,user_id,role) select v::uuid,:'b','owner' from ctx where k='crew';
reset role;

\echo === 2. invite + join
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'code', create_crew_invite((select v::uuid from ctx where k='crew'));
reset role;
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select name, member_count, already_member from preview_crew_by_code((select v from ctx where k='code'));
select join_crew_by_code((select v from ctx where k='code')) is not null as b_joined;
select count(*) as b_sees_crews_EXPECT_1 from crews;
select count(*) as b_sees_roster_EXPECT_2 from crew_members;
select length(create_crew_invite((select v::uuid from ctx where k='crew'))) as member_can_invite_EXPECT_16;
update crews set name='pwn' where true;
select name as name_still from crews;
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select count(*) as c_sees_crews_EXPECT_0 from crews;
select create_crew_invite((select v::uuid from ctx where k='crew'));  -- non-member: expect 'not allowed'
select join_crew_by_code('nonsense');
select count(*) as c_preview_bad_code_EXPECT_0 from preview_crew_by_code('nonsense');
reset role;

\echo === 3. A manager rights, owner column locked
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
update crews set name='Weekend Nomads 2' where true;
select name as renamed from crews;
update crews set owner_id = :'b' where true;
reset role;

\echo === 4. expeditions
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
insert into ctx select 'exp_adhoc', create_expedition('Solo B trip')::text;
insert into ctx select 'exp_crew', create_expedition('Carpathians', (select v::uuid from ctx where k='crew'), 'hiking', '2026-12-10', '2026-12-14')::text;
select create_expedition('bad', '00000000-0000-0000-0000-000000000000'::uuid);
reset role;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select name as a_sees_expeditions_EXPECT_Carpathians_only from expeditions;
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select count(*) as c_sees_expeditions_EXPECT_0 from expeditions;
reset role;

\echo === 5. routes + stops
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select add_route_to_expedition((select v::uuid from ctx where k='exp_crew'), (select v::uuid from ctx where k='pub')) is not null as pub_added;
select add_route_to_expedition((select v::uuid from ctx where k='exp_crew'), (select v::uuid from ctx where k='priv'));
select add_expedition_stop((select v::uuid from ctx where k='exp_crew'),'accommodation','Hut',null,48.1,24.5,1) is not null as stop_added;
select add_expedition_stop((select v::uuid from ctx where k='exp_adhoc'),'poi','nope');
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select add_route_to_expedition((select v::uuid from ctx where k='exp_crew'), (select v::uuid from ctx where k='pub'));
select count(*) as c_sees_stops_EXPECT_0 from expedition_stops;
reset role;

\echo === 6. block hides roster entry
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into user_blocks(blocker_id,blocked_id) values (:'a',:'b');
select count(*) as a_roster_after_block_EXPECT_1 from crew_members;
delete from user_blocks;
reset role;

\echo === 7. invite limits
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
insert into ctx select 'code1', create_crew_invite((select v::uuid from ctx where k='crew'), 1);
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select join_crew_by_code((select v from ctx where k='code1')) is not null as c_joined_via_single_use;
reset role;
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select revoke_crew_invite((select v from ctx where k='code'));
reset role;
select count(*) as members_now_EXPECT_3 from crew_members;

\echo === 8. delete account of owner A: ownership passes, data survives
select set_config('request.jwt.claim.sub', :'a', false); set role authenticated;
select delete_my_account();
reset role;
select c.name, m.user_id=:'b' as owner_is_b, m.role from crews c join crew_members m on m.crew_id=c.id and m.role='owner';
select count(*) as members_after_EXPECT_2 from crew_members;
select name, organizer_id=:'b' as organizer_b from expeditions order by name;
select count(*) as stops_survive_EXPECT_1, bool_and(added_by is null) as added_by_nulled from expedition_stops;

\echo === 9. last member deletes -> crew gone
select set_config('request.jwt.claim.sub', :'b', false); set role authenticated;
select delete_my_account();
reset role;
select set_config('request.jwt.claim.sub', :'c', false); set role authenticated;
select delete_my_account();
reset role;
select (select count(*) from crews) as crews_EXPECT_0, (select count(*) from expeditions) as exps_EXPECT_0, (select count(*) from profiles) as profiles_EXPECT_0;

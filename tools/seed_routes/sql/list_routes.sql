-- All current routes: who owns them, how big, where. Run read-only:
--   supabase db query --linked -f tools/seed_routes/sql/list_routes.sql
select r.id,
       r.created_at::date as created,
       r.status,
       r.visibility,
       p.username as author,
       r.title,
       r.place,
       r.transport,
       r.difficulty,
       r.distance_km,
       jsonb_array_length(r.track_points) as track_pts,
       (select count(*) from public.route_likes l where l.route_id = r.id) as likes,
       (select count(*) from public.route_saves s where s.route_id = r.id) as saves
from public.routes r
join public.profiles p on p.id = r.author_id
order by r.created_at desc;

-- Permanently deletes every route that is NOT one of the 12 Nomad Curated routes
-- and NOT authored by illya_kovaliuk (the owner's own recorded route is kept).
-- Cascades to that route's segments, requirements, POIs, comments, likes, saves, photos rows.
-- IRREVERSIBLE (no undo except a database backup). Preview first with the SELECT below.
--
--   preview:  supabase db query --linked "<the select>"   (or run this file after checking)
begin;
delete from public.routes r
 using public.profiles p
 where p.id = r.author_id
   and p.username not in ('nomad_curated', 'illya_kovaliuk')
returning r.id, left(replace(r.title, E'\n', ' / '), 40) as title, p.username as author;
commit;
select count(*) as routes_left_total,
       count(*) filter (where p.username = 'nomad_curated') as curated,
       count(*) filter (where p.username = 'illya_kovaliuk') as yours
from public.routes r join public.profiles p on p.id = r.author_id;

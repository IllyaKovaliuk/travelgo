-- Hide junk routes WITHOUT deleting anything (status='hidden' keeps the row,
-- its comments, likes and photos; it just stops showing publicly). Reversible:
--   update public.routes set status = 'published' where id = '<id>';
-- 1) Replace the ids below with the routes you marked as junk (from list_routes.sql).
-- 2) Run: supabase db query --linked -f tools/seed_routes/sql/hide_routes.sql
update public.routes
   set status = 'hidden'
 where id in (
   '00000000-0000-0000-0000-000000000000'  -- <- paste real ids, comma-separated
 )
returning id, title, status;

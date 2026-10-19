-- Fixes the dead km_logged/routes_completed columns on `profiles`: real
-- columns, real schema, but nothing ever wrote to them — every reader
-- (AuthorProfileView's "KM LOGGED" stat, RouteDTO's route.author.routeCount
-- shown as "@handle · N routes" on every Route Detail screen) has been
-- silently showing 0 for every account since those screens were built.
-- Redefines routes_completed's real meaning as "how many routes this
-- person has published" — the one route-completion concept that actually
-- exists in this app (there's still no "mark someone else's route as
-- done" feature) — matching what ProfileView/AuthorProfileView already
-- call "ROUTES LOGGED"/"ROUTES CREATED" when they compute it client-side.
--
-- Scoped to published + public routes only, on purpose: this is what
-- OTHER people see on someone's profile (AuthorProfileView, route author
-- rows) — a private draft shouldn't inflate the number a stranger reads.
-- The owner's own ProfileView keeps computing its own (larger, private-
-- inclusive) totals client-side from the full route fetch it already
-- needs for its Routes tab — a different, intentionally different number,
-- not something this trigger should overwrite.
create or replace function public.sync_profile_route_stats(p_author_id uuid)
returns void as $$
  update public.profiles p
  set km_logged = coalesce((
        select sum(r.distance_km) from public.routes r
        where r.author_id = p_author_id and r.status = 'published' and r.visibility = 'public'
      ), 0),
      routes_completed = coalesce((
        select count(*)::int from public.routes r
        where r.author_id = p_author_id and r.status = 'published' and r.visibility = 'public'
      ), 0)
  where p.id = p_author_id;
$$ language sql security definer set search_path = public;

create or replace function public.routes_stats_trigger()
returns trigger as $$
begin
  if TG_OP = 'DELETE' then
    perform public.sync_profile_route_stats(OLD.author_id);
    return OLD;
  else
    perform public.sync_profile_route_stats(NEW.author_id);
    if TG_OP = 'UPDATE' and OLD.author_id is distinct from NEW.author_id then
      perform public.sync_profile_route_stats(OLD.author_id);
    end if;
    return NEW;
  end if;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_routes_change_sync_profile_stats on public.routes;
create trigger on_routes_change_sync_profile_stats
after insert or delete or update of distance_km, status, visibility, author_id
on public.routes
for each row execute function public.routes_stats_trigger();

-- Backfill every author's real numbers now, instead of waiting for their
-- next route insert/edit to first populate a correct value.
do $$
declare r record;
begin
  for r in select distinct author_id from public.routes loop
    perform public.sync_profile_route_stats(r.author_id);
  end loop;
end $$;

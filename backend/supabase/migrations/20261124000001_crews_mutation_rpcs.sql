-- Every crew / expedition mutation goes through an RPC so the rules live in
-- one place (and an Android client can reuse them). The first crews migration
-- left column-level UPDATE/DELETE grants for rename / reorder / remove; this
-- replaces them with RPCs and drops those grants, so a client can only READ
-- the tables directly.

create or replace function public.update_crew(p_crew_id uuid, p_name text, p_cover text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_crew_manager(p_crew_id) then raise exception 'not allowed'; end if;
  update crews set name = btrim(p_name), cover_image_url = coalesce(p_cover, cover_image_url)
   where id = p_crew_id;
end;
$$;

create or replace function public.update_expedition(
  p_expedition_id uuid, p_name text, p_trip_type public.trip_type,
  p_start date default null, p_end date default null,
  p_status public.expedition_status default null, p_cover text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  update expeditions set
      name = btrim(p_name),
      trip_type = p_trip_type,
      start_date = p_start,
      end_date = p_end,
      status = coalesce(p_status, status),
      cover_image_url = coalesce(p_cover, cover_image_url)
   where id = p_expedition_id;
end;
$$;

create or replace function public.delete_expedition(p_expedition_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  delete from expeditions where id = p_expedition_id;
end;
$$;

-- An organizer leaving must hand the trip over first (RESTRICT on organizer_id).
create or replace function public.leave_expedition(p_expedition_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if exists (select 1 from expeditions where id = p_expedition_id and organizer_id = uid) then
    raise exception 'transfer ownership before leaving';
  end if;
  delete from expedition_members where expedition_id = p_expedition_id and user_id = uid;
end;
$$;

create or replace function public.remove_expedition_route(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from expedition_routes r
   where r.id = p_item_id and can_see_expedition(r.expedition_id);
end;
$$;

create or replace function public.remove_expedition_stop(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from expedition_stops s
   where s.id = p_item_id and can_see_expedition(s.expedition_id);
end;
$$;

-- Itinerary reorder: [{id, day_index, position}] for routes and for stops, in
-- one transaction. Only rows that belong to this expedition are touched.
create or replace function public.reorder_expedition_items(
  p_expedition_id uuid, p_routes jsonb default '[]', p_stops jsonb default '[]')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not can_see_expedition(p_expedition_id) then raise exception 'not allowed'; end if;
  update expedition_routes r set day_index = x.day_index, position = x.position
    from jsonb_to_recordset(p_routes) as x(id uuid, day_index integer, position integer)
   where r.id = x.id and r.expedition_id = p_expedition_id;
  update expedition_stops s set day_index = x.day_index, position = x.position
    from jsonb_to_recordset(p_stops) as x(id uuid, day_index integer, position integer)
   where s.id = x.id and s.expedition_id = p_expedition_id;
end;
$$;

revoke all on function
  public.update_crew(uuid, text, text),
  public.update_expedition(uuid, text, trip_type, date, date, expedition_status, text),
  public.delete_expedition(uuid), public.leave_expedition(uuid),
  public.remove_expedition_route(uuid), public.remove_expedition_stop(uuid),
  public.reorder_expedition_items(uuid, jsonb, jsonb) from public, anon;
grant execute on function
  public.update_crew(uuid, text, text),
  public.update_expedition(uuid, text, trip_type, date, date, expedition_status, text),
  public.delete_expedition(uuid), public.leave_expedition(uuid),
  public.remove_expedition_route(uuid), public.remove_expedition_stop(uuid),
  public.reorder_expedition_items(uuid, jsonb, jsonb) to authenticated;

-- Reads only from here on.
revoke update, delete on public.crews, public.expeditions,
  public.expedition_routes, public.expedition_stops from authenticated;

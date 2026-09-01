-- Points of interest — arbitrary user-dropped pins along a route ("water
-- here", "homestay here", "waterfall here"), distinct from segments
-- (which describe a *stretch* of the path) and requirements (gear/permits).
-- Any number per route. Same RLS shape as route_segments/route_requirements.
create table public.route_points_of_interest (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes (id) on delete cascade,
  lat numeric not null,
  lng numeric not null,
  category text not null,
  title text not null,
  note text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.route_points_of_interest enable row level security;

create policy "POIs follow their route's visibility"
  on public.route_points_of_interest for select
  using (exists (
    select 1 from public.routes r
    where r.id = route_id
      and (r.author_id = auth.uid() or (r.status = 'published' and r.visibility = 'public'))
  ));

create policy "Owners manage their route's POIs"
  on public.route_points_of_interest for all
  using (exists (select 1 from public.routes r where r.id = route_id and r.author_id = auth.uid()))
  with check (exists (select 1 from public.routes r where r.id = route_id and r.author_id = auth.uid()));

-- Follow-up to 20261002000001: route_segments/route_requirements/
-- route_points_of_interest each had their own copy of the stale two-way
-- "owner OR public-published" visibility check (same one `routes` itself
-- had until the last migration), never updated to the three-way
-- owner/public/followers check `route_readable_by_viewer()` now encodes.
-- Even once a follower could read the parent `routes` row, these embedded
-- sub-resources (what RouteDetailView actually renders as segments,
-- requirements, POIs) would still come back empty for them — a published
-- route opened by a follower with a visible title/cover but nothing
-- inside it.
drop policy if exists "Segments follow their route's visibility" on route_segments;
create policy "Segments follow their route's visibility"
on route_segments for select
using (
  exists (
    select 1 from routes r
    where r.id = route_segments.route_id
      and route_readable_by_viewer(r.author_id, r.status, r.visibility)
  )
);

drop policy if exists "Requirements follow their route's visibility" on route_requirements;
create policy "Requirements follow their route's visibility"
on route_requirements for select
using (
  exists (
    select 1 from routes r
    where r.id = route_requirements.route_id
      and route_readable_by_viewer(r.author_id, r.status, r.visibility)
  )
);

drop policy if exists "POIs follow their route's visibility" on route_points_of_interest;
create policy "POIs follow their route's visibility"
on route_points_of_interest for select
using (
  exists (
    select 1 from routes r
    where r.id = route_points_of_interest.route_id
      and route_readable_by_viewer(r.author_id, r.status, r.visibility)
  )
);

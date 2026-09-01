-- Real GPS tracks. Until now `routes` had no actual geodata at all — the
-- map header was a hand-drawn stand-in and Record-a-route simulated pace
-- instead of reading CoreLocation. This adds a place to persist the real
-- recorded polyline once the app records one.
alter table public.routes
  add column track_points jsonb not null default '[]'::jsonb;

comment on column public.routes.track_points is
  'Recorded GPS polyline as a JSON array of {"lat": number, "lng": number} points, in recording order. Empty for routes published before this column existed or logged without a live recording.';

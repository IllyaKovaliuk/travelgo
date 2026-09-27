-- Part 3 — passive Visits journal (CLVisit-based, separate from active
-- LogRoute recordings). Entirely private: unlike routes/comments/photos,
-- nobody else ever reads another user's visits, so this gets a single
-- "owner only, full CRUD" policy rather than the routes-style public/
-- author split.
create table public.visits (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    lat numeric not null,
    lng numeric not null,
    -- Reverse-geocoded "Locality, Country" — same shape routes.place
    -- already uses, so ProfileView's existing `countryTag(from:)` parser
    -- (splits on the last comma) works unchanged for kept visits too,
    -- instead of needing a second country-parsing path.
    place_name text,
    arrival_at timestamptz not null,
    -- Null while the visit is still "open" (iOS hasn't reported a
    -- departure yet — see VisitsMonitor's arrival/departure correlation).
    departure_at timestamptz,
    -- pending: detected, not yet reviewed by the user (never counted
    -- anywhere). kept: user confirmed it — counts toward "countries
    -- visited" only, never km/streak/leaderboard (those stay tied to real
    -- active recordings, or the leaderboard becomes gameable by just
    -- carrying the phone around). dismissed: user discarded it.
    status text not null default 'pending' check (status in ('pending', 'kept', 'dismissed')),
    linked_route_id uuid references public.routes(id) on delete set null,
    created_at timestamptz not null default now()
);

create index visits_user_id_idx on public.visits(user_id);
-- VisitsMonitor looks up "is there already an open pending visit near
-- here" on every departure-only CLVisit callback to correlate it with the
-- earlier arrival instead of creating a duplicate row.
create index visits_open_lookup_idx on public.visits(user_id, status) where departure_at is null;

alter table public.visits enable row level security;

create policy "Users manage their own visits"
    on public.visits for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

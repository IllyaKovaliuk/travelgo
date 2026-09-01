-- NomadTerminal — initial schema.
-- Mirrors the SwiftUI mock models 1:1 (Route, RouteDetailInfo, Author, Badge)
-- so swapping mock data for live queries is a drop-in change, not a rewrite.

create extension if not exists "pgcrypto";

-- ── Profiles ────────────────────────────────────────────────────────────
-- One row per auth.users row, created automatically on sign-up (trigger below).
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  display_name text not null,
  home_location text,
  avatar_url text,
  km_logged numeric not null default 0,
  routes_completed integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Profiles are publicly readable"
  on public.profiles for select
  using (true);

create policy "Users manage their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create a profile row when someone signs up.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'nomad_' || substr(new.id::text, 1, 8)),
    coalesce(new.raw_user_meta_data ->> 'display_name', 'New Nomad')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── Routes ──────────────────────────────────────────────────────────────
create type public.difficulty as enum ('easy', 'moderate', 'hard');
create type public.transport_mode as enum ('overland', 'foot', 'water', 'climb');
create type public.route_visibility as enum ('public', 'followers', 'private');
create type public.route_status as enum ('draft', 'published');

create table public.routes (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  place text not null,
  cover_image_url text,
  difficulty public.difficulty not null,
  transport public.transport_mode not null,
  transport_label text not null,
  secondary_badge_icon text,
  secondary_badge_label text,
  distance_km numeric not null,
  coordinates text,
  season text,
  duration text,
  ascent_m integer,
  high_point_m integer,
  elevation_profile numeric[] not null default '{}',
  elevation_peak_label text,
  quote text,
  quote_author text,
  visibility public.route_visibility not null default 'public',
  status public.route_status not null default 'published',
  created_at timestamptz not null default now()
);

create index routes_author_idx on public.routes (author_id);
create index routes_visibility_idx on public.routes (visibility) where status = 'published';

alter table public.routes enable row level security;

create policy "Published public routes are readable by anyone"
  on public.routes for select
  using (status = 'published' and visibility = 'public');

create policy "Owners can read all their own routes"
  on public.routes for select
  using (auth.uid() = author_id);

create policy "Owners manage their own routes"
  on public.routes for all
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

-- ── Segments & requirements (children of a route) ─────────────────────
create table public.route_segments (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes (id) on delete cascade,
  icon text not null,
  name text not null,
  distance_km numeric not null,
  tint text not null,
  sort_order integer not null default 0
);

create table public.route_requirements (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes (id) on delete cascade,
  icon text not null,
  title text not null,
  subtitle text,
  tint text not null,
  sort_order integer not null default 0
);

alter table public.route_segments enable row level security;
alter table public.route_requirements enable row level security;

create policy "Segments follow their route's visibility"
  on public.route_segments for select
  using (exists (
    select 1 from public.routes r
    where r.id = route_id
      and (r.author_id = auth.uid() or (r.status = 'published' and r.visibility = 'public'))
  ));

create policy "Owners manage their route's segments"
  on public.route_segments for all
  using (exists (select 1 from public.routes r where r.id = route_id and r.author_id = auth.uid()))
  with check (exists (select 1 from public.routes r where r.id = route_id and r.author_id = auth.uid()));

create policy "Requirements follow their route's visibility"
  on public.route_requirements for select
  using (exists (
    select 1 from public.routes r
    where r.id = route_id
      and (r.author_id = auth.uid() or (r.status = 'published' and r.visibility = 'public'))
  ));

create policy "Owners manage their route's requirements"
  on public.route_requirements for all
  using (exists (select 1 from public.routes r where r.id = route_id and r.author_id = auth.uid()))
  with check (exists (select 1 from public.routes r where r.id = route_id and r.author_id = auth.uid()));

-- ── Social: likes, saves, follows ──────────────────────────────────────
create table public.route_likes (
  route_id uuid not null references public.routes (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (route_id, user_id)
);

create table public.route_saves (
  route_id uuid not null references public.routes (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  downloaded_offline boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (route_id, user_id)
);

create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

alter table public.route_likes enable row level security;
alter table public.route_saves enable row level security;
alter table public.follows enable row level security;

create policy "Likes are publicly readable" on public.route_likes for select using (true);
create policy "Users manage their own likes" on public.route_likes for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users read their own saves" on public.route_saves for select using (auth.uid() = user_id);
create policy "Users manage their own saves" on public.route_saves for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Follows are publicly readable" on public.follows for select using (true);
create policy "Users manage their own follows" on public.follows for all
  using (auth.uid() = follower_id) with check (auth.uid() = follower_id);

-- ── Badges ──────────────────────────────────────────────────────────────
create table public.badges (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  title text not null,
  subtitle text not null,
  icon text not null,
  color_start text not null,
  color_end text not null
);

create table public.user_badges (
  user_id uuid not null references public.profiles (id) on delete cascade,
  badge_id uuid not null references public.badges (id) on delete cascade,
  earned_at timestamptz not null default now(),
  primary key (user_id, badge_id)
);

alter table public.badges enable row level security;
alter table public.user_badges enable row level security;

create policy "Badges are publicly readable" on public.badges for select using (true);
create policy "Earned badges are publicly readable" on public.user_badges for select using (true);

-- ── Storage: route cover photos ─────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('route-covers', 'route-covers', true)
on conflict (id) do nothing;

create policy "Cover photos are publicly readable"
  on storage.objects for select
  using (bucket_id = 'route-covers');

create policy "Authenticated users can upload cover photos"
  on storage.objects for insert
  with check (bucket_id = 'route-covers' and auth.role() = 'authenticated');

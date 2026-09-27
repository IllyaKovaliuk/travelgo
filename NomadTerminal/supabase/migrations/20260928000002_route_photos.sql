-- Part 2 (photos on routes) — modeled directly on route_comments: same
-- user + route + timestamp + content shape, same visibility-follows-route
-- read policy, same open "any authenticated user can add" write policy,
-- same hidden-boolean moderation flag instead of a separate table.
create table public.route_photos (
    id uuid primary key default gen_random_uuid(),
    route_id uuid not null references public.routes(id) on delete cascade,
    uploader_id uuid not null references public.profiles(id) on delete cascade,
    image_url text not null,
    -- Real GPS coordinate captured live mid-recording (Part 2a) — null for
    -- an after-the-fact library upload (Part 2b) with no known trail
    -- position. Never guessed/interpolated from the route's other points.
    lat numeric,
    lng numeric,
    caption text,
    created_at timestamptz not null default now(),
    hidden boolean not null default false
);

create index route_photos_route_id_idx on public.route_photos(route_id);

alter table public.route_photos enable row level security;

create policy "Photos follow their route's visibility"
    on public.route_photos for select
    using (
        not hidden and exists (
            select 1 from public.routes r
            where r.id = route_photos.route_id
              and (r.author_id = auth.uid() or (r.status = 'published' and r.visibility = 'public'))
        )
    );

-- Matches route_comments: anyone signed in can contribute, not just the
-- route's own author — that's the whole point of this being a shared
-- social layer, same as comments already are.
create policy "Authenticated users can add photos"
    on public.route_photos for insert
    with check (auth.uid() = uploader_id);

create policy "Uploaders manage their own photos"
    on public.route_photos for delete
    using (auth.uid() = uploader_id);

-- Extend the existing auto-hide trigger (route_comments/routes) to cover
-- photos too, rather than a parallel photo-specific mechanism.
create or replace function public.auto_hide_reported_content()
returns trigger as $$
declare
  distinct_reporters integer;
begin
  select count(distinct reporter_id) into distinct_reporters
  from public.content_reports
  where target_type = new.target_type and target_id = new.target_id;

  if distinct_reporters >= 3 then
    if new.target_type = 'route' then
      update public.routes set status = 'hidden' where id = new.target_id and status <> 'hidden';
    elsif new.target_type = 'comment' then
      update public.route_comments set hidden = true where id = new.target_id;
    elsif new.target_type = 'photo' then
      update public.route_photos set hidden = true where id = new.target_id;
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- Admin moderation RPCs, mirroring admin_list_hidden_comments /
-- admin_reinstate_comment exactly (including their existing trust model —
-- see AdminModerationView's own header comment on why these aren't
-- role-gated at the DB level today).
create or replace function public.admin_list_hidden_photos()
returns table (
    id uuid,
    image_url text,
    caption text,
    route_id uuid,
    route_title text,
    uploader_id uuid,
    uploader_name text,
    report_count int,
    reasons text[],
    created_at timestamptz
) as $$
  select
    ph.id, ph.image_url, ph.caption, ph.route_id, r.title, ph.uploader_id, p.display_name,
    (select count(distinct cr.reporter_id)::int from content_reports cr
      where cr.target_type = 'photo' and cr.target_id = ph.id),
    (select array_agg(distinct cr.reason) from content_reports cr
      where cr.target_type = 'photo' and cr.target_id = ph.id),
    ph.created_at
  from route_photos ph
  join routes r on r.id = ph.route_id
  join profiles p on p.id = ph.uploader_id
  where ph.hidden = true
  order by ph.created_at desc;
$$ language sql security definer set search_path = public;

create or replace function public.admin_reinstate_photo(target_id uuid)
returns void as $$
  update route_photos set hidden = false where id = target_id;
$$ language sql security definer set search_path = public;

-- A dedicated bucket rather than folding into route-covers: route-covers
-- is one image per route, owned/replaced by the route's author; this is
-- many images per route, contributed by anyone, each independently
-- deletable by whoever uploaded it — different enough lifecycle to keep
-- its policies separate rather than overloading route-covers' existing
-- "any authenticated user" insert policy with a second meaning.
insert into storage.buckets (id, name, public)
values ('route-photos', 'route-photos', true)
on conflict (id) do nothing;

create policy "Route photos are publicly readable"
    on storage.objects for select
    using (bucket_id = 'route-photos');

create policy "Authenticated users can upload route photos"
    on storage.objects for insert
    with check (bucket_id = 'route-photos' and auth.role() = 'authenticated');

create policy "Uploaders can delete their own route photo files"
    on storage.objects for delete
    using (bucket_id = 'route-photos' and auth.role() = 'authenticated' and owner = auth.uid());

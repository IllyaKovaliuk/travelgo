-- Comments on routes — same visibility rule as the route itself.
create table public.route_comments (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index route_comments_route_idx on public.route_comments (route_id, created_at);

alter table public.route_comments enable row level security;

create policy "Comments follow their route's visibility"
  on public.route_comments for select
  using (exists (
    select 1 from public.routes r
    where r.id = route_id
      and (r.author_id = auth.uid() or (r.status = 'published' and r.visibility = 'public'))
  ));

create policy "Authenticated users can comment"
  on public.route_comments for insert
  with check (auth.uid() = author_id);

create policy "Authors manage their own comments"
  on public.route_comments for delete
  using (auth.uid() = author_id);

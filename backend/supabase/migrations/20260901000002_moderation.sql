-- Basic content moderation: anyone can report a route or a comment; once a
-- piece of content collects reports from 3 distinct people, it's
-- auto-hidden from public view. No admin dashboard yet — reviewing/
-- reinstating wrongly-hidden content is a manual SQL job for now, which is
-- an acceptable trade-off at this scale but should become a real admin
-- tool once there's enough volume for false positives to matter.

create type public.report_target as enum ('route', 'comment');

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  target_type public.report_target not null,
  target_id uuid not null,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  unique (target_type, target_id, reporter_id) -- one report per person per item
);

alter table public.content_reports enable row level security;

create policy "Users can file reports"
  on public.content_reports for insert
  with check (auth.uid() = reporter_id);

create policy "Users can see their own reports"
  on public.content_reports for select
  using (auth.uid() = reporter_id);

-- Add a hidden state alongside the existing draft/published statuses, and
-- a parallel flag on comments (which have no status column of their own).
alter type public.route_status add value if not exists 'hidden';
alter table public.route_comments add column hidden boolean not null default false;

-- Re-scope the comments select policy to also exclude hidden ones.
drop policy "Comments follow their route's visibility" on public.route_comments;

create policy "Comments follow their route's visibility"
  on public.route_comments for select
  using (
    not hidden
    and exists (
      select 1 from public.routes r
      where r.id = route_id
        and (r.author_id = auth.uid() or (r.status = 'published' and r.visibility = 'public'))
    )
  );

create or replace function public.auto_hide_reported_content()
returns trigger
language plpgsql
security definer set search_path = public
as $$
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
    end if;
  end if;

  return new;
end;
$$;

create trigger on_content_report_check_threshold
  after insert on public.content_reports
  for each row execute procedure public.auto_hide_reported_content();

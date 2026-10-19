-- App Review guideline 1.2: users must be able to block abusive users.
-- A block hides the blocked user's content from the blocker, enforced by
-- Postgres (RESTRICTIVE select policies) so no client query can bypass it.

create table public.user_blocks (
    blocker_id uuid not null references public.profiles(id) on delete cascade,
    blocked_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index user_blocks_blocked_id_idx on public.user_blocks(blocked_id);

alter table public.user_blocks enable row level security;

create policy "Users read their own blocks"
    on public.user_blocks for select
    using (auth.uid() = blocker_id);

create policy "Users create their own blocks"
    on public.user_blocks for insert
    with check (auth.uid() = blocker_id);

create policy "Users remove their own blocks"
    on public.user_blocks for delete
    using (auth.uid() = blocker_id);

-- Explicit grants rather than relying on default privileges. No UPDATE: a
-- block is a row that exists or doesn't.
revoke all on public.user_blocks from anon, authenticated;
grant select, insert, delete on public.user_blocks to authenticated;

-- True when the current viewer has blocked `p_user_id`. SECURITY DEFINER so
-- it also works for roles with no direct access to user_blocks (anon, which
-- the restrictive policies below still evaluate for); it only ever looks at
-- rows where blocker_id = auth.uid(), so it reveals nothing about anyone
-- else's blocks.
create or replace function public.is_blocked_by_viewer(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks b
    where b.blocker_id = auth.uid()
      and b.blocked_id = p_user_id
  );
$$;
revoke all on function public.is_blocked_by_viewer(uuid) from public;
grant execute on function public.is_blocked_by_viewer(uuid) to anon, authenticated;

-- RESTRICTIVE policies are AND-ed with every existing permissive SELECT
-- policy, so visibility rules (public / followers / owner / hidden) stay
-- exactly as they were and a block is simply one more condition.
create policy "Hide blocked users' routes"
    on public.routes as restrictive for select
    using (author_id = auth.uid() or not public.is_blocked_by_viewer(author_id));

create policy "Hide blocked users' comments"
    on public.route_comments as restrictive for select
    using (author_id = auth.uid() or not public.is_blocked_by_viewer(author_id));

create policy "Hide blocked users' photos"
    on public.route_photos as restrictive for select
    using (uploader_id = auth.uid() or not public.is_blocked_by_viewer(uploader_id));

create policy "Hide blocked users' hazard reports"
    on public.reports as restrictive for select
    using (user_id = auth.uid() or not public.is_blocked_by_viewer(user_id));

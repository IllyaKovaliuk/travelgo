-- Real identities only — no more "New Nomad" leaking into feeds/leaderboard/
-- followers as if it were a real person's name.
--
-- Client-side, real signup (AuthView) already requires a name and always
-- sends `display_name` in signup metadata — that path was never the
-- problem. The gap was `handle_new_user()`'s own fallback: any account
-- created WITHOUT that metadata (chiefly the defensive last-resort
-- anonymous sign-in in `RouteRepository.ensureSession()`, meant only to
-- guard against a caller somehow running before the onboarding auth gate)
-- silently got a *real-looking* placeholder name, "New Nomad", instead of
-- an honest "this account has no name yet" NULL. That's how a route
-- authored by one such leftover account could show up with a name that
-- reads exactly like something a real person typed.
--
-- Fixed at two levels:
--   1. `display_name` becomes nullable and the fallback becomes NULL, not
--      a fake-looking string — a nameless account is now honestly
--      nameless, not disguised as "New Nomad".
--   2. A hard DB-level guard on `routes`: publishing is refused outright
--      unless the author's profile has a real, non-blank display_name.
--      This is enforced no matter what client code does or doesn't check
--      — "everyone must enter a name, no exceptions" holds even against a
--      future client bug, not just today's UI validation.

alter table public.profiles alter column display_name drop not null;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'nomad_' || substr(new.id::text, 1, 8)),
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), '')
  );
  return new;
end;
$$;

create or replace function public.require_real_author_name()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  author_name text;
begin
  select display_name into author_name from public.profiles where id = new.author_id;
  if author_name is null or trim(author_name) = '' then
    raise exception 'A real display name is required before publishing a route.';
  end if;
  return new;
end;
$$;

drop trigger if exists require_real_author_name_trigger on public.routes;
create trigger require_real_author_name_trigger
  before insert on public.routes
  for each row execute function public.require_real_author_name();

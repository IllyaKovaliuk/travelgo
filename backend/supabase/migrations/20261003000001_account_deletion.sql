-- Real self-service account deletion — a hard App Store requirement
-- (5.1.1(v)) for any app that supports account creation. No in-app
-- deletion existed before this; the previous answer was "email us."
--
-- `profiles` has no enforced foreign key to `auth.users` (confirmed by
-- querying information_schema — `profiles.id` matches `auth.users.id`
-- only by convention, set once at signup by `handle_new_user()`), so
-- deleting the `auth.users` row alone would NOT cascade to the profile or
-- anything under it. `profiles` itself DOES already have real `on delete
-- cascade` foreign keys from routes, route_comments, route_likes,
-- route_saves, route_photos, follows (both directions), emergency_contacts,
-- points_ledger, referrals (both directions), user_badges, visits, and
-- content_reports.reporter_id — confirmed by querying
-- information_schema.referential_constraints, not assumed. So: delete
-- `profiles` first (cascades through all of that), then `auth.users`
-- (ends the session and the login for good).
create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  delete from profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

grant execute on function delete_my_account() to authenticated;

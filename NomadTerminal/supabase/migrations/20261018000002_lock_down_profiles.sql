-- SECURITY FIX. `authenticated` had a table-level UPDATE grant on
-- `profiles`, so the earlier column-level `REVOKE UPDATE (points_balance,
-- bonus_pro_until)` had no effect (a column REVOKE can't subtract from a
-- table-level GRANT). Combined with the "Users manage their own profile"
-- UPDATE policy (row filter only), any signed-in user could PATCH their own
-- row and set points_balance, bonus_pro_until (free Pro), is_admin,
-- is_super_admin or is_banned directly through PostgREST.
--
-- Fix: drop all client-side write grants, then allow UPDATE on exactly the
-- columns the app edits itself. Everything else (points, Pro grant, roles,
-- bans, stats, referral code) is written only by SECURITY DEFINER
-- functions/triggers, which run as the table owner and are unaffected.
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (username, display_name, home_location, avatar_url) on public.profiles to authenticated;

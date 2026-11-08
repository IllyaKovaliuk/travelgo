-- Sign in with Apple token revocation (App Review 5.1.1(v)): when a user
-- deletes their account, Apple requires the app to revoke the SIWA token.
-- Revoking needs the *refresh token*, which only exists server-side (it's
-- minted by exchanging the one-time authorizationCode with Apple using a
-- client secret signed with our private key — see
-- functions/apple-revoke). This table keeps it between sign-in and
-- deletion.
--
-- RLS is enabled with NO policies and all client grants revoked: no
-- client (anon or authenticated) can ever read or write a refresh token.
-- Only the edge function, using the service role, touches this table.
create table public.apple_refresh_tokens (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);

alter table public.apple_refresh_tokens enable row level security;
revoke all on public.apple_refresh_tokens from anon, authenticated;

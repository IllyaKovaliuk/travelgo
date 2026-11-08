// Sign in with Apple token lifecycle (App Review 5.1.1(v)).
//
//   action "store":  { action: "store", authorizationCode }
//     Called by the app right after a successful Apple sign-in. Exchanges the
//     one-time code for a refresh token and keeps it (service role only).
//   action "revoke": { action: "revoke" }
//     Called by the app right before delete_my_account(). Revokes the stored
//     token at Apple and forgets it. A no-op for accounts that never stored
//     one (email/Google users, or Apple users from before this shipped).
//
// Required secrets (supabase secrets set …):
//   APPLE_TEAM_ID        10-char Apple developer Team ID
//   APPLE_KEY_ID         Key ID of a "Sign in with Apple" key (.p8)
//   APPLE_PRIVATE_KEY    contents of that .p8 file (PKCS8 PEM)
//   APPLE_CLIENT_ID      the app's bundle id (io.nomadterminal.app)
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
// by the platform.
import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function clientSecret(): Promise<string> {
  const key = await importPKCS8(Deno.env.get("APPLE_PRIVATE_KEY")!.replace(/\\n/g, "\n"), "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APPLE_KEY_ID")! })
    .setIssuer(Deno.env.get("APPLE_TEAM_ID")!)
    .setSubject(Deno.env.get("APPLE_CLIENT_ID")!)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(key);
}

async function appleForm(path: string, params: Record<string, string>) {
  return await fetch(`https://appleid.apple.com/auth/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: Deno.env.get("APPLE_CLIENT_ID")!,
      client_secret: await clientSecret(),
      ...params,
    }),
  });
}

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await caller.auth.getUser();
  if (!user) return json({ error: "not authenticated" }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { action, authorizationCode } = await req.json().catch(() => ({}));

  if (action === "store") {
    if (!authorizationCode) return json({ error: "missing authorizationCode" }, 400);
    const res = await appleForm("token", { code: authorizationCode, grant_type: "authorization_code" });
    if (!res.ok) return json({ error: "apple token exchange failed" }, 502);
    const { refresh_token } = await res.json();
    if (!refresh_token) return json({ error: "no refresh token" }, 502);
    await admin.from("apple_refresh_tokens").upsert({
      user_id: user.id, refresh_token, updated_at: new Date().toISOString(),
    });
    return json({ ok: true });
  }

  if (action === "revoke") {
    const { data } = await admin.from("apple_refresh_tokens").select("refresh_token").eq("user_id", user.id).maybeSingle();
    if (!data) return json({ ok: true, revoked: false });
    const res = await appleForm("revoke", { token: data.refresh_token, token_type_hint: "refresh_token" });
    if (!res.ok) return json({ error: "apple revoke failed" }, 502);
    await admin.from("apple_refresh_tokens").delete().eq("user_id", user.id);
    return json({ ok: true, revoked: true });
  }

  return json({ error: "unknown action" }, 400);
});

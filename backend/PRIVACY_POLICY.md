# NomadCompass Privacy Policy

**Last updated:** October 2, 2026

This policy describes what NomadCompass ("the app", "we") collects, why, and how it's handled. It's written to match what the app actually does — not a generic template — and should be kept in sync with the code whenever data collection changes.

## What we collect

**Account information.** When you create an account, we collect your email address and a username/display name you choose. Authentication is handled by our backend provider, Supabase — we never see or store your password ourselves. If you sign in with Google, Google shares your name, email, and profile photo with us for that purpose.

**Location data.** NomadCompass is a route-logging and navigation app; location is core to what it does, in several distinct ways:
- **While recording a route**, we collect a live stream of GPS coordinates (latitude, longitude, altitude) to compute your distance, elevation gain, and the path you traveled. This is stored as part of the route you choose to publish.
- **While navigating a published route** (Compass's map mode), we read your live position to show it on the map and compute your real-time distance/progress along the route — this is not stored, only used live on your device.
- **If you use the SOS screen**, your last known position is included in the message it prepares for your emergency contacts.
- **Background location is optional and off by default.** If you turn on "Passive visit detection" in Settings, the app requests "Always" location access and uses iOS's Visits API to notice when you've stopped somewhere new, so it can log the place to your Journal. This runs in the background, independent of an active recording session, and only happens if you explicitly enable it. You can turn it off at any time in Settings or by changing the app's location permission in iOS Settings.
- The recorded path of a route you publish is visible to whoever can see that route (public, followers-only, or private, per your chosen visibility).

**Emergency contacts.** If you add emergency contacts in Settings, we store the name, phone number, and/or email address you enter for each one. This is other people's contact information that you provide, used only to pre-fill the message the SOS screen opens in your device's own Messages app — we never contact them ourselves, and this data is visible only to your own account.

**Content you create.** Routes, segments, requirements/gear notes, comments, cover photos, route photos, and your profile avatar are stored so they can be shown to you and (depending on visibility) other users.

**Usage analytics.** We record a small set of in-app events tied to your account (e.g. that you signed up, published a route, or triggered SOS) to understand how the app is used and to fix what's broken. This is event names and timestamps, not content, and it's never shared or sold.

**Usage data.** Likes, saves, follows, and comments are stored to power those features (e.g., showing your saved routes, a route's like count).

**Device storage.** Routes you've opened are cached locally on your device (the route's own data and its cover photo) so they remain viewable without a network connection; this does not include map tiles, which still require a connection to load. This stays on your device and is not uploaded anywhere beyond the normal publish flow.

**Purchase information.** Subscription purchases (NomadCompass Pro) are processed entirely by Apple through StoreKit. We receive confirmation that you have an active subscription; we do not receive or store your payment details.

## What we don't do

- We don't run ads or use third-party ad/tracking SDKs.
- We don't sell or share your data with data brokers.
- We don't collect background location unless you explicitly turn on Passive visit detection.
- SOS does not dispatch any emergency service or notify anyone automatically — it opens a pre-filled message in your own Messages app that you choose to send yourself. See the in-app SOS screen and Field Guide for details on what this does and doesn't do.

## Where data lives

Account, route, and social data is stored with Supabase (Postgres + Auth), our backend provider, hosted in the EU (eu-west-1). Supabase acts as our data processor and is bound by its own security practices; we don't operate our own servers for this data.

## Your controls

- **Route visibility** — set per route to public, followers-only, or private at publish time.
- **Passive visit detection** — off by default; toggle it in Settings at any time. Turning it off stops background location use immediately.
- **Emergency contacts** — add, edit, or remove them at any time in Settings.
- **Account deletion** — contact us (see below) to delete your account and associated data. In-app self-service deletion is planned but not yet built; until then, this is a manual request we process ourselves.
- **Location permission** — controlled via iOS Settings → NomadCompass → Location. Denying it disables route recording, live navigation, and SOS's position-sharing, but the rest of the app still works.
- **Reporting content** — you can report a route, photo, or comment; content that collects enough reports is automatically hidden pending review, and our moderators can review, hide, or remove it directly.

## Children

NomadCompass is not directed at children under 13, and we don't knowingly collect data from them.

## Changes to this policy

If what we collect changes in a material way, we'll update this document and the "Last updated" date above.

## Contact

Questions about this policy or a data request: **[insert contact email before publishing]**

---
*Internal note: accurate as of the code at commit time (includes background Visits/Passive detection, analytics events, and emergency contacts, which the previous draft omitted or contradicted). Before submitting to App Store Connect: (1) fill in a real contact email you actually monitor, (2) host this at a public URL (App Store Connect requires a live privacy policy link — a published Artifact page works as a quick first host), (3) re-check it against the code if data collection changes again.*

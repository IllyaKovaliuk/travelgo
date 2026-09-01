# NomadTerminal Privacy Policy

**Last updated:** September 1, 2026

This policy describes what NomadTerminal ("the app", "we") collects, why, and how it's handled. It's written to match what the app actually does — not a generic template — and should be kept in sync with the code whenever data collection changes.

## What we collect

**Account information.** When you create an account, we collect your email address and a username/display name you choose. Authentication is handled by our backend provider, Supabase — we never see or store your password ourselves.

**Location data.** NomadTerminal is a route-logging app; location is core to what it does:
- While recording a route, we collect a live stream of GPS coordinates (latitude, longitude, altitude) to compute your distance, elevation gain, and the path you traveled.
- The recorded path is stored as part of the route you choose to publish, and is visible to whoever can see that route (public, followers-only, or private, per your chosen visibility).
- Location is only collected while you are actively recording — we do not track your location in the background outside of an active recording session.

**Content you create.** Routes, segments, requirements/gear notes, comments, and any cover photos you add are stored so they can be shown to you and (depending on visibility) other users.

**Usage data.** Likes, saves, follows, and comments are stored to power those features (e.g., showing your saved routes, a route's like count).

**Device storage.** Routes you explicitly download for offline use are cached locally on your device (route details and a static map image), so they remain viewable without a network connection. This stays on your device and is not uploaded anywhere beyond the normal publish flow.

**Purchase information.** Subscription purchases (NomadTerminal Pro) are processed entirely by Apple through StoreKit. We receive confirmation that you have an active subscription; we do not receive or store your payment details.

## What we don't do

- We don't run ads or use third-party ad/tracking SDKs.
- We don't sell or share your data with data brokers.
- We don't track your location outside of an active route recording.

## Where data lives

Account, route, and social data is stored with Supabase (Postgres + Auth), our backend provider, hosted in the EU (eu-west-1). Supabase acts as our data processor and is bound by its own security practices; we don't operate our own servers for this data.

## Your controls

- **Route visibility** — set per route to public, followers-only, or private at publish time.
- **Account deletion** — contact us (see below) to delete your account and associated data. (In-app self-service deletion is planned but not yet built — until then, this is a manual request.)
- **Location permission** — controlled via iOS Settings → NomadTerminal → Location. Denying it disables route recording but the rest of the app still works.
- **Reporting content** — you can report a route or comment; content that collects enough reports is automatically hidden pending review.

## Children

NomadTerminal is not directed at children under 13, and we don't knowingly collect data from them.

## Changes to this policy

If what we collect changes in a material way, we'll update this document and the "Last updated" date above.

## Contact

Questions about this policy or a data request: **[insert contact email before publishing]**

---
*Internal note: this is a first draft, accurate as of the code at commit time. Before submitting to App Store Connect: (1) fill in the real contact email, (2) host this at a public URL (App Store Connect requires a live privacy policy link), (3) re-check it against the code if data collection changes (e.g., if Apple/Google Sign-In, push notifications, or analytics get added).*

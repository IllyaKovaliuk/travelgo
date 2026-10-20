# Nomad Privacy Policy

**Last updated:** October 20, 2026

This policy describes what Nomad ("the app", "we") collects, why, who else receives it, and how you control it. It is written to match what the app actually does.

## What we collect

**Account information.** When you create an account we collect your email address and a username and display name you choose. Sign-in is handled by our backend provider, Supabase; we never see or store your password. If you sign in with Google or Apple, that provider shares your name and email with us (Apple may give you a private relay address instead of your real email) for that purpose only.

**Location data.** Location is core to what Nomad does:
- **While recording a route**, we collect a live stream of GPS coordinates (latitude, longitude, altitude) to compute distance, elevation gain and the path you travelled. Recording keeps working while the phone is locked or the app is in the background, and only while a recording is active. The recorded path is stored as part of the route you choose to publish.
- **While navigating a route or using the map**, your live position is read to show it on the map and compute progress and hazard proximity. This is used on your device and is not stored.
- **When you report a trail hazard**, the report is stored with the coordinates where you are. To confirm or dispute someone else's hazard report, your device's position is checked against the hazard (within about 300 m) on our server; that position is used for the check and not kept.
- **If you use SOS**, your last known position is placed in the message prepared for your emergency contacts.
- **Passive visit detection is optional and off by default.** If you enable it in Settings, the app asks for "Always" location access and uses iOS's Visits API to log places you have stopped at to your private Journal. You can turn it off at any time.
- The recorded path of a route you publish is visible to whoever can see that route (public, followers-only or private, per your choice).

**Photos.** Photos you choose or take (route covers, route photos, hazard photos, your avatar) are uploaded and stored so they can be shown to you and, depending on the visibility you set, to other users. Camera access is requested only when you photograph a hazard.

**Hazard reports.** A hazard report (type, optional photo, location, time) and other users' confirmations or dismissals of it are visible to other signed-in users near that location. Reports expire automatically after 14 days.

**Emergency contacts.** If you add emergency contacts we store the name, phone number and/or email you enter for each. This is other people's contact information provided by you. It is used only to pre-fill the message SOS opens in your own Messages app, is visible only to your account, and we never contact those people ourselves.

**Content you create.** Routes, segments, requirements, comments, likes, saves and follows are stored to power those features.

**NomadPoints and vouchers.** We keep a ledger of the points you earn (for example for publishing routes or hazard reports) and spend, and the partner vouchers you redeem, so your balance and vouchers are accurate.

**Blocking and reports.** If you block a user, we store that choice so their content stays hidden from you. They are not notified. If you report content, we store the report to review it.

**Usage analytics.** We record a small set of in-app events tied to your account (for example that you signed up, published a route or triggered SOS) to understand how the app is used and to fix problems. These are event names and timestamps, not content. They are not shared or sold.

**Purchases.** Subscriptions (Nomad Pro) are processed entirely by Apple through StoreKit. We learn whether you have an active subscription; we never receive your payment details.

**Device storage.** Routes you open are cached on your device, and you may download offline map regions. This stays on your device.

## Who else receives data

We don't run ads or use third-party advertising or tracking SDKs, and we don't sell your data. The services below process data only to provide the features named here:

- **Supabase** (database, authentication, file storage), hosted in the EU. Processes account data, routes, photos, hazard reports, points and the other data described above.
- **Mapbox** provides the maps. To draw maps and download offline regions the app sends map requests that include the area being viewed, and Mapbox may receive limited device and usage telemetry under its own privacy policy.
- **Open-Meteo** (weather forecasts). The Meteo feature sends a handful of coordinates along the route you are viewing and no account information.
- **RainViewer** (weather radar). The Meteo feature downloads radar map tiles for the area you are viewing; no account information is sent.
- **Apple and Google**, if you choose Sign in with Apple or Google, and Apple for subscriptions.

## What we don't do

- We don't collect background location except during an active recording or, if you turned it on, Passive visit detection.
- SOS does not dispatch any emergency service or notify anyone automatically. It opens a pre-filled message in your own Messages app that you choose to send.

## Retention and your controls

- **Route visibility**: public, followers-only or private, chosen per route.
- **Block users**: from their profile or a comment's menu; manage the list in Settings → Blocked users.
- **Passive visit detection**: toggle in Settings at any time.
- **Emergency contacts**: add or remove at any time in Settings.
- **Location and camera permissions**: controlled in iOS Settings → Nomad. Denying location disables recording, live navigation and SOS position sharing; the rest of the app still works.
- **Reporting content**: report a route, photo or comment; content with enough reports is hidden pending review and moderators can remove it.
- **Account deletion**: Settings → Delete account. This permanently removes your profile, routes, comments, likes, saves, follows, emergency contacts, points, vouchers, referrals, badges, hazard reports and block list, and deletes the files you uploaded (covers, route photos, hazard photos, avatar). It takes effect immediately and cannot be undone. Anonymous backups at our provider may persist for a short period before being overwritten.

## Children

Nomad is not directed at children under 13 and we don't knowingly collect data from them.

## Changes to this policy

If what we collect changes in a material way, we will update this page and the "Last updated" date.

## Contact

Questions about this policy or a data request: **illyakovaliuk@gmail.com**

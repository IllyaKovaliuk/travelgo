# App Store submission assets

Drafts, ready for App Store Connect once that step is unblocked. Nothing here has been uploaded anywhere — these are local files only.

## screenshots/
Captured from the iPhone 17 Pro simulator at the app's actual current state (real backend data where shown). These are 1206×2622px — App Store Connect will want them resized/cropped to the exact required device sizes (6.9" and 6.5" display classes) before upload; treat these as source material, not final uploads.

1. `01-onboarding-welcome.png` — first screen, brand mark + tagline
2. `02-home-feed.png` — live feed pulling real routes from Supabase
3. `03-route-detail.png` — full route page (map, stats, requirements, gear)
4. `04-search-results.png` — filtered search results
5. `05-paywall.png` — Pro upsell (cropped to the hero/feature-list; the live price cards only render when StoreKit is active, which needs an Xcode-launched build, not this simulator screenshot pipeline)

## Icon
The app icon lives in the actual asset catalog, not here: `NomadTerminal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` — a 1024×1024, no-alpha PNG (Apple's requirement) generated to match the in-app `CompassMark` brand element exactly (same needle geometry, same Pine/accent/milk colors).

## Privacy policy
`../backend/PRIVACY_POLICY.md` — drafted against what the app actually collects. Needs a real contact email filled in and a public hosting URL before submission (App Store Connect requires a live link, not a document upload).

## What's still needed before actual submission
- App Store Connect account access + the two IAP product IDs created there (see `nomadterminal-ios-build-progress` memory)
- App description / keywords / promotional text copy
- Final-size screenshot exports per required device class
- Support URL
- Age rating questionnaire

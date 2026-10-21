import Foundation

/// Real, published, publicly-reachable documents — Apple requires both
/// linked directly from any paywall offering a subscription (App Store
/// Review Guideline 3.1.2), and Settings is the obvious second place
/// someone looks for them. Source content lives in
/// `backend/PRIVACY_POLICY.md`/`TERMS_OF_SERVICE.md` (+ .uk.md; kept in sync by
/// hand); these are the hosted pages built from that content.
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://nomad-legal.vercel.app/privacy/")!
    static let termsOfService = URL(string: "https://nomad-legal.vercel.app/terms/")!
}

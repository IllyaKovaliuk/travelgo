import SwiftUI
import Supabase
import AuthenticationServices
import CryptoKit

/// 12 · Auth — sign in. Email/password and Google are real and live; Apple
/// is real code (`appleButton`/`handleAppleSignIn`) but currently hidden
/// behind `appleSignInEnabled` — confirmed via a real Xcode signing error
/// that a free "Personal Team" Apple ID can't use the Sign In with Apple
/// capability at all, not something worth guessing around.
///
/// No "skip for now" here anymore — registration is mandatory for every
/// user, so this screen is a wall, not a suggestion. `onDone` is only ever
/// called after a real Supabase session actually exists AND that account
/// has a real display name — a social sign-in that doesn't hand one over
/// (Apple only shares `fullName` on someone's very first authorization;
/// Google usually does via its `full_name` claim, but isn't guaranteed to)
/// routes through `nameCaptureView` first rather than letting a nameless
/// account through, matching the same "no exceptions" policy the DB itself
/// now enforces (`require_real_author_name_trigger`).
///
/// It also stamps `authSessionStartedAt` in UserDefaults, which `RootView`
/// reads to force a re-login after the session's own max age — real
/// accounts still shouldn't stay signed in forever on a shared or lost
/// device.
///
/// Two things this code can't finish alone — real external accounts, not
/// something fixable from inside the repo:
///   1. Apple: needs a real, paid Apple Developer Program membership —
///      confirmed (not assumed) that the free Personal Team tier can't
///      use Sign In with Apple at all. Once paid, re-add
///      `com.apple.developer.applesignin` to `NomadTerminal.entitlements`,
///      flip `appleSignInEnabled` to `true`, and add the bundle ID as a
///      valid Client ID in Supabase's Apple provider (Auth → Providers →
///      Apple) — no private key needed for this native, ID-token-only flow.
///   2. Google: needs a real OAuth 2.0 Client ID + Secret from Google
///      Cloud Console (Web application type — Supabase's own backend
///      exchanges the code, not this app directly), pasted into Supabase's
///      Google provider (Auth → Providers → Google), plus
///      `io.nomadterminal.app://auth-callback` added to Auth → URL
///      Configuration → Redirect URLs.
struct AuthView: View {
    var onDone: () -> Void

    /// Off for now — this project is signed with a free "Personal Team"
    /// Apple ID, and Apple flat-out doesn't allow the Sign In with Apple
    /// capability for those (confirmed via a real Xcode signing error,
    /// not a guess). The real implementation below (`appleButton`,
    /// `handleAppleSignIn`, the whole nonce flow) is untouched and ready —
    /// flip this back to `true` and re-add `com.apple.developer.
    /// applesignin` to `NomadTerminal.entitlements` the moment the $99/yr
    /// Apple Developer Program is paid for. Nothing else needs to change.
    private static let appleSignInEnabled = false

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var name = ""
    /// Optional, Telegram-style — free to skip entirely (an auto-generated
    /// `nomad_<id>` username is always there as a fallback either way; see
    /// `handle_new_user()`). If typed, it has to be globally unique — the
    /// same `profiles.username` column and `UNIQUE` constraint an existing
    /// account can already change later in Edit Profile, just offered here
    /// too so someone doesn't have to hunt for it after signing up.
    @State private var tag = ""
    /// Optional — a real code (see `RouteRepository.redeemReferralCode`),
    /// never required to sign up. Left blank for anyone who doesn't have
    /// one.
    @State private var referralCode = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var confirmEmailSent = false

    /// Raw (unhashed) nonce for the current Apple request — generated
    /// fresh per attempt, SHA256-hashed into `request.nonce`, then the raw
    /// value is handed to Supabase so GoTrue can hash it the same way and
    /// compare against the claim inside Apple's identity token. Standard
    /// Sign in with Apple + OIDC replay-protection pattern.
    @State private var currentAppleNonce: String?
    /// Set once a social sign-in succeeds but the provider gave no usable
    /// name (a returning Apple user who shared it before, or Google
    /// metadata missing one) — blocks `onDone()` until a real name exists,
    /// same as `require_real_author_name_trigger` would block anyway the
    /// moment this account tried to publish a route.
    @State private var needsNameCapture = false
    @State private var pendingDisplayName = ""
    @State private var isFinalizingAccount = false

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            if needsNameCapture {
                nameCaptureView
            } else if confirmEmailSent {
                confirmEmailView
            } else {
                formView
            }
        }
        .foregroundStyle(NTColor.milk)
    }

    private var confirmEmailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompassMark(size: 52)

            Text("Check your\ninbox.")
                .font(NTFont.heading(34, .extraBold))
                .foregroundStyle(NTColor.milk)
                .padding(.top, 22)

            Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
                .font(NTFont.body(15, .light))
                .foregroundStyle(NTColor.milk(0.62))
                .padding(.top, 10)

            Spacer()

            Button {
                withAnimation { confirmEmailSent = false; mode = .signIn; password = "" }
            } label: {
                Text("Back to sign in")
                    .font(NTFont.body(16, .semibold))
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(NTColor.accent, in: Capsule())
                    .shadow(color: NTColor.accent.opacity(0.5), radius: 14, y: 8)
            }
            .buttonStyle(.plain)

        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var formView: some View {
            VStack(alignment: .leading, spacing: 0) {
                CompassMark(size: 52)

                Text(mode == .signIn ? "Get your\nbearings." : "Join the\nnomads.")
                    .font(NTFont.heading(34, .extraBold))
                    .foregroundStyle(NTColor.milk)
                    .padding(.top, 22)

                Text("Sign in to sync routes, badges and offline maps across every device you carry.")
                    .font(NTFont.body(15, .light))
                    .foregroundStyle(NTColor.milk(0.62))
                    .padding(.top, 10)

                VStack(spacing: 12) {
                    if Self.appleSignInEnabled {
                        appleButton
                    }
                    socialButton(icon: "globe", title: "Continue with Google", filled: false) {
                        Task { await signInWithGoogle() }
                    }
                }
                .padding(.top, 26)

                HStack(spacing: 14) {
                    Rectangle().fill(NTColor.milk(0.14)).frame(height: 1)
                    Text("OR EMAIL").font(NTFont.mono(10, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.4))
                    Rectangle().fill(NTColor.milk(0.14)).frame(height: 1)
                }
                .padding(.vertical, 22)

                VStack(spacing: 10) {
                    if mode == .signUp {
                        textField(icon: "person", placeholder: "Your name", text: $name, isSecure: false)
                        tagField
                        textField(icon: "gift", placeholder: "Referral code (optional)", text: $referralCode, isSecure: false)
                            .textInputAutocapitalization(.characters)
                    }
                    textField(icon: "envelope", placeholder: "you@nomadterminal.io", text: $email, isSecure: false)
                    textField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(Color(hex: 0xE58272))
                        .padding(.top, 10)
                }

                Spacer()

                Button(action: submit) {
                    HStack {
                        if isBusy { ProgressView().tint(Color(hex: 0x231007)) }
                        else { Text(mode == .signIn ? "Sign in" : "Create account").font(NTFont.body(16, .semibold)) }
                    }
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(NTColor.accent, in: Capsule())
                    .shadow(color: NTColor.accent.opacity(0.5), radius: 14, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !canSubmit)
                .opacity(canSubmit ? 1 : 0.6)

                // Real, required link, not boilerplate — this is the one
                // place someone agrees to these before an account even
                // exists. Only shown creating an account, not signing
                // back into one that already agreed.
                if mode == .signUp {
                    // One flowing `Text` with Markdown link syntax, not an
                    // `HStack` of separate Text/Link pieces — an HStack's
                    // children don't reflow onto a second line on a narrow
                    // screen, they just overflow; a single Text wraps
                    // normally while keeping the two links real and
                    // tappable inline.
                    // The URLs are plain literal text here on purpose, not
                    // `\(LegalLinks....)` interpolation — a String
                    // interpolation inside a LocalizedStringKey compiles
                    // to a `%@` format placeholder at the actual runtime
                    // lookup key (regardless of what Xcode's own
                    // extraction tool shows), not the resolved URL text,
                    // which would silently break this catalog entry. These
                    // must match `LegalLinks` exactly.
                    Text("By continuing you agree to our [Terms](https://claude.ai/artifact/NNr9ARH5XQAf7CD3AnDd2z) and [Privacy Policy](https://claude.ai/artifact/KAsoSUfBRMAPHnxdy2oNAd).")
                        .font(NTFont.body(11, .medium))
                        .foregroundStyle(NTColor.milk(0.5))
                        .tint(NTColor.milk(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }

                Button {
                    withAnimation { mode = mode == .signIn ? .signUp : .signIn }
                } label: {
                    HStack(spacing: 4) {
                        Text(mode == .signIn ? "New here?" : "Already have an account?")
                            .foregroundStyle(NTColor.milk(0.55))
                        Text(mode == .signIn ? "Create an account" : "Sign in")
                            .foregroundStyle(NTColor.milk)
                            .fontWeight(.semibold)
                    }
                    .font(NTFont.body(14, .light))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)

                // Real, required, reachable regardless of which mode this
                // screen is in — unlike the agreement sentence above
                // (sign-up only, since "by continuing you agree" only
                // makes sense there), Apple's own review guideline
                // (5.1.1/3.1.2) means these have to be findable the moment
                // someone lands on this screen, including the very first
                // open where `mode` defaults to `.signIn`. This is the
                // last mandatory screen before an account exists — there's
                // no "onboarding slide after this" to put it on instead.
                HStack(spacing: 14) {
                    Link(destination: LegalLinks.termsOfService) { Text("Terms of Service") }
                    Text("·").foregroundStyle(NTColor.milk(0.3))
                    Link(destination: LegalLinks.privacyPolicy) { Text("Privacy Policy") }
                }
                .font(NTFont.mono(10, .medium)).tracking(0.2)
                .foregroundStyle(NTColor.milk(0.4))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 20)
    }

    private func socialButton(icon: String, title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView().tint(filled ? Color(hex: 0x231007) : NTColor.milk)
                } else {
                    Image(systemName: icon).font(.system(size: 15))
                    Text(title).font(NTFont.body(15, .semibold))
                }
            }
            .foregroundStyle(filled ? NTColor.ink : NTColor.milk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            // milkSurface (fixed) when filled — paired with the also-fixed
            // `ink` text above; the reactive `milk` would go dark-on-dark
            // in Milk theme.
            .background(filled ? NTColor.milkSurface : .clear, in: Capsule())
            .overlay(Capsule().stroke(NTColor.milk(0.28), lineWidth: filled ? 0 : 1.4))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    /// Apple requires its own button view for real (Human Interface
    /// Guidelines) — can't be hand-rolled with `socialButton` the way
    /// Google's plain "open a web page" flow can. Shaped to match this
    /// screen's capsule buttons via `.cornerRadius`, which the official
    /// button respects.
    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonceString()
            currentAppleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            Task { await handleAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 54)
        .cornerRadius(27)
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
    }

    /// Telegram-style: an "@" prefix that's always visible (not typed),
    /// free-form otherwise but optional — no error shown for an empty
    /// field, only for one that's non-empty and badly formed.
    private var tagField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("@").font(NTFont.body(14.5, .medium)).foregroundStyle(NTColor.milk(0.5))
                TextField("", text: $tag, prompt: Text("tag (optional)").foregroundStyle(NTColor.milk(0.35)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(NTFont.body(14.5, .medium))
                    .foregroundStyle(NTColor.milk)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))

            if !tag.isEmpty && !isTagValid {
                Text("Letters, numbers and underscores only — 3 to 20 characters.")
                    .font(NTFont.body(11.5, .medium))
                    .foregroundStyle(Color(hex: 0xE58272))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var isTagValid: Bool {
        tag.range(of: "^[a-zA-Z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    private func textField(icon: String, placeholder: LocalizedStringKey, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(NTColor.milk(0.5))
            Group {
                if isSecure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(NTColor.milk(0.35)))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(NTColor.milk(0.35)))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
            }
            .font(NTFont.body(14.5, .medium))
            .foregroundStyle(NTColor.milk)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
    }

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 6 else { return false }
        if mode == .signUp {
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if !tag.isEmpty && !isTagValid { return false }
        }
        return true
    }

    private func submit() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                if mode == .signIn {
                    try await supabase.auth.signIn(email: email, password: password)
                    UserDefaults.standard.set(Date(), forKey: "authSessionStartedAt")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onDone()
                } else {
                    let trimmedName = name.trimmingCharacters(in: .whitespaces)
                    var metadata: [String: AnyJSON] = ["display_name": .string(trimmedName)]
                    let trimmedTag = tag.trimmingCharacters(in: .whitespaces)
                    if !trimmedTag.isEmpty { metadata["username"] = .string(trimmedTag.lowercased()) }
                    let response = try await supabase.auth.signUp(
                        email: email, password: password,
                        data: metadata
                    )
                    if response.session != nil {
                        // Autoconfirm is on for this project — signing up
                        // really did log them in immediately.
                        UserDefaults.standard.set(Date(), forKey: "authSessionStartedAt")
                        RouteRepository.shared.logEvent("signup_completed")
                        let trimmedReferral = referralCode.trimmingCharacters(in: .whitespaces)
                        if !trimmedReferral.isEmpty {
                            // Best-effort — a wrong/expired code should
                            // never block someone from actually finishing
                            // sign-up, so failures here are silent.
                            try? await RouteRepository.shared.redeemReferralCode(trimmedReferral)
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onDone()
                    } else {
                        // No session back means Supabase is holding this
                        // account pending email confirmation. Silently
                        // calling onDone() here (the old behavior) closed
                        // the screen while the person was still logged out
                        // — indistinguishable from "nothing happened."
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { confirmEmailSent = true }
                    }
                }
            } catch {
                errorMessage = friendlyMessage(error)
            }
            isBusy = false
        }
    }

    // MARK: - Apple

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            // ASAuthorizationError.canceled fires when someone just backs
            // out of the system sheet — not a real error worth surfacing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple sign in failed — try again."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentAppleNonce else {
                errorMessage = "Apple sign in failed — try again."
                return
            }
            isBusy = true
            do {
                try await supabase.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                // Only ever present on this exact, first-ever authorization
                // — Apple won't hand it over again on a later sign-in with
                // the same Apple ID, so this is the one chance to capture it.
                let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                await finishSocialSignIn(candidateName: fullName.isEmpty ? nil : fullName)
            } catch {
                errorMessage = friendlyMessage(error)
            }
            isBusy = false
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Google

    private func signInWithGoogle() async {
        errorMessage = nil
        guard let redirectURL = URL(string: "io.nomadterminal.app://auth-callback") else { return }
        isBusy = true
        do {
            let session = try await supabase.auth.signInWithOAuth(provider: .google, redirectTo: redirectURL)
            // GoTrue normalizes Google's own profile claims into
            // user_metadata — "full_name" and "name" both show up
            // depending on the exact Google account/consent, so check both
            // rather than assuming one key.
            let metadata = session.user.userMetadata
            let candidateName = (metadata["full_name"]?.stringValue ?? metadata["name"]?.stringValue)?
                .trimmingCharacters(in: .whitespaces)
            await finishSocialSignIn(candidateName: (candidateName?.isEmpty ?? true) ? nil : candidateName)
        } catch {
            // A user just closing the web sheet without finishing throws
            // too (ASWebAuthenticationSessionError.canceledLogin) — not a
            // real error worth a red banner.
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                errorMessage = friendlyMessage(error)
            }
        }
        isBusy = false
    }

    // MARK: - Shared post-social-sign-in

    /// Real session exists at this point either way — the only open
    /// question is whether the account already has (or was just given) a
    /// real name. If not, `onDone()` waits behind `nameCaptureView` rather
    /// than letting a nameless account through, same "no exceptions" the
    /// database itself already enforces for publishing a route.
    private func finishSocialSignIn(candidateName: String?) async {
        UserDefaults.standard.set(Date(), forKey: "authSessionStartedAt")
        let existingName = try? await RouteRepository.shared.fetchMyProfile().displayName
        let hasRealName = !(existingName ?? "").trimmingCharacters(in: .whitespaces).isEmpty

        if !hasRealName, let candidateName, !candidateName.isEmpty {
            try? await RouteRepository.shared.updateDisplayName(candidateName)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        } else if !hasRealName {
            pendingDisplayName = ""
            withAnimation { needsNameCapture = true }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        }
    }

    private var nameCaptureView: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompassMark(size: 52)

            Text("One last\nthing.")
                .font(NTFont.heading(34, .extraBold))
                .foregroundStyle(NTColor.milk)
                .padding(.top, 22)

            Text("\(mode == .signIn ? "Apple" : "Your provider") didn't share a name with us this time — what should we call you?")
                .font(NTFont.body(15, .light))
                .foregroundStyle(NTColor.milk(0.62))
                .padding(.top, 10)

            textField(icon: "person", placeholder: "Your name", text: $pendingDisplayName, isSecure: false)
                .padding(.top, 26)

            Spacer()

            Button {
                let trimmed = pendingDisplayName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                isFinalizingAccount = true
                Task {
                    try? await RouteRepository.shared.updateDisplayName(trimmed)
                    isFinalizingAccount = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onDone()
                }
            } label: {
                HStack {
                    if isFinalizingAccount { ProgressView().tint(Color(hex: 0x231007)) }
                    else { Text("Continue").font(NTFont.body(16, .semibold)) }
                }
                .foregroundStyle(Color(hex: 0x231007))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(NTColor.accent, in: Capsule())
                .shadow(color: NTColor.accent.opacity(0.5), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(isFinalizingAccount || pendingDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(pendingDisplayName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func friendlyMessage(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("email_not_confirmed") || text.contains("Email not confirmed") {
            return "Confirm your email first — check the link we sent you, then sign in."
        }
        if text.contains("Invalid login") { return "Wrong email or password." }
        if text.contains("profiles_username_key") { return "That tag's already taken — try a different one (or leave it blank)." }
        if text.contains("already registered") || text.contains("already exists") { return "That email already has an account — try signing in." }
        if text.contains("rate_limit") { return "Too many attempts — wait a minute and try again." }
        if text.contains("email_address_invalid") { return "That email address looks invalid." }
        if text.contains("weak_password") || text.contains("Password") { return "Password needs to be at least 6 characters." }
        return "Something went wrong. Check your connection and try again."
    }
}

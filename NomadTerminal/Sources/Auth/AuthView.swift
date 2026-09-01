import SwiftUI
import Supabase

/// 12 · Auth — sign in. Email is real (Supabase email/password); Apple
/// and Google are visual placeholders until Sign in with Apple's
/// entitlement and a Google OAuth client are set up.
struct AuthView: View {
    var onDone: () -> Void

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()
            OrganicBlob((0.54, 0.46, 0.48, 0.52), (0.5, 0.54, 0.46, 0.5))
                .fill(NTColor.pineRaised)
                .frame(width: 460, height: 400)
                .position(x: 80, y: -110)
                .ignoresSafeArea()

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
                    socialButton(icon: "apple.logo", title: "Continue with Apple", filled: true)
                    socialButton(icon: "globe", title: "Continue with Google", filled: false)
                }
                .padding(.top, 26)

                HStack(spacing: 14) {
                    Rectangle().fill(NTColor.milk(0.14)).frame(height: 1)
                    Text("OR EMAIL").font(NTFont.mono(10, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.4))
                    Rectangle().fill(NTColor.milk(0.14)).frame(height: 1)
                }
                .padding(.vertical, 22)

                VStack(spacing: 10) {
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
                .disabled(isBusy || email.isEmpty || password.count < 6)
                .opacity((email.isEmpty || password.count < 6) ? 0.6 : 1)

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

                Button("Skip for now", action: onDone)
                    .font(NTFont.body(13, .medium))
                    .foregroundStyle(NTColor.milk(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .foregroundStyle(NTColor.milk)
    }

    private func socialButton(icon: String, title: String, filled: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(NTFont.body(15, .semibold))
            }
            .foregroundStyle(filled ? NTColor.ink : NTColor.milk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(filled ? NTColor.milk : .clear, in: Capsule())
            .overlay(Capsule().stroke(NTColor.milk(0.28), lineWidth: filled ? 0 : 1.4))
        }
        .buttonStyle(.plain)
    }

    private func textField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
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
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
    }

    private func submit() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                if mode == .signIn {
                    try await supabase.auth.signIn(email: email, password: password)
                } else {
                    try await supabase.auth.signUp(email: email, password: password)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDone()
            } catch {
                errorMessage = friendlyMessage(error)
            }
            isBusy = false
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("Invalid login") { return "Wrong email or password." }
        if text.contains("already registered") || text.contains("already exists") { return "That email already has an account — try signing in." }
        if text.contains("rate_limit") { return "Too many attempts — wait a minute and try again." }
        if text.contains("email_address_invalid") { return "That email address looks invalid." }
        if text.contains("weak_password") || text.contains("Password") { return "Password needs to be at least 6 characters." }
        return "Something went wrong. Check your connection and try again."
    }
}

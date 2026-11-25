import SwiftUI

/// What someone sees after tapping a crew invite: the crew's name, cover and
/// size (`preview_crew_by_code`), then one tap to join (`join_crew_by_code`).
/// Works the same for an invite opened by a signed-in user and for one saved
/// from before sign-up — `RootTabView` only mounts this once there's a session.
struct JoinCrewView: View {
    let code: String
    /// `true` when the person ended up in the crew (joined now or already was).
    var onClose: (Bool) -> Void

    @State private var preview: CrewInvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button { onClose(false) } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(NTColor.milk(0.1)))
                            .overlay(Circle().stroke(NTColor.milk(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView().tint(NTColor.milk)
                } else if let preview {
                    VStack(spacing: 16) {
                        RouteCoverImage(url: preview.coverImageUrl, tint: NTColor.pineRaised)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        Text("You're invited to join")
                            .font(NTFont.mono(11, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.6))
                        Text(preview.name)
                            .font(NTFont.heading(30, .extraBold)).multilineTextAlignment(.center)
                        Text("\(preview.memberCount) members")
                            .font(NTFont.body(14, .light)).foregroundStyle(NTColor.milk(0.6))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "link.badge.plus").font(.system(size: 34)).foregroundStyle(NTColor.milk(0.3))
                        Text("This invite isn't valid").font(NTFont.heading(22, .bold))
                        Text("It may have expired or been used up. Ask your friend for a new link.")
                            .font(NTFont.body(14, .light)).foregroundStyle(NTColor.milk(0.6)).multilineTextAlignment(.center)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                if let preview {
                    if preview.alreadyMember {
                        NTPrimaryButton(title: "You're already in this crew") { onClose(true) }
                    } else {
                        NTAccentButton(title: isJoining ? "Joining…" : "Join crew") { join() }
                            .disabled(isJoining)
                    }
                    NTGhostButton(title: "Not now") { onClose(false) }
                } else if !isLoading {
                    NTPrimaryButton(title: "Close") { onClose(false) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
    }

    private func load() async {
        preview = try? await CrewRepository.shared.previewInvite(code: code)
        isLoading = false
    }

    private func join() {
        isJoining = true
        errorMessage = nil
        Task {
            do {
                try await CrewRepository.shared.joinCrew(code: code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onClose(true)
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }
}

/// "Join with a code": paste the invite link (or just its code).
struct JoinCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void

    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste the invite link or code your friend sent you.")
                    .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.6))
                TextField("Invite link or code", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(NTFont.body(16, .medium))
                    .padding(.horizontal, 16).frame(height: 54)
                    .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                if invalid {
                    Text("That doesn't look like a Nomad invite.")
                        .font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                }
                NTAccentButton(title: "Continue") {
                    if let code = CrewLinks.inviteCode(fromText: text) {
                        dismiss()
                        onCode(code)
                    } else {
                        invalid = true
                    }
                }
                .opacity(text.isEmpty ? 0.5 : 1)
                .disabled(text.isEmpty)
                Spacer()
            }
            .padding(.horizontal, 22).padding(.top, 8)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Join with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }
}

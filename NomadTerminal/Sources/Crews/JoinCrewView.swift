import SwiftUI

/// What someone sees after tapping a crew invite: the crew's name, cover and
/// size (`preview_crew_by_code`), then one tap to join (`join_crew_by_code`).
/// Works the same for an invite opened by a signed-in user and for one saved
/// from before sign-up — `RootTabView` only mounts this once there's a session.
struct JoinCrewView: View {
    let code: String
    /// 'link' or 'code' — only for the analytics events.
    var source = "link"
    /// `true` when the person ended up in the crew (joined now or already was).
    var onClose: (Bool) -> Void

    @State private var preview: CrewInvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()
            ContourLines(seed: 5)
                .stroke(NTColor.sage.opacity(0.14), lineWidth: 1)
                .frame(height: 380).frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    CircleIconButton(icon: "xmark", label: "Close", filled: true) { onClose(false) }
                }

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity)
                } else if let preview {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            CompassMark(size: 30)
                            Text("You're invited to join").font(NTFont.body(15)).foregroundStyle(NTColor.milk(0.8))
                        }
                        Text(preview.name)
                            .font(NTFont.heading(48, .extraBold)).tracking(-1.6)
                            .lineLimit(3).minimumScaleFactor(0.6)
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(preview.memberCount)").font(NTFont.heading(26, .extraBold))
                                Text("MEMBERS").font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14).crewCard(radius: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: "lock").font(.system(size: 20, weight: .semibold)).frame(height: 31)
                                Text("PRIVATE CREW").font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14).crewCard(radius: 16)
                        }
                        Text("Joining shows you the crew's trips, routes and member names.")
                            .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.6))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "link.badge.plus").font(.system(size: 34)).foregroundStyle(NTColor.milk(0.3))
                        Text("This invite isn't valid").font(NTFont.heading(22, .bold))
                        Text("It may have expired or been used up. Ask your friend for a new link.")
                            .font(NTFont.body(14, .light)).foregroundStyle(NTColor.milk(0.6)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let errorMessage {
                    Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                }

                if let preview {
                    if preview.alreadyMember {
                        NTPrimaryButton(title: "Open crew") { onClose(true) }
                    } else {
                        NTAccentButton(title: isJoining ? "Joining…" : "Join crew") { join() }
                            .disabled(isJoining)
                    }
                    NTGhostButton(title: "Not now") { onClose(false) }
                        .frame(maxWidth: .infinity)
                    Text("CODE \(code.prefix(16).uppercased()) · PRIVATE CREW")
                        .font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.4))
                        .frame(maxWidth: .infinity)
                } else if !isLoading {
                    NTPrimaryButton(title: "Close") { onClose(false) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
    }

    private func load() async {
        preview = try? await CrewRepository.shared.previewInvite(code: code)
        isLoading = false
        // Funnel step 2: the invite was actually opened (valid or not).
        RouteRepository.shared.logEvent("crew_invite_opened", metadata: [
            "source": source,
            "valid": preview == nil ? "false" : "true",
            "already_member": preview?.alreadyMember == true ? "true" : "false",
            "crew_id": preview?.crewId.uuidString ?? "",
        ])
    }

    private func join() {
        isJoining = true
        errorMessage = nil
        Task {
            do {
                let crewId = try await CrewRepository.shared.joinCrew(code: code)
                // Funnel step 3: a person actually joined.
                RouteRepository.shared.logEvent("crew_join", metadata: ["source": source, "crew_id": crewId.uuidString])
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
                    .crewCard(radius: 16)
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

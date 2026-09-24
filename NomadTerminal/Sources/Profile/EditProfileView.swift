import SwiftUI

/// Lets a signed-in user fix their own name/username/home — the gap this
/// closes: signup only asks for a display name once, and accounts created
/// before that field existed (or anyone who just wants to change it later)
/// otherwise have no way to correct what shows on their own Profile.
struct EditProfileView: View {
    let current: RouteRepository.MyProfile
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var username: String
    @State private var homeLocation: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(current: RouteRepository.MyProfile, onSaved: @escaping () -> Void) {
        self.current = current
        self.onSaved = onSaved
        _displayName = State(initialValue: current.displayName)
        _username = State(initialValue: current.username)
        _homeLocation = State(initialValue: current.homeLocation ?? "")
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                field(label: "NAME") {
                    TextField("", text: $displayName, prompt: Text("Your name").foregroundStyle(NTColor.milk(0.3)))
                }
                field(label: "USERNAME") {
                    HStack(spacing: 4) {
                        Text("@").foregroundStyle(NTColor.milk(0.5))
                        TextField("", text: $username, prompt: Text("username").foregroundStyle(NTColor.milk(0.3)))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                field(label: "HOME LOCATION (OPTIONAL)") {
                    TextField("", text: $homeLocation, prompt: Text("Almaty, KZ").foregroundStyle(NTColor.milk(0.3)))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(Color(hex: 0xE58272))
                }

                Spacer()

                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView().tint(Color(hex: 0x231007)) }
                        else { Text("Save").font(NTFont.body(16, .semibold)) }
                    }
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(NTColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(24)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await RouteRepository.shared.updateMyProfile(
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    username: username.trimmingCharacters(in: .whitespaces),
                    homeLocation: homeLocation.trimmingCharacters(in: .whitespaces)
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSaved()
                dismiss()
            } catch {
                let text = "\(error)"
                errorMessage = text.contains("profiles_username_key")
                    ? "That username's already taken — try a different one."
                    : error.localizedDescription
            }
            isSaving = false
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            content()
                .font(NTFont.body(15, .medium))
                .foregroundStyle(NTColor.milk)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
        }
    }
}

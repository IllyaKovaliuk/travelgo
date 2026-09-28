import SwiftUI

/// Real contacts backing the "Emergency contacts" Settings row and
/// SOSView's contacts row — both were previously either a dead stub or a
/// hardcoded fake name. A phone number and/or email, nothing more; no
/// automated dispatch is wired to these yet (see SOSView's own doc
/// comment) — this is the real, honest scope of what exists today:
/// people you'd want to know your last known position and route, who you
/// can reach yourself once SOS triggers.
struct EmergencyContactsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [RouteRepository.EmergencyContact] = []
    @State private var isLoading = true
    @State private var showAdd = false
    @State private var deletingId: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Who should know if you trigger SOS — you reach out to them yourself, nothing is sent automatically yet.")
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(NTColor.milk(0.55))

                    if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if contacts.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(contacts) { contact in
                                contactCard(contact)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Emergency contacts")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                AddEmergencyContactView()
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 26)).foregroundStyle(NTColor.milk(0.3))
            Text("No emergency contacts yet").font(NTFont.body(14.5, .semibold))
            Text("Add someone you'd want to know if you trigger SOS.")
                .font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func contactCard(_ contact: RouteRepository.EmergencyContact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials(contact.name)).font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.milk)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name).font(NTFont.body(14.5, .semibold))
                Text([contact.phone, contact.email].compactMap { $0 }.joined(separator: " · "))
                    .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer(minLength: 0)

            Button {
                delete(contact)
            } label: {
                if deletingId == contact.id.uuidString {
                    ProgressView().tint(NTColor.milk(0.5))
                } else {
                    Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(Color(hex: 0xE58272))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }

    private func load() async {
        contacts = (try? await RouteRepository.shared.fetchEmergencyContacts()) ?? []
        withAnimation { isLoading = false }
    }

    private func delete(_ contact: RouteRepository.EmergencyContact) {
        deletingId = contact.id.uuidString
        Task {
            try? await RouteRepository.shared.deleteEmergencyContact(id: contact.id.uuidString)
            contacts.removeAll { $0.id == contact.id }
            deletingId = nil
        }
    }
}

private struct AddEmergencyContactView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (!phone.trimmingCharacters(in: .whitespaces).isEmpty || !email.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                field(label: "NAME") {
                    TextField("", text: $name, prompt: Text("Giorgi K.").foregroundStyle(NTColor.milk(0.3)))
                        .textContentType(.name)
                }
                field(label: "PHONE") {
                    TextField("", text: $phone, prompt: Text("+995 555 123 456").foregroundStyle(NTColor.milk(0.3)))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                field(label: "EMAIL") {
                    TextField("", text: $email, prompt: Text("giorgi@example.com").foregroundStyle(NTColor.milk(0.3)))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Text("At least a phone number or an email.")
                    .font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.4))

                if let errorMessage {
                    Text(LocalizedStringKey(errorMessage)).font(NTFont.body(12.5, .medium)).foregroundStyle(Color(hex: 0xE58272))
                }

                Spacer()

                Button { save() } label: {
                    if isSaving {
                        ProgressView().tint(NTColor.pine).frame(maxWidth: .infinity).frame(height: 54)
                    } else {
                        Text("Save contact")
                            .font(NTFont.body(15, .semibold))
                            .foregroundStyle(NTColor.pine)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                }
                .buttonStyle(.plain)
                .background(NTColor.milk, in: Capsule())
                .disabled(!canSave || isSaving)
                .opacity(canSave ? 1 : 0.4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Add contact")
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

    private func field<Content: View>(label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
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

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await RouteRepository.shared.addEmergencyContact(
                    name: name.trimmingCharacters(in: .whitespaces),
                    phone: phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces)
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = "Couldn't save — check your connection and try again."
            }
            isSaving = false
        }
    }
}

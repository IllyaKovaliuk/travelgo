import SwiftUI
import PhotosUI

/// New crew: a name and an optional cover. `create_crew` makes the crew and
/// the owner's membership in one transaction.
struct CreateCrewView: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: (UUID) -> Void

    @State private var name = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var coverData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A crew is private — only people you invite can see it.")
                        .font(NTFont.body(13, .light))
                        .foregroundStyle(NTColor.milk(0.6))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME").font(NTFont.mono(10.5, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
                        TextField("Weekend Nomads", text: $name)
                            .font(NTFont.body(16, .medium))
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                            .onChange(of: name) { _, new in if new.count > 60 { name = String(new.prefix(60)) } }
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                                .fill(NTColor.milk(0.05))
                            if let preview {
                                Image(uiImage: preview).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.badge.plus").font(.system(size: 22))
                                    Text("Add a cover (optional)").font(NTFont.body(13, .medium))
                                }
                                .foregroundStyle(NTColor.milk(0.55))
                            }
                        }
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                    }

                    if let errorMessage {
                        Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                    }

                    NTAccentButton(title: isSaving ? "Creating…" : "Create crew") { create() }
                        .opacity(trimmed.isEmpty || isSaving ? 0.5 : 1)
                        .disabled(trimmed.isEmpty || isSaving)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("New crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadCover(item) }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }

    private func loadCover(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorMessage = String(localized: "Couldn't load that photo.")
            return
        }
        let small = image.resized(maxDimension: 1600)
        preview = small
        coverData = small.jpegData(compressionQuality: 0.8)
        errorMessage = nil
    }

    private func create() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                var coverURL: String?
                if let coverData { coverURL = try await RouteRepository.shared.uploadCoverImage(coverData) }
                let id = try await CrewRepository.shared.createCrew(name: trimmed, coverURL: coverURL)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onCreated(id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

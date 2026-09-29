import SwiftUI

/// Review/reinstate auto-hidden content — was a manual SQL job (see
/// `backend/supabase/migrations/20260901000002_moderation.sql`'s header
/// comment). Real `is_admin` role now (see
/// `20260929000003_admin_role.sql`) — this screen only shows in Settings
/// for an actual admin, and the RPCs behind it re-check `is_admin`
/// server-side too, so hiding the row is real UX, not the actual security
/// boundary. Used to be reachable by literally any signed-in user.
struct AdminModerationView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var hiddenRoutes: [RouteRepository.HiddenRoute] = []
    @State private var hiddenComments: [RouteRepository.HiddenComment] = []
    @State private var hiddenPhotos: [RouteRepository.HiddenPhoto] = []
    @State private var isLoading = true
    @State private var reinstatingId: String?
    @State private var deletingId: String?
    @State private var confirmDeleteAction: (() -> Void)?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    aboutCard

                    if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if hiddenRoutes.isEmpty && hiddenComments.isEmpty && hiddenPhotos.isEmpty {
                        emptyState
                    } else {
                        if !hiddenRoutes.isEmpty {
                            sectionLabel("HIDDEN ROUTES (\(hiddenRoutes.count))")
                            VStack(spacing: 12) { ForEach(hiddenRoutes) { routeCard($0) } }
                        }
                        if !hiddenComments.isEmpty {
                            sectionLabel("HIDDEN COMMENTS (\(hiddenComments.count))")
                            VStack(spacing: 12) { ForEach(hiddenComments) { commentCard($0) } }
                        }
                        if !hiddenPhotos.isEmpty {
                            sectionLabel("HIDDEN PHOTOS (\(hiddenPhotos.count))")
                            VStack(spacing: 12) { ForEach(hiddenPhotos) { photoCard($0) } }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(LocalizedStringKey(toast))
                        .font(NTFont.body(13, .semibold))
                        .foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(NTColor.milk, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .confirmationDialog(
                "Delete this permanently? This can't be undone.",
                isPresented: Binding(get: { confirmDeleteAction != nil }, set: { if !$0 { confirmDeleteAction = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    confirmDeleteAction?()
                    confirmDeleteAction = nil
                }
                Button("Cancel", role: .cancel) { confirmDeleteAction = nil }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await load() }
    }

    private func load() async {
        async let routes = (try? RouteRepository.shared.fetchHiddenRoutes()) ?? []
        async let comments = (try? RouteRepository.shared.fetchHiddenComments()) ?? []
        async let photos = (try? RouteRepository.shared.fetchHiddenPhotos()) ?? []
        hiddenRoutes = await routes
        hiddenComments = await comments
        hiddenPhotos = await photos
        isLoading = false
    }

    private var aboutCard: some View {
        Label("Content auto-hides once 3 different people report it. Reinstate anything that was flagged wrongly.", systemImage: "eye.slash")
            .font(NTFont.body(12.5, .medium))
            .foregroundStyle(NTColor.milk(0.6))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield").font(.system(size: 26)).foregroundStyle(NTColor.milk(0.3))
            Text("Nothing hidden right now").font(NTFont.body(14.5, .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
    }

    private func reasonsLine(_ reasons: [String]?, count: Int) -> String {
        let list = (reasons ?? []).joined(separator: ", ")
        return "\(count) report\(count == 1 ? "" : "s")" + (list.isEmpty ? "" : " · \(list)")
    }

    private func routeCard(_ route: RouteRepository.HiddenRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(route.title.replacingOccurrences(of: "\n", with: " "))
                    .font(NTFont.body(14.5, .semibold))
                Text("\(route.place) · by \(route.authorName)")
                    .font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.55))
                Text(reasonsLine(route.reasons, count: route.reportCount))
                    .font(NTFont.mono(10.5, .medium)).foregroundStyle(Color(hex: 0xE58272))
            }
            actionRow(
                id: route.id.uuidString,
                reinstate: {
                    try await RouteRepository.shared.reinstateRoute(id: route.id.uuidString)
                    hiddenRoutes.removeAll { $0.id == route.id }
                },
                delete: {
                    try await RouteRepository.shared.adminDeleteRoute(id: route.id.uuidString)
                    hiddenRoutes.removeAll { $0.id == route.id }
                }
            )
        }
        .padding(16)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func commentCard(_ comment: RouteRepository.HiddenComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\"\(comment.body)\"")
                    .font(NTFont.body(14, .medium))
                    .lineLimit(3)
                Text("by \(comment.authorName) on \(comment.routeTitle.replacingOccurrences(of: "\n", with: " "))")
                    .font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.55))
                Text(reasonsLine(comment.reasons, count: comment.reportCount))
                    .font(NTFont.mono(10.5, .medium)).foregroundStyle(Color(hex: 0xE58272))
            }
            actionRow(
                id: comment.id.uuidString,
                reinstate: {
                    try await RouteRepository.shared.reinstateComment(id: comment.id.uuidString)
                    hiddenComments.removeAll { $0.id == comment.id }
                },
                delete: {
                    try await RouteRepository.shared.adminDeleteComment(id: comment.id.uuidString)
                    hiddenComments.removeAll { $0.id == comment.id }
                }
            )
        }
        .padding(16)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func photoCard(_ photo: RouteRepository.HiddenPhoto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: URL(string: photo.imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(NTColor.milk(0.08))
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("by \(photo.uploaderName) on \(photo.routeTitle.replacingOccurrences(of: "\n", with: " "))")
                    .font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.55))
                Text(reasonsLine(photo.reasons, count: photo.reportCount))
                    .font(NTFont.mono(10.5, .medium)).foregroundStyle(Color(hex: 0xE58272))
            }
            actionRow(
                id: photo.id.uuidString,
                reinstate: {
                    try await RouteRepository.shared.reinstatePhoto(id: photo.id.uuidString)
                    hiddenPhotos.removeAll { $0.id == photo.id }
                },
                delete: {
                    try await RouteRepository.shared.adminDeletePhoto(id: photo.id.uuidString)
                    hiddenPhotos.removeAll { $0.id == photo.id }
                }
            )
        }
        .padding(16)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    /// Two real actions per hidden item now, not just reinstate — a
    /// permanent `delete` (`admin_delete_*`), confirmed first since it
    /// can't be undone, alongside the existing `reinstate`.
    private func actionRow(id: String, reinstate: @escaping () async throws -> Void, delete: @escaping () async throws -> Void) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    reinstatingId = id
                    do {
                        try await reinstate()
                        showToast("Reinstated")
                    } catch {
                        showToast("Couldn't reinstate — try again")
                    }
                    reinstatingId = nil
                }
            } label: {
                if reinstatingId == id {
                    ProgressView().tint(NTColor.pine)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Capsule().fill(NTColor.milk(0.5)))
                } else {
                    Text("Reinstate")
                        .font(NTFont.body(13, .semibold))
                        .foregroundStyle(NTColor.pine)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Capsule().fill(NTColor.sage))
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                confirmDeleteAction = {
                    deletingId = id
                    Task {
                        do {
                            try await delete()
                            showToast("Deleted")
                        } catch {
                            showToast("Couldn't delete — try again")
                        }
                        deletingId = nil
                    }
                }
            } label: {
                if deletingId == id {
                    ProgressView().tint(Color(hex: 0xE58272))
                        .frame(width: 62, height: 38)
                        .overlay(Capsule().stroke(Color(hex: 0xE58272).opacity(0.5), lineWidth: 1))
                } else {
                    Text("Delete")
                        .font(NTFont.body(13, .semibold))
                        .foregroundStyle(Color(hex: 0xE58272))
                        .frame(width: 62, height: 38)
                        .overlay(Capsule().stroke(Color(hex: 0xE58272).opacity(0.5), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
        }
        .disabled(reinstatingId != nil || deletingId != nil)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toast = nil }
        }
    }
}

#Preview {
    AdminModerationView()
}

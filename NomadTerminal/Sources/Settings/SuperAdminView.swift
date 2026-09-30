import SwiftUI

/// The super-admin control panel — search any real account, promote/
/// revoke admin (super-admin only), ban/unban (any admin), and drill into
/// a specific person's real routes/photos to hide or delete them directly
/// rather than only ever reacting to something that already collected 3
/// reports. Only shows in Settings for `profiles.is_super_admin` — the
/// RPCs behind every action here re-check the right role server-side too
/// (`is_super_admin` for the admin toggle, `is_admin` for everything
/// else), so this screen being hidden is real UX, not the actual
/// security boundary.
struct SuperAdminView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var users: [RouteRepository.AdminUser] = []
    @State private var isLoading = true
    @State private var openUser: RouteRepository.AdminUser?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if isLoading {
                            ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 40)
                        } else if users.isEmpty {
                            Text("No accounts match.").font(NTFont.body(13.5, .medium)).foregroundStyle(NTColor.milk(0.5))
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(users) { user in
                                    userRow(user).onTapGesture { openUser = user }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Admin panel")
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
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await search() }
        .onChange(of: query) { _, _ in Task { await search() } }
        .sheet(item: $openUser, onDismiss: { Task { await search() } }) { user in
            UserModerationDetailView(user: user, onToast: { showToast($0) })
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(NTColor.milk(0.5))
            TextField("", text: $query, prompt: Text("Search username or name").foregroundStyle(NTColor.milk(0.35)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(NTFont.body(14, .medium))
                .foregroundStyle(NTColor.milk)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func userRow(_ user: RouteRepository.AdminUser) -> some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials(user.displayName ?? user.username)).font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.milk)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName ?? user.username).font(NTFont.body(14, .semibold))
                Text("@\(user.username)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if user.isSuperAdmin {
                    badge("SUPER", NTColor.gold)
                } else if user.isAdmin {
                    badge("ADMIN", NTColor.sage)
                }
                if user.isBanned {
                    badge("BANNED", Color(hex: 0xE58272))
                }
            }
        }
        .padding(12)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func badge(_ text: LocalizedStringKey, _ color: Color) -> some View {
        Text(text).font(NTFont.mono(8, .semibold)).tracking(0.5).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }

    private func search() async {
        isLoading = true
        users = (try? await RouteRepository.shared.searchUsers(query.trimmingCharacters(in: .whitespaces))) ?? []
        withAnimation { isLoading = false }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// One person's real moderation surface — role toggle (super admin
/// only), ban toggle, and their real routes/photos with a direct hide or
/// permanent delete on each, no waiting on reports.
private struct UserModerationDetailView: View {
    let user: RouteRepository.AdminUser
    var onToast: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentUserIsSuperAdmin = false
    @State private var isAdmin: Bool
    @State private var isBanned: Bool
    @State private var isBusy = false
    @State private var routes: [RouteRepository.AdminUserRoute] = []
    @State private var photos: [RouteRepository.AdminUserPhoto] = []
    @State private var isLoadingContent = true

    init(user: RouteRepository.AdminUser, onToast: @escaping (String) -> Void) {
        self.user = user
        self.onToast = onToast
        _isAdmin = State(initialValue: user.isAdmin)
        _isBanned = State(initialValue: user.isBanned)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if currentUserIsSuperAdmin && !user.isSuperAdmin {
                        toggleRow(title: "Admin", isOn: Binding(
                            get: { isAdmin },
                            set: { newValue in
                                isAdmin = newValue
                                Task {
                                    do {
                                        try await RouteRepository.shared.setAdminRole(userId: user.id.uuidString, isAdmin: newValue)
                                        onToast(newValue ? "Made admin" : "Admin revoked")
                                    } catch {
                                        isAdmin = !newValue
                                        onToast("Couldn't change admin role")
                                    }
                                }
                            }
                        ))
                    }

                    if !user.isSuperAdmin {
                        toggleRow(title: "Banned", isOn: Binding(
                            get: { isBanned },
                            set: { newValue in
                                isBanned = newValue
                                Task {
                                    do {
                                        try await RouteRepository.shared.setUserBanned(userId: user.id.uuidString, banned: newValue)
                                        onToast(newValue ? "User banned" : "User unbanned")
                                    } catch {
                                        isBanned = !newValue
                                        onToast("Couldn't change ban status")
                                    }
                                }
                            }
                        ), tint: Color(hex: 0xE58272))
                    }

                    if isLoadingContent {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 20)
                    } else {
                        if !routes.isEmpty {
                            sectionLabel("ROUTES (\(routes.count))")
                            VStack(spacing: 10) { ForEach(routes) { routeRow($0) } }
                        }
                        if !photos.isEmpty {
                            sectionLabel("PHOTOS (\(photos.count))")
                            VStack(spacing: 10) { ForEach(photos) { photoRow($0) } }
                        }
                        if routes.isEmpty && photos.isEmpty {
                            Text("Nothing posted yet.").font(NTFont.body(13, .medium)).foregroundStyle(NTColor.milk(0.5))
                                .padding(.top, 10)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("@\(user.username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task {
            currentUserIsSuperAdmin = (try? await RouteRepository.shared.fetchMyProfile())?.isSuperAdmin ?? false
            async let r = (try? RouteRepository.shared.fetchUserRoutesForAdmin(userId: user.id.uuidString)) ?? []
            async let p = (try? RouteRepository.shared.fetchUserPhotos(userId: user.id.uuidString)) ?? []
            routes = await r
            photos = await p
            withAnimation { isLoadingContent = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.displayName ?? user.username).font(NTFont.heading(20, .bold))
            Text("Joined \(user.createdAt.prefix(10))").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
        }
    }

    private func toggleRow(title: LocalizedStringKey, isOn: Binding<Bool>, tint: Color = NTColor.sage) -> some View {
        HStack {
            Text(title).font(NTFont.body(14.5, .medium))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(tint)
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
    }

    private func routeRow(_ route: RouteRepository.AdminUserRoute) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(13, .semibold)).lineLimit(1)
                Text(route.status.uppercased()).font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
            if route.status != "hidden" {
                smallButton("Hide") {
                    try await RouteRepository.shared.adminHideRoute(id: route.id.uuidString)
                    routes.removeAll { $0.id == route.id }
                    onToast("Hidden")
                }
            }
            smallButton("Delete", destructive: true) {
                try await RouteRepository.shared.adminDeleteRoute(id: route.id.uuidString)
                routes.removeAll { $0.id == route.id }
                onToast("Deleted")
            }
        }
        .padding(12)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func photoRow(_ photo: RouteRepository.AdminUserPhoto) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: photo.imageUrl)) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { Rectangle().fill(NTColor.milk(0.08)) }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(photo.routeTitle.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(12.5, .medium)).lineLimit(1)
                if photo.hidden {
                    Text("HIDDEN").font(NTFont.mono(9, .medium)).foregroundStyle(Color(hex: 0xE58272))
                }
            }
            Spacer()
            if !photo.hidden {
                smallButton("Hide") {
                    try await RouteRepository.shared.adminHidePhoto(id: photo.id.uuidString)
                    photos = photos.map { $0.id == photo.id ? RouteRepository.AdminUserPhoto(id: $0.id, imageUrl: $0.imageUrl, routeId: $0.routeId, routeTitle: $0.routeTitle, hidden: true, createdAt: $0.createdAt) : $0 }
                    onToast("Hidden")
                }
            }
            smallButton("Delete", destructive: true) {
                try await RouteRepository.shared.adminDeletePhoto(id: photo.id.uuidString)
                photos.removeAll { $0.id == photo.id }
                onToast("Deleted")
            }
        }
        .padding(10)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func smallButton(_ title: LocalizedStringKey, destructive: Bool = false, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                isBusy = true
                do {
                    try await action()
                } catch {
                    // Was `try?` before — a failed hide/delete (a real
                    // network error, a revoked permission mid-session)
                    // silently did nothing, no different from the button
                    // not working at all. `action`'s own success path
                    // already calls `onToast`; this is just the failure
                    // side of that same contract.
                    onToast("Something went wrong — try again")
                }
                isBusy = false
            }
        } label: {
            Text(title)
                .font(NTFont.mono(10.5, .semibold))
                .foregroundStyle(destructive ? Color(hex: 0xE58272) : NTColor.milk(0.75))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Capsule().stroke((destructive ? Color(hex: 0xE58272) : NTColor.milk).opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

#Preview {
    SuperAdminView()
}

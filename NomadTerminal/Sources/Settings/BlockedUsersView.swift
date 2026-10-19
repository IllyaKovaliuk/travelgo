import SwiftUI

/// Settings → Blocked users. The list comes from `user_blocks`; the actual
/// hiding of content is enforced server-side (RLS), so unblocking here makes
/// the person's routes, comments and photos reappear on the next load.
struct BlockedUsersView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var users: [RouteRepository.BlockedUser] = []
    @State private var isLoading = true
    @State private var workingId: String?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("People you block can't appear in your feed, search, routes or comments. They aren't told.")
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(NTColor.milk(0.55))

                    if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if users.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(users) { userCard($0) }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Blocked users")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Couldn't update the block list", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again.")
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised").font(.system(size: 26)).foregroundStyle(NTColor.milk(0.3))
            Text("You haven't blocked anyone").font(NTFont.body(14.5, .semibold))
            Text("Block someone from their profile or from a comment's menu.")
                .font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func userCard(_ user: RouteRepository.BlockedUser) -> some View {
        HStack(spacing: 12) {
            Group {
                if let urlString = user.avatarUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            initialsBadge(user)
                        }
                    }
                } else {
                    initialsBadge(user)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName).font(NTFont.body(14.5, .semibold))
                Text("@\(user.username)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer(minLength: 0)

            Button { unblock(user) } label: {
                if workingId == user.id {
                    ProgressView().tint(NTColor.milk(0.7))
                } else {
                    Text("Unblock")
                        .font(NTFont.body(13, .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Capsule().stroke(NTColor.milk(0.4), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .disabled(workingId != nil)
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func initialsBadge(_ user: RouteRepository.BlockedUser) -> some View {
        ZStack {
            LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(user.initials).font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.milk)
        }
    }

    private func load() async {
        users = (try? await RouteRepository.shared.fetchBlockedUsers()) ?? []
        withAnimation { isLoading = false }
    }

    private func unblock(_ user: RouteRepository.BlockedUser) {
        workingId = user.id
        Task {
            do {
                try await RouteRepository.shared.unblockUser(user.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(NTMotion.spring) { users.removeAll { $0.id == user.id } }
            } catch {
                failed = true
            }
            workingId = nil
        }
    }
}

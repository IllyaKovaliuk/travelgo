import SwiftUI

/// 18 · Activity — real data now, assembled from follows/likes/comments/
/// badges/new-routes-from-people-you-follow (see
/// `RouteRepository.fetchNotifications`). There's no single notifications
/// table on the backend; this merges four real sources client-side.
///
/// Used both as its own bottom-tab (the social feed — a normal vertical
/// list of activity rows, same pattern Strava uses, not another full-
/// screen swipe surface) and, with `onClose` set, as a modal from anywhere
/// else that still wants to push it — `onClose == nil` hides the back
/// button since a tab has nowhere to "close" to.
struct NotificationsView: View {
    var onClose: (() -> Void)? = nil

    @State private var items: [RouteRepository.NotificationItem] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        if let onClose {
                            Button(action: onClose) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(NTColor.milk(0.08)))
                                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Activity").font(NTFont.heading(26, .extraBold))
                        if !items.isEmpty {
                            Text("\(items.count)").font(NTFont.mono(10, .semibold)).foregroundStyle(NTColor.accent)
                        }
                    }

                    if isLoading {
                        ProgressView().tint(NTColor.milk).padding(.top, 60).frame(maxWidth: .infinity)
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(items) { row($0) }
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(NTColor.milk)
        .task {
            items = (try? await RouteRepository.shared.fetchNotifications()) ?? []
            isLoading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash").font(.system(size: 26)).foregroundStyle(NTColor.milk(0.3))
            Text("Nothing yet").font(NTFont.body(14.5, .semibold))
            Text("Follows, likes, comments and badges will show up here.")
                .font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func icon(for kind: RouteRepository.NotificationKind) -> String {
        switch kind {
        case .follow: return "person.fill"
        case .comment: return "bubble.left.fill"
        case .like: return "heart.fill"
        case .badge: return "star.fill"
        case .newRoute: return "flag.fill"
        }
    }

    private func tint(for kind: RouteRepository.NotificationKind) -> Color {
        switch kind {
        case .follow: return NTColor.extreme
        case .comment: return NTColor.sage
        case .like: return NTColor.hardBright
        case .badge: return NTColor.gold
        case .newRoute: return NTColor.water
        }
    }

    private func row(_ item: RouteRepository.NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let initials = item.avatarInitials {
                ZStack {
                    LinearGradient(colors: [NTColor.extreme, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(initials).font(NTFont.heading(12, .semibold)).foregroundStyle(NTColor.milk)
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(tint(for: item.kind).opacity(0.2))
                    Image(systemName: icon(for: item.kind)).font(.system(size: 15)).foregroundStyle(tint(for: item.kind))
                }
                .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(NTFont.body(14, .medium))
                    .foregroundStyle(NTColor.milk)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = item.sub {
                    Text(sub).font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.createdAgo).font(NTFont.mono(9.5, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
    }
}

#Preview {
    NotificationsView(onClose: {})
}

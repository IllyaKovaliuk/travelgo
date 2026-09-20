import SwiftUI
import UIKit

/// One full-bleed card in the Home feed — cover, gradient, location pill,
/// title, tags, author row, stats row. Matches "04 · Home feed" 1:1.
struct RouteCard: View {
    let route: Route
    var onOpen: () -> Void = {}

    @State private var liked = false
    @State private var saved = false
    @State private var following = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var showComments = false
    @State private var showReportDialog = false
    @State private var reported = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RouteCoverImage(url: route.coverImageUrl, caption: route.coverPlaceholder, tint: route.transport.color)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
                    .contextMenu {
                        if reported {
                            Label("Reported", systemImage: "checkmark").disabled(true)
                        } else {
                            Button(role: .destructive) { showReportDialog = true } label: {
                                Label("Report route", systemImage: "flag")
                            }
                        }
                    }

                LinearGradient(
                    stops: [
                        .init(color: NTColor.pineDeep.opacity(0.72), location: 0),
                        .init(color: NTColor.pineDeep.opacity(0.08), location: 0.26),
                        .init(color: NTColor.pineDeep.opacity(0.06), location: 0.46),
                        .init(color: NTColor.pineDeep.opacity(0.86), location: 0.84),
                        .init(color: NTColor.pineDeep, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    HStack(spacing: 7) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                        Text(route.place)
                            .font(NTFont.mono(11, .medium))
                            .tracking(0.9)
                    }
                    .foregroundStyle(NTColor.milk)
                    .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                    .background(Capsule().fill(NTColor.milk(0.16)))
                    .overlay(Capsule().stroke(NTColor.milk(0.24), lineWidth: 1))

                    Text(route.title)
                        .font(NTFont.heading(38, .extraBold))
                        .foregroundStyle(NTColor.milk)
                        .lineSpacing(0)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
                        .padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(NTColor.milk).frame(width: 6, height: 6)
                            Text(route.difficulty.rawValue)
                                .font(NTFont.mono(11, .semibold))
                                .tracking(0.9)
                        }
                        .foregroundStyle(route.difficulty == .moderate ? Color(hex: 0x2B1B05) : NTColor.milk)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(Capsule().fill(route.difficulty.color))

                        transportBadge(icon: route.transport.icon, tint: route.transport.color, label: route.transportLabel)

                        if let extra = route.secondaryBadge {
                            transportBadge(icon: extra.icon, tint: NTColor.sage, label: extra.label)
                        }
                    }
                    .padding(.top, 14)

                    HStack(spacing: 12) {
                        ZStack {
                            LinearGradient(colors: route.author.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(route.author.initials)
                                .font(NTFont.heading(15, .semibold))
                                .foregroundStyle(NTColor.milk)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(NTColor.milk(0.45), lineWidth: 1.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.author.name)
                                .font(NTFont.body(14.5, .semibold))
                                .foregroundStyle(NTColor.milk)
                            Text("\(route.author.handle) · \(route.author.routeCount) routes")
                                .font(NTFont.mono(11, .medium))
                                .foregroundStyle(NTColor.milk(0.55))
                        }

                        Spacer()

                        Button {
                            tapHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { following.toggle() }
                            let newValue = following
                            Task { try? await RouteRepository.shared.setFollowing(authorId: route.author.id, following: newValue) }
                        } label: {
                            Text(following ? "Following" : "Follow")
                                .font(NTFont.body(13, .semibold))
                                .foregroundStyle(following ? NTColor.pine : NTColor.milk)
                                .padding(.horizontal, 18)
                                .frame(height: 38)
                                .background(Capsule().fill(following ? NTColor.milk : .clear))
                                .overlay(Capsule().stroke(NTColor.milk(0.55), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 22)

                    HStack(spacing: 26) {
                        ForEach(route.stats) { stat in
                            VStack(alignment: .leading, spacing: 6) {
                                (Text(stat.value).font(NTFont.mono(18, .semibold))
                                 + Text(" " + stat.unit).font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.6)))
                                    .foregroundStyle(NTColor.milk)
                                Text(stat.label)
                                    .font(NTFont.mono(9, .medium))
                                    .tracking(1.2)
                                    .foregroundStyle(NTColor.milk(0.5))
                            }
                        }
                    }
                    .padding(.top, 18)
                    .padding(.top, 16)
                    .overlay(Rectangle().fill(NTColor.milk(0.16)).frame(height: 1), alignment: .top)

                    Spacer().frame(height: 118)
                }
                .padding(.horizontal, 22)

                actionRail
            }
        }
        .clipped()
        .fullScreenCover(isPresented: $showComments, onDismiss: {
            // Re-fetch rather than guess — covers both a new comment posted
            // and none, without needing CommentsView to report back.
            Task { commentCount = (try? await RouteRepository.shared.fetchComments(routeId: route.id).count) ?? commentCount }
        }) {
            CommentsView(route: route)
        }
        .confirmationDialog("Why are you reporting this route?", isPresented: $showReportDialog, titleVisibility: .visible) {
            ForEach(["Spam", "Inappropriate content", "Misleading or unsafe info", "Other"], id: \.self) { reason in
                Button(reason) { report(reason: reason) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            following = await RouteRepository.shared.isFollowing(authorId: route.author.id)
            liked = await RouteRepository.shared.isLiked(routeId: route.id)
            saved = await RouteRepository.shared.isSaved(routeId: route.id)
            likeCount = route.likeCount
            commentCount = route.commentCount
        }
    }

    private var shareText: String {
        "Check out \"\(route.title.replacingOccurrences(of: "\n", with: " "))\" on NomadTerminal — \(String(format: "%.1f", route.distanceKM))km in \(route.place)."
    }

    private func report(reason: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { reported = true }
        Task { try? await RouteRepository.shared.report(.route, id: route.id, reason: reason) }
    }

    private var actionRail: some View {
        VStack(spacing: 14) {
            railButton(
                icon: liked ? "heart.fill" : "heart",
                tint: liked ? NTColor.accent : NTColor.milk,
                caption: formatCount(likeCount)
            ) {
                tapHaptic()
                liked.toggle()
                likeCount += liked ? 1 : -1
                let newValue = liked
                Task { try? await RouteRepository.shared.setLiked(routeId: route.id, liked: newValue) }
            }
            railButton(
                icon: saved ? "bookmark.fill" : "bookmark",
                tint: saved ? NTColor.sage : NTColor.milk,
                caption: saved ? "SAVED" : "SAVE"
            ) {
                tapHaptic()
                saved.toggle()
                let newValue = saved
                Task { try? await RouteRepository.shared.setSaved(routeId: route.id, saved: newValue) }
            }
            ShareLink(item: shareText) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 19)).foregroundStyle(NTColor.milk)
                    Text("SHR").font(NTFont.mono(8.5, .semibold)).foregroundStyle(NTColor.milk)
                }
                .frame(width: 52, height: 52)
                .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .background(Circle().fill(NTColor.milk(0.12)))
                .overlay(Circle().stroke(NTColor.milk(0.26), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { tapHaptic() })
            railButton(icon: "bubble.left", tint: NTColor.milk, caption: formatCount(commentCount)) { showComments = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .padding(.bottom, 210)
    }

    private func railButton(icon: String, tint: Color, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(tint)
                Text(caption)
                    .font(NTFont.mono(8.5, .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 52, height: 52)
            .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
            .background(Circle().fill(NTColor.milk(0.12)))
            .overlay(Circle().stroke(NTColor.milk(0.26), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: nil)
    }

    private func transportBadge(icon: String, tint: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
                .foregroundStyle(tint)
            Text(label)
                .font(NTFont.mono(11, .medium))
        }
        .foregroundStyle(NTColor.milk)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().stroke(NTColor.milk(0.3), lineWidth: 1))
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

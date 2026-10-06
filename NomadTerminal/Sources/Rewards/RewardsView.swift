import SwiftUI

/// NomadPoints — the loyalty ledger from `RouteRepository`'s points
/// methods (backed by `backend/supabase/migrations/20260908000001_points.sql`).
/// Deliberately not a blockchain token: real, server-verified points for
/// real activity (published routes, genuine likes/saves from other
/// people, new followers), redeemable today for bonus Pro time or
/// exclusive badges. See the migration's header comment for why this
/// ledger is also the honest first step toward a future token, if that
/// ever happens for real.
struct RewardsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var balance: Int?
    @State private var ledger: [RouteRepository.PointsLedgerEntry] = []
    @State private var catalog: [RouteRepository.PointReward] = []
    @State private var isLoading = true
    @State private var redeemingKey: String?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    balanceCard
                    aboutCard
                    if !catalog.isEmpty {
                        sectionLabel("REDEEM")
                        VStack(spacing: 12) { ForEach(catalog) { rewardRow($0) } }
                    }
                    if !ledger.isEmpty {
                        sectionLabel("ACTIVITY")
                        VStack(spacing: 0) { ForEach(ledger) { ledgerRow($0) } }
                            .padding(.horizontal, 18)
                            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
                    } else if !isLoading {
                        Text("Publish a route, get liked or saved by someone, or gain a follower — your first points will show up here.")
                            .font(NTFont.body(13, .light))
                            .foregroundStyle(NTColor.milk(0.5))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("NomadPoints")
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
        .task { await load() }
    }

    private func load() async {
        async let summary = try? RouteRepository.shared.fetchPointsSummary()
        async let ledgerRows = (try? RouteRepository.shared.fetchPointsLedger()) ?? []
        async let catalogRows = (try? RouteRepository.shared.fetchRewardCatalog()) ?? []
        balance = await summary?.balance
        ledger = await ledgerRows
        catalog = await catalogRows
        isLoading = false
    }

    private var balanceCard: some View {
        VStack(spacing: 6) {
            Text(balance.map(String.init) ?? "—")
                .font(NTFont.heading(52, .extraBold))
                .contentTransition(.numericText())
            Text("NOMADPOINTS").font(NTFont.mono(11, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RadialGradient(colors: [NTColor.accent.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 220),
            in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous)
        )
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How you earn them", systemImage: "sparkles")
                .font(NTFont.body(13, .semibold))
                .foregroundStyle(NTColor.gold)
            VStack(alignment: .leading, spacing: 6) {
                earnLine("Publish a real recorded route")
                earnLine("Add segments, gear, pins or a cover photo")
                earnLine("Someone else likes or saves your route")
                earnLine("Someone new follows you")
            }
            Text("Every point is awarded server-side from real activity — there's no way to fake it from the app. If Nomad ever does a real token, this history is the honest snapshot of who was actually here early.")
                .font(NTFont.body(11.5, .light))
                .foregroundStyle(NTColor.milk(0.5))
                .padding(.top, 4)
        }
        .padding(18)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func earnLine(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(NTColor.sage).frame(width: 5, height: 5).padding(.top, 6)
            Text(text).font(NTFont.body(13, .light)).foregroundStyle(NTColor.milk(0.75))
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
    }

    private func rewardRow(_ reward: RouteRepository.PointReward) -> some View {
        let affordable = (balance ?? 0) >= reward.cost
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill((reward.kind == "badge" ? NTColor.gold : NTColor.sage).opacity(0.2))
                Image(systemName: reward.kind == "badge" ? "star.circle.fill" : "crown.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(reward.kind == "badge" ? NTColor.gold : NTColor.sage)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(reward.title).font(NTFont.body(14.5, .semibold))
                Text(reward.description).font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.55))
            }
            Spacer()

            Button {
                Task { await redeem(reward) }
            } label: {
                if redeemingKey == reward.key {
                    ProgressView().tint(NTColor.pine)
                        .frame(width: 74, height: 34)
                        .background(Capsule().fill(NTColor.milk(0.5)))
                } else {
                    Text("\(reward.cost) PT")
                        .font(NTFont.mono(11.5, .semibold))
                        .foregroundStyle(affordable ? NTColor.pine : NTColor.milk(0.4))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(affordable ? NTColor.milk : NTColor.milk(0.12)))
                }
            }
            .buttonStyle(.plain)
            .disabled(!affordable || redeemingKey != nil)
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func redeem(_ reward: RouteRepository.PointReward) async {
        redeemingKey = reward.key
        do {
            try await RouteRepository.shared.redeemReward(key: reward.key)
            await SubscriptionManager.shared.refreshBonusPro()
            if let summary = try? await RouteRepository.shared.fetchPointsSummary() {
                withAnimation { balance = summary.balance }
            }
            ledger = (try? await RouteRepository.shared.fetchPointsLedger()) ?? ledger
            showToast("Redeemed — \(reward.title)")
        } catch {
            showToast(error.localizedDescription)
        }
        redeemingKey = nil
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toast = nil }
        }
    }

    private func ledgerRow(_ entry: RouteRepository.PointsLedgerEntry) -> some View {
        HStack(spacing: 12) {
            Text(label(for: entry.reason))
                .font(NTFont.body(13.5, .medium))
            Spacer()
            Text(entry.delta >= 0 ? "+\(entry.delta)" : "\(entry.delta)")
                .font(NTFont.mono(13, .semibold))
                .foregroundStyle(entry.delta >= 0 ? NTColor.sage : Color(hex: 0xE58272))
        }
        .padding(.vertical, 13)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
    }

    private func label(for reason: String) -> String {
        switch reason {
        case "route_published": return "Route published"
        case "segment_added": return "Segment added"
        case "requirement_added": return "Gear/requirement added"
        case "poi_added": return "Pin dropped"
        case "cover_photo_added": return "Cover photo added"
        case "route_liked": return "Someone liked your route"
        case "route_unliked": return "Like removed"
        case "route_saved": return "Someone saved your route"
        case "route_unsaved": return "Save removed"
        case "route_commented": return "Someone commented on your route"
        case "new_follower": return "New follower"
        case "unfollowed": return "Lost a follower"
        default:
            if reason.hasPrefix("redeemed_") { return "Redeemed a reward" }
            return reason
        }
    }
}

#Preview {
    RewardsView()
}

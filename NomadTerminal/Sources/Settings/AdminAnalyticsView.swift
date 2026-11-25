import SwiftUI

/// Real, first-party analytics — there was no such screen anywhere in
/// this app before it, so anything about "how many people actually use
/// this" was pure guesswork. Backed by `analytics_events` (real rows,
/// logged from real actions via `RouteRepository.logEvent`) and
/// `admin_analytics_summary()`, which itself re-checks `is_admin` and
/// throws for anyone else — same trust model as `AdminModerationView`,
/// gated the same way in Settings.
struct AdminAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var summary: RouteRepository.AnalyticsSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if let errorMessage {
                        Text(errorMessage).font(NTFont.body(13, .medium)).foregroundStyle(Color(hex: 0xE58272))
                    } else if let summary {
                        statsGrid(summary)
                        sectionLabel("EVENTS, LAST 7 DAYS")
                        if summary.topEvents7d.isEmpty {
                            Text("No events logged yet.").font(NTFont.body(13, .medium)).foregroundStyle(NTColor.milk(0.5))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(summary.topEvents7d) { event in
                                    eventRow(event)
                                }
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
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await load() }
    }

    private func statsGrid(_ s: RouteRepository.AnalyticsSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            stat("\(s.dau)", "ACTIVE TODAY")
            stat("\(s.wau)", "ACTIVE 7D")
            stat("\(s.totalUsers)", "TOTAL USERS")
            stat("\(s.signups7d)", "SIGNUPS 7D")
            stat("\(s.totalRoutesPublished)", "ROUTES PUBLISHED")
            stat("\(s.routesPublished7d)", "PUBLISHED 7D")
            stat("\(s.sosTriggers7d)", "SOS TRIGGERS 7D")
            if let f = s.crewFunnel {
                stat("\(f.invitesSent7d)", "CREW INVITES SENT 7D")
                stat("\(f.invitesOpened7d)", "INVITES OPENED 7D")
                stat("\(f.joins7d)", "CREW JOINS 7D")
                stat(String(format: "%.1f", f.invitesPerInviter7d), "INVITES / INVITER")
            }
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(NTFont.mono(24, .semibold))
            Text(label).font(NTFont.mono(9.5, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
    }

    private func eventRow(_ event: RouteRepository.AnalyticsSummary.TopEvent) -> some View {
        HStack {
            Text(event.eventName).font(NTFont.body(13, .medium))
            Spacer()
            Text("\(event.count)").font(NTFont.mono(12, .semibold)).foregroundStyle(NTColor.milk(0.6))
        }
        .padding(12)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func load() async {
        do {
            summary = try await RouteRepository.shared.fetchAnalyticsSummary()
        } catch {
            errorMessage = "Couldn't load analytics — check your connection and try again."
        }
        withAnimation { isLoading = false }
    }
}

#Preview {
    AdminAnalyticsView()
}

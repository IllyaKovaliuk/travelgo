import SwiftUI
import CoreLocation

/// 10/11 · Settings — Pine/Milk appearance is real now: picking a tile
/// writes to `ThemeManager.shared`, which every `NTColor.pine`/`.milk`
/// call site across the app already reads live. "Download over Wi-Fi
/// only" and "Background location" are real now too (see
/// `AppPreferences`/`OfflineRouteStore` and the location-status row below).
/// Weather/ford alerts (the row that used to live here as an honest
/// "Coming soon") was dropped entirely rather than kept as a placeholder —
/// not a feature this app is building.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    @State private var languageManager = LanguageManager.shared
    @State private var wifiOnly = AppPreferences.wifiOnlyDownloads
    /// Real `CLLocationManager.authorizationStatus`, not a local toggle —
    /// an app can't silently grant itself Always location, so this reflects
    /// truth and routes any tap to Settings rather than pretending to flip.
    @State private var backgroundLocationGranted = false
    @State private var visitsMonitoringEnabled = AppPreferences.visitsMonitoringEnabled
    @State private var showPaywall = false
    @State private var showAuth = false
    @State private var showRewards = false
    @State private var showModeration = false
    @State private var showAnalytics = false
    @State private var showEmergencyContacts = false
    @State private var isAdmin = false
    @State private var isSigningOut = false
    @State private var subscription = SubscriptionManager.shared
    /// Real bytes under `OfflineRoutes`, not the hardcoded fake "2.4 / 8
    /// GB" this row used to show — there's no real storage quota anywhere
    /// in this app, so this is usage only, no invented cap.
    @State private var offlineStorageBytes: Int64 = 0
    @State private var emergencyContactCount = 0

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    proRow
                    pointsRow

                    appearanceCard

                    cardGroup {
                        languageRow
                        divider
                        toggleRow(icon: "arrow.down.circle.fill", tint: NTColor.sage, title: "Download over Wi-Fi only", isOn: Binding(
                            get: { wifiOnly },
                            set: { wifiOnly = $0; AppPreferences.wifiOnlyDownloads = $0 }
                        ))
                        divider
                        backgroundLocationRow
                        divider
                        visitsMonitoringRow
                        divider
                        valueRow(title: "Units", value: "METRIC")
                    }

                    cardGroup {
                        valueRow(title: "Offline storage", value: formattedOfflineStorage)
                        divider
                        Button { showEmergencyContacts = true } label: {
                            valueRow(
                                title: "Emergency contacts",
                                value: emergencyContactCount > 0 ? "\(emergencyContactCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)
                        divider
                        valueRow(title: "About NomadCompass", value: "v2.4.0")
                    }

                    // Real now — `profiles.is_admin`, checked here (so the
                    // row doesn't even show) and again server-side inside
                    // every admin_* RPC (so hiding the row is real UX, not
                    // the actual security boundary). Used to be reachable
                    // by literally any signed-in user.
                    if isAdmin {
                        cardGroup {
                            Button { showModeration = true } label: {
                                valueRow(title: "Moderation (review hidden content)", value: nil)
                            }
                            .buttonStyle(.plain)
                            divider
                            Button { showAnalytics = true } label: {
                                valueRow(title: "Analytics", value: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        signOut()
                    } label: {
                        HStack {
                            if isSigningOut { ProgressView().tint(Color(hex: 0xE58272)) }
                            Text("Sign out")
                        }
                        .font(NTFont.body(14.5, .semibold))
                        .foregroundStyle(Color(hex: 0xE58272))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .overlay(Capsule().stroke(Color(hex: 0xB33A2B).opacity(0.5), lineWidth: 1.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSigningOut)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(themeManager.colorScheme, for: .navigationBar)
            .fullScreenCover(isPresented: $showPaywall) { PaywallView(onClose: { showPaywall = false }) }
            .fullScreenCover(isPresented: $showAuth) { AuthView(onDone: { showAuth = false; dismiss() }) }
            .sheet(isPresented: $showRewards) { RewardsView() }
            .sheet(isPresented: $showModeration) { AdminModerationView() }
            .sheet(isPresented: $showAnalytics) { AdminAnalyticsView() }
            .sheet(isPresented: $showEmergencyContacts, onDismiss: { Task { await loadEmergencyContactCount() } }) {
                EmergencyContactsView()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(themeManager.colorScheme)
        .task {
            refreshLocationStatus()
            offlineStorageBytes = await OfflineRouteStore.shared.diskUsageBytes()
            await loadEmergencyContactCount()
            isAdmin = (try? await RouteRepository.shared.fetchMyProfile())?.isAdmin ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Catches coming back from the system Settings deep link below —
            // the only way this status can actually change.
            refreshLocationStatus()
        }
    }

    private func refreshLocationStatus() {
        backgroundLocationGranted = CLLocationManager().authorizationStatus == .authorizedAlways
    }

    private func loadEmergencyContactCount() async {
        emergencyContactCount = (try? await RouteRepository.shared.fetchEmergencyContacts().count) ?? emergencyContactCount
    }

    private var formattedOfflineStorage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: offlineStorageBytes)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Real, live app-language override — `LanguageManager.current`, not
    /// just reading whatever iOS itself is set to. "System" (nil) is the
    /// original, only behavior before this row existed.
    private var languageRow: some View {
        Menu {
            Button { setLanguage(nil) } label: {
                if languageManager.current == nil { Label("System", systemImage: "checkmark") } else { Text("System") }
            }
            ForEach(LanguageManager.supportedCodes, id: \.self) { code in
                Button { setLanguage(code) } label: {
                    if languageManager.current == code { Label(languageName(code), systemImage: "checkmark") } else { Text(languageName(code)) }
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "globe").font(.system(size: 17)).foregroundStyle(NTColor.water).frame(width: 20)
                Text("Language").font(NTFont.body(15, .medium)).foregroundStyle(NTColor.milk)
                Spacer()
                Text(languageManager.current.map(languageName) ?? "System")
                    .font(NTFont.mono(12, .semibold)).foregroundStyle(NTColor.milk(0.6))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(NTColor.milk(0.4))
            }
            .padding(.vertical, 15)
        }
    }

    private func languageName(_ code: String) -> String {
        switch code {
        case "en": return "English"
        case "uk": return "Українська"
        case "es": return "Español"
        default: return code
        }
    }

    private func setLanguage(_ code: String?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { languageManager.current = code }
    }

    private var backgroundLocationRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.fill").font(.system(size: 17)).foregroundStyle(NTColor.sage).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Background location").font(NTFont.body(15, .medium))
                if !backgroundLocationGranted {
                    Text("Tap to enable in Settings").font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.45))
                }
            }
            Spacer()
            // The switch itself can't grant Always location — any tap,
            // on or off, routes to the system Settings deep link; the
            // visible state always reflects the real authorization status.
            Toggle("", isOn: Binding(get: { backgroundLocationGranted }, set: { _ in openSystemSettings() }))
                .labelsHidden().tint(NTColor.sage)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .onTapGesture { if !backgroundLocationGranted { openSystemSettings() } }
    }

    /// Deliberately its own toggle, separate from `backgroundLocationRow`
    /// above — that one is about an active LogRoute recording continuing
    /// in the background; this is always-on passive detection for the
    /// Journal, a materially different privacy trade-off that shouldn't
    /// get silently bundled into approving the other.
    private var visitsMonitoringRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.magnifyingglass").font(.system(size: 17)).foregroundStyle(NTColor.water).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Passive visit detection").font(NTFont.body(15, .medium))
                Text("Low-power arrival/stay detection for your Journal").font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.45))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { visitsMonitoringEnabled },
                set: { newValue in
                    visitsMonitoringEnabled = newValue
                    AppPreferences.visitsMonitoringEnabled = newValue
                    if newValue { VisitsMonitor.shared.start() } else { VisitsMonitor.shared.stop() }
                }
            ))
            .labelsHidden().tint(NTColor.sage)
        }
        .padding(.vertical, 15)
    }

    private var proRow: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(NTColor.gold.opacity(0.2))
                    Image(systemName: subscription.isPro ? "checkmark.seal.fill" : "crown.fill")
                        .font(.system(size: 15)).foregroundStyle(NTColor.gold)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(subscription.isPro ? "NomadCompass Pro" : "Get NomadCompass Pro").font(NTFont.body(14.5, .semibold))
                    Text(subscription.isPro ? "Active — manage your plan" : "Offline maps, SOS beacon")
                        .font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.4))
            }
            .foregroundStyle(NTColor.milk)
        }
        .buttonStyle(.plain)
        .padding(18)
        .background(NTColor.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.gold.opacity(0.3), lineWidth: 1))
    }

    private var pointsRow: some View {
        Button { showRewards = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(NTColor.sage.opacity(0.2))
                    Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(NTColor.sage)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NomadPoints").font(NTFont.body(14.5, .semibold))
                    Text("Earn from real activity, redeem for Pro & badges").font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.4))
            }
            .foregroundStyle(NTColor.milk)
        }
        .buttonStyle(.plain)
        .padding(18)
        .background(NTColor.sage.opacity(0.1), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.sage.opacity(0.3), lineWidth: 1))
    }

    private func signOut() {
        isSigningOut = true
        Task {
            try? await supabase.auth.signOut()
            UserDefaults.standard.removeObject(forKey: "authSessionStartedAt")
            isSigningOut = false
            showAuth = true
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("APPEARANCE").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            HStack(spacing: 12) {
                // Fixed literal colors here on purpose, not NTColor.pine/
                // .milk — those are theme-reactive now, so the swatches
                // must NOT follow the live theme or "Pine" would stop
                // looking like Pine once Milk is active. Values below are
                // `NTColor.pine`/`.milk`'s own current dark-mode values
                // (0x0A0A0A/0xF5F5F5) — this used to preview a dark-green
                // 0x00311F, a stale leftover from before Pine moved to the
                // current near-black "terminal" look, so the swatch was
                // lying about what picking it actually looked like.
                themeTile("Pine", selected: themeManager.current == .pine, bg: Color(hex: 0x0A0A0A), fg: Color(hex: 0xF5F5F5)) {
                    themeManager.current = .pine
                }
                themeTile("Milk", selected: themeManager.current == .milk, bg: NTColor.milkSurface, fg: NTColor.ink) {
                    themeManager.current = .milk
                }
            }
        }
        .padding(20)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func themeTile(_ label: LocalizedStringKey, selected: Bool, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bg)
                        .frame(height: 56)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 5) {
                                RoundedRectangle(cornerRadius: 3).fill(fg.opacity(0.7)).frame(width: 44, height: 6)
                                RoundedRectangle(cornerRadius: 3).fill(fg.opacity(0.35)).frame(width: 26, height: 5)
                            }
                            .padding(9)
                        }
                    RoundedRectangle(cornerRadius: 7).fill(NTColor.accent).frame(width: 26, height: 13).padding(7)
                }
                HStack(spacing: 7) {
                    Circle().fill(selected ? NTColor.accent : .clear)
                        .overlay(Circle().stroke(NTColor.milk(0.4), lineWidth: selected ? 0 : 1))
                        .frame(width: 13, height: 13)
                    Text(label).font(NTFont.body(13, .semibold)).foregroundStyle(selected ? NTColor.milk : NTColor.milk(0.65))
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NTColor.milk(0.04), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(selected ? NTColor.accent : NTColor.milk(0.14), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(NTColor.milk(0.1)).frame(height: 1)
    }

    private func toggleRow(icon: String, tint: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint).frame(width: 20)
            Text(title).font(NTFont.body(15, .medium))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(NTColor.sage)
        }
        .padding(.vertical, 15)
    }

    private func valueRow(title: LocalizedStringKey, value: String?) -> some View {
        HStack(spacing: 14) {
            Text(title).font(NTFont.body(15, .medium))
            Spacer()
            if let value {
                Text(value).font(NTFont.mono(12, .semibold)).foregroundStyle(NTColor.milk(0.6))
            } else {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.45))
            }
        }
        .padding(.vertical, 15)
    }
}

#Preview {
    SettingsView()
}

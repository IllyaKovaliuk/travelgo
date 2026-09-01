import SwiftUI

/// 10/11 · Settings — appearance card previews both themes; the rest of
/// the app stays on Pine until a real theming pass wires Milk through
/// the design tokens.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var theme: Theme = .pine
    @State private var wifiOnly = true
    @State private var backgroundLocation = true
    @State private var weatherAlerts = false
    @State private var showPaywall = false
    @State private var showAuth = false
    @State private var isSigningOut = false
    @State private var subscription = SubscriptionManager.shared

    enum Theme { case pine, milk }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    proRow

                    appearanceCard

                    cardGroup {
                        toggleRow(icon: "arrow.down.circle.fill", tint: NTColor.sage, title: "Download over Wi-Fi only", isOn: $wifiOnly)
                        divider
                        toggleRow(icon: "location.fill", tint: NTColor.sage, title: "Background location", isOn: $backgroundLocation)
                        divider
                        toggleRow(icon: "cloud.rain.fill", tint: NTColor.milk(0.6), title: "Ford & weather alerts", isOn: $weatherAlerts)
                        divider
                        valueRow(title: "Units", value: "METRIC")
                    }

                    cardGroup {
                        valueRow(title: "Offline storage", value: "2.4 / 8 GB")
                        divider
                        valueRow(title: "Emergency contacts", value: nil)
                        divider
                        valueRow(title: "About NomadTerminal", value: "v2.4.0")
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .fullScreenCover(isPresented: $showPaywall) { PaywallView(onClose: { showPaywall = false }) }
            .fullScreenCover(isPresented: $showAuth) { AuthView(onDone: { showAuth = false; dismiss() }) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
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
                    Text(subscription.isPro ? "NomadTerminal Pro" : "Get NomadTerminal Pro").font(NTFont.body(14.5, .semibold))
                    Text(subscription.isPro ? "Active — manage your plan" : "Offline maps, SOS beacon, weather alerts")
                        .font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.4))
            }
            .foregroundStyle(NTColor.milk)
        }
        .buttonStyle(.plain)
        .padding(18)
        .background(NTColor.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NTColor.gold.opacity(0.3), lineWidth: 1))
    }

    private func signOut() {
        isSigningOut = true
        Task {
            try? await supabase.auth.signOut()
            isSigningOut = false
            showAuth = true
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("APPEARANCE").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            HStack(spacing: 12) {
                themeTile("Pine", selected: theme == .pine, bg: NTColor.pine, fg: NTColor.milk) { theme = .pine }
                themeTile("Milk", selected: theme == .milk, bg: NTColor.milkSurface, fg: NTColor.ink) { theme = .milk }
            }
        }
        .padding(20)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func themeTile(_ label: String, selected: Bool, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
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
            .background(NTColor.milk(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? NTColor.accent : NTColor.milk(0.14), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
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

    private func valueRow(title: String, value: String?) -> some View {
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

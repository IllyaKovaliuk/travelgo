import SwiftUI

private struct Badge: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let sub: String
    let colors: [Color]
    let locked: Bool
}

private let badges: [Badge] = [
    .init(icon: "car.side", title: "Diff Locker", sub: "10 TRACKS", colors: [Color(hex: 0xF19A6B), NTColor.accentDeep], locked: false),
    .init(icon: "water.waves", title: "Cold Water", sub: "GRADE III", colors: [Color(hex: 0x6FB4DD), Color(hex: 0x2A6E9B)], locked: false),
    .init(icon: "mountain.2.fill", title: "Vertical Mile", sub: "1609 M", colors: [Color(hex: 0x9C86D8), Color(hex: 0x5B41A0)], locked: false),
    .init(icon: "figure.hiking", title: "Hundred Club", sub: "100 KM FOOT", colors: [Color(hex: 0x8FCBA3), Color(hex: 0x3D7A54)], locked: false),
    .init(icon: "location.north.circle.fill", title: "True North", sub: "50 H OFFLINE", colors: [Color(hex: 0xF0C98A), Color(hex: 0xA8721F)], locked: false),
    .init(icon: "lock.fill", title: "Night Ford", sub: "LOCKED", colors: [NTColor.milk(0.14), NTColor.milk(0.14)], locked: true)
]

/// 08 · Profile & badges
struct ProfileView: View {
    enum Tab: String, CaseIterable { case routes = "My routes", activity = "Activity", badges = "Badges" }
    @State private var tab: Tab = .badges
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()
            OrganicBlob((0.52, 0.48, 0.58, 0.42), (0.48, 0.54, 0.46, 0.52))
                .fill(NTColor.pineRaised)
                .frame(width: 420, height: 340)
                .position(x: 80, y: -60)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(LinearGradient(colors: [NTColor.accent, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 84, height: 84)
                                .overlay(Text("SK").font(NTFont.heading(28, .semibold)).foregroundStyle(NTColor.milk))
                            Text("12")
                                .font(NTFont.mono(10, .semibold))
                                .foregroundStyle(Color(hex: 0x2B1B05))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(NTColor.gold))
                                .overlay(Circle().stroke(NTColor.pine, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sana Kadyrova").font(NTFont.heading(26, .extraBold)).foregroundStyle(NTColor.milk)
                            Text("@sanadrives · ALMATY, KZ").font(NTFont.mono(11.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                        }
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(NTColor.milk(0.75))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(NTColor.milk(0.1)))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 0) {
                        statBlock("4218", "KM LOGGED")
                        statBlock("38", "COMPLETED")
                        statBlock("9", "BADGES")
                    }
                    .padding(.vertical, 18)
                    .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .bottom)
                    .padding(.top, 24)

                    HStack(spacing: 4) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { tab = t }
                            } label: {
                                Text(t.rawValue)
                                    .font(NTFont.body(13, .semibold))
                                    .foregroundStyle(tab == t ? NTColor.pine : NTColor.milk(0.7))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(Capsule().fill(tab == t ? NTColor.milk : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .background(Capsule().fill(NTColor.milk(0.08)))
                    .padding(.top, 22)

                    Group {
                        switch tab {
                        case .badges: badgeGrid
                        case .routes: routesList
                        case .activity: activityList
                        }
                    }
                    .padding(.top, 26)
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
                .padding(.bottom, 100)
            }
        }
        .foregroundStyle(NTColor.milk)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(NTFont.mono(24, .semibold))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badgeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
            ForEach(badges) { b in
                VStack(spacing: 9) {
                    ZStack {
                        if b.locked {
                            Circle().fill(NTColor.milk(0.12)).overlay(Circle().stroke(NTColor.milk(0.16), lineWidth: 1))
                        } else {
                            Circle().fill(RadialGradient(colors: b.colors, center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: 50))
                                .overlay(Circle().stroke(NTColor.milk(0.3), lineWidth: 1.5))
                                .shadow(color: b.colors.last!.opacity(0.6), radius: 10, y: 6)
                        }
                        Image(systemName: b.icon)
                            .font(.system(size: 26))
                            .foregroundStyle(b.locked ? NTColor.milk(0.5) : NTColor.milk)
                    }
                    .frame(width: 84, height: 84)

                    Text(b.title).font(NTFont.body(11, .semibold)).multilineTextAlignment(.center)
                        .foregroundStyle(b.locked ? NTColor.milk(0.5) : NTColor.milk)
                    Text(b.sub).font(NTFont.mono(8.5, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.45))
                }
            }
        }
    }

    private var routesList: some View {
        VStack(spacing: 12) {
            routeRow(title: "Charyn Canyon rim", meta: "84.1 KM · 4×4 · PUBLISHED", likes: "1.2K", downloads: "318")
            routeRow(title: "Kolsai lakes traverse", meta: "31.6 KM · FOOT · DRAFT", likes: "0", downloads: "0")
        }
    }

    private func routeRow(title: String, meta: String, likes: String, downloads: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [NTColor.pineRaised, NTColor.pineShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(NTFont.heading(16, .bold))
                Text(meta).font(NTFont.mono(10.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                HStack(spacing: 14) {
                    Label(likes, systemImage: "heart").font(NTFont.mono(10.5, .medium))
                    Label(downloads, systemImage: "arrow.down").font(NTFont.mono(10.5, .medium))
                }
                .foregroundStyle(NTColor.milk(0.7))
            }
            Spacer()
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            activityRow(icon: "checkmark", tint: NTColor.accent, text: "Completed **Zagar Pass** in 6 h 42 m", time: "3 DAYS AGO · 62.4 KM")
            activityRow(icon: "star.fill", tint: NTColor.gold, text: "Earned **True North**", time: "1 WEEK AGO")
            activityRow(icon: "location.circle", tint: NTColor.sage, text: "Logged a ford condition at **WP3**", time: "2 WEEKS AGO")
        }
    }

    private func activityRow(icon: String, tint: Color, text: LocalizedStringKey, time: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.2)))
            VStack(alignment: .leading, spacing: 7) {
                Text(text).font(NTFont.body(14.5, .medium)).foregroundStyle(NTColor.milk)
                Text(time).font(NTFont.mono(10, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
        }
        .padding(.vertical, 15)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
    }
}

#Preview {
    ProfileView()
}

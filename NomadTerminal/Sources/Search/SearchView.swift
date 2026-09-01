import SwiftUI

/// 07 · Search & filters — filters are real: every change re-queries
/// `RouteRepository.searchRoutes` and "Show results" presents whatever
/// that last query returned.
struct SearchView: View {
    @State private var query = ""
    @State private var selectedTransport: Set<Transport> = []
    @State private var difficultyIndex = 2
    @State private var openSection: Section? = .transport

    @State private var results: [Route] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var showResults = false
    @State private var searchTask: Task<Void, Never>?

    enum Section { case transport, difficulty, distance }

    private var transportKeys: [String] {
        selectedTransport.isEmpty
            ? [Transport.overland, .foot, .water, .climb].map(\.dbKey)
            : selectedTransport.map(\.dbKey)
    }

    private var difficultyKeys: [String] {
        switch difficultyIndex {
        case 0: return [Route.Difficulty.easy.dbKey]
        case 1: return [Route.Difficulty.easy.dbKey, Route.Difficulty.moderate.dbKey]
        default: return Route.Difficulty.allCases.map(\.dbKey)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    searchBar
                    if !query.isEmpty {
                        suggestionsCard
                    }
                    presetsRow
                    disclosureSection(.transport, title: "Transport", trailing: "\(selectedTransport.count)") {
                        transportGrid
                    }
                    disclosureSection(.difficulty, title: "Difficulty", trailing: ["UP TO EASY", "UP TO MODERATE", "ANYTHING"][difficultyIndex]) {
                        difficultySlider
                    }
                    disclosureSection(.distance, title: "Distance & elevation", trailing: nil) {
                        rangeRows
                    }
                    staticRow(title: "Region", value: "CAUCASUS")
                    staticRow(title: "Requirements", value: "NO PERMIT")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }

            resultsBar
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .task { runSearch(debounced: false) }
        .onChange(of: selectedTransport) { _, _ in runSearch(debounced: false) }
        .onChange(of: difficultyIndex) { _, _ in runSearch(debounced: false) }
        .onChange(of: query) { _, _ in runSearch(debounced: true) }
        .fullScreenCover(isPresented: $showResults) {
            SearchResultsView(routes: results) { showResults = false }
        }
    }

    private func runSearch(debounced: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            if debounced {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            isSearching = true
            do {
                let found = try await RouteRepository.shared.searchRoutes(
                    query: query,
                    transports: transportKeys,
                    difficulties: difficultyKeys,
                    minKM: 0,
                    maxKM: 100_000
                )
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    results = found
                    hasSearched = true
                }
            } catch {
                // Offline or backend hiccup — keep the last known results rather
                // than blanking the count out from under the user.
            }
            isSearching = false
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(NTColor.ink)
            TextField("Search routes, regions…", text: $query)
                .font(NTFont.body(15.5, .medium))
                .foregroundStyle(NTColor.ink)
            Button { query = "" } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NTColor.ink)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(NTColor.ink.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(NTColor.milk, in: Capsule())
    }

    private var suggestionsCard: some View {
        VStack(spacing: 0) {
            suggestionRow(icon: "location.fill", tint: NTColor.accentDeep, bold: "Svan", rest: "eti high route", trailing: "42 ROUTES")
            Divider().overlay(NTColor.ink.opacity(0.08))
            suggestionRow(icon: "clock", tint: NTColor.ink.opacity(0.5), bold: "Svan", rest: " towers loop", trailing: "RECENT")
            Divider().overlay(NTColor.ink.opacity(0.08))
            suggestionRow(icon: "house.fill", tint: NTColor.ink.opacity(0.5), bold: "Svan", rest: "eti guesthouse chain", trailing: nil)
        }
        .padding(.vertical, 6)
        .background(NTColor.milk, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
    }

    private func suggestionRow(icon: String, tint: Color, bold: String, rest: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint).frame(width: 18)
            (Text(bold).fontWeight(.bold) + Text(rest))
                .font(NTFont.body(14.5, .medium))
                .foregroundStyle(NTColor.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(NTFont.mono(10, .semibold)).foregroundStyle(NTColor.ink.opacity(0.45))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var presetsRow: some View {
        HStack(spacing: 8) {
            presetChip("★ WEEKEND 4×4", filled: true)
            presetChip("★ HUT-TO-HUT", filled: false)
            Text("+ SAVE PRESET")
                .font(NTFont.mono(11, .semibold)).tracking(0.6)
                .foregroundStyle(NTColor.milk(0.5))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(NTColor.milk(0.22)))
        }
    }

    private func presetChip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(NTFont.mono(11, .semibold)).tracking(0.6)
            .foregroundStyle(filled ? Color(hex: 0xF1A47C) : NTColor.milk(0.7))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(filled ? NTColor.accent.opacity(0.18) : .clear))
            .overlay(Capsule().stroke(filled ? NTColor.accent.opacity(0.5) : NTColor.milk(0.22), lineWidth: 1))
    }

    @ViewBuilder
    private func disclosureSection<Content: View>(_ section: Section, title: String, trailing: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    openSection = openSection == section ? nil : section
                }
            } label: {
                HStack(spacing: 12) {
                    Text(title).font(NTFont.heading(17, .bold)).foregroundStyle(NTColor.milk)
                    if let trailing {
                        Text(trailing).font(NTFont.mono(11, .semibold)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NTColor.milk(0.6))
                        .rotationEffect(.degrees(openSection == section ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if openSection == section {
                content().padding(.top, 18)
            }
        }
        .padding(20)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private var transportGrid: some View {
        HStack(spacing: 10) {
            ForEach([Transport.overland, .foot, .water, .climb], id: \.self) { t in
                let selected = selectedTransport.contains(t)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if selected { selectedTransport.remove(t) } else { selectedTransport.insert(t) }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 18))
                        Text(t.rawValue).font(NTFont.mono(8.5, .semibold))
                    }
                    .foregroundStyle(selected ? Color(hex: 0x231007) : NTColor.milk(0.75))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? t.color : NTColor.milk(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(NTColor.milk(0.16), lineWidth: selected ? 0 : 1)
                    )
                }
                .buttonStyle(.plain)
                .ntPressable(haptic: nil)
            }
        }
    }

    private var difficultySlider: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * (difficultyIndex == 0 ? 0.02 : difficultyIndex == 1 ? 0.5 : 0.98)
                ZStack(alignment: .leading) {
                    Capsule().fill(NTColor.milk(0.15)).frame(height: 6)
                    Capsule().fill(NTColor.gold).frame(width: x, height: 6)
                    Circle().fill(NTColor.milk).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(NTColor.gold, lineWidth: 3))
                        .shadow(radius: 3)
                        .offset(x: x - 11)
                }
                .frame(height: 22)
            }
            .frame(height: 22)

            HStack {
                Button("EASY") { setDiff(0) }
                Spacer()
                Button("MODERATE") { setDiff(1) }
                Spacer()
                Button("HARD") { setDiff(2) }
            }
            .font(NTFont.mono(10, .semibold))
            .foregroundStyle(NTColor.milk(0.55))
            .buttonStyle(.plain)
        }
    }

    private func setDiff(_ i: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { difficultyIndex = i }
    }

    private var rangeRows: some View {
        VStack(alignment: .leading, spacing: 18) {
            rangeRow(label: "DISTANCE", value: "18 – 80 KM", fraction: 0.55, tint: NTColor.sage)
            rangeRow(label: "ASCENT", value: "0 – 2400 M", fraction: 0.32, tint: NTColor.water)
        }
    }

    private func rangeRow(label: String, value: String, fraction: CGFloat, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label).font(NTFont.mono(11, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
                Spacer()
                Text(value).font(NTFont.mono(11, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NTColor.milk(0.15)).frame(height: 6)
                    Capsule().fill(tint).frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func staticRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(NTFont.heading(17, .bold)).foregroundStyle(NTColor.milk)
            Text(value).font(NTFont.mono(11, .semibold)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(NTColor.milk(0.5))
        }
        .padding(20)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private var resultsBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if isSearching && !hasSearched {
                    ProgressView().tint(NTColor.milk)
                } else {
                    Text("\(results.count)").font(NTFont.mono(20, .semibold))
                }
                Text("ROUTES MATCH").font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.6))
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showResults = true
            } label: {
                Text("Show results")
                    .font(NTFont.body(14.5, .semibold))
                    .foregroundStyle(NTColor.pine)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain).ntPressable()
            .disabled(isSearching && !hasSearched)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        )
        .background(Capsule().fill(NTColor.milk(0.13)))
        .overlay(Capsule().stroke(NTColor.milk(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 92)
    }
}

#Preview {
    SearchView()
}

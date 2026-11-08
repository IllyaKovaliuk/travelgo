import SwiftUI

/// 07 · Search & filters — filters are real: every change re-queries
/// `RouteRepository.searchRoutes` and "Show results" presents whatever
/// that last query returned.
struct SearchView: View {
    enum Mode { case routes, places }
    @State private var mode: Mode = .routes

    @State private var query = ""
    @State private var selectedTransport: Set<Transport> = []
    @State private var difficultyIndex = 2
    @State private var openSection: Section? = .transport

    private static let distanceBounds: ClosedRange<Double> = 0...200
    private static let ascentBounds: ClosedRange<Double> = 0...3000
    @State private var minDistanceKM: Double = distanceBounds.lowerBound
    @State private var maxDistanceKM: Double = distanceBounds.upperBound
    @State private var minAscentM: Double = ascentBounds.lowerBound
    @State private var maxAscentM: Double = ascentBounds.upperBound

    @State private var results: [Route] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var showResults = false
    @State private var searchTask: Task<Void, Never>?
    @State private var openRoute: Route?

    @State private var availableRegions: [String] = []
    @State private var selectedRegion: String?
    @State private var showRegionMap = false

    enum Section { case transport, difficulty, distance }

    private var transportKeys: [String] {
        selectedTransport.isEmpty
            ? Transport.allCases.map(\.dbKey)
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
            modeToggle

            if mode == .routes {
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
                        regionRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }

                resultsBar
            } else {
                PlaceExploreView()
            }
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .task {
            runSearch(debounced: false)
            availableRegions = (try? await RouteRepository.shared.fetchRegions()) ?? []
        }
        .onChange(of: selectedTransport) { _, _ in runSearch(debounced: false) }
        .onChange(of: difficultyIndex) { _, _ in runSearch(debounced: false) }
        .onChange(of: query) { _, _ in runSearch(debounced: true) }
        .onChange(of: minDistanceKM) { _, _ in runSearch(debounced: true) }
        .onChange(of: maxDistanceKM) { _, _ in runSearch(debounced: true) }
        .onChange(of: minAscentM) { _, _ in runSearch(debounced: true) }
        .onChange(of: maxAscentM) { _, _ in runSearch(debounced: true) }
        .onChange(of: selectedRegion) { _, _ in runSearch(debounced: false) }
        .fullScreenCover(isPresented: $showResults) {
            SearchResultsView(routes: results) { showResults = false }
        }
        .sheet(isPresented: $showRegionMap) {
            RegionMapPickerView(availableRegions: availableRegions) { picked in
                selectedRegion = picked
            }
        }
        .fullScreenCover(item: $openRoute) { route in
            RouteDetailFlow(route: route)
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
                    minKM: minDistanceKM,
                    maxKM: maxDistanceKM,
                    minAscentM: minAscentM > Self.ascentBounds.lowerBound ? minAscentM : nil,
                    maxAscentM: maxAscentM < Self.ascentBounds.upperBound ? maxAscentM : nil,
                    region: selectedRegion
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

    /// Routes (our own logged content) vs. Places (Apple's global places
    /// database, works in any city with zero content of our own) — one
    /// search surface, two very different data sources behind it.
    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeButton("Routes", .routes)
            modeButton("Places", .places)
        }
        .padding(4)
        .background(Capsule().fill(NTColor.milk(0.08)))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func modeButton(_ title: LocalizedStringKey, _ m: Mode) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(NTMotion.spring) { mode = m }
        } label: {
            Text(title)
                .font(NTFont.body(13.5, .semibold))
                .foregroundStyle(mode == m ? NTColor.pine : NTColor.milk(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(mode == m ? NTColor.milk : .clear))
        }
        .buttonStyle(.plain)
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
        // milkSurface (fixed) — the ink icon/text above needs a reliably
        // light backing, not the theme-reactive `milk`.
        .background(NTColor.milkSurface, in: Capsule())
    }

    /// Real live matches while typing — was hardcoded "Svaneti…" rows that
    /// looked tappable but did nothing at all when tapped, the exact kind
    /// of thing that makes search feel broken even when the query behind
    /// it works. Taps straight into the matching route now.
    private var suggestionsCard: some View {
        Group {
            if isSearching && !hasSearched {
                HStack(spacing: 10) {
                    ProgressView().tint(NTColor.ink)
                    Text("Searching…").font(NTFont.body(13.5, .medium)).foregroundStyle(NTColor.ink.opacity(0.6))
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(NTColor.milkSurface, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            } else if results.isEmpty {
                Text("No routes match \"\(query)\" yet.")
                    .font(NTFont.body(13.5, .medium))
                    .foregroundStyle(NTColor.ink.opacity(0.6))
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .background(NTColor.milkSurface, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.prefix(4).enumerated()), id: \.element.id) { index, route in
                        if index > 0 { Divider().overlay(NTColor.ink.opacity(0.08)) }
                        Button { openRoute = route } label: {
                            suggestionRow(route)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .background(NTColor.milkSurface, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
            }
        }
    }

    private func suggestionRow(_ route: Route) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill").font(.system(size: 15)).foregroundStyle(NTColor.accentDeep).frame(width: 18)
            Text(route.title.replacingOccurrences(of: "\n", with: " "))
                .font(NTFont.body(14.5, .medium))
                .foregroundStyle(NTColor.ink)
                .lineLimit(1)
            Spacer()
            Text(route.place).font(NTFont.mono(10, .semibold)).foregroundStyle(NTColor.ink.opacity(0.45)).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private enum Preset { case weekend4x4, hutToHut }

    /// Real filter shortcuts now — used to be plain `Text`, not even
    /// wrapped in a `Button`, so tapping did nothing at all.
    private var presetsRow: some View {
        HStack(spacing: 8) {
            presetChip("★ WEEKEND 4×4", filled: activePreset == .weekend4x4) { applyPreset(.weekend4x4) }
            presetChip("★ HUT-TO-HUT", filled: activePreset == .hutToHut) { applyPreset(.hutToHut) }
            Text("+ SAVE PRESET")
                .font(NTFont.mono(11, .semibold)).tracking(0.6)
                .foregroundStyle(NTColor.milk(0.5))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(NTColor.milk(0.22)))
        }
    }

    private var activePreset: Preset? {
        if selectedTransport == [.overland] && maxDistanceKM <= 100 { return .weekend4x4 }
        if selectedTransport == [.foot] && difficultyIndex <= 1 { return .hutToHut }
        return nil
    }

    private func applyPreset(_ preset: Preset) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(NTMotion.spring) {
            switch preset {
            case .weekend4x4:
                selectedTransport = [.overland]
                maxDistanceKM = min(maxDistanceKM, 100)
                minDistanceKM = Self.distanceBounds.lowerBound
            case .hutToHut:
                selectedTransport = [.foot]
                difficultyIndex = 1
            }
        }
    }

    private func presetChip(_ text: LocalizedStringKey, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(NTFont.mono(11, .semibold)).tracking(0.6)
                .foregroundStyle(filled ? Color(hex: 0xF1A47C) : NTColor.milk(0.7))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(filled ? NTColor.accent.opacity(0.18) : .clear))
                .overlay(Capsule().stroke(filled ? NTColor.accent.opacity(0.5) : NTColor.milk(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func disclosureSection<Content: View>(_ section: Section, title: LocalizedStringKey, trailing: LocalizedStringKey?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NTMotion.spring) {
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
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private var transportGrid: some View {
        HStack(spacing: 10) {
            ForEach(Transport.allCases, id: \.self) { t in
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
                        RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                            .fill(selected ? t.color : NTColor.milk(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
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
                        // A tap target bigger than the visible thumb, and a
                        // drag gesture on the whole track (not just the tiny
                        // thumb) — snaps to whichever third of the track the
                        // finger is over. The visible thumb used to have no
                        // gesture attached at all, so dragging it did nothing.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .offset(x: x - 22)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / w))
                            setDiff(fraction < 0.33 ? 0 : fraction < 0.67 ? 1 : 2)
                        }
                )
            }
            .frame(height: 44)

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
        withAnimation(NTMotion.spring) { difficultyIndex = i }
    }

    private var rangeRows: some View {
        VStack(alignment: .leading, spacing: 22) {
            rangeRow(
                label: "DISTANCE",
                value: "\(Int(minDistanceKM)) – \(Int(maxDistanceKM)) KM",
                low: $minDistanceKM, high: $maxDistanceKM, bounds: Self.distanceBounds, tint: NTColor.sage
            )
            rangeRow(
                label: "ASCENT",
                value: "\(Int(minAscentM)) – \(Int(maxAscentM)) M",
                low: $minAscentM, high: $maxAscentM, bounds: Self.ascentBounds, tint: NTColor.water
            )
        }
    }

    private func rangeRow(label: LocalizedStringKey, value: String, low: Binding<Double>, high: Binding<Double>, bounds: ClosedRange<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(label).font(NTFont.mono(11, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
                Spacer()
                Text(value).font(NTFont.mono(11, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
            }
            DualRangeSlider(low: low, high: high, bounds: bounds, tint: tint)
                .padding(.horizontal, 3)
        }
    }

    /// Real filter — populated from the actual distinct `place` values
    /// among published routes, not a hardcoded list.
    private var regionRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedRegion = nil
                } label: {
                    if selectedRegion == nil { Label("Any region", systemImage: "checkmark") }
                    else { Text("Any region") }
                }
                ForEach(availableRegions, id: \.self) { region in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedRegion = region
                    } label: {
                        if selectedRegion == region { Label(region, systemImage: "checkmark") }
                        else { Text(region) }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Region").font(NTFont.heading(17, .bold)).foregroundStyle(NTColor.milk)
                    Text(selectedRegion ?? "ANY").font(NTFont.mono(11, .semibold)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.5))
                }
                .padding(20)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
            }
            .disabled(availableRegions.isEmpty)

            // Real ask: pick a region by tapping anywhere on an actual
            // world map, not just a text list.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showRegionMap = true
            } label: {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(NTColor.milk)
                    .frame(width: 60, height: 60)
                    .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
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

import SwiftUI
import MapKit
import CoreLocation

/// Real place discovery — restaurants, cafés, hotels, fuel, camping,
/// attractions, shops — anywhere on Earth via Apple's own places database
/// (PlaceSearcher/MKLocalSearch). This is what makes "useful on day one in
/// any city" true without needing a single route logged there yet.
struct PlaceExploreView: View {
    @State private var searcher = PlaceSearcher()
    @State private var query = ""
    @State private var selectedCategory: PlaceCategory? = nil
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            categoryChips

            if searcher.authorizationDenied {
                deniedState
            } else if searcher.isSearching && searcher.results.isEmpty {
                ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 60)
            } else if searcher.results.isEmpty {
                emptyState
            } else {
                resultsMap
                resultsList
            }
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .onAppear { searcher.requestLocation() }
        .onChange(of: query) { _, _ in runSearch() }
        .onChange(of: searcher.locationUpdateCount) { _, _ in
            // Once we know where the user actually is, re-run whatever
            // search/category was already active so results center on them
            // instead of the whole-world default MKLocalSearch would use.
            if !query.isEmpty || selectedCategory != nil { runSearch() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(NTColor.ink)
            TextField("Search places anywhere…", text: $query)
                .font(NTFont.body(15.5, .medium))
                .foregroundStyle(NTColor.ink)
                .onSubmit { runSearch() }
            if !query.isEmpty {
                Button { query = ""; runSearch() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NTColor.ink)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(NTColor.ink.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(NTColor.milkSurface, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlaceCategory.allCases) { cat in
                    let selected = selectedCategory == cat
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCategory = selected ? nil : cat
                        runSearch()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon).font(.system(size: 11, weight: .semibold))
                            Text(cat.label).font(NTFont.mono(11, .semibold)).tracking(0.3)
                        }
                        .foregroundStyle(selected ? Color(hex: 0x231007) : NTColor.milk(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(selected ? NTColor.accent : NTColor.milk(0.08)))
                        .overlay(Capsule().stroke(NTColor.milk(0.16), lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var resultsMap: some View {
        Map(position: .constant(.region(resultsRegion))) {
            ForEach(Array(searcher.results.enumerated()), id: \.offset) { _, item in
                Annotation("", coordinate: item.placemark.coordinate) {
                    ZStack {
                        Circle().fill(NTColor.accent)
                        Image(systemName: icon(for: item))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                }
            }
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(Array(searcher.results.enumerated()), id: \.offset) { _, item in
                    resultRow(item)
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(NTColor.accent.opacity(0.18))
                    Image(systemName: icon(for: item)).font(.system(size: 16)).foregroundStyle(NTColor.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name ?? "Unnamed place").font(NTFont.body(14.5, .semibold)).foregroundStyle(NTColor.milk)
                    if let distance = distanceLabel(to: item) {
                        Text(distance).font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                    } else if let locality = item.placemark.locality {
                        Text(locality).font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(NTColor.milk(0.5))
            }
            .padding(14)
            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map").font(.system(size: 32, weight: .light)).foregroundStyle(NTColor.milk(0.35))
            Text(searcher.currentLocation == nil ? "Finding your location…" : "Search or pick a category")
                .font(NTFont.body(14, .medium))
                .foregroundStyle(NTColor.milk(0.55))
            Text("Restaurants, hotels, fuel, camping and more — anywhere in the world, powered by Apple's own places data.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var deniedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.slash.fill").font(.system(size: 28)).foregroundStyle(Color(hex: 0xE58272))
            Text("Location access needed").font(NTFont.body(14.5, .semibold))
            Text("Enable it in Settings to search places near you — you can still search by name without it.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    /// Real per-place icon from Apple's own category for that result, not a
    /// blanket guess — falls back to the active category filter (if any),
    /// then a plain pin.
    private func icon(for item: MKMapItem) -> String {
        if let mkCat = item.pointOfInterestCategory,
           let match = PlaceCategory.allCases.first(where: { $0.mkCategory == mkCat }) {
            return match.icon
        }
        return selectedCategory?.icon ?? "mappin"
    }

    private func runSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await searcher.search(query: query, category: selectedCategory?.mkCategory)
        }
    }

    private func distanceLabel(to item: MKMapItem) -> String? {
        guard let current = searcher.currentLocation else { return nil }
        let distanceM = current.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
        if distanceM < 1000 { return "\(Int(distanceM)) M AWAY" }
        return String(format: "%.1f KM AWAY", distanceM / 1000)
    }

    private var resultsRegion: MKCoordinateRegion {
        let coords = searcher.results.map(\.placemark.coordinate)
        guard !coords.isEmpty else {
            let center = searcher.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 0.02), longitudeDelta: max((maxLng - minLng) * 1.6, 0.02))
        )
    }
}

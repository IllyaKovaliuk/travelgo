import SwiftUI
import MapboxMaps
import CoreLocation

/// One real country pin — where routes actually exist. Coordinate is the
/// centroid of that country's routes' real recorded start points (each
/// route's `trackPoints.first`), not a country-outline centroid — cheap,
/// honest, and always lands somewhere a route actually starts. Carries a
/// real cover photo when one of that country's routes has one, for the
/// circular photo-pin look (falls back to a plain icon otherwise, not a
/// fake photo).
struct CountryRoutePin: Identifiable {
    let id: String // country name
    let coordinate: CLLocationCoordinate2D
    let coverImageUrl: String?
    /// (place, count) pairs, most routes first — a country pin can cover
    /// several distinct `place` regions (e.g. several valleys in one
    /// country), and the existing region filter only takes one `place` at
    /// a time, so tapping a pin lists them rather than guessing which one.
    let placeCounts: [(place: String, count: Int)]
    var totalCount: Int { placeCounts.reduce(0) { $0 + $1.count } }
}

/// Tap anywhere on a real 3D world globe to filter Search by region —
/// reverse-geocodes the tapped point (Apple's own `CLGeocoder`, works
/// anywhere on Earth) and matches it against the real distinct `place`
/// values among published routes. Real numbered photo-pins show per-country
/// route counts up front too, geocoded from every published route's real
/// start coordinate. Runs on Mapbox (Standard Satellite — real 3D terrain +
/// satellite imagery, adaptive globe projection at low zoom) instead of
/// flat MapKit, at the user's explicit request for something that actually
/// looks premium. Most of the globe still won't have a pin, honestly, since
/// there are only a handful of routes logged so far — that's real data
/// sparsity, not a broken feature.
struct RegionMapPickerView: View {
    let availableRegions: [String]
    var onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 15), zoom: 1.4, bearing: 0, pitch: 15
    )
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var isResolving = false
    @State private var resolvedPlace: String?
    @State private var matchedRegion: String?
    @State private var noMatchMessage: String?
    @State private var countryPins: [CountryRoutePin] = []
    @State private var selectedCountryPin: CountryRoutePin?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(viewport: $viewport) {
                    ForEvery(countryPins) { pin in
                        MapViewAnnotation(coordinate: pin.coordinate) {
                            countBadge(pin)
                        }
                    }
                    if let pinCoordinate {
                        MapViewAnnotation(coordinate: pinCoordinate) {
                            tapMarker
                        }
                    }
                }
                .mapStyle(.standardSatellite)
                .onMapTapGesture { context in
                    handleTap(context.coordinate)
                }
                .ignoresSafeArea(edges: .bottom)

                statusCard
            }
            .navigationTitle("Pick a region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear") { onSelect(nil); dismiss() }
                        .disabled(pinCoordinate == nil)
                }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await loadCountryPins() }
    }

    /// The plain "you tapped here" marker — separate from the real
    /// photo-count pins, so it's obvious which one is your tap vs. real data.
    private var tapMarker: some View {
        ZStack {
            Circle().fill(matchedRegion != nil ? NTColor.accent : NTColor.milk(0.6))
            Image(systemName: "mappin").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
    }

    private func countBadge(_ pin: CountryRoutePin) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            pinCoordinate = nil
            matchedRegion = nil
            noMatchMessage = nil
            selectedCountryPin = pin
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let urlString = pin.coverImageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                pinPlaceholder
                            }
                        }
                    } else {
                        pinPlaceholder
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                Text("\(pin.totalCount)")
                    .font(NTFont.mono(10, .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(NTColor.accent))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: 5, y: 5)
            }
        }
        .buttonStyle(.plain)
    }

    /// Honest fallback for a country with no route cover photo yet — a
    /// plain tinted circle with a pin glyph, not a fake photo.
    private var pinPlaceholder: some View {
        ZStack {
            NTColor.pineRaised
            Image(systemName: "mappin").font(.system(size: 16, weight: .semibold)).foregroundStyle(NTColor.milk(0.75))
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pin = selectedCountryPin {
                Text("\(pin.id.uppercased()) · \(pin.totalCount) ROUTE\(pin.totalCount == 1 ? "" : "S")")
                    .font(NTFont.mono(11, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pin.placeCounts, id: \.place) { item in
                            Button {
                                onSelect(item.place)
                                dismiss()
                            } label: {
                                Text("\(item.place) · \(item.count)")
                                    .font(NTFont.body(13, .semibold))
                                    .foregroundStyle(Color(hex: 0x231007))
                                    .padding(.horizontal, 16)
                                    .frame(height: 42)
                                    .background(NTColor.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if pinCoordinate == nil {
                Text("Tap anywhere on the globe — any country, any spot on Earth. Numbered photo pins already show where routes exist.")
                    .font(NTFont.body(13.5, .medium))
                    .foregroundStyle(NTColor.milk(0.7))
            } else if isResolving {
                HStack(spacing: 10) {
                    ProgressView().tint(NTColor.milk)
                    Text("Finding out where that is…").font(NTFont.body(13.5, .medium)).foregroundStyle(NTColor.milk(0.7))
                }
            } else if let matchedRegion {
                VStack(alignment: .leading, spacing: 10) {
                    Text(resolvedPlace ?? matchedRegion).font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.milk)
                    Button {
                        onSelect(matchedRegion)
                        dismiss()
                    } label: {
                        Text("Filter to \(matchedRegion)")
                            .font(NTFont.body(14, .semibold))
                            .foregroundStyle(Color(hex: 0x231007))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(NTColor.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else if let noMatchMessage {
                Text(noMatchMessage)
                    .font(NTFont.body(13.5, .medium))
                    .foregroundStyle(NTColor.milk(0.6))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.001), in: Rectangle()) // keeps taps below from passing through
        .background(NTColor.pine.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(16)
    }

    /// Geocodes every published route's real recorded start point to a
    /// country and groups — a client-side aggregation, not a backend
    /// feature, since routes don't store a structured country column. Fine
    /// at the current real data volume; would want server-side caching if
    /// the route count grows a lot.
    private func loadCountryPins() async {
        guard let locations = try? await RouteRepository.shared.fetchRouteLocations() else { return }
        let geocoder = CLGeocoder()
        var byCountry: [String: [RouteRepository.RouteLocation]] = [:]
        for location in locations {
            let placemarks = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            )
            guard let country = placemarks?.first?.country else { continue }
            byCountry[country, default: []].append(location)
        }
        countryPins = byCountry.map { country, locs in
            let centroid = CLLocationCoordinate2D(
                latitude: locs.map(\.coordinate.latitude).reduce(0, +) / Double(locs.count),
                longitude: locs.map(\.coordinate.longitude).reduce(0, +) / Double(locs.count)
            )
            var counts: [String: Int] = [:]
            for loc in locs { counts[loc.place, default: 0] += 1 }
            let placeCounts = counts.map { (place: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
            let cover = locs.first(where: { $0.coverImageUrl != nil })?.coverImageUrl
            return CountryRoutePin(id: country, coordinate: centroid, coverImageUrl: cover, placeCounts: placeCounts)
        }
    }

    private func handleTap(_ coordinate: CLLocationCoordinate2D) {
        pinCoordinate = coordinate
        isResolving = true
        resolvedPlace = nil
        matchedRegion = nil
        noMatchMessage = nil
        selectedCountryPin = nil
        Task {
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            let placemark = placemarks?.first
            let country = placemark?.country
            let adminArea = placemark?.administrativeArea
            let locality = placemark?.locality

            resolvedPlace = [locality, adminArea ?? country].compactMap { $0 }.joined(separator: ", ").isEmpty
                ? country : [locality, adminArea ?? country].compactMap { $0 }.joined(separator: ", ")
            isResolving = false

            guard let country else {
                noMatchMessage = "That's open water — try land."
                return
            }
            let match = availableRegions.first { place in
                place.localizedCaseInsensitiveContains(country)
                    || (adminArea.map { place.localizedCaseInsensitiveContains($0) } ?? false)
                    || (locality.map { place.localizedCaseInsensitiveContains($0) } ?? false)
            }
            if let match {
                matchedRegion = match
            } else {
                noMatchMessage = "No routes logged in \(country) yet — the real region list only covers where people have actually published so far."
            }
        }
    }
}

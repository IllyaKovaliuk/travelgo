import SwiftUI
import MapKit
import CoreLocation

/// Tap anywhere on a real world map to filter Search by region — reverse-
/// geocodes the tapped point (Apple's own `CLGeocoder`, works anywhere on
/// Earth) and matches it against the real distinct `place` values among
/// published routes. Most of the globe won't match anything yet, honestly,
/// since there are only a handful of routes logged so far — that's real
/// data sparsity, not a broken feature.
struct RegionMapPickerView: View {
    let availableRegions: [String]
    var onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 15),
                            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140))
    )
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var isResolving = false
    @State private var resolvedPlace: String?
    @State private var matchedRegion: String?
    @State private var noMatchMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let pinCoordinate {
                            Marker(resolvedPlace ?? "…", coordinate: pinCoordinate)
                                .tint(matchedRegion != nil ? NTColor.accent : NTColor.milk(0.6))
                        }
                    }
                    .mapStyle(.standard)
                    .onTapGesture { screenPoint in
                        guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                        handleTap(coordinate)
                    }
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
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pinCoordinate == nil {
                Text("Tap anywhere on the map — any country, any spot on Earth.")
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

    private func handleTap(_ coordinate: CLLocationCoordinate2D) {
        pinCoordinate = coordinate
        isResolving = true
        resolvedPlace = nil
        matchedRegion = nil
        noMatchMessage = nil
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

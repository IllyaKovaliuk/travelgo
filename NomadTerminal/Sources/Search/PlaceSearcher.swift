import Foundation
import MapKit
import CoreLocation
import Observation

/// Real place search, anywhere on Earth — backed by Apple's own global
/// places database via MKLocalSearch, not anything we'd have to build or
/// crowdsource ourselves. This is what makes "useful in any city, day one"
/// honest instead of a promise with nothing behind it: a restaurant/hotel/
/// attraction search that already works in Kyiv, New York, Kathmandu, or
/// anywhere else, with zero user-generated content required.
@MainActor
@Observable
final class PlaceSearcher: NSObject {
    private(set) var results: [MKMapItem] = []
    private(set) var isSearching = false
    private(set) var currentLocation: CLLocation?
    /// Bumped every time `currentLocation` updates — plain `Int`, so
    /// SwiftUI's `.onChange` can observe it (`CLLocation` itself isn't
    /// `Equatable`).
    private(set) var locationUpdateCount = 0
    var authorizationDenied = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            manager.requestLocation()
        }
    }

    /// Text query and/or a category filter (e.g. restaurants only),
    /// centered on the last known location when we have one — otherwise
    /// MKLocalSearch just searches broadly by query text.
    func search(query: String, category: MKPointOfInterestCategory? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || category != nil else {
            results = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        if !trimmed.isEmpty {
            request.naturalLanguageQuery = trimmed
        }
        if let category {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
        }
        if let loc = currentLocation {
            request.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
        } catch {
            results = []
        }
    }
}

extension PlaceSearcher: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.authorizationDenied = false
                manager.requestLocation()
            case .denied, .restricted:
                self.authorizationDenied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.currentLocation = locations.last
            self.locationUpdateCount += 1
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient — a stale/last-known location is fine for centering search.
    }
}

/// A curated set spanning both audiences on purpose — fuel/camping serve
/// overlanders, food/hotels/attractions/shops serve city travelers. One
/// feature, not two apps.
enum PlaceCategory: String, CaseIterable, Identifiable {
    case food, cafe, hotel, fuel, camping, attractions, shops

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: return "Food"
        case .cafe: return "Cafés"
        case .hotel: return "Hotels"
        case .fuel: return "Fuel"
        case .camping: return "Camping"
        case .attractions: return "Attractions"
        case .shops: return "Shops"
        }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .hotel: return "bed.double.fill"
        case .fuel: return "fuelpump.fill"
        case .camping: return "tent.fill"
        case .attractions: return "building.columns.fill"
        case .shops: return "bag.fill"
        }
    }

    var mkCategory: MKPointOfInterestCategory {
        switch self {
        case .food: return .restaurant
        case .cafe: return .cafe
        case .hotel: return .hotel
        case .fuel: return .gasStation
        case .camping: return .campground
        case .attractions: return .museum
        case .shops: return .store
        }
    }
}

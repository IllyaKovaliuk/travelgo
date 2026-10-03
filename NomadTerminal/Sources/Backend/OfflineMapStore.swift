import Foundation
import CoreLocation
import MapboxMaps

enum OfflineMapError: LocalizedError {
    case invalidRegion
    var errorDescription: String? { "Couldn't prepare this route's map for offline use." }
}

/// Real offline map TILES — not the old "offline" that only ever cached a
/// route's own JSON plus a flat static PNG snapshot (`OfflineRouteStore`)
/// while the actual live, interactive `Map` on Route Detail / Compass still
/// needed real network for every tile the moment you opened it. This uses
/// Mapbox's own `OfflineManager`/`TileStore` to pre-download genuine style +
/// tile data for a route's area, into `TileStore.default` — the exact same
/// store every `Map(viewport:)` in this app already reads from with zero
/// extra wiring, so once a region lands here, Route Detail's map, the full
/// map, and Compass navigation all serve it automatically with no signal.
///
/// Downloads BOTH map styles Compass's 2D/3D toggle can show
/// (`.standard`/`.standardSatellite` — see `CompassView.mapStyle`), because
/// a route saved offline in 2D shouldn't go blank the moment someone flips
/// to 3D with no signal.
///
/// `@MainActor`, not `actor` — found the hard way (real device/simulator
/// testing, not a guess): Mapbox's `OfflineManager`/`TileStore` objects
/// latch onto whichever OS thread first touches them and assert
/// ("called from a thread that is not owning the object") on every call
/// after that if it lands on a different one. A plain Swift `actor` does
/// NOT pin its isolated code to one real OS thread between suspension
/// points, so `offlineManager.loadStylePack(...)` and
/// `tileStore.loadTileRegion(...)` were silently erroring on the SDK's
/// internal thread check, which starves their completion closures and
/// leaks the wrapping continuation forever — confirmed in the device log
/// (`SWIFT TASK CONTINUATION MISUSE: ... leaked its continuation without
/// resuming it`) during a real download that hung indefinitely. The real
/// main thread is the one consistent thread every other Mapbox call in
/// this app (the live `Map` view itself included) already runs on, so
/// `@MainActor` is what actually matches the SDK's own requirement.
@MainActor
final class OfflineMapStore {
    static let shared = OfflineMapStore()

    private let offlineManager = OfflineManager()
    private let tileStore = TileStore.default

    /// 10 (whole-route overview) through 16 — NOT 17, even though
    /// `CompassView`'s live `.followPuck(zoom: 17, ...)` goes one level
    /// past this: found the hard way (a real download that hung forever,
    /// not a guess) that zoom 17 sits above this style's own documented
    /// offline batch tiers (Mapbox's own docs: "Streets detail: 15-16" is
    /// the highest tier that exists), and requesting it made the
    /// `hd-road-v1-bounded` tileset's loader fail every resource in that
    /// batch with a real HTTP 400 and retry it forever, which never let
    /// the region finish. Capping at 16 is a one-level overzoom while
    /// live-navigating at 17 with no signal — normal, visually fine
    /// Mapbox behavior, not a missing-data gap.
    private let zoomRange: ClosedRange<UInt8> = 10...16
    private let trackedRouteIdsKey = "offlineMapRegions.routeIds"

    private static func regionId(_ routeId: String) -> String { "route-\(routeId)" }

    private var trackedRouteIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: trackedRouteIdsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: trackedRouteIdsKey) }
    }

    func isDownloaded(routeId: String) -> Bool {
        trackedRouteIds.contains(routeId)
    }

    /// How many routes currently have real map tiles on disk — backs
    /// Settings' offline-storage row; deliberately a count, not a fabricated
    /// byte figure the SDK doesn't cleanly expose for a *combined* multi-
    /// style tile region the way `OfflineRouteStore.diskUsageBytes()` can
    /// for its own plain files.
    func downloadedRegionCount() -> Int { trackedRouteIds.count }

    /// Downloads real tiles for the given coordinates' area. `onProgress`
    /// is called repeatedly with 0...1, driven by the tile region's own
    /// real `completedResourceCount`/`requiredResourceCount` — the slow,
    /// dominant part of the download; the two style packs (glyphs/sprites)
    /// are comparatively tiny and loaded before it starts.
    func download(
        routeId: String,
        coordinates: [CLLocationCoordinate2D],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard !coordinates.isEmpty else { return }

        let polygon = Polygon([Self.paddedRing(coordinates)])
        let styles: [StyleURI] = [.standard, .standardSatellite]
        let descriptors = styles.map { style in
            offlineManager.createTilesetDescriptor(
                for: TilesetDescriptorOptions(styleURI: style, zoomRange: zoomRange, tilesets: nil)
            )
        }
        guard let loadOptions = TileRegionLoadOptions(
            geometry: .polygon(polygon),
            descriptors: descriptors,
            metadata: ["routeId": routeId],
            acceptExpired: true
        ) else {
            throw OfflineMapError.invalidRegion
        }

        // Style packs (glyphs/sprites) for both styles first — shared
        // across every downloaded route, so this is a one-time cost after
        // the first route, not per-route.
        for style in styles {
            try await loadStylePack(style, routeId: routeId)
        }

        try await loadTileRegion(routeId: routeId, loadOptions: loadOptions, onProgress: onProgress)

        var ids = trackedRouteIds
        ids.insert(routeId)
        trackedRouteIds = ids
    }

    /// Only drops this route's own tile region — deliberately does NOT
    /// touch the shared style packs, since other downloaded routes still
    /// need them. `TileStore`'s own disk-quota eviction (ambient cache)
    /// handles actually freeing space over time; this just un-pins this
    /// route's tiles from "always keep."
    func remove(routeId: String) {
        tileStore.removeTileRegion(forId: Self.regionId(routeId))
        var ids = trackedRouteIds
        ids.remove(routeId)
        trackedRouteIds = ids
    }

    private func loadStylePack(_ style: StyleURI, routeId: String) async throws {
        guard let options = StylePackLoadOptions(glyphsRasterizationMode: nil, metadata: ["routeId": routeId]) else {
            throw OfflineMapError.invalidRegion
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            offlineManager.loadStylePack(for: style, loadOptions: options) { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadTileRegion(
        routeId: String,
        loadOptions: TileRegionLoadOptions,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            tileStore.loadTileRegion(forId: Self.regionId(routeId), loadOptions: loadOptions) { progress in
                let fraction = progress.requiredResourceCount > 0
                    ? Double(progress.completedResourceCount) / Double(progress.requiredResourceCount)
                    : 0
                onProgress(min(1, max(0, fraction)))
            } completion: { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A padded bounding rectangle around every coordinate — simple and
    /// robust rather than a hand-rolled line-buffer polygon (easy to get
    /// subtly wrong), at the cost of downloading a bit more than the exact
    /// corridor for a long, diagonal route. 25% padding on each side so
    /// panning near the route's edges during live navigation doesn't fall
    /// straight off the downloaded area; a 0.01°-ish floor (~1km) keeps a
    /// short or single-point route from producing a degenerate region.
    private static func paddedRing(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let lats = coordinates.map(\.latitude), lngs = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let padLat = max((maxLat - minLat) * 0.25, 0.01)
        let padLng = max((maxLng - minLng) * 0.25, 0.01)
        let south = minLat - padLat, north = maxLat + padLat
        let west = minLng - padLng, east = maxLng + padLng
        return [
            CLLocationCoordinate2D(latitude: south, longitude: west),
            CLLocationCoordinate2D(latitude: south, longitude: east),
            CLLocationCoordinate2D(latitude: north, longitude: east),
            CLLocationCoordinate2D(latitude: north, longitude: west),
            CLLocationCoordinate2D(latitude: south, longitude: west),
        ]
    }
}

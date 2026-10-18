import Foundation
import MapKit
import Network
import UIKit

enum OfflineDownloadError: LocalizedError {
    case wifiRequired
    var errorDescription: String? {
        "Wi-Fi required — turn off \"Download over Wi-Fi only\" in Settings, or connect to Wi-Fi."
    }
}

/// Makes "Save offline" actually save something. Caches the exact `RouteDTO`
/// the server sent (so decoding it later reuses the same `toRoute()` mapper
/// and can never drift from the live shape) plus, for routes with a real
/// recorded track, a static map snapshot — because a live MapKit `Map` still
/// needs network to fetch tiles even once you already have the coordinates.
actor OfflineRouteStore {
    static let shared = OfflineRouteStore()

    private var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("OfflineRoutes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func jsonURL(_ routeId: String) -> URL { directory.appendingPathComponent("\(routeId).json") }
    private func imageURL(_ routeId: String) -> URL { directory.appendingPathComponent("\(routeId).png") }

    /// Fetches the route fresh, writes its DTO to disk, and — if it has a
    /// real recorded polyline — renders and saves a static map snapshot so
    /// the route detail header has something to show with zero connectivity.
    /// `wifiOnly` actually enforces Settings' "Download over Wi-Fi only"
    /// toggle now (was previously decorative — the toggle existed, nothing
    /// downstream ever read it) via a real `NWPathMonitor` check of the
    /// current connection, not just a Reachability-style guess.
    @discardableResult
    func download(routeId: String, wifiOnly: Bool = false) async throws -> Route {
        if wifiOnly {
            let onWifi = await currentPathIsWiFi()
            guard onWifi else { throw OfflineDownloadError.wifiRequired }
        }
        let dto = try await RouteRepository.shared.fetchRouteDTO(id: routeId)
        let data = try JSONEncoder().encode(dto)
        try data.write(to: jsonURL(routeId), options: .atomic)

        let route = dto.toRoute()
        if route.detail.trackPoints.count > 1 {
            if let image = try? await snapshot(for: route.detail.trackPoints, segments: route.detail.segments), let png = image.pngData() {
                try? png.write(to: imageURL(routeId), options: .atomic)
            }
        }
        return route
    }

    func remove(routeId: String) {
        try? FileManager.default.removeItem(at: jsonURL(routeId))
        try? FileManager.default.removeItem(at: imageURL(routeId))
    }

    func isDownloaded(routeId: String) -> Bool {
        FileManager.default.fileExists(atPath: jsonURL(routeId).path)
    }

    /// Real total bytes on disk under `OfflineRoutes` — backs Settings'
    /// "Offline storage" row, which used to just show a hardcoded fake
    /// "2.4 / 8 GB" with nothing behind either number. There's no real
    /// storage quota anywhere in this app, so this reports actual usage
    /// only, not a fake cap.
    func diskUsageBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    /// Reconstructs a `Route` from whatever's cached on disk — no network.
    func loadRoute(routeId: String) -> Route? {
        guard let data = try? Data(contentsOf: jsonURL(routeId)) else { return nil }
        guard let dto = try? JSONDecoder().decode(RouteDTO.self, from: data) else { return nil }
        return dto.toRoute()
    }

    /// Every route with a local copy, newest cache first isn't tracked —
    /// order is whatever the filesystem returns, which is fine for a
    /// "your downloads" list of a handful of routes.
    func allDownloadedRoutes() -> [Route] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode(RouteDTO.self, from: $0) }
            .map { $0.toRoute() }
    }

    /// The cached static snapshot for a route's map header, if one was
    /// rendered at download time.
    func snapshotImage(routeId: String) -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL(routeId)) else { return nil }
        return UIImage(data: data)
    }

    /// One-shot real read of the current network path — resumes on the
    /// first callback `NWPathMonitor` delivers (it fires immediately with
    /// the already-known current path, then again on every real change;
    /// only the first one is needed here) and cancels itself right after.
    private func currentPathIsWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            // `resumed` is only ever touched from `pathUpdateHandler`, and
            // that handler only ever runs serially on this one dedicated
            // queue — real exclusion, just not one the compiler can see
            // through a plain `Bool` capture, hence `nonisolated(unsafe)`.
            nonisolated(unsafe) var resumed = false
            let queue = DispatchQueue(label: "io.nomadterminal.pathmonitor")
            monitor.pathUpdateHandler = { path in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: path.usesInterfaceType(.wifi))
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }

    /// This is the *other* real map renderer in this app, and the one
    /// easy to forget about: `RouteMapHeader` shows this cached PNG
    /// instead of its own live Mapbox map whenever one exists (offline
    /// viewing needs *something* to show with zero connectivity, and a
    /// live `Map` still needs network for tiles even with the coordinates
    /// already on hand) — so a route that's ever been "Saved offline"
    /// keeps showing whatever this function drew at that moment, frozen,
    /// until the next re-download. It used to draw one plain raw-point
    /// line with no relation to `MapSegmentStretch`'s styling at all
    /// (predating that work); now it runs the exact same simplify-then-
    /// smooth-then-case pipeline, so "saved offline" doesn't quietly look
    /// like an old build.
    private func snapshot(for points: [TrackPoint], segments: [RouteDetailInfo.Segment]) async throws -> UIImage {
        let lats = points.map(\.lat), lngs = points.map(\.lng)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.5, 0.01)
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 800, height: 640)
        options.mapType = .standard
        options.showsBuildings = true

        let snapshot = try await MKMapSnapshotter(options: options).start()
        let stretches = MapSegmentStretch.compute(trackPoints: points, segments: segments)
        return await MainActor.run { drawTrack(points.map(\.coordinate), stretches: stretches, on: snapshot) }
    }

    @MainActor
    private func drawTrack(_ rawCoordinates: [CLLocationCoordinate2D], stretches: [MapSegmentStretch], on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            func stroke(_ coordinates: [CLLocationCoordinate2D], color: UIColor, width: CGFloat) {
                guard coordinates.count > 1 else { return }
                let path = UIBezierPath()
                for (i, coordinate) in coordinates.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                color.setStroke()
                path.stroke()
            }

            let casing = UIColor.white.withAlphaComponent(0.95)
            if stretches.isEmpty {
                // No segments to color per-transport — same real
                // simplify-then-smooth pass the live map applies, still
                // cased for the same depth, just one color.
                let smoothed = MapSegmentStretch.smoothed(MapSegmentStretch.simplified(rawCoordinates))
                stroke(smoothed, color: casing, width: 9)
                stroke(smoothed, color: UIColor(NTColor.accent), width: 6)
            } else {
                // Casing pass first (under every segment), then each
                // segment's real transport-tinted line on top — the same
                // two-pass technique `lineBorderColor`/`lineBorderWidth`
                // gives the live Mapbox line for free on a single layer;
                // a static image has to actually draw it as two passes.
                for stretch in stretches { stroke(stretch.coordinates, color: casing, width: 9) }
                for stretch in stretches { stroke(stretch.coordinates, color: UIColor(stretch.tint), width: 6) }
            }
        }
    }
}

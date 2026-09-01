import Foundation
import MapKit
import UIKit

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
    @discardableResult
    func download(routeId: String) async throws -> Route {
        let dto = try await RouteRepository.shared.fetchRouteDTO(id: routeId)
        let data = try JSONEncoder().encode(dto)
        try data.write(to: jsonURL(routeId), options: .atomic)

        let route = dto.toRoute()
        if route.detail.trackPoints.count > 1 {
            if let image = try? await snapshot(for: route.detail.trackPoints), let png = image.pngData() {
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

    private func snapshot(for points: [TrackPoint]) async throws -> UIImage {
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
        return await MainActor.run { drawTrack(points.map(\.coordinate), on: snapshot) }
    }

    @MainActor
    private func drawTrack(_ coordinates: [CLLocationCoordinate2D], on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, coordinate) in coordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.white.withAlphaComponent(0.95).setStroke()
            path.stroke()
        }
    }
}

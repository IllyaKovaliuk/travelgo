import SwiftUI

/// Wraps Route Detail + the Compass mode it can push to, so callers just
/// present one `RouteDetailFlow` and don't need to know about the nested
/// navigation.
struct RouteDetailFlow: View {
    let route: Route
    @State private var showCompass = false

    var body: some View {
        RouteDetailView(route: route, onNavigate: { showCompass = true })
            .fullScreenCover(isPresented: $showCompass) {
                CompassView(
                    waypointName: route.detail.segments.last?.name ?? "Route end",
                    waypointIndex: min(3, route.detail.segments.count),
                    waypointTotal: max(route.detail.segments.count, 1),
                    targetCoordinate: route.detail.trackPoints.last?.coordinate,
                    onClose: { showCompass = false }
                )
            }
    }
}

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
                    routeId: route.id,
                    segments: route.detail.segments,
                    trackPoints: route.detail.trackPoints,
                    pois: route.detail.pois,
                    onClose: { showCompass = false }
                )
            }
    }
}

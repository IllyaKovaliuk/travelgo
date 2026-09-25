import SwiftUI

/// Wraps Route Detail + the navigation mode it can push to, so callers
/// just present one `RouteDetailFlow` and don't need to know about the
/// nested navigation.
///
/// "Navigate" now opens `NavigationModeView` (the Waze-style 3D map) —
/// used to open the plain compass dial directly. That dial isn't gone,
/// it's one tap away from inside Navigation Mode itself (its own
/// compass-icon button), for anyone who still wants it.
struct RouteDetailFlow: View {
    let route: Route
    @State private var showNavigation = false

    var body: some View {
        RouteDetailView(route: route, onNavigate: { showNavigation = true })
            .fullScreenCover(isPresented: $showNavigation) {
                NavigationModeView(route: route, onClose: { showNavigation = false })
            }
    }
}

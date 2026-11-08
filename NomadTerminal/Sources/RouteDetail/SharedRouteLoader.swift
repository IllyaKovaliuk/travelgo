import SwiftUI

/// Opens a route from a shared link: fetches it by id, then shows the normal
/// Route Detail. Handles the not-found / offline cases instead of leaving a
/// spinner (a route can be unpublished, hidden or deleted after it was shared).
struct SharedRouteLoader: View {
    let routeID: String
    var onClose: () -> Void

    @State private var route: Route?
    @State private var failed = false

    var body: some View {
        Group {
            if let route {
                RouteDetailFlow(route: route)
            } else {
                ZStack {
                    NTColor.pine.ignoresSafeArea()
                    VStack(spacing: 16) {
                        if failed {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(NTColor.milk(0.6))
                            Text("This route isn't available")
                                .font(NTFont.body(16, .semibold)).foregroundStyle(NTColor.milk)
                            Text("It may have been removed, or you're offline.")
                                .font(NTFont.body(13, .light)).foregroundStyle(NTColor.milk(0.6))
                            NTGhostButton(title: "Close", action: onClose)
                        } else {
                            ProgressView().tint(NTColor.milk)
                        }
                    }
                    .padding(30)
                }
            }
        }
        .task {
            do {
                route = try await RouteRepository.shared.fetchRouteDTO(id: routeID).toRoute()
            } catch {
                failed = true
            }
        }
    }
}

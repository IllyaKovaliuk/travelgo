import SwiftUI

struct NewRouteDraft {
    var title: String = ""
    var place: String = ""
    var transport: Transport = .overland
    var difficulty: Route.Difficulty = .hard
    var distanceKM: String = ""
    var ascentM: Double = 0
    /// The real recorded GPS polyline from `RecordTrackView` — empty if the
    /// user backed out of recording (no path to skip straight to details yet).
    var trackPoints: [TrackPoint] = []
}

/// Coordinates the whole "log a route" flow — start → record → details →
/// publish — as pushes on one NavigationStack inside a single modal.
struct LogRouteFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var draft = NewRouteDraft()

    enum Step: Hashable { case record, details, publish }

    var body: some View {
        NavigationStack(path: $path) {
            LogRouteStartView(
                onRecord: { path.append(.record) },
                onClose: { dismiss() }
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .record:
                    RecordTrackView(onFinish: { distanceKM, ascentM, points in
                        draft.distanceKM = String(format: "%.2f", distanceKM)
                        draft.ascentM = ascentM
                        draft.trackPoints = points
                        path.append(.details)
                    })
                case .details:
                    RouteUploadDetailsView(draft: $draft, onContinue: { path.append(.publish) })
                case .publish:
                    RouteReviewPublishView(draft: draft, onDone: { dismiss() })
                }
            }
        }
        .tint(NTColor.milk)
        .preferredColorScheme(.dark)
    }
}

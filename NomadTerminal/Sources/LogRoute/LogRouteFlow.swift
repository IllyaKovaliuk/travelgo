import SwiftUI

struct NewRouteDraft {
    var title: String = ""
    var place: String = ""
    var transport: Transport = .overland
    var difficulty: Route.Difficulty = .hard
    var distanceKM: String = ""
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
                    RecordTrackView(onFinish: { path.append(.details) })
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

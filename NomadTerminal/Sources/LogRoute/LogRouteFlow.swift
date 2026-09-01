import SwiftUI

struct DraftPOI: Identifiable {
    let id = UUID()
    var lat: Double
    var lng: Double
    var category: POICategory
    var title: String
    var note: String = ""
}

struct DraftSegment: Identifiable {
    let id = UUID()
    var transport: Transport = .foot
    var name: String = ""
    var distanceKM: String = ""
}

struct DraftRequirement: Identifiable {
    let id = UUID()
    var category: RequirementCategory = .gear
    var title: String = ""
    var subtitle: String = ""
}

/// A small fixed set instead of free icon-picking — keeps the "add a
/// requirement" form to three fields instead of a full icon browser.
enum RequirementCategory: String, CaseIterable {
    case vehicle = "Vehicle", water = "Water", weather = "Weather", permit = "Permit", gear = "Gear"

    var icon: String {
        switch self {
        case .vehicle: return "car.side"
        case .water: return "drop.fill"
        case .weather: return "cloud.rain.fill"
        case .permit: return "doc.text.fill"
        case .gear: return "backpack.fill"
        }
    }

    var tint: Color {
        switch self {
        case .vehicle: return NTColor.accentDeep
        case .water: return NTColor.water
        case .weather: return NTColor.hard
        case .permit: return NTColor.sage
        case .gear: return NTColor.gold
        }
    }

    /// Matches the `tint` colors above — stored alongside a published
    /// requirement so it renders with the same color on Route Detail.
    var dbHex: String {
        switch self {
        case .vehicle: return "#C2551F"
        case .water: return "#3E92CC"
        case .weather: return "#B33A2B"
        case .permit: return "#5FA777"
        case .gear: return "#E0A458"
        }
    }
}

struct NewRouteDraft {
    var title: String = ""
    var place: String = ""
    var transport: Transport = .overland
    var difficulty: Route.Difficulty = .hard
    var distanceKM: String = ""
    var ascentM: Double = 0
    var highPointM: Double = 0
    /// The real recorded GPS polyline from `RecordTrackView` — empty if the
    /// user backed out of recording (no path to skip straight to details yet).
    var trackPoints: [TrackPoint] = []
    var season: String = ""
    var duration: String = ""
    var quote: String = ""
    var segments: [DraftSegment] = []
    var requirements: [DraftRequirement] = []
    var pois: [DraftPOI] = []
    var coverImageUrl: String? = nil
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
                    RecordTrackView(onFinish: { result in
                        draft.distanceKM = String(format: "%.2f", result.distanceKM)
                        draft.ascentM = result.ascentM
                        draft.highPointM = result.highPointM
                        draft.trackPoints = result.points
                        draft.pois = result.pois
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

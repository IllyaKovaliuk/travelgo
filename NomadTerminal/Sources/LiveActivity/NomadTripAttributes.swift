import ActivityKit
import Foundation

/// Live Activity model for an in-progress trip. One activity ever exists at
/// a time: a route recording, and — if SOS gets triggered — the *same*
/// activity flips into SOS mode instead of a second, competing island entry
/// getting stacked on top. Cancelling SOS restores whatever recording state
/// was live before it (see `LiveActivityManager`).
///
/// Shared verbatim between the app target and the widget extension target
/// (both need the type to encode/decode and render the same content).
struct NomadTripAttributes: ActivityAttributes {
    /// Live snapshot pushed from `RouteTracker`'s real GPS math every few
    /// seconds while recording — never simulated. A struct rather than
    /// bare associated values so the expanded island's richer layout
    /// (matches `RecordTrackView.statsCard`'s time/distance/ascent/speed
    /// four-up exactly) doesn't need a 6-value tuple pattern everywhere.
    struct RecordingSnapshot: Codable, Hashable {
        var distanceKM: Double
        var elapsedSeconds: Int
        var ascentM: Double
        var avgSpeedKMH: Double
        /// Drives the island's Pause/Resume button label and the
        /// dot-vs-solid indicator, same as the in-app RECORDING/PAUSED pill.
        var isPaused: Bool
        /// The real selected `Transport`'s SF Symbol name + `NTColor`
        /// hex — plain data rather than the `Transport` type itself, since
        /// the widget extension target doesn't compile
        /// `Sources/Models/Route.swift` (only `Sources/LiveActivity` and
        /// `Sources/DesignSystem/NTColor.swift`). Lives on the per-update
        /// snapshot rather than the static `NomadTripAttributes` because
        /// ActivityKit has no API to change an activity's `attributes`
        /// after `Activity.request` — only `content.state` — and
        /// `RecordTrackView` lets transport change mid-recording.
        var transportIcon: String
        var transportColorHex: UInt32
    }

    struct ContentState: Codable, Hashable {
        enum Mode: Codable, Hashable {
            case recording(RecordingSnapshot)
            /// `triggeredAt` is the real hold-to-send moment. Deliberately
            /// shows elapsed time, never a "sent" / "help is on the way"
            /// claim — there's no real dispatch to emergency contacts wired
            /// yet (see SOSView), and the island is too visible (lock
            /// screen!) to overclaim.
            case sos(triggeredAt: Date)
        }
        var mode: Mode
    }

    /// Static for the activity's lifetime. Nil for a standalone SOS
    /// triggered with no route being recorded (e.g. from the plain Compass).
    var routeName: String?
    /// A target distance, when one is actually known — real today only for
    /// a route recording started against a planned length; freeform
    /// recording (the only mode this app has right now — see
    /// `LogRouteStartView`, there's no "follow a planned route" flow yet)
    /// always passes nil, and every progress indicator below is written to
    /// simply not render rather than fake a target that doesn't exist.
    var plannedLengthKM: Double? = nil
}

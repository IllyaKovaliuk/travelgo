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
    struct ContentState: Codable, Hashable {
        enum Mode: Codable, Hashable {
            /// Live snapshot pushed from `RouteTracker`'s real GPS math
            /// every few seconds while recording — never simulated.
            case recording(distanceKM: Double, elapsedSeconds: Int, ascentM: Double, paceMinPerKM: Double?)
            /// `triggeredAt` is the real moment the hold-to-send gesture
            /// completed. Deliberately shows elapsed time, never a
            /// "sent" / "help is on the way" claim — there's no real
            /// dispatch to emergency contacts wired yet (see SOSView),
            /// and the island is too visible (lock screen!) to overclaim.
            case sos(triggeredAt: Date)
        }
        var mode: Mode
    }

    /// Static for the activity's lifetime. Nil for a standalone SOS
    /// triggered with no route being recorded (e.g. from the plain Compass).
    var routeName: String?
}

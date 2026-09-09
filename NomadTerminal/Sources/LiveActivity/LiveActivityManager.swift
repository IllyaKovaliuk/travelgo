import ActivityKit
import Foundation
import Observation

/// Owns the single Live Activity for an in-progress trip — a route
/// recording and/or an SOS beacon. Recording and SOS are never two separate
/// island entries: triggering SOS mid-recording flips the same activity's
/// content state (see `NomadTripAttributes`); cancelling SOS resumes
/// whatever recording state was live before it, or ends the activity if
/// SOS was triggered standalone (no recording in progress).
///
/// Compiled into both the app target (the only place that calls
/// start/update/end) and the widget extension target (so `CancelSOSIntent`,
/// which runs in the app's process via `LiveActivityIntent`, can reach it).
@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<NomadTripAttributes>?
    /// The recording state to restore if the active SOS gets cancelled —
    /// nil when SOS was triggered standalone.
    private var preSOSRecordingState: NomadTripAttributes.ContentState.Mode?

    var isSOSActive: Bool {
        if case .sos = activity?.content.state.mode { return true }
        return false
    }

    // MARK: Recording

    func startRecording(routeName: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A fresh recording replaces any stale activity (e.g. left over
        // from a force-quit session) rather than stacking a second one.
        endActivity(dismissalPolicy: .immediate)

        let state = NomadTripAttributes.ContentState(
            mode: .recording(.init(distanceKM: 0, elapsedSeconds: 0, ascentM: 0, avgSpeedKMH: 0, isPaused: false))
        )
        activity = try? Activity.request(
            attributes: NomadTripAttributes(routeName: routeName),
            content: .init(state: state, staleDate: nil)
        )
    }

    /// Call on every meaningful change — a periodic tick while running
    /// (throttle that to every few seconds, ActivityKit doesn't need
    /// per-second pushes) and immediately on any pause/resume toggle so the
    /// island's button label and PAUSED state don't lag behind the app.
    func updateRecording(_ snapshot: NomadTripAttributes.RecordingSnapshot) {
        guard let activity, case .recording = activity.content.state.mode else { return }
        let state = NomadTripAttributes.ContentState(mode: .recording(snapshot))
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    /// Route finished normally (Finish button) — end the activity, briefly
    /// leaving the last frame up so a "route saved" moment registers
    /// instead of the island just vanishing mid-glance.
    func endRecording() {
        guard let activity, case .recording = activity.content.state.mode else { return }
        endActivity(dismissalPolicy: .after(Date.now.addingTimeInterval(3)), for: activity)
    }

    // MARK: SOS

    /// Called the instant the hold-to-send gesture completes — whether or
    /// not a recording is currently in progress.
    func triggerSOS() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let sosState = NomadTripAttributes.ContentState(mode: .sos(triggeredAt: Date()))

        if let activity {
            preSOSRecordingState = activity.content.state.mode
            Task { await activity.update(.init(state: sosState, staleDate: nil)) }
        } else {
            preSOSRecordingState = nil
            activity = try? Activity.request(
                attributes: NomadTripAttributes(routeName: nil),
                content: .init(state: sosState, staleDate: nil)
            )
        }
    }

    /// Called from the island's own "Cancel SOS" button (via
    /// `CancelSOSIntent`, runs without opening the app) or from tapping
    /// Cancel in `SOSView` itself.
    func cancelSOS() {
        guard let activity, case .sos = activity.content.state.mode else { return }
        if let restored = preSOSRecordingState {
            preSOSRecordingState = nil
            Task { await activity.update(.init(state: .init(mode: restored), staleDate: nil)) }
        } else {
            endActivity(dismissalPolicy: .immediate, for: activity)
        }
    }

    // MARK: Shared teardown

    private func endActivity(dismissalPolicy: ActivityUIDismissalPolicy, for target: Activity<NomadTripAttributes>? = nil) {
        guard let target = target ?? activity else { return }
        let finalState = target.content.state
        activity = nil
        preSOSRecordingState = nil
        Task { await target.end(.init(state: finalState, staleDate: nil), dismissalPolicy: dismissalPolicy) }
    }
}

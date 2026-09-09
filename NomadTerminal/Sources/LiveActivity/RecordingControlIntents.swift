import AppIntents
import Foundation

/// `RouteTracker`/the pause+finish actions live as `@State` on
/// `RecordTrackView` itself, not a reachable singleton (it owns a real
/// `CLLocationManagerDelegate` tied to that specific view's lifecycle) — so
/// unlike `CancelSOSIntent`, these can't call into a manager directly.
/// `LiveActivityIntent` still runs them in the app's process, so a plain
/// `NotificationCenter` post reaches the live view the same tick, no app
/// launch needed. `RecordTrackView` listens and calls the exact same
/// functions its own Pause/Finish buttons do.
extension Notification.Name {
    static let nomadIslandTogglePause = Notification.Name("io.nomadterminal.island.togglePause")
    static let nomadIslandFinish = Notification.Name("io.nomadterminal.island.finish")
}

struct ToggleRecordingPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause/Resume Recording"

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .nomadIslandTogglePause, object: nil)
        return .result()
    }
}

struct FinishRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Recording"

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .nomadIslandFinish, object: nil)
        return .result()
    }
}

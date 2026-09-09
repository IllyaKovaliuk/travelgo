import AppIntents

/// The Dynamic Island's own "Cancel SOS" button. `LiveActivityIntent` runs
/// in the app's process (that's the whole point of the protocol — no
/// `openAppWhenRun` needed), so this can flip the shared activity straight
/// back to recording/end it without ever bringing the app to the foreground.
struct CancelSOSIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel SOS"

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveActivityManager.shared.cancelSOS()
        return .result()
    }
}

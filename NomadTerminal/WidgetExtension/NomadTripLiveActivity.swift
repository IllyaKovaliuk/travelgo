import ActivityKit
import WidgetKit
import SwiftUI

/// Renders `NomadTripAttributes` on the Lock Screen and Dynamic Island.
/// Uses the real NTColor palette (shared source, no resource bundling
/// needed) but system fonts rather than the app's custom Bricolage/Plex
/// Mono files — those would need duplicating into this extension's own
/// bundle + Info.plist to register reliably, which wasn't worth the
/// fragility for a first pass. `.monospaced`/`.rounded` system designs get
/// close to the same character; can revisit if it reads too generic.
struct NomadTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NomadTripAttributes.self) { context in
            LockScreenTripView(mode: context.state.mode, routeName: context.attributes.routeName, plannedLengthKM: context.attributes.plannedLengthKM)
                .activityBackgroundTint(backgroundTint(for: context.state.mode))
                .activitySystemActionForegroundColor(NTColor.milk)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(mode: context.state.mode)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(mode: context.state.mode)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let routeName = context.attributes.routeName, case .recording = context.state.mode {
                        Text(routeName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NTColor.milk(0.8))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(mode: context.state.mode, plannedLengthKM: context.attributes.plannedLengthKM)
                }
            } compactLeading: {
                CompactLeading(mode: context.state.mode, plannedLengthKM: context.attributes.plannedLengthKM)
            } compactTrailing: {
                CompactTrailing(mode: context.state.mode)
            } minimal: {
                CompactLeading(mode: context.state.mode, plannedLengthKM: context.attributes.plannedLengthKM)
            }
            .keylineTint(tint(for: context.state.mode))
        }
    }
}

// MARK: - Shared color/format helpers

@MainActor
private func tint(for mode: NomadTripAttributes.ContentState.Mode) -> Color {
    switch mode {
    case .recording: return NTColor.accent
    case .sos: return NTColor.hard
    }
}

@MainActor
private func backgroundTint(for mode: NomadTripAttributes.ContentState.Mode) -> Color {
    switch mode {
    case .recording: return NTColor.pineDeep
    case .sos: return Color(hex: 0x1A0A07) // matches SOSView's own background
    }
}

/// The one visual language addition here: a thin capsule progress track,
/// styled to match the rest of this island (NTColor tokens, no default
/// iOS `ProgressView` chrome) — only ever appears when
/// `NomadTripAttributes.plannedLengthKM` is real.
private struct LinearProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NTColor.milk(0.14))
                Capsule().fill(NTColor.accent).frame(width: geo.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 4)
    }
}

private func elapsedString(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

// MARK: - Compact / minimal

/// A generic route-line glyph, not the transport icon — that lives in the
/// expanded view instead (see `ExpandedLeading`), matching how little room
/// compact actually has. Gains a thin circular progress ring around it
/// when `plannedLengthKM` is real (never true for today's freeform-only
/// recording, but the whole point is this doesn't lie when it is).
private struct CompactLeading: View {
    let mode: NomadTripAttributes.ContentState.Mode
    let plannedLengthKM: Double?

    var body: some View {
        switch mode {
        case .recording(let s):
            if let planned = plannedLengthKM, planned > 0 {
                Gauge(value: min(s.distanceKM / planned, 1)) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(NTColor.accent)
            } else {
                Image(systemName: s.isPaused ? "pause.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(NTColor.accent)
            }
        case .sos:
            Image(systemName: "sos").foregroundStyle(NTColor.hardBright)
        }
    }
}

private struct CompactTrailing: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording(let s):
            Text(String(format: "%.1f", s.distanceKM) + " KM")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(NTColor.milk)
        case .sos(let triggeredAt):
            Text(triggeredAt, style: .timer)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(NTColor.hardBright)
                .frame(width: 46)
        }
    }
}

// MARK: - Expanded regions

private struct ExpandedLeading: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording(let s):
            HStack(spacing: 8) {
                Image(systemName: s.transportIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: s.transportColorHex))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(hex: s.transportColorHex).opacity(0.16)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(s.isPaused ? "PAUSED" : "RECORDING")
                        .font(.system(size: 9, weight: .semibold)).tracking(1)
                        .foregroundStyle(s.isPaused ? NTColor.hardBright : NTColor.milk(0.55))
                    Text(elapsedString(s.elapsedSeconds))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NTColor.milk)
                }
            }
        case .sos:
            VStack(alignment: .leading, spacing: 3) {
                Text("SOS ACTIVE")
                    .font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(NTColor.hardBright)
                Text("GPS beacon on")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NTColor.milk(0.7))
            }
        }
    }
}

/// Mirrors `RecordTrackView.statsCard`'s three-up (distance/ascent/speed)
/// exactly, at island scale — the same stats the user already reads in-app,
/// not a different subset.
private struct ExpandedTrailing: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording(let s):
            VStack(alignment: .trailing, spacing: 4) {
                stat(String(format: "%.2f", s.distanceKM), "KM")
                stat(String(format: "%.0f", s.ascentM), "M ASCENT")
                stat(String(format: "%.1f", s.avgSpeedKMH), "KM/H")
            }
        case .sos(let triggeredAt):
            Text(triggeredAt, style: .relative)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(NTColor.hardBright)
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(NTColor.milk)
            Text(unit).font(.system(size: 9, weight: .medium)).foregroundStyle(NTColor.milk(0.55))
        }
    }
}

/// The one region with real, tappable functionality — Pause/Resume and
/// Finish reach `RecordTrackView` via `LiveActivityIntent` +
/// `NotificationCenter` (see `RecordingControlIntents.swift`), so they work
/// straight from the island without opening the app. SOS's Cancel button
/// works the same way through `CancelSOSIntent`.
private struct ExpandedBottom: View {
    let mode: NomadTripAttributes.ContentState.Mode
    let plannedLengthKM: Double?
    var body: some View {
        switch mode {
        case .recording(let s):
            VStack(spacing: 8) {
                if let planned = plannedLengthKM, planned > 0 {
                    LinearProgressBar(progress: s.distanceKM / planned)
                }
                HStack(spacing: 10) {
                    Button(intent: ToggleRecordingPauseIntent()) {
                        Label(s.isPaused ? "Resume" : "Pause", systemImage: s.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NTColor.milk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(NTColor.milk(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(intent: FinishRecordingIntent()) {
                        Label("Finish", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NTColor.pine)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(NTColor.milk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .sos:
            Button(intent: CancelSOSIntent()) {
                Text("Cancel SOS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NTColor.milk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(NTColor.hard, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Lock screen

private struct LockScreenTripView: View {
    let mode: NomadTripAttributes.ContentState.Mode
    let routeName: String?
    let plannedLengthKM: Double?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NTColor.milk(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(caption)
                        .font(.system(size: 10, weight: .bold)).tracking(1)
                        .foregroundStyle(iconColor)
                    Text(headline)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NTColor.milk)
                    if let routeName, case .recording = mode {
                        Text(routeName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NTColor.milk(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if case .recording(let s) = mode {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(format: "%.2f KM", s.distanceKM))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NTColor.milk)
                        Text(String(format: "%.0f M · %.1f KM/H", s.ascentM, s.avgSpeedKMH))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NTColor.milk(0.55))
                    }
                }
            }

            if case .recording(let s) = mode, let planned = plannedLengthKM, planned > 0 {
                LinearProgressBar(progress: s.distanceKM / planned)
            }

            HStack(spacing: 10) {
                switch mode {
                case .recording(let s):
                    Button(intent: ToggleRecordingPauseIntent()) {
                        Label(s.isPaused ? "Resume" : "Pause", systemImage: s.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NTColor.milk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(NTColor.milk(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button(intent: FinishRecordingIntent()) {
                        Label("Finish", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NTColor.pine)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(NTColor.milk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                case .sos:
                    Button(intent: CancelSOSIntent()) {
                        Text("Cancel SOS")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NTColor.milk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(NTColor.hard, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    private var icon: String {
        switch mode { case .recording(let s): return s.isPaused ? "pause.fill" : s.transportIcon; case .sos: return "sos" }
    }
    private var iconColor: Color {
        switch mode {
        case .recording(let s): return s.isPaused ? NTColor.milk(0.55) : Color(hex: s.transportColorHex)
        case .sos: return NTColor.hardBright
        }
    }
    private var caption: LocalizedStringKey {
        switch mode {
        case .recording(let s): return s.isPaused ? "PAUSED" : "RECORDING"
        case .sos: return "SOS ACTIVE"
        }
    }
    private var headline: String {
        switch mode {
        case .recording(let s): return elapsedString(s.elapsedSeconds)
        case .sos(let triggeredAt): return elapsedString(Int(Date.now.timeIntervalSince(triggeredAt)))
        }
    }
}

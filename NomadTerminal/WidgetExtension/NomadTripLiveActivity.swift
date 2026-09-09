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
            LockScreenTripView(mode: context.state.mode, routeName: context.attributes.routeName)
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
                    ExpandedBottom(mode: context.state.mode)
                }
            } compactLeading: {
                CompactLeading(mode: context.state.mode)
            } compactTrailing: {
                CompactTrailing(mode: context.state.mode)
            } minimal: {
                CompactLeading(mode: context.state.mode)
            }
            .keylineTint(tint(for: context.state.mode))
        }
    }
}

// MARK: - Shared color/format helpers

private func tint(for mode: NomadTripAttributes.ContentState.Mode) -> Color {
    switch mode {
    case .recording: return NTColor.accent
    case .sos: return NTColor.hard
    }
}

private func backgroundTint(for mode: NomadTripAttributes.ContentState.Mode) -> Color {
    switch mode {
    case .recording: return NTColor.pineDeep
    case .sos: return Color(hex: 0x1A0A07) // matches SOSView's own background
    }
}

private func elapsedString(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

private func paceString(_ pace: Double?) -> String {
    guard let pace, pace.isFinite, pace > 0 else { return "— /KM" }
    let m = Int(pace)
    let s = Int((pace - Double(m)) * 60)
    return String(format: "%d:%02d /KM", m, s)
}

// MARK: - Compact / minimal

private struct CompactLeading: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording:
            Image(systemName: "figure.hiking").foregroundStyle(NTColor.accent)
        case .sos:
            Image(systemName: "sos").foregroundStyle(NTColor.hardBright)
        }
    }
}

private struct CompactTrailing: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording(let distanceKM, _, _, _):
            Text(String(format: "%.1f", distanceKM) + " KM")
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
        case .recording(_, let elapsed, _, _):
            VStack(alignment: .leading, spacing: 3) {
                Text("RECORDING")
                    .font(.system(size: 9, weight: .semibold)).tracking(1)
                    .foregroundStyle(NTColor.milk(0.55))
                Text(elapsedString(elapsed))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NTColor.milk)
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

private struct ExpandedTrailing: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording(let distanceKM, _, let ascentM, _):
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.2f KM", distanceKM))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NTColor.milk)
                Text(String(format: "%.0f M ASCENT", ascentM))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NTColor.milk(0.55))
            }
        case .sos(let triggeredAt):
            Text(triggeredAt, style: .relative)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(NTColor.hardBright)
        }
    }
}

private struct ExpandedBottom: View {
    let mode: NomadTripAttributes.ContentState.Mode
    var body: some View {
        switch mode {
        case .recording(_, _, _, let pace):
            Text(paceString(pace))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NTColor.milk(0.6))
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

    var body: some View {
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

            if case .recording(let distanceKM, _, let ascentM, _) = mode {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.2f KM", distanceKM))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NTColor.milk)
                    Text(String(format: "%.0f M", ascentM))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NTColor.milk(0.55))
                }
            }

            if case .sos = mode {
                Button(intent: CancelSOSIntent()) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NTColor.milk)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(NTColor.hard, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var icon: String {
        switch mode { case .recording: return "figure.hiking"; case .sos: return "sos" }
    }
    private var iconColor: Color {
        switch mode { case .recording: return NTColor.accent; case .sos: return NTColor.hardBright }
    }
    private var caption: String {
        switch mode { case .recording: return "RECORDING"; case .sos: return "SOS ACTIVE" }
    }
    private var headline: String {
        switch mode {
        case .recording(_, let elapsed, _, _): return elapsedString(elapsed)
        case .sos(let triggeredAt): return elapsedString(Int(Date.now.timeIntervalSince(triggeredAt)))
        }
    }
}

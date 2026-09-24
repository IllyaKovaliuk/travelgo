import SwiftUI

/// A row of tap-to-pick transport icons — the same real control across
/// every "how did you get the line" path (live recording, importing a
/// file, drawing on the map), not a decoration. Extracted out of
/// `RecordTrackView` (its original, only user) once `ImportRouteView` and
/// `DrawRouteView` needed the identical control.
struct TransportPicker: View {
    @Binding var selection: Transport
    /// Fires on every tap, in addition to updating `selection` — e.g.
    /// `RecordTrackView` uses this to push a fresh Live Activity update.
    var onChange: ((Transport) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Transport.allCases, id: \.self) { t in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selection = t
                    onChange?(t)
                } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == t ? Color(hex: 0x231007) : t.color)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(selection == t ? t.color : t.color.opacity(0.14)))
                        .overlay(Circle().stroke(t.color.opacity(selection == t ? 0 : 0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

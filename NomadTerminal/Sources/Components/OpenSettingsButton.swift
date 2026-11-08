import SwiftUI

/// "Open Settings" deep link for screens where location is denied — iOS
/// won't re-show the system prompt, so Settings is the only way back.
struct OpenSettingsButton: View {
    var body: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            Text("Open Settings")
                .font(NTFont.body(13.5, .semibold))
                .foregroundStyle(NTColor.milk)
                .padding(.horizontal, 20)
                .frame(height: 40)
                .background(NTColor.milk(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

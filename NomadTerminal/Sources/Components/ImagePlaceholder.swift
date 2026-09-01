import SwiftUI

/// Stands in for real photography — cover slots are intentionally empty
/// per the doc ("drag a muted expedition frame onto any slot and it
/// sticks"). A soft diagonal gradient + icon reads as "photo goes here"
/// without looking like a broken image.
struct ImagePlaceholder: View {
    var caption: String? = nil
    var tint: Color = NTColor.pineRaised

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.9), NTColor.pineShadow],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(NTColor.milk(0.18))
            if let caption {
                VStack {
                    Spacer()
                    Text(caption)
                        .font(NTFont.mono(9, .medium))
                        .tracking(0.5)
                        .foregroundStyle(NTColor.milk(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

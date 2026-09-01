import SwiftUI

/// 13 · Log a route — choose method.
struct LogRouteStartView: View {
    var onRecord: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(NTColor.milk(0.08)))
                            .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Text("Log a route").font(NTFont.body(15, .semibold))
                }
                .revealOnAppear(delay: 0.02)

                Text("How did you\nget the line?")
                    .font(NTFont.heading(32, .extraBold))
                    .foregroundStyle(NTColor.milk)
                    .padding(.top, 26)
                    .revealOnAppear(delay: 0.06)

                VStack(spacing: 14) {
                    optionCard(
                        icon: "location.circle.fill",
                        title: "Record it live",
                        subtitle: "GPS tracks you as you drive, paddle or walk it",
                        tint: NTColor.accent,
                        filled: true,
                        action: onRecord
                    )
                    .revealOnAppear(delay: 0.12, distance: 20)

                    optionCard(
                        icon: "doc.badge.plus",
                        title: "Import a file",
                        subtitle: "GPX, KML or a Garmin / Strava export",
                        tint: NTColor.water,
                        filled: false,
                        action: {}
                    )
                    .opacity(0.5)
                    .revealOnAppear(delay: 0.17, distance: 20)

                    optionCard(
                        icon: "hand.draw.fill",
                        title: "Draw on the map",
                        subtitle: "Trace waypoints by hand over satellite imagery",
                        tint: NTColor.extreme,
                        filled: false,
                        action: {}
                    )
                    .opacity(0.5)
                    .revealOnAppear(delay: 0.22, distance: 20)
                }
                .padding(.top, 28)

                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(NTColor.milk(0.6))
                    Text("You can edit every detail — gear, grade, segments — before it goes live.")
                        .font(NTFont.body(13, .light))
                        .foregroundStyle(NTColor.milk(0.62))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
                .revealOnAppear(delay: 0.3)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func optionCard(icon: String, title: String, subtitle: String, tint: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(filled ? tint : tint.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 21))
                        .foregroundStyle(filled ? Color(hex: 0x231007) : tint)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(NTFont.heading(17, .bold)).foregroundStyle(NTColor.milk)
                    Text(subtitle)
                        .font(NTFont.body(13, .light))
                        .foregroundStyle(NTColor.milk(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(NTColor.milk(0.5))
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(filled ? tint.opacity(0.14) : NTColor.milk(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(filled ? tint.opacity(0.45) : NTColor.milk(0.12), lineWidth: filled ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: nil)
    }
}

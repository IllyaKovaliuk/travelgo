import SwiftUI

/// 01 · Onboarding — Welcome
struct WelcomeView: View {
    var onStart: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background(in: geo.size)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.14)

                    CompassMark(size: 96)
                        .revealOnAppear(delay: 0.05)

                    Text("NOMADTERMINAL")
                        .font(NTFont.mono(11, .medium))
                        .tracking(3.7)
                        .foregroundStyle(NTColor.milk(0.6))
                        .padding(.top, 40)
                        .revealOnAppear(delay: 0.12)

                    Text("Find the road\nnobody mapped.")
                        .font(NTFont.heading(46, .extraBold))
                        .foregroundStyle(NTColor.milk)
                        .lineSpacing(2)
                        .padding(.top, 16)
                        .revealOnAppear(delay: 0.18)

                    Text("Overland routes, river lines and ridge traverses, logged by the people who drove them.")
                        .font(NTFont.body(16, .light))
                        .foregroundStyle(NTColor.milk(0.68))
                        .lineSpacing(5)
                        .frame(maxWidth: 280, alignment: .leading)
                        .padding(.top, 18)
                        .revealOnAppear(delay: 0.24)

                    Spacer()

                    PageDots(count: 3, index: 0)
                        .padding(.bottom, 24)
                        .revealOnAppear(delay: 0.32)

                    NTPrimaryButton(title: "Start exploring", action: onStart)
                        .revealOnAppear(delay: 0.36)

                    NTGhostButton(title: "I already have an account", action: onSignIn)
                        .frame(maxWidth: .infinity)
                        .revealOnAppear(delay: 0.4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 30)
            }
        }
        .background(NTColor.pine)
    }

    @ViewBuilder
    private func background(in size: CGSize) -> some View {
        ZStack {
            NTColor.pine

            OrganicBlob(
                (topLeft: 0.58, topRight: 0.42, bottomRight: 0.46, bottomLeft: 0.54),
                (topLeft: 0.52, topRight: 0.48, bottomRight: 0.55, bottomLeft: 0.45)
            )
            .fill(NTColor.pineRaised.opacity(0.85))
            .frame(width: 520, height: 460)
            .position(x: 80, y: -60)
            .ambientDrift(dx: 10, dy: 6, duration: 10)

            OrganicBlob(
                (topLeft: 0.46, topRight: 0.54, bottomRight: 0.62, bottomLeft: 0.38),
                (topLeft: 0.58, topRight: 0.44, bottomRight: 0.56, bottomLeft: 0.42)
            )
            .fill(NTColor.sage.opacity(0.22))
            .frame(width: 340, height: 300)
            .position(x: size.width + 60, y: 340)
            .ambientDrift(dx: 8, dy: -8, duration: 12)

            OrganicBlob(
                (topLeft: 0.62, topRight: 0.38, bottomRight: 0.48, bottomLeft: 0.52),
                (topLeft: 0.44, topRight: 0.58, bottomRight: 0.42, bottomLeft: 0.56)
            )
            .fill(NTColor.accent.opacity(0.16))
            .frame(width: 300, height: 260)
            .position(x: 10, y: size.height - 150)
            .ambientDrift(dx: -6, dy: 8, duration: 11)

            TopoLines(lineCount: 5, spacing: 30)
                .stroke(NTColor.milk(0.16), lineWidth: 1)
                .frame(width: size.width, height: size.height)
        }
        .clipped()
        .ignoresSafeArea()
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}

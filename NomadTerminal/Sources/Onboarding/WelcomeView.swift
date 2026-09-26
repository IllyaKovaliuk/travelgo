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

                    Text("NOMADCOMPASS")
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

            // Flat ground + a faint straight-line contour pattern — the old
            // three color-tinted organic blobs were pure decoration with no
            // data function; this is the one place the redesign keeps any
            // background texture at all, and it's a straight-line pattern
            // now, not a soft shape.
            TopoLines(lineCount: 6, spacing: 30)
                .stroke(NTColor.milk(0.08), lineWidth: 1)
                .frame(width: size.width, height: size.height)
        }
        .clipped()
        .ignoresSafeArea()
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}

import SwiftUI

/// Staggered fade + rise-in used on every onboarding element. Give each
/// element an incremental `delay` and the screen reads as one composed
/// entrance instead of everything popping in at once.
private struct RevealOnAppear: ViewModifier {
    var delay: Double
    var distance: CGFloat
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance)
            .onAppear {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.82).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func revealOnAppear(delay: Double = 0, distance: CGFloat = 14) -> some View {
        modifier(RevealOnAppear(delay: delay, distance: distance))
    }
}

/// Slow, continuous ambient drift for background blobs — a few points of
/// motion over several seconds so the screen never feels static.
struct AmbientDrift: ViewModifier {
    var dx: CGFloat
    var dy: CGFloat
    var duration: Double
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .offset(x: on ? dx : -dx, y: on ? dy : -dy)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func ambientDrift(dx: CGFloat = 8, dy: CGFloat = 10, duration: Double = 9) -> some View {
        modifier(AmbientDrift(dx: dx, dy: dy, duration: duration))
    }
}

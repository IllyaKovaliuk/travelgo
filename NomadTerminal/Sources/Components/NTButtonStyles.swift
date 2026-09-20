import SwiftUI
import UIKit

/// Shared press feedback: a snappy spring scale-down + a light haptic tick
/// on release. This is what makes the buttons feel "expensive" rather than
/// flat system controls.
private struct NTPressEffect: ViewModifier {
    @State private var isPressed = false
    var haptic: UIImpactFeedbackGenerator.FeedbackStyle? = .light

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            if let haptic {
                                UIImpactFeedbackGenerator(style: haptic).impactOccurred()
                            }
                        }
                    }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func ntPressable(haptic: UIImpactFeedbackGenerator.FeedbackStyle? = .light) -> some View {
        modifier(NTPressEffect(haptic: haptic))
    }
}

/// Real bug this fixes: `ntPressable`'s `DragGesture(minimumDistance: 0)`
/// is fine on a small, standalone button (the bell, the "+"), but attached
/// to a row/tile that fills most of a `ScrollView`'s width — every card in
/// Home's list, every tile in Search results — it competes with the
/// ScrollView's own pan gesture for the touch and regularly wins, so the
/// list stops scrolling and only registers taps. A `ButtonStyle` reading
/// `configuration.isPressed` uses the *same* gesture SwiftUI's Button (and
/// therefore the ScrollView it sits in) already recognizes, instead of a
/// second gesture layered on top competing for the same touch — same scale
/// feedback, no competing recognizer, scrolls correctly.
struct NTCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NTCardPressStyle {
    static var ntCard: NTCardPressStyle { NTCardPressStyle() }
}

/// Solid Milk pill — the primary action on dark Pine screens
/// ("Start exploring", "Continue", …).
struct NTPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(NTFont.body(16, .semibold))
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(NTColor.pine)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(NTColor.milk, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        }
        .buttonStyle(.plain)
        .ntPressable()
    }
}

/// Solid terracotta pill — used sparingly for the "hero" action
/// (record, publish, sign-in).
struct NTAccentButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(NTFont.body(16, .semibold))
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(Color(hex: 0x231007))
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(NTColor.accent, in: Capsule())
            .shadow(color: NTColor.accent.opacity(0.55), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .ntPressable()
    }
}

/// Text-only ghost button — "I already have an account", "Skip for now".
struct NTGhostButton: View {
    let title: String
    var color: Color = NTColor.milk(0.62)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NTFont.body(14, .medium))
                .foregroundStyle(color)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: nil)
    }
}

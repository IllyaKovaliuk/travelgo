import SwiftUI

/// A single pick on the Interests screen. Selection drives a bouncy spring
/// (scale + opacity), on top of the shared press micro-bounce.
struct InterestCard: View {
    let interest: Interest
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: interest.icon)
                    .font(.system(size: interest.isOutline ? 24 : 28, weight: .medium))
                Text(interest.title)
                    .font(NTFont.body(interest.isOutline ? 13 : 14, .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(interest.onColor)
            .frame(width: interest.frame.w, height: interest.frame.h)
            .background(background)
            .overlay(border)
            .shadow(
                color: interest.isOutline ? .clear : interest.color.opacity(0.45),
                radius: 16, y: 10
            )
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: .rigid)
        .scaleEffect(isSelected ? 1 : 0.94)
        .opacity(isSelected ? 1 : 0.42)
        .animation(.spring(response: 0.42, dampingFraction: 0.58), value: isSelected)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous) }

    @ViewBuilder private var background: some View {
        if interest.isOutline {
            shape.fill(NTColor.milk(0.1))
        } else {
            shape.fill(interest.color.opacity(0.9))
        }
    }

    @ViewBuilder private var border: some View {
        if interest.isOutline {
            shape.stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .foregroundStyle(NTColor.milk(0.3))
        }
    }
}

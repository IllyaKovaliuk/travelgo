import SwiftUI

/// One Milk permission card — icon blob, title, copy, and a full-width
/// action button that morphs into a confirmed state with a spring.
struct PermissionCard: View {
    let icon: String
    let iconTint: Color
    let title: String
    let description: String
    let buttonLabel: String
    let doneLabel: String
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    OrganicBlob.soft(seed: 2)
                        .fill(iconTint.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 46, height: 46)

                Text(title)
                    .font(NTFont.heading(19, .bold))
                    .foregroundStyle(NTColor.ink)
            }

            Text(description)
                .font(NTFont.body(14.5, .light))
                .foregroundStyle(NTColor.ink.opacity(0.7))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.bottom, 18)

            Button(action: action) {
                HStack(spacing: 8) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isDone ? doneLabel : buttonLabel)
                        .font(NTFont.body(14.5, .semibold))
                }
                .foregroundStyle(NTColor.milk)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isDone ? NTColor.sage : NTColor.pine, in: Capsule())
            }
            .buttonStyle(.plain)
            .ntPressable(haptic: isDone ? nil : .medium)
            .disabled(isDone)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDone)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        // milkSurface (fixed) — title/description above are NTColor.ink,
        // also fixed; the reactive `milk` would go dark-on-dark in Milk theme.
        .background(NTColor.milkSurface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

import SwiftUI

private struct NotifItem: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let text: String
    let sub: String?
    let time: String
    let isAlert: Bool
    let avatarInitials: String?
}

private let items: [NotifItem] = [
    .init(icon: "exclamationmark.triangle.fill", tint: NTColor.gold, text: "Ford at WP3 flagged impassable", sub: "Someone logged high water on Zagar Pass, 40 min ago", time: "2H AGO", isAlert: true, avatarInitials: nil),
    .init(icon: "person.fill", tint: .clear, text: "Ainara Ruiz started following you", sub: nil, time: "3H AGO", isAlert: false, avatarInitials: "AR"),
    .init(icon: "bubble.left.fill", tint: NTColor.sage, text: "Luka Kranjc commented on Zagar Pass", sub: "\"Did this in June — ford was ankle-deep, no issue\"", time: "5H AGO", isAlert: false, avatarInitials: nil),
    .init(icon: "star.fill", tint: NTColor.gold, text: "You earned True North", sub: nil, time: "1D AGO", isAlert: false, avatarInitials: nil),
    .init(icon: "flag.fill", tint: .clear, text: "Luka Kranjc published a new route", sub: "The Emerald Corridor · 18.9 KM", time: "2D AGO", isAlert: false, avatarInitials: "LK")
]

/// 18 · Notifications
struct NotificationsView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(NTColor.milk(0.08)))
                                .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Text("Notifications").font(NTFont.heading(26, .extraBold))
                        Text("4 NEW").font(NTFont.mono(10, .semibold)).foregroundStyle(NTColor.accent)
                    }

                    VStack(spacing: 0) {
                        ForEach(items) { item in row(item) }
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(NTColor.milk)
    }

    private func row(_ item: NotifItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let initials = item.avatarInitials {
                ZStack {
                    LinearGradient(colors: [NTColor.extreme, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(initials).font(NTFont.heading(12, .semibold)).foregroundStyle(NTColor.milk)
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(item.tint.opacity(0.2))
                    Image(systemName: item.icon).font(.system(size: 15)).foregroundStyle(item.tint)
                }
                .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(NTFont.body(14, .medium))
                    .foregroundStyle(NTColor.milk)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = item.sub {
                    Text(sub).font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.time).font(NTFont.mono(9.5, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, item.isAlert ? 14 : 0)
        .background(item.isAlert ? NTColor.gold.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            item.isAlert ? RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.gold.opacity(0.4), lineWidth: 1) : nil
        )
        .overlay(!item.isAlert ? Rectangle().fill(NTColor.milk(0.1)).frame(height: 1) : nil, alignment: .bottom)
        .padding(.bottom, item.isAlert ? 10 : 0)
    }
}

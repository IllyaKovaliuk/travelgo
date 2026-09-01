import SwiftUI

/// 20 · NomadTerminal Pro — paywall. Visual only; StoreKit purchase flow
/// is a separate, dedicated pass once pricing/products are set up in
/// App Store Connect.
struct PaywallView: View {
    var onClose: () -> Void

    @State private var plan: Plan = .annual
    enum Plan { case monthly, annual }

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()
            OrganicBlob((0.56, 0.44, 0.48, 0.52), (0.46, 0.56, 0.44, 0.54))
                .fill(NTColor.pineRaised.opacity(0.9))
                .frame(width: 480, height: 420)
                .position(x: 60, y: -60)
                .ignoresSafeArea()
            OrganicBlob((0.46, 0.54, 0.62, 0.38), (0.58, 0.44, 0.56, 0.42))
                .fill(NTColor.accent.opacity(0.14))
                .frame(width: 320, height: 280)
                .position(x: 380, y: 320)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(NTColor.milk(0.1)))
                            .overlay(Circle().stroke(NTColor.milk(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                ZStack {
                    Circle().fill(NTColor.gold.opacity(0.2))
                    Image(systemName: "crown.fill").font(.system(size: 24)).foregroundStyle(NTColor.gold)
                }
                .frame(width: 56, height: 56)
                .padding(.top, 20)

                Text("Go further\noff grid.")
                    .font(NTFont.heading(32, .extraBold))
                    .foregroundStyle(NTColor.milk)
                    .padding(.top, 18)

                Text("NomadTerminal Pro — everything you need where there's no signal at all.")
                    .font(NTFont.body(14.5, .light))
                    .foregroundStyle(NTColor.milk(0.62))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 13) {
                    feature("Unlimited offline map downloads")
                    feature("Satellite SOS beacon, no bars needed")
                    feature("Live ford & weather condition alerts")
                    feature("Publish unlimited routes")
                }
                .padding(.top, 22)

                Spacer(minLength: 20)

                HStack(spacing: 10) {
                    planCard(.monthly, title: "Monthly", price: "$7.99")
                    planCard(.annual, title: "Annual", price: "$59.99", badge: "SAVE 38%")
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("Start 7-day free trial")
                        .font(NTFont.body(16, .semibold))
                        .foregroundStyle(NTColor.pine)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(NTColor.milk, in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .ntPressable()
                .padding(.top, 18)

                Text("Cancel anytime. Renews at \(plan == .annual ? "$59.99/yr" : "$7.99/mo").")
                    .font(NTFont.mono(10.5, .medium)).tracking(0.3)
                    .foregroundStyle(NTColor.milk(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .foregroundStyle(NTColor.milk)
    }

    private func feature(_ text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(NTColor.sage.opacity(0.2))
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x8FCBA3))
            }
            .frame(width: 26, height: 26)
            Text(text).font(NTFont.body(14.5, .medium))
        }
    }

    private func planCard(_ p: Plan, title: String, price: String, badge: String? = nil) -> some View {
        Button { plan = p } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let badge {
                    Text(badge)
                        .font(NTFont.mono(9, .semibold)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0x231007))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(NTColor.accent))
                }
                Text(title).font(NTFont.body(13, .semibold))
                Text(price).font(NTFont.mono(20, .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(plan == p ? NTColor.accent.opacity(0.14) : NTColor.milk(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(plan == p ? NTColor.accent : NTColor.milk(0.16), lineWidth: plan == p ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

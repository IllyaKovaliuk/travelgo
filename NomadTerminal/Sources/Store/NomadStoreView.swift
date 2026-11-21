import SwiftUI
import CoreImage.CIFilterBuiltins

/// Nomad Store & Rewards — partner perks bought with NomadPoints.
struct NomadStoreView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Environment(\.dismiss) private var dismiss
    @State private var model = NomadStoreViewModel()
    @State private var confirming: Reward?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    balanceCard

                    if !model.vouchers.filter(\.isActive).isEmpty {
                        sectionLabel("MY VOUCHERS")
                        VStack(spacing: 10) {
                            ForEach(model.vouchers.filter(\.isActive)) { voucher in
                                Button { model.presentedVoucher = voucher } label: { voucherRow(voucher) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionLabel("PARTNER OFFERS")
                    if model.rewards.isEmpty && !model.isLoading {
                        Text("No partner offers near you yet — check back soon.")
                            .font(NTFont.body(13, .light)).foregroundStyle(NTColor.milk(0.5))
                    }
                    LazyVGrid(columns: AdaptiveColumns.grid(spacing: 12, sizeClass: sizeClass), spacing: 12) {
                        ForEach(model.rewards) { rewardCard($0) }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Nomad Store")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .refreshable { await model.load() }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task { await model.load() }
        .sheet(item: $model.presentedVoucher) { VoucherView(voucher: $0) }
        .confirmationDialog(
            confirming.map { "Redeem \($0.title) for \($0.pointsCost) pts?" } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button("Redeem") { if let r = confirming { Task { await model.redeem(r) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The points are spent right away and you get a QR voucher valid for 7 days.")
        }
        .alert("Couldn't redeem", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private var balanceCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(NTColor.gold)
                Text(model.balance.map { $0.formatted() } ?? "—")
                    .font(NTFont.heading(44, .extraBold)).contentTransition(.numericText())
                Text("pts").font(NTFont.mono(14, .medium)).foregroundStyle(NTColor.milk(0.6)).padding(.top, 14)
            }
            Text("Earn more: report hazards, publish routes").font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
    }

    private func rewardCard(_ reward: Reward) -> some View {
        let affordable = (model.balance ?? 0) >= reward.pointsCost
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let partner = reward.partner {
                    Image(systemName: partner.category.icon).font(.system(size: 11)).foregroundStyle(NTColor.gold)
                    Text(partner.name).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.6)).lineLimit(1)
                    if partner.isVerified { Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(NTColor.sage) }
                }
            }
            Text(reward.title).font(NTFont.body(14.5, .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(reward.description).font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.55)).lineLimit(3)
            Spacer(minLength: 0)
            Text("\(reward.stock) left").font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.4))
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                confirming = reward
            } label: {
                Group {
                    if model.redeemingId == reward.id { ProgressView().tint(NTColor.pine) }
                    else { Text("\(reward.pointsCost) PT").font(NTFont.mono(12, .semibold)) }
                }
                .foregroundStyle(affordable ? NTColor.pine : NTColor.milk(0.4))
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(Capsule().fill(affordable ? NTColor.milk : NTColor.milk(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(!affordable || model.redeemingId != nil)
        }
        .padding(14)
        .frame(minHeight: 190)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func voucherRow(_ voucher: UserVoucher) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode").font(.system(size: 22)).foregroundStyle(NTColor.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(voucher.reward?.title ?? "Voucher").font(NTFont.body(14, .semibold))
                Text(voucher.reward?.partner?.name ?? "").font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.55))
            }
            Spacer()
            Text(voucher.expiresAt, style: .relative).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.5))
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }
}

/// QR voucher shown at the partner location, with a live expiry countdown.
struct VoucherView: View {
    let voucher: UserVoucher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(NTColor.milk(0.25)).frame(width: 40, height: 4).padding(.top, 10)
            Text(voucher.reward?.partner?.name ?? "Partner").font(NTFont.mono(11, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.6))
            Text(voucher.reward?.title ?? "Voucher").font(NTFont.heading(24, .extraBold)).multilineTextAlignment(.center)

            if let qr = Self.qrImage(voucher.qrCodeHash) {
                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, voucher.expiresAt.timeIntervalSince(context.date))
                VStack(spacing: 4) {
                    Text(voucher.isRedeemed ? "USED" : remaining > 0 ? Self.format(remaining) : "EXPIRED")
                        .font(NTFont.mono(22, .semibold))
                        .foregroundStyle(voucher.isRedeemed || remaining == 0 ? Color(hex: 0xE58272) : NTColor.sage)
                    Text("TIME LEFT TO USE").font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                }
            }
            Text("Show this code to the partner. It can be used once.")
                .font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.55))
            Spacer()
            Button { dismiss() } label: {
                Text("Done").font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.pine)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(NTColor.milk))
            }.buttonStyle(.plain)
        }
        .padding(22)
        .foregroundStyle(NTColor.milk)
        .background(NTColor.pine.ignoresSafeArea())
        .presentationDetents([.large])
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        return d > 0 ? String(format: "%dd %02dh %02dm", d, h, m) : String(format: "%02d:%02d:%02d", h, m, sec)
    }

    static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

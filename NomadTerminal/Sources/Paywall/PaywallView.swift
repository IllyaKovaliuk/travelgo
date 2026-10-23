import SwiftUI
import StoreKit

/// 20 · Nomad Pro — paywall. Real StoreKit 2 purchase flow, backed
/// by `SubscriptionManager` and the two products in `Configuration.storekit`
/// (must be mirrored exactly in App Store Connect before shipping).
struct PaywallView: View {
    var onClose: () -> Void

    @State private var manager = SubscriptionManager.shared
    @State private var selectedProductID = SubscriptionManager.annualID
    @State private var isPurchasing = false

    private var selectedProduct: Product? {
        manager.products.first { $0.id == selectedProductID }
    }

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

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

                if manager.isPro {
                    proActiveState
                } else {
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

                    Text("Nomad Pro — route weather, offline maps and full itineraries.")
                        .font(NTFont.body(14.5, .light))
                        .foregroundStyle(NTColor.milk(0.62))
                        .padding(.top, 8)

                    // Two real things behind this paywall now —
                    // `RouteItineraryPanel.isPro` and `OfflineMapStore`
                    // (real Mapbox tile regions, not just the route's own
                    // JSON) — so only real claims belong here. SOS and
                    // publishing stay free for everyone regardless of Pro
                    // status; claiming otherwise (a past version of this
                    // screen did, including a fictional "satellite SOS
                    // beacon") is exactly the kind of thing that gets an
                    // app rejected or worse, trusted wrongly in an
                    // emergency.
                    VStack(alignment: .leading, spacing: 13) {
                        feature("Meteo-Terminal — weather timeline, storm risk on the route, radar and the best time to leave")
                        feature("Real offline maps — the whole route downloaded, not just the data")
                        feature("Full leg-by-leg itinerary with estimated timing on every route")
                        feature("Supports Nomad's development")
                    }
                    .padding(.top, 22)

                    Spacer(minLength: 20)

                    if let error = manager.purchaseError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xE58272))
                            Text(error).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.milk(0.85))
                        }
                        .padding(14)
                        .background(Color(hex: 0xB33A2B).opacity(0.18), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                        .padding(.bottom, 14)
                    }

                    if manager.isLoadingProducts {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if manager.products.isEmpty {
                        Text("Subscription options unavailable right now.")
                            .font(NTFont.body(13, .medium))
                            .foregroundStyle(NTColor.milk(0.55))
                            .padding(.vertical, 20)
                    } else {
                        HStack(spacing: 10) {
                            ForEach(manager.products) { product in
                                planCard(product)
                            }
                        }

                        Button {
                            purchase()
                        } label: {
                            HStack(spacing: 9) {
                                if isPurchasing {
                                    ProgressView().tint(NTColor.pine)
                                } else {
                                    Text(trialCopy)
                                        .font(NTFont.body(16, .semibold))
                                }
                            }
                            .foregroundStyle(NTColor.pine)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(NTColor.milk, in: Capsule())
                            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                        }
                        .buttonStyle(.plain)
                        .ntPressable()
                        .disabled(isPurchasing || selectedProduct == nil)
                        .padding(.top, 18)

                        if let selectedProduct {
                            Text("Cancel anytime. Renews at \(selectedProduct.displayPrice)\(renewalSuffix).")
                                .font(NTFont.mono(10.5, .medium)).tracking(0.3)
                                .foregroundStyle(NTColor.milk(0.45))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                        }

                        Button {
                            Task { await manager.restore() }
                        } label: {
                            Text("Restore purchases")
                                .font(NTFont.mono(10.5, .medium)).tracking(0.3)
                                .foregroundStyle(NTColor.milk(0.55))
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Real, required directly on the paywall for any
                        // app offering a subscription (App Store Review
                        // Guideline 3.1.2) — neither existed anywhere in
                        // the app before this.
                        HStack(spacing: 14) {
                            Link(destination: LegalLinks.termsOfService) {
                                Text("Terms of Service")
                            }
                            Text("·").foregroundStyle(NTColor.milk(0.3))
                            Link(destination: LegalLinks.privacyPolicy) {
                                Text("Privacy Policy")
                            }
                        }
                        .font(NTFont.mono(10, .medium)).tracking(0.2)
                        .foregroundStyle(NTColor.milk(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .foregroundStyle(NTColor.milk)
        .task {
            await manager.loadProducts()
            if selectedProduct == nil { selectedProductID = manager.products.first?.id ?? SubscriptionManager.annualID }
        }
    }

    private var trialCopy: LocalizedStringKey {
        selectedProduct?.subscription?.introductoryOffer != nil ? "Start 7-day free trial" : "Subscribe"
    }

    /// Real saving of annual vs 12 × monthly, from the live StoreKit prices
    /// (rounded down so the badge never overpromises). Nil if either product
    /// is missing or annual isn't actually cheaper.
    private var annualSavingsPercent: Int? {
        guard let monthly = manager.products.first(where: { $0.id == SubscriptionManager.monthlyID }),
              let annual = manager.products.first(where: { $0.id == SubscriptionManager.annualID }),
              monthly.price > 0 else { return nil }
        let ratio = (annual.price / (monthly.price * 12) as NSDecimalNumber).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    private var renewalSuffix: String {
        guard let period = selectedProduct?.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .month: return "/mo"
        case .year: return "/yr"
        default: return ""
        }
    }

    private var proActiveState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(NTColor.sage.opacity(0.2))
                Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(NTColor.sage)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 30)

            Text("You're Pro.").font(NTFont.heading(28, .extraBold))
            Text("Route weather, offline maps and full itineraries are unlocked.")
                .font(NTFont.body(14, .light))
                .foregroundStyle(NTColor.milk(0.62))
                .multilineTextAlignment(.center)

            Button(action: onClose) {
                Text("Done")
                    .font(NTFont.body(16, .semibold))
                    .foregroundStyle(NTColor.pine)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(NTColor.sage.opacity(0.2))
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x8FCBA3))
            }
            .frame(width: 26, height: 26)
            Text(text)
                .font(NTFont.body(14.5, .medium))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isAnnual = product.id == SubscriptionManager.annualID
        return Button { selectedProductID = product.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                if isAnnual, let percent = annualSavingsPercent {
                    Text("SAVE \(percent)%")
                        .font(NTFont.mono(9, .semibold)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0x231007))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(NTColor.accent))
                }
                Text(isAnnual ? "Annual" : "Monthly").font(NTFont.body(13, .semibold))
                Text(product.displayPrice).font(NTFont.mono(20, .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).fill(selectedProductID == product.id ? NTColor.accent.opacity(0.14) : NTColor.milk(0.06)))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(selectedProductID == product.id ? NTColor.accent : NTColor.milk(0.16), lineWidth: selectedProductID == product.id ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: nil)
    }

    private func purchase() {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        Task {
            await manager.purchase(product)
            isPurchasing = false
            if manager.isPro {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

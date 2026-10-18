import Foundation
import UIKit
import Observation

@MainActor
@Observable
final class NomadStoreViewModel {
    private(set) var balance: Int?
    private(set) var rewards: [Reward] = []
    private(set) var vouchers: [UserVoucher] = []
    private(set) var isLoading = true
    private(set) var redeemingId: UUID?
    var errorMessage: String?
    /// Set after a successful redemption → presents the voucher modal.
    var presentedVoucher: UserVoucher?

    private let repo = CommunityRepository.shared

    func load() async {
        async let summary = try? RouteRepository.shared.fetchPointsSummary()
        async let rewardRows = try? repo.fetchRewards()
        async let voucherRows = try? repo.fetchMyVouchers()
        balance = await summary?.balance
        rewards = await rewardRows ?? rewards
        vouchers = await voucherRows ?? vouchers
        isLoading = false
    }

    func redeem(_ reward: Reward) async {
        redeemingId = reward.id
        defer { redeemingId = nil }
        do {
            let voucher = try await repo.redeem(reward)
            presentedVoucher = voucher
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load() // server is the source of truth for balance + stock
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}

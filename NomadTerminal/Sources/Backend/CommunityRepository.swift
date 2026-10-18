import Foundation
import UIKit
import CoreLocation
import Supabase

/// Hazard reports ("Proof of Exploration") and the partner marketplace.
/// Every points-moving or state-changing step is a server RPC / trigger —
/// the client can read, and file a report, nothing else.
@MainActor
final class CommunityRepository {
    static let shared = CommunityRepository()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    private func session() async throws -> UUID {
        try await RouteRepository.shared.ensureSession()
    }

    // MARK: Hazards

    enum HazardError: LocalizedError {
        case rateLimited, lowTrust, tooFar, alreadyVoted, ownReport, inactive, other(String)
        var errorDescription: String? {
            switch self {
            case .rateLimited: return String(localized: "You've reached today's limit of 5 hazard reports.")
            case .lowTrust: return String(localized: "Reporting is paused for your account after several dismissed reports.")
            case .tooFar: return String(localized: "You need to be within 300 m of the hazard to vote on it.")
            case .alreadyVoted: return String(localized: "You've already voted on this hazard.")
            case .ownReport: return String(localized: "You can't vote on your own report.")
            case .inactive: return String(localized: "This hazard is no longer active.")
            case .other(let m): return m
            }
        }
        static func map(_ error: Error) -> HazardError {
            let m = error.localizedDescription
            if m.contains("rate limit") { return .rateLimited }
            if m.contains("low trust") { return .lowTrust }
            if m.contains("too far") { return .tooFar }
            if m.contains("already voted") { return .alreadyVoted }
            if m.contains("own report") { return .ownReport }
            if m.contains("not active") { return .inactive }
            return .other(m)
        }
    }

    /// Active, unexpired hazards inside a lat/lng box around `center`.
    func fetchHazards(near center: CLLocationCoordinate2D, radiusKM: Double = 25) async throws -> [HazardReport] {
        _ = try await session()
        let dLat = radiusKM / 111.0
        let dLng = radiusKM / (111.0 * max(0.2, cos(center.latitude * .pi / 180)))
        let response = try await supabase.from("reports")
            .select()
            .eq("status", value: "active")
            .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
            .gte("latitude", value: center.latitude - dLat).lte("latitude", value: center.latitude + dLat)
            .gte("longitude", value: center.longitude - dLng).lte("longitude", value: center.longitude + dLng)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
        return try decoder.decode([HazardReport].self, from: response.data)
    }

    /// Downscales + JPEG-compresses before upload (long edge 1280 px).
    func uploadHazardPhoto(_ image: UIImage) async throws -> String {
        let userId = try await session()
        guard let data = image.resized(maxDimension: 1280).jpegData(compressionQuality: 0.7) else {
            throw HazardError.other("Couldn't encode photo")
        }
        let path = "\(userId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage.from("hazard-photos").upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg")
        )
        return try supabase.storage.from("hazard-photos").getPublicURL(path: path).absoluteString
    }

    /// Files a report. Points (+50) are awarded by a database trigger, and
    /// the 5/day limit is enforced there too — see `before_report_insert`.
    func submitHazard(type: HazardType, coordinate: CLLocationCoordinate2D, description: String?, imageUrl: String?) async throws {
        let userId = try await session()
        struct Insert: Encodable {
            let user_id: String
            let latitude: Double
            let longitude: Double
            let hazard_type: String
            let description: String?
            let image_url: String?
        }
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await supabase.from("reports").insert(Insert(
                user_id: userId.uuidString, latitude: coordinate.latitude, longitude: coordinate.longitude,
                hazard_type: type.rawValue, description: (trimmed?.isEmpty ?? true) ? nil : trimmed, image_url: imageUrl
            )).execute()
        } catch {
            throw HazardError.map(error)
        }
    }

    /// Confirm or dismiss a hazard. The server checks the voter is within
    /// 300 m of it using the coordinates passed here.
    func vote(on report: HazardReport, confirm: Bool, from location: CLLocationCoordinate2D) async throws -> HazardReport {
        _ = try await session()
        struct Params: Encodable {
            let p_report_id: String
            let p_vote: String
            let p_lat: Double
            let p_lng: Double
        }
        do {
            let response = try await supabase.rpc("vote_on_report", params: Params(
                p_report_id: report.id.uuidString, p_vote: confirm ? "confirm" : "dismiss",
                p_lat: location.latitude, p_lng: location.longitude
            )).execute()
            return try decoder.decode(HazardReport.self, from: response.data)
        } catch {
            throw HazardError.map(error)
        }
    }

    // MARK: Partners & marketplace

    func fetchPartners(near center: CLLocationCoordinate2D, radiusKM: Double = 100) async throws -> [Partner] {
        _ = try await session()
        let dLat = radiusKM / 111.0
        let dLng = radiusKM / (111.0 * max(0.2, cos(center.latitude * .pi / 180)))
        let response = try await supabase.from("partners")
            .select()
            .gte("latitude", value: center.latitude - dLat).lte("latitude", value: center.latitude + dLat)
            .gte("longitude", value: center.longitude - dLng).lte("longitude", value: center.longitude + dLng)
            .limit(100)
            .execute()
        return try decoder.decode([Partner].self, from: response.data)
    }

    func fetchRewards() async throws -> [Reward] {
        _ = try await session()
        let response = try await supabase.from("rewards")
            .select("*, partners(*)")
            .gt("stock", value: 0)
            .order("points_cost")
            .execute()
        return try decoder.decode([Reward].self, from: response.data)
    }

    func fetchMyVouchers() async throws -> [UserVoucher] {
        _ = try await session()
        let response = try await supabase.from("user_vouchers")
            .select("*, rewards(*, partners(*))")
            .order("created_at", ascending: false)
            .execute()
        return try decoder.decode([UserVoucher].self, from: response.data)
    }

    enum RedeemPartnerError: LocalizedError {
        case insufficientPoints, outOfStock, unavailable, other(String)
        var errorDescription: String? {
            switch self {
            case .insufficientPoints: return String(localized: "Not enough NomadPoints for this one yet.")
            case .outOfStock: return String(localized: "This offer just ran out of stock.")
            case .unavailable: return String(localized: "This offer is no longer available.")
            case .other(let m): return m
            }
        }
    }

    /// Atomic server-side redemption: points deducted through the ledger,
    /// stock decremented, voucher minted — all in one transaction.
    func redeem(_ reward: Reward) async throws -> UserVoucher {
        _ = try await session()
        struct Params: Encodable { let p_reward_id: String }
        do {
            let response = try await supabase.rpc("redeem_partner_reward", params: Params(p_reward_id: reward.id.uuidString)).execute()
            var voucher = try decoder.decode(UserVoucher.self, from: response.data)
            voucher.reward = reward
            return voucher
        } catch {
            let m = error.localizedDescription
            if m.contains("insufficient points") { throw RedeemPartnerError.insufficientPoints }
            if m.contains("out of stock") { throw RedeemPartnerError.outOfStock }
            if m.contains("unavailable") { throw RedeemPartnerError.unavailable }
            throw RedeemPartnerError.other(m)
        }
    }
}

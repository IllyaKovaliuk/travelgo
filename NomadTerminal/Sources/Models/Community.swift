import Foundation
import CoreLocation
import SwiftUI

/// Wire models for the hazard-report and partner-marketplace tables (see
/// `backend/supabase/migrations/20261018000001_hazard_reports_and_marketplace.sql`).
/// Plain Codable structs — the app has no SwiftData layer; offline
/// persistence for the rest of the app is the JSON stores in `Backend/`.

enum HazardType: String, Codable, CaseIterable, Identifiable {
    case treeFall = "tree_fall"
    case bridgeBroken = "bridge_broken"
    case deepFord = "deep_ford"
    case other

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .treeFall: return "Tree Fall"
        case .bridgeBroken: return "Broken Bridge"
        case .deepFord: return "Deep Ford"
        case .other: return "Other"
        }
    }
    var icon: String {
        switch self {
        case .treeFall: return "tree.fill"
        case .bridgeBroken: return "exclamationmark.triangle.fill"
        case .deepFord: return "water.waves"
        case .other: return "questionmark.diamond.fill"
        }
    }
}

struct HazardReport: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let hazardType: HazardType
    let description: String?
    let imageUrl: String?
    let status: String
    let pointsAwarded: Int
    let confirmations: Int
    let dismissals: Int
    let expiresAt: Date
    let createdAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, description, status, confirmations, dismissals
        case userId = "user_id"
        case hazardType = "hazard_type"
        case imageUrl = "image_url"
        case pointsAwarded = "points_awarded"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

enum PartnerCategory: String, Codable {
    case quadRental = "quad_rental"
    case hotel, equipment, cafe

    var icon: String {
        switch self {
        case .quadRental: return "car.side.fill"
        case .hotel: return "bed.double.fill"
        case .equipment: return "backpack.fill"
        case .cafe: return "cup.and.saucer.fill"
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .quadRental: return "Quad rental"
        case .hotel: return "Hotel"
        case .equipment: return "Equipment"
        case .cafe: return "Café"
        }
    }
}

struct Partner: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let category: PartnerCategory
    let latitude: Double
    let longitude: Double
    let logoUrl: String?
    let isVerified: Bool

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    enum CodingKeys: String, CodingKey {
        case id, name, category, latitude, longitude
        case logoUrl = "logo_url"
        case isVerified = "is_verified"
    }
}

struct Reward: Identifiable, Codable, Hashable {
    let id: UUID
    let partnerId: UUID
    let title: String
    let description: String
    let pointsCost: Int
    let stock: Int
    let expiresAt: Date?
    /// Joined from `partners` by the store query; absent on other reads.
    var partner: Partner?

    enum CodingKeys: String, CodingKey {
        case id, title, description, stock, partner = "partners"
        case partnerId = "partner_id"
        case pointsCost = "points_cost"
        case expiresAt = "expires_at"
    }
}

struct UserVoucher: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let rewardId: UUID
    let qrCodeHash: String
    let isRedeemed: Bool
    let redeemedAt: Date?
    let expiresAt: Date
    let createdAt: Date
    var reward: Reward?

    var isActive: Bool { !isRedeemed && expiresAt > Date() }

    enum CodingKeys: String, CodingKey {
        case id, reward = "rewards"
        case userId = "user_id"
        case rewardId = "reward_id"
        case qrCodeHash = "qr_code_hash"
        case isRedeemed = "is_redeemed"
        case redeemedAt = "redeemed_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

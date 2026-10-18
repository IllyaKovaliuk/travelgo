import Foundation
import CoreLocation
import UIKit
import Observation

/// View-model behind the hazard layer on the map: loads nearby hazards and
/// partners, files reports, and handles confirm/dismiss voting.
@MainActor
@Observable
final class HazardStore {
    private(set) var hazards: [HazardReport] = []
    private(set) var partners: [Partner] = []
    var selectedHazard: HazardReport?
    var selectedPartner: Partner?
    /// Set to +N right after a successful report to drive the reward animation.
    var rewardBurst: Int?
    var errorMessage: String?
    private(set) var isSubmitting = false
    private(set) var isVoting = false
    private var lastCenter: CLLocationCoordinate2D?

    /// Closest not-yet-passed hazard within `alertRadiusM` of the user.
    struct ProximityAlert: Equatable {
        let hazard: HazardReport
        var distanceM: Int
    }
    private(set) var proximityAlert: ProximityAlert?
    private var alertedIds: Set<UUID> = []
    static let alertRadiusM: Double = 500
    private static let clearRadiusM: Double = 700

    private let repo = CommunityRepository.shared

    // Local anti-spam mirror of the server's 5-per-24h limit (the server is
    // still the authority — this just lets the UI say "N left" and stop
    // early without a round trip).
    static let dailyLimit = 5
    private static let submissionsKey = "hazard.submissions.v1"
    private(set) var submittedInLast24h: [Date] = HazardStore.loadSubmissions()

    var reportsLeftToday: Int { max(0, Self.dailyLimit - submittedInLast24h.count) }

    private static func loadSubmissions() -> [Date] {
        let cutoff = Date().addingTimeInterval(-86_400)
        let stored = (UserDefaults.standard.array(forKey: submissionsKey) as? [Double]) ?? []
        return stored.map { Date(timeIntervalSince1970: $0) }.filter { $0 > cutoff }
    }

    private func recordSubmission() {
        submittedInLast24h = Self.loadSubmissions() + [Date()]
        UserDefaults.standard.set(submittedInLast24h.map(\.timeIntervalSince1970), forKey: Self.submissionsKey)
    }

    func refresh(near center: CLLocationCoordinate2D) async {
        lastCenter = center
        async let h = try? repo.fetchHazards(near: center)
        async let p = try? repo.fetchPartners(near: center)
        if let h = await h { hazards = h }
        if let p = await p { partners = p }
    }

    /// Hazards that sit on (within 150 m of) a published route — for the
    /// route detail page and full map, so people see problems *before*
    /// they set out.
    func loadAlongRoute(_ points: [TrackPoint]) async {
        guard points.count > 1, let area = HazardGeometry.searchArea(for: points) else { return }
        guard let nearby = try? await repo.fetchHazards(near: area.center, radiusKM: area.radiusKM) else { return }
        let line = points.map(\.coordinate)
        hazards = nearby.filter { HazardGeometry.distance(from: $0.coordinate, toPolyline: line) <= 150 }
    }

    /// Call on every location update. Fires a warning haptic + banner once
    /// per hazard as the user comes within 500 m; keeps the distance live
    /// and clears it once they're past (>700 m) or it's been resolved.
    func updateProximity(at location: CLLocationCoordinate2D) {
        if var current = proximityAlert {
            guard let live = hazards.first(where: { $0.id == current.hazard.id }) else { proximityAlert = nil; return }
            let d = HazardGeometry.meters(location, live.coordinate)
            if d > Self.clearRadiusM { proximityAlert = nil } else { current.distanceM = Int(d.rounded()); proximityAlert = current }
            return
        }
        let candidate = hazards
            .filter { !alertedIds.contains($0.id) }
            .map { ($0, HazardGeometry.meters(location, $0.coordinate)) }
            .filter { $0.1 <= Self.alertRadiusM }
            .min { $0.1 < $1.1 }
        if let (hazard, d) = candidate {
            alertedIds.insert(hazard.id)
            proximityAlert = ProximityAlert(hazard: hazard, distanceM: Int(d.rounded()))
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func dismissProximityAlert() { proximityAlert = nil }

    /// Returns true on success. Photo upload failure aborts the report so a
    /// hazard never silently loses the picture the user took.
    func submit(type: HazardType, at coordinate: CLLocationCoordinate2D, description: String, photo: UIImage?) async -> Bool {
        submittedInLast24h = Self.loadSubmissions()
        guard reportsLeftToday > 0 else {
            errorMessage = String(localized: "You've reached today's limit of 5 hazard reports.")
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var imageUrl: String?
            if let photo { imageUrl = try await repo.uploadHazardPhoto(photo) }
            try await repo.submitHazard(type: type, coordinate: coordinate, description: description, imageUrl: imageUrl)
            recordSubmission()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            rewardBurst = 50
            await refresh(near: coordinate)
            return true
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    func vote(confirm: Bool, from location: CLLocationCoordinate2D?) async {
        guard let hazard = selectedHazard else { return }
        guard let location else {
            errorMessage = String(localized: "Waiting for your location — try again in a moment.")
            return
        }
        isVoting = true
        defer { isVoting = false }
        do {
            let updated = try await repo.vote(on: hazard, confirm: confirm, from: location)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if updated.status == "resolved" {
                hazards.removeAll { $0.id == updated.id }
                selectedHazard = nil
            } else if let i = hazards.firstIndex(where: { $0.id == updated.id }) {
                hazards[i] = updated
                selectedHazard = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

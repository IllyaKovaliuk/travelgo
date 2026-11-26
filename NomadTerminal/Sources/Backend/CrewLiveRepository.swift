import Foundation
import Supabase

/// Polls, trip day, live location, convoy and awareness events. Same split as
/// `CrewRepository`: RLS-scoped reads, every write is an RPC.
@MainActor
final class CrewLiveRepository {
    static let shared = CrewLiveRepository()
    private init() {}

    private func session() async throws { _ = try await RouteRepository.shared.ensureSession() }
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    private func fail(_ error: Error) -> CrewRepository.CrewError { CrewRepository.CrewError(error) }
    nonisolated private static func date(_ s: String) -> Date { CrewRepository.parse(s) ?? Date() }

    // MARK: Polls

    func fetchPolls(crewId: UUID, expeditionId: UUID?) async throws -> [Poll] {
        try await session()
        // Deadlines are enforced lazily: opening the list closes what expired.
        try? await supabase.rpc("settle_polls", params: ["p_crew_id": crewId.uuidString]).execute()

        struct Row: Decodable {
            let id: UUID
            let crewId: UUID
            let expeditionId: UUID?
            let dayIndex: Int?
            let kind: PollKind
            let question: String
            let createdBy: UUID?
            let closesAt: String?
            let allowMemberOptions: Bool
            let closeWhenAllVoted: Bool
            let status: String
            let winnerOptionId: UUID?
            let pollOptions: [Opt]
            let pollVotes: [Vote]
            struct Opt: Decodable {
                let id: UUID
                let label: String
                let payload: PollPayload?
                let addedBy: UUID?
                let position: Int
                enum CodingKeys: String, CodingKey { case id, label, payload, position, addedBy = "added_by" }
            }
            struct Vote: Decodable {
                let userId: UUID
                let optionId: UUID
                enum CodingKeys: String, CodingKey { case userId = "user_id", optionId = "option_id" }
            }
            enum CodingKeys: String, CodingKey {
                case id, kind, question, status
                case crewId = "crew_id", expeditionId = "expedition_id", dayIndex = "day_index"
                case createdBy = "created_by", closesAt = "closes_at"
                case allowMemberOptions = "allow_member_options", closeWhenAllVoted = "close_when_all_voted"
                case winnerOptionId = "winner_option_id", pollOptions = "poll_options", pollVotes = "poll_votes"
            }
        }
        var query = supabase.from("polls")
            .select("id, crew_id, expedition_id, day_index, kind, question, created_by, closes_at, allow_member_options, close_when_all_voted, status, winner_option_id, poll_options(id, label, payload, added_by, position), poll_votes(user_id, option_id)")
            .eq("crew_id", value: crewId.uuidString)
        if let expeditionId { query = query.eq("expedition_id", value: expeditionId.uuidString) }
        else { query = query.is("expedition_id", value: nil) }
        let rows: [Row] = try await query.order("created_at", ascending: false).execute().value
        return rows.map { r in
            Poll(id: r.id, crewId: r.crewId, expeditionId: r.expeditionId, dayIndex: r.dayIndex, kind: r.kind,
                 question: r.question, createdBy: r.createdBy, closesAt: r.closesAt.map(Self.date),
                 allowMemberOptions: r.allowMemberOptions, closeWhenAllVoted: r.closeWhenAllVoted,
                 isClosed: r.status == "closed", winnerOptionId: r.winnerOptionId,
                 options: r.pollOptions.sorted { $0.position < $1.position }.map {
                     PollOption(id: $0.id, label: $0.label, payload: $0.payload ?? PollPayload(), addedBy: $0.addedBy, position: $0.position)
                 },
                 votes: r.pollVotes.map { PollVote(userId: $0.userId, optionId: $0.optionId) })
        }
    }

    @discardableResult
    func createPoll(crewId: UUID, expeditionId: UUID?, day: Int?, kind: PollKind, question: String,
                    options: [(label: String, payload: PollPayload)], closesAt: Date?,
                    allowMemberOptions: Bool, closeWhenAllVoted: Bool) async throws -> UUID {
        struct Opt: Encodable { let label: String; let payload: PollPayload }
        struct Params: Encodable {
            let p_crew_id: UUID; let p_expedition_id: UUID?; let p_day: Int?; let p_kind: String; let p_question: String
            let p_options: [Opt]; let p_closes_at: String?; let p_allow_member_options: Bool; let p_close_when_all_voted: Bool
        }
        do {
            return try await supabase.rpc("create_poll", params: Params(
                p_crew_id: crewId, p_expedition_id: expeditionId, p_day: day, p_kind: kind.rawValue, p_question: question,
                p_options: options.map { Opt(label: $0.label, payload: $0.payload) },
                p_closes_at: closesAt.map(iso), p_allow_member_options: allowMemberOptions,
                p_close_when_all_voted: closeWhenAllVoted)).execute().value
        } catch { throw fail(error) }
    }

    func addOption(pollId: UUID, label: String, payload: PollPayload = PollPayload()) async throws {
        struct Params: Encodable { let p_poll_id: UUID; let p_label: String; let p_payload: PollPayload }
        do { try await supabase.rpc("add_poll_option", params: Params(p_poll_id: pollId, p_label: label, p_payload: payload)).execute() }
        catch { throw fail(error) }
    }

    func vote(pollId: UUID, optionId: UUID) async throws {
        struct Params: Encodable { let p_poll_id: UUID; let p_option_id: UUID }
        do { try await supabase.rpc("vote_poll", params: Params(p_poll_id: pollId, p_option_id: optionId)).execute() }
        catch { throw fail(error) }
    }

    func closePoll(pollId: UUID, winner: UUID? = nil) async throws {
        struct Params: Encodable { let p_poll_id: UUID; let p_winner: UUID? }
        do { try await supabase.rpc("close_poll", params: Params(p_poll_id: pollId, p_winner: winner)).execute() }
        catch { throw fail(error) }
    }

    // MARK: Trip day

    func startExpedition(id: UUID, mode: String) async throws {
        struct Params: Encodable { let p_expedition_id: UUID; let p_mode: String }
        do { try await supabase.rpc("start_expedition", params: Params(p_expedition_id: id, p_mode: mode)).execute() }
        catch { throw fail(error) }
    }

    func finishExpedition(id: UUID) async throws {
        do { try await supabase.rpc("finish_expedition", params: ["p_expedition_id": id.uuidString]).execute() }
        catch { throw fail(error) }
    }

    func joinExpedition(id: UUID) async throws {
        do { try await supabase.rpc("join_expedition", params: ["p_expedition_id": id.uuidString]).execute() }
        catch { throw fail(error) }
    }

    func setRole(expeditionId: UUID, userId: UUID, role: AwarenessRole?) async throws {
        struct Params: Encodable { let p_expedition_id: UUID; let p_user_id: UUID; let p_role: String? }
        do { try await supabase.rpc("set_expedition_role", params: Params(p_expedition_id: expeditionId, p_user_id: userId, p_role: role?.rawValue)).execute() }
        catch { throw fail(error) }
    }

    func setMyCar(expeditionId: UUID, driverId: UUID?) async throws {
        struct Params: Encodable { let p_expedition_id: UUID; let p_driver_id: UUID? }
        do { try await supabase.rpc("set_my_car", params: Params(p_expedition_id: expeditionId, p_driver_id: driverId)).execute() }
        catch { throw fail(error) }
    }

    func setReadiness(expeditionId: UUID, offlinePct: Int, gpsOn: Bool, battery: Int?, ready: Bool) async throws {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_offline_pct: Int; let p_gps_on: Bool; let p_battery: Int?; let p_ready: Bool
        }
        do {
            try await supabase.rpc("set_readiness", params: Params(
                p_expedition_id: expeditionId, p_offline_pct: offlinePct, p_gps_on: gpsOn, p_battery: battery, p_ready: ready)).execute()
        } catch { throw fail(error) }
    }

    func fetchReadiness(expeditionId: UUID) async throws -> [Readiness] {
        try await session()
        struct Row: Decodable {
            let userId: UUID; let offlinePct: Int; let gpsOn: Bool; let battery: Int?; let ready: Bool
            enum CodingKeys: String, CodingKey { case userId = "user_id", offlinePct = "offline_pct", gpsOn = "gps_on", battery, ready }
        }
        let rows: [Row] = try await supabase.from("expedition_readiness").select()
            .eq("expedition_id", value: expeditionId.uuidString).execute().value
        return rows.map { Readiness(userId: $0.userId, offlinePct: $0.offlinePct, gpsOn: $0.gpsOn, battery: $0.battery, ready: $0.ready) }
    }

    // MARK: Live location

    func startShare(expeditionId: UUID, mode: String, until: Date, lowPower: Bool) async throws {
        struct Params: Encodable { let p_expedition_id: UUID; let p_mode: String; let p_until: String; let p_low_power: Bool }
        do {
            try await supabase.rpc("start_live_share", params: Params(
                p_expedition_id: expeditionId, p_mode: mode, p_until: iso(until), p_low_power: lowPower)).execute()
        } catch { throw fail(error) }
    }

    func stopShare(expeditionId: UUID) async throws {
        do { try await supabase.rpc("stop_live_share", params: ["p_expedition_id": expeditionId.uuidString]).execute() }
        catch { throw fail(error) }
    }

    func upsertFix(expeditionId: UUID, lat: Double, lng: Double, altitude: Double?, accuracy: Double?,
                   speed: Double?, heading: Double?, battery: Int?, recordedAt: Date) async throws {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_lat: Double; let p_lng: Double; let p_altitude: Double?
            let p_accuracy: Double?; let p_speed: Double?; let p_heading: Double?; let p_battery: Int?; let p_recorded_at: String
        }
        try await supabase.rpc("upsert_live_fix", params: Params(
            p_expedition_id: expeditionId, p_lat: lat, p_lng: lng, p_altitude: altitude, p_accuracy: accuracy,
            p_speed: speed, p_heading: heading, p_battery: battery, p_recorded_at: iso(recordedAt))).execute()
    }

    func fetchFixes(expeditionId: UUID) async throws -> [LiveFix] {
        try await session()
        struct Row: Decodable {
            let userId: UUID; let lat: Double; let lng: Double; let altitude: Double?; let accuracy: Double?
            let speed: Double?; let heading: Double?; let battery: Int?; let recordedAt: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id", lat, lng, altitude, accuracy, speed, heading, battery, recordedAt = "recorded_at"
            }
        }
        let rows: [Row] = try await supabase.from("live_fixes").select()
            .eq("expedition_id", value: expeditionId.uuidString).execute().value
        return rows.map {
            LiveFix(userId: $0.userId, lat: $0.lat, lng: $0.lng, altitude: $0.altitude, accuracy: $0.accuracy,
                    speed: $0.speed, heading: $0.heading, battery: $0.battery, recordedAt: Self.date($0.recordedAt))
        }
    }

    func fetchShares(expeditionId: UUID) async throws -> [LiveShare] {
        try await session()
        struct Row: Decodable {
            let userId: UUID; let mode: String; let until: String; let lowPower: Bool
            enum CodingKeys: String, CodingKey { case userId = "user_id", mode, until, lowPower = "low_power" }
        }
        let rows: [Row] = try await supabase.from("live_shares").select()
            .eq("expedition_id", value: expeditionId.uuidString).execute().value
        return rows.map { LiveShare(userId: $0.userId, mode: $0.mode, until: Self.date($0.until), lowPower: $0.lowPower) }
            .filter { $0.until > Date() }
    }

    // MARK: Convoy

    @discardableResult
    func postConvoyEvent(expeditionId: UUID, kind: String, status: ConvoyReason? = nil, etaMin: Int? = nil,
                         askOthers: String? = nil, lat: Double? = nil, lng: Double? = nil) async throws -> UUID {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_kind: String; let p_status: String?; let p_eta_min: Int?
            let p_ask_others: String?; let p_lat: Double?; let p_lng: Double?
        }
        do {
            return try await supabase.rpc("post_convoy_event", params: Params(
                p_expedition_id: expeditionId, p_kind: kind, p_status: status?.rawValue, p_eta_min: etaMin,
                p_ask_others: askOthers, p_lat: lat, p_lng: lng)).execute().value
        } catch { throw fail(error) }
    }

    func fetchConvoyEvents(expeditionId: UUID, since: Date) async throws -> [ConvoyEvent] {
        try await session()
        struct Row: Decodable {
            let id: UUID; let driverId: UUID; let kind: String; let status: String?; let etaMin: Int?
            let askOthers: String?; let lat: Double?; let lng: Double?; let createdAt: String
            enum CodingKeys: String, CodingKey {
                case id, kind, status, lat, lng, driverId = "driver_id", etaMin = "eta_min", askOthers = "ask_others", createdAt = "created_at"
            }
        }
        let rows: [Row] = try await supabase.from("convoy_events").select()
            .eq("expedition_id", value: expeditionId.uuidString)
            .gte("created_at", value: iso(since))
            .order("created_at", ascending: false).execute().value
        return rows.map {
            ConvoyEvent(id: $0.id, driverId: $0.driverId, kind: $0.kind, status: $0.status.flatMap(ConvoyReason.init(rawValue:)),
                        etaMin: $0.etaMin, askOthers: $0.askOthers, lat: $0.lat, lng: $0.lng, createdAt: Self.date($0.createdAt))
        }
    }

    // MARK: Alerts + awareness events

    func fetchRules(expeditionId: UUID) async throws -> [AlertRule] {
        try await session()
        struct Row: Decodable { let kind: String; let mode: String; let threshold: Double?; let enabled: Bool }
        let rows: [Row] = try await supabase.from("alert_rules").select()
            .eq("expedition_id", value: expeditionId.uuidString).execute().value
        return rows.compactMap { r in
            guard let k = AlertKind(rawValue: r.kind), let m = AwarenessMode(rawValue: r.mode) else { return nil }
            return AlertRule(kind: k, mode: m, threshold: r.threshold ?? AlertDefaults.threshold(k, m), enabled: r.enabled)
        }
    }

    func setRule(expeditionId: UUID, rule: AlertRule) async throws {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_kind: String; let p_mode: String; let p_threshold: Double; let p_enabled: Bool
        }
        do {
            try await supabase.rpc("set_alert_rule", params: Params(
                p_expedition_id: expeditionId, p_kind: rule.kind.rawValue, p_mode: rule.mode.rawValue,
                p_threshold: rule.threshold, p_enabled: rule.enabled)).execute()
        } catch { throw fail(error) }
    }

    @discardableResult
    func postAwareness(expeditionId: UUID, kind: String, value: Double? = nil, lat: Double? = nil, lng: Double? = nil,
                       target: UUID? = nil) async throws -> UUID {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_kind: String; let p_value: Double?
            let p_lat: Double?; let p_lng: Double?; let p_target: UUID?
        }
        do {
            return try await supabase.rpc("post_awareness_event", params: Params(
                p_expedition_id: expeditionId, p_kind: kind, p_value: value, p_lat: lat, p_lng: lng, p_target: target))
                .execute().value
        } catch { throw fail(error) }
    }

    func fetchAwareness(expeditionId: UUID, since: Date) async throws -> [AwarenessEvent] {
        try await session()
        struct Row: Decodable {
            let id: UUID; let userId: UUID; let kind: String; let value: Double?; let targetUserId: UUID?
            let lat: Double?; let lng: Double?; let createdAt: String
            enum CodingKeys: String, CodingKey {
                case id, kind, value, lat, lng, userId = "user_id", targetUserId = "target_user_id", createdAt = "created_at"
            }
        }
        let rows: [Row] = try await supabase.from("awareness_events").select()
            .eq("expedition_id", value: expeditionId.uuidString)
            .gte("created_at", value: iso(since))
            .order("created_at", ascending: false).execute().value
        return rows.map {
            AwarenessEvent(id: $0.id, userId: $0.userId, kind: $0.kind, value: $0.value, targetUserId: $0.targetUserId,
                           lat: $0.lat, lng: $0.lng, createdAt: Self.date($0.createdAt))
        }
    }
}

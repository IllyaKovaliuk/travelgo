import SwiftUI
import CoreLocation
import MapKit

/// Tap a person on the map: how far, which way, last known altitude and battery, navigate or ping.
struct LiveMemberSheet: View {
    let person: CrewPerson
    let fix: LiveFix
    let session: LiveSession
    var onClose: () -> Void

    @State private var pinged = false

    private var mine: CLLocationCoordinate2D? { session.myLocation?.coordinate }
    private var distance: Double? { mine.map { Geo.distance($0, fix.coordinate) } }
    private var bearing: Double? { mine.map { Geo.bearing(from: $0, to: fix.coordinate) } }
    private var lost: Bool { fix.freshness() != .live }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PersonAvatar(person: person, size: 52)
                    .overlay(Circle().stroke(lost ? NTColor.gold : NTColor.sage, style: StrokeStyle(lineWidth: 3, dash: lost ? [4, 3] : [])).padding(-4))
                    .padding(4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.displayName).font(NTFont.heading(22, .extraBold)).lineLimit(1)
                    Text(lost ? String(localized: "Lost signal · last seen \(fix.ageLabel().lowercased()) ago") : String(localized: "Live"))
                        .font(NTFont.body(13.5, .medium)).foregroundStyle(lost ? NTColor.gold : NTColor.sage)
                }
                Spacer()
                CircleIconButton(icon: "xmark", label: "Close", filled: true, action: onClose)
            }
            HStack(spacing: 10) {
                stat(distance.map(Geo.distanceLabel) ?? "—", sub: bearing.map { "\(Int($0))° \(Geo.compass($0))" } ?? "")
                stat(fix.altitude.map { "\(Int($0)) m" } ?? "—", sub: "LAST ALT")
                stat(fix.battery.map { "\($0)%" } ?? "—", sub: "BATTERY", color: (fix.battery ?? 100) < 20 ? NTColor.hardBright : NTColor.milk)
            }
            Text(String(format: "LAST FIX %@ · %.4f°N %.4f°E", fix.recordedAt.formatted(.dateTime.hour().minute()), fix.lat, fix.lng)
                 + (fix.accuracy.map { " · ±\(Int($0)) M" } ?? "")
                 + (lost ? (fix.speed.map { $0 > 0 ? "\nMOVING \(String(format: "%.1f", $0 * 3.6)) KM/H WHEN SIGNAL DROPPED" : "" } ?? "") : ""))
                .font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55))
            HStack(spacing: 12) {
                Button { navigate() } label: {
                    Label("Navigate to last fix", systemImage: "location.north.fill").font(NTFont.body(15, .semibold))
                        .foregroundStyle(Color(hex: 0x231007)).frame(maxWidth: .infinity).frame(height: 54).background(Capsule().fill(NTColor.accent))
                }.buttonStyle(.plain)
                Button {
                    pinged = true; UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task { await session.ping(person.id) }
                } label: {
                    Text(pinged ? "Pinged" : "Ping").font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 28).frame(height: 54).background(Capsule().fill(NTColor.milk))
                }.buttonStyle(.plain).disabled(pinged)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 20)
        .background(NTColor.pineElevated.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
    }

    private func stat(_ value: String, sub: String, color: Color = NTColor.milk) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(NTFont.heading(22, .extraBold)).foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
            Text(sub).font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).crewCard(radius: 14)
    }

    private func navigate() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: fix.coordinate))
        item.name = person.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

/// The stopped driver's view: one tap for the reason, how long until back on the road, what the others should do.
struct ConvoyStatusSheet: View {
    let expedition: Expedition
    let alert: LiveAlert
    let session: LiveSession
    var onClose: () -> Void

    @State private var reason: ConvoyReason = .flatTire
    @State private var eta = 20
    @State private var ask = "wait"
    @State private var isSending = false

    private var minutes: Int { max(1, Int(Date().timeIntervalSince(alert.since) / 60)) }
    private var carNo: Int {
        let d = session.members.first { $0.person.id == alert.subject }?.carDriverId ?? alert.subject
        let ids = Set(session.members.map { $0.carDriverId ?? $0.person.id })
        return (ids.sorted { $0.uuidString < $1.uuidString }.firstIndex(of: d) ?? 0) + 1
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("CAR \(carNo) · STOPPED \(minutes) MIN").font(NTFont.mono(10.5, .semibold)).foregroundStyle(NTColor.gold)
                Text("What happened?").font(NTFont.heading(30, .extraBold)).tracking(-0.8)
                Text("The rest of the convoy sees this instantly.").font(NTFont.body(14)).foregroundStyle(NTColor.milk(0.7))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(ConvoyReason.allCases) { r in
                        Button { reason = r } label: {
                            HStack(spacing: 10) {
                                Image(systemName: r.icon); Text(r.title).font(NTFont.body(15, .semibold)); Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16).frame(height: 58)
                            .foregroundStyle(reason == r ? NTColor.pine : NTColor.milk)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(reason == r ? NTColor.milk : NTColor.pineRaised))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(reason == r ? .clear : NTColor.pineLine, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }

                Button { Task { await send(kind: "help") } } label: {
                    Label("Need help — tell the crew", systemImage: "exclamationmark.triangle").font(NTFont.body(15, .semibold))
                        .foregroundStyle(NTColor.hardBright).frame(maxWidth: .infinity).frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NTColor.hard.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NTColor.hard.opacity(0.6), lineWidth: 1))
                }.buttonStyle(.plain)
                Text("This alerts your crew only. It does not call emergency services — use SOS to message your emergency contacts.")
                    .font(NTFont.body(12)).foregroundStyle(NTColor.milk(0.55))

                MonoLabel("Back on the road in")
                CrewSegments(items: [(10, "10 min"), (20, "20 min"), (40, "40+ min")], selection: $eta)

                MonoLabel("Car \(max(carNo - 1, 1)) should")
                CrewSegments(items: [("keep_going", String(localized: "Keep going")), ("wait", String(localized: "Wait at a safe stop"))], selection: $ask)

                NTAccentButton(title: isSending ? "Sending…" : "Send to convoy") { Task { await send(kind: "status") } }.disabled(isSending)
                Button { Task { await session.reportResumed(); onClose() } } label: {
                    Text("We're moving again").font(NTFont.body(14.5, .semibold)).underline().frame(maxWidth: .infinity).frame(height: 44)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 12)
        }
        .background(NTColor.pineElevated.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
    }

    private func send(kind: String) async {
        isSending = true
        _ = try? await CrewLiveRepository.shared.postConvoyEvent(
            expeditionId: expedition.id, kind: kind, status: reason, etaMin: eta, askOthers: ask,
            lat: session.myLocation?.coordinate.latitude, lng: session.myLocation?.coordinate.longitude)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await session.refresh()
        isSending = false
        onClose()
    }
}

/// Crew placed on the elevation profile of the current route: who is where along it and how high.
struct AscentProfileView: View {
    let session: LiveSession
    var onFocus: (UUID) -> Void

    private struct Mark: Identifiable { let id: UUID; let x: Double; let alt: Double; let fix: LiveFix }

    private var marks: [Mark] {
        session.fixes.values.compactMap { f in
            guard let alt = f.altitude, let p = Geo.project(f.coordinate, onto: session.routeLine) else { return nil }
            let total = max(totalLength, 1)
            return Mark(id: f.userId, x: min(max(p.along / total, 0), 1), alt: alt, fix: f)
        }
    }

    private var totalLength: Double {
        zip(session.routeLine, session.routeLine.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    private var lowAlt: Double { min(marks.map(\.alt).min() ?? session.profileHighM, session.profileHighM - max(session.profileAscentM, 50)) }
    private var highAlt: Double { max(session.profileHighM, marks.map(\.alt).max() ?? 0, lowAlt + 50) }

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CREW ON PROFILE").font(NTFont.mono(10.5, .semibold))
                    Spacer()
                    if let spread { Text("SPREAD \(Geo.distanceLabel(spread.0)) · ↕ \(Int(spread.1)) M").font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55)) }
                }
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        profilePath(in: geo.size).stroke(NTColor.accent, lineWidth: 2.5)
                        ForEach(marks) { m in
                            let pt = point(x: m.x, alt: m.alt, in: geo.size)
                            let stopped = session.alerts.contains { $0.subject == m.id }
                            Button { onFocus(m.id) } label: {
                                Text(initials(m.id)).font(NTFont.mono(9, .semibold))
                                    .frame(width: 26, height: 26).background(Circle().fill(NTColor.pineRaised))
                                    .overlay(Circle().stroke(stopped ? NTColor.gold : (m.fix.freshness() == .live ? NTColor.sage : NTColor.gold),
                                                             style: StrokeStyle(lineWidth: 2, dash: m.fix.freshness() == .live ? [] : [3, 2])))
                            }
                            .buttonStyle(.plain).position(pt)
                        }
                    }
                }
                .frame(height: 170)
                if session.profile.isEmpty {
                    Text("Add a route with an elevation profile to see the crew on it.").font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55))
                }
            }
            .padding(14).crewCard(radius: 22)

            if let lag = laggard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(lag.name) · \(lag.line)").font(NTFont.heading(17, .bold)).lineLimit(2)
                    HStack(spacing: 10) {
                        Button { Task { await session.setRegroup(at: lag.leadCoordinate) } } label: {
                            Text("Regroup at \(Int(lag.leadAlt)) m").font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.pine)
                                .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(NTColor.milk))
                        }.buttonStyle(.plain)
                        Button { Task { await session.ping(lag.id) } } label: {
                            Text("Ping").font(NTFont.body(15, .semibold)).padding(.horizontal, 26).frame(height: 48)
                                .background(Capsule().fill(NTColor.pineRaised)).overlay(Capsule().stroke(NTColor.pineLine, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x2A2210)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NTColor.gold.opacity(0.5), lineWidth: 1))
            }
        }
    }

    private func point(x: Double, alt: Double, in size: CGSize) -> CGPoint {
        let y = 1 - (alt - lowAlt) / max(highAlt - lowAlt, 1)
        return CGPoint(x: 14 + x * (size.width - 28), y: 14 + y * (size.height - 28))
    }

    private func profilePath(in size: CGSize) -> Path {
        var p = Path()
        let samples = session.profile
        guard samples.count > 1 else { return p }
        let span = max(session.profileAscentM, 50)
        for (i, s) in samples.enumerated() {
            let x = Double(i) / Double(samples.count - 1)
            let alt = (session.profileHighM - span) + s * span
            let pt = point(x: x, alt: alt, in: size)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }

    private func initials(_ id: UUID) -> String { session.person[id]?.initials ?? "?" }

    private var spread: (Double, Double)? {
        guard marks.count > 1 else { return nil }
        let xs = marks.map(\.x), alts = marks.map(\.alt)
        return ((xs.max()! - xs.min()!) * totalLength, alts.max()! - alts.min()!)
    }

    /// The person furthest behind the lead — the one the regroup button is about.
    private var laggard: (id: UUID, name: String, line: String, leadAlt: Double, leadCoordinate: CLLocationCoordinate2D)? {
        guard marks.count > 1, let lead = marks.max(by: { $0.x < $1.x }), let last = marks.min(by: { $0.x < $1.x }), last.id != lead.id else { return nil }
        let gap = (lead.x - last.x) * totalLength
        guard gap > 100 else { return nil }
        let name = session.person[last.id]?.displayName.split(separator: " ").first.map(String.init) ?? "—"
        let fresh = last.fix.freshness() == .live ? "" : " " + String(localized: "· last seen \(last.fix.ageLabel().lowercased()) ago")
        return (last.id, name, "\(Int(lead.alt - last.alt)) m " + String(localized: "below the lead") + " · \(Geo.distanceLabel(gap)) " + String(localized: "back") + fresh,
                lead.alt, lead.fix.coordinate)
    }
}

/// Per-expedition rules: who leads and sweeps, and the thresholds per mode.
struct CrewAlertsView: View {
    let expedition: Expedition
    var onClose: () -> Void

    private let session = LiveSession.shared
    @State private var mode: AwarenessMode = LiveSession.shared.mode
    @State private var canManage = false
    @State private var local: [String: AlertRule] = [:]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Crew alerts").font(NTFont.heading(24, .extraBold))
                    Spacer()
                    CircleIconButton(icon: "xmark", label: "Close", filled: true, action: onClose)
                }
                Text("Everyone on \(expedition.name) gets these. Same rules on the road, the trail and the climb — only the thresholds change.")
                    .font(NTFont.body(14)).foregroundStyle(NTColor.milk(0.7))

                HStack(spacing: 10) {
                    roleCard(.lead, title: "LEAD")
                    roleCard(.sweep, title: "SWEEP · LAST")
                }
                CrewSegments(items: AwarenessMode.allCases.map { ($0, $0.title) }, selection: $mode)

                VStack(spacing: 0) {
                    ForEach(Array(AlertKind.allCases.enumerated()), id: \.element) { i, kind in
                        if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                        ruleRow(kind)
                    }
                }
                .crewCard()

                Text(canManage ? "ORGANIZERS EDIT · EVERYONE SEES THE SAME RULES." : "ONLY ORGANIZERS EDIT THE RULES.")
                    .font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.55))
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 20)
        }
        .background(NTColor.pineElevated.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .task {
            await session.attach(expedition)
            let me = session.myId
            canManage = expedition.organizerId == me || session.members.first { $0.person.id == me }?.role == .organizer
            local = Dictionary(uniqueKeysWithValues: AlertKind.allCases.flatMap { k in AwarenessMode.allCases.map { m -> (String, AlertRule) in
                let key = "\(k.rawValue)|\(m.rawValue)"
                return (key, session.rules[key] ?? AlertRule(kind: k, mode: m, threshold: AlertDefaults.threshold(k, m), enabled: k != .turnaround))
            } })
        }
    }

    private func roleCard(_ role: AwarenessRole, title: String) -> some View {
        let holder = session.members.first { $0.awarenessRole == role }
        return Menu {
            if canManage {
                ForEach(session.members) { m in
                    Button(m.person.displayName) { Task { try? await CrewLiveRepository.shared.setRole(expeditionId: expedition.id, userId: m.person.id, role: role); await session.attach(expedition) } }
                }
                if holder != nil { Button("None", role: .destructive) { Task { try? await CrewLiveRepository.shared.setRole(expeditionId: expedition.id, userId: holder!.person.id, role: nil); await session.attach(expedition) } } }
            }
        } label: {
            HStack(spacing: 10) {
                if let p = holder?.person { PersonAvatar(person: p, size: 34) } else { Circle().fill(NTColor.pine).frame(width: 34, height: 34) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NTFont.mono(9, .medium)).foregroundStyle(NTColor.milk(0.55))
                    Text(holder?.person.displayName.split(separator: " ").first.map(String.init) ?? String(localized: "Not set")).font(NTFont.body(15, .semibold))
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity).crewCard(radius: 16)
        }
        .disabled(!canManage)
    }

    private func ruleRow(_ kind: AlertKind) -> some View {
        let key = "\(kind.rawValue)|\(mode.rawValue)"
        let rule = local[key] ?? AlertRule(kind: kind, mode: mode, threshold: AlertDefaults.threshold(kind, mode), enabled: true)
        return HStack(spacing: 12) {
            Circle().fill(kind == .lowBattery ? NTColor.hard : (kind == .noSignal ? NTColor.milk(0.4) : NTColor.gold)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(NTFont.body(15, .semibold))
                if kind == .turnaround {
                    Text(rule.threshold > 0 ? "AT " + String(format: "%02d:%02d", Int(rule.threshold) / 60, Int(rule.threshold) % 60) : "OFF")
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                } else {
                    Text("\(Int(rule.threshold)) \(AlertDefaults.unit(kind, mode))").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                }
            }
            Spacer()
            if canManage && kind != .turnaround {
                Stepper("", value: Binding(get: { rule.threshold }, set: { v in update(rule, threshold: v) }),
                        in: 1...(AlertDefaults.threshold(kind, mode) * 10), step: step(kind, mode)).labelsHidden().fixedSize()
            }
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { v in update(rule, enabled: v) })).labelsHidden().tint(NTColor.sage).disabled(!canManage)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func step(_ kind: AlertKind, _ mode: AwarenessMode) -> Double {
        switch AlertDefaults.unit(kind, mode) { case "MIN": return 1; case "%": return 5; default: return AlertDefaults.threshold(kind, mode) >= 1_000 ? 500 : 50 }
    }

    private func update(_ rule: AlertRule, threshold: Double? = nil, enabled: Bool? = nil) {
        var r = rule
        if let threshold { r.threshold = threshold }
        if let enabled { r.enabled = enabled }
        local["\(r.kind.rawValue)|\(r.mode.rawValue)"] = r
        Task { try? await CrewLiveRepository.shared.setRule(expeditionId: expedition.id, rule: r); await session.attach(expedition) }
    }
}

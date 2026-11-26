import SwiftUI

/// Part 3 — the Journal. A tab within `ProfileView` (`Tab.journal`), not a
/// separate screen, listing what `VisitsMonitor`'s passive detection has
/// found. Pending entries are real detections nobody has reviewed yet —
/// shown honestly as "needs review," never silently folded into anything
/// else (see `ProfileView.countriesVisited`, which only ever counts
/// `kept`). Three ways to handle an entry, matching the spec exactly:
/// attach it to a route already published, go record a brand new one now
/// ("converted into a full recording"), or just leave it as a plain
/// journal entry — the last one needs no action at all.
struct JournalView: View {
    @State private var visits: [RouteRepository.Visit] = []
    @State private var myRoutes: [Route] = []
    @State private var isLoading = true
    @State private var attachingVisit: RouteRepository.Visit?
    @State private var showRecordFlow = false
    @State private var exportText: String?
    @State private var busyId: String?

    private var pending: [RouteRepository.Visit] { visits.filter { $0.status == "pending" } }
    private var kept: [RouteRepository.Visit] { visits.filter { $0.status == "kept" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if isLoading {
                ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 40)
            } else if visits.isEmpty {
                emptyState
            } else {
                if !pending.isEmpty {
                    sectionLabel("NEEDS REVIEW (\(pending.count))")
                    VStack(spacing: 10) { ForEach(pending) { pendingCard($0) } }
                }
                if !kept.isEmpty {
                    sectionLabel("KEPT (\(kept.count))")
                    VStack(spacing: 10) { ForEach(kept) { keptCard($0) } }
                }
            }
        }
        .task { await load() }
        .sheet(item: $attachingVisit) { visit in
            attachRoutePicker(visit)
        }
        .ntFullScreenCover(isPresented: $showRecordFlow, edgeSwipeBack: false, onDismiss: { Task { await load() } }) {
            LogRouteFlow()
        }
        .sheet(isPresented: Binding(get: { exportText != nil }, set: { if !$0 { exportText = nil } })) {
            if let exportText {
                ShareLink(item: exportText) {
                    Label("Share visits.json", systemImage: "square.and.arrow.up")
                        .font(NTFont.body(14.5, .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .padding(24)
                .presentationDetents([.height(140)])
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Passive stops CoreLocation noticed — kept ones count toward your countries, nothing else on your profile.")
                .font(NTFont.body(12, .light))
                .foregroundStyle(NTColor.milk(0.5))
            Spacer()
            if !visits.isEmpty {
                Button { exportVisits() } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 15)).foregroundStyle(NTColor.milk(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.magnifyingglass").font(.system(size: 24)).foregroundStyle(NTColor.milk(0.3))
            Text(AppPreferences.visitsMonitoringEnabled ? "Nothing detected yet" : "Passive detection is off")
                .font(NTFont.body(13.5, .medium)).foregroundStyle(NTColor.milk(0.55))
            if !AppPreferences.visitsMonitoringEnabled {
                Text("Turn it on in Settings to start filling this in on its own.")
                    .font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.4))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
    }

    private func pendingCard(_ visit: RouteRepository.Visit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            visitInfo(visit)
            HStack(spacing: 10) {
                actionButton("Keep", tint: NTColor.sage, filled: true) { setStatus(visit, "kept") }
                actionButton("Dismiss", tint: NTColor.milk(0.5), filled: false) { setStatus(visit, "dismissed") }
            }
        }
        .padding(16)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        .opacity(busyId == visit.id.uuidString ? 0.5 : 1)
        .disabled(busyId == visit.id.uuidString)
    }

    private func keptCard(_ visit: RouteRepository.Visit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            visitInfo(visit)
            if let linkedRouteId = visit.linkedRouteId, let route = myRoutes.first(where: { $0.id == linkedRouteId.uuidString }) {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: 11)).foregroundStyle(NTColor.sage)
                    Text(route.title.replacingOccurrences(of: "\n", with: " "))
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.sage)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 10) {
                    actionButton("Attach a route", tint: NTColor.water, filled: false) { attachingVisit = visit }
                    actionButton("Record now", tint: NTColor.water, filled: false) { showRecordFlow = true }
                }
            }
        }
        .padding(16)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        .contextMenu {
            Button(role: .destructive) { deleteVisit(visit) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func visitInfo(_ visit: RouteRepository.Visit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(visit.placeName ?? "Unknown place")
                .font(NTFont.body(14.5, .semibold)).foregroundStyle(NTColor.milk)
            Text(dateRangeLabel(visit))
                .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
        }
    }

    private func actionButton(_ title: LocalizedStringKey, tint: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NTFont.body(13, .semibold))
                .foregroundStyle(filled ? NTColor.pine : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(.clear), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func attachRoutePicker(_ visit: RouteRepository.Visit) -> some View {
        NavigationStack {
            List(myRoutes) { route in
                Button {
                    Task {
                        try? await RouteRepository.shared.attachRouteToVisit(id: visit.id.uuidString, routeId: route.id)
                        attachingVisit = nil
                        await load()
                    }
                } label: {
                    Text(route.title.replacingOccurrences(of: "\n", with: " "))
                }
            }
            .navigationTitle("Attach a route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { attachingVisit = nil }
                }
            }
        }
    }

    /// "Svaneti — overnight, Jun 14–15" for a multi-day stay; a same-day
    /// stop just gets the one date. Still-open (`departureAt == nil`)
    /// visits — real but ongoing — show "arrived" instead of a range,
    /// since there's honestly no end date yet.
    private func dateRangeLabel(_ visit: RouteRepository.Visit) -> String {
        let iso = ISO8601DateFormatter()
        guard let arrival = iso.date(from: visit.arrivalAt) else { return "" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        guard let departureStr = visit.departureAt, let departure = iso.date(from: departureStr) else {
            return "arrived \(df.string(from: arrival))"
        }
        let cal = Calendar.current
        if cal.isDate(arrival, inSameDayAs: departure) {
            return df.string(from: arrival)
        }
        let nights = cal.dateComponents([.day], from: cal.startOfDay(for: arrival), to: cal.startOfDay(for: departure)).day ?? 0
        let stayLabel = nights == 1 ? "overnight" : "\(nights) nights"
        return "\(stayLabel), \(df.string(from: arrival))–\(df.string(from: departure))"
    }

    private func load() async {
        async let visitsResult = (try? RouteRepository.shared.fetchVisits()) ?? []
        async let routesResult = (try? RouteRepository.shared.fetchMyRoutesFull()) ?? []
        visits = await visitsResult
        myRoutes = await routesResult
        withAnimation { isLoading = false }
    }

    private func setStatus(_ visit: RouteRepository.Visit, _ status: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        busyId = visit.id.uuidString
        Task {
            try? await RouteRepository.shared.setVisitStatus(id: visit.id.uuidString, status: status)
            await load()
            busyId = nil
        }
    }

    private func deleteVisit(_ visit: RouteRepository.Visit) {
        visits.removeAll { $0.id == visit.id }
        Task { try? await RouteRepository.shared.deleteVisit(id: visit.id.uuidString) }
    }

    /// Real export, not a placeholder — the whole point of "the same
    /// delete/export control they have over routes" is that this data
    /// doesn't get trapped in the app. Plain JSON via the system share
    /// sheet rather than a file-picker save flow, which this app has no
    /// existing pattern for anywhere else.
    private func exportVisits() {
        struct ExportRow: Encodable {
            let place: String?, arrivalAt: String, departureAt: String?, status: String
        }
        let rows = visits.map { ExportRow(place: $0.placeName, arrivalAt: $0.arrivalAt, departureAt: $0.departureAt, status: $0.status) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rows), let json = String(data: data, encoding: .utf8) else { return }
        exportText = json
    }
}

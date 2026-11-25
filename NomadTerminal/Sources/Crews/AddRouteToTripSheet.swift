import SwiftUI

/// Pick Nomad routes to add to a trip's day — the same published routes the
/// feed and Search show, filtered by a text query. Several can be ticked and
/// added at once; the server only accepts public, published routes
/// (`add_route_to_expedition`).
struct AddRouteToTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expeditionId: UUID
    var day: Int? = nil
    let alreadyAdded: Set<UUID>
    var onAdded: () -> Void

    @State private var routes: [Route] = []
    @State private var query = ""
    @State private var selected: [String] = []
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var filtered: [Route] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return routes }
        return routes.filter { $0.title.lowercased().contains(q) || $0.place.lowercased().contains(q) }
    }

    private var selectedKm: Double {
        routes.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.distanceKM }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NTColor.pine.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(icon: "xmark", label: "Close", filled: true) { dismiss() }
                    Spacer()
                    Text("Add route").font(NTFont.body(17, .semibold))
                    Spacer()
                    if let day {
                        StatusChip(text: "Day \(day)", color: NTColor.accent)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NTColor.milk(0.55))
                    TextField("Search your routes", text: $query)
                        .font(NTFont.body(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.horizontal, 16).frame(height: 50)
                .crewCard(radius: 25)
                .padding(.horizontal, 16).padding(.top, 14)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        if isLoading {
                            ProgressView().tint(NTColor.milk).padding(.top, 40)
                        } else if filtered.isEmpty {
                            Text("No routes found.")
                                .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.55)).padding(.top, 40)
                        } else {
                            ForEach(filtered) { row($0) }
                        }
                        if let errorMessage {
                            Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if !selected.isEmpty {
                Button { addSelected() } label: {
                    HStack(spacing: 10) {
                        Text(isAdding ? "Adding…" : addTitle).font(NTFont.body(16, .semibold))
                        Text(String(format: "%.1f KM", selectedKm)).font(NTFont.mono(11, .medium)).opacity(0.75)
                    }
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(NTColor.accent, in: Capsule())
                    .shadow(color: NTColor.accent.opacity(0.5), radius: 18, y: 10)
                }
                .buttonStyle(.plain).disabled(isAdding)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .foregroundStyle(NTColor.milk)
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task {
            routes = (try? await RouteRepository.shared.fetchRoutes()) ?? []
            isLoading = false
        }
    }

    private var addTitle: String {
        let n = selected.count
        if let day { return String(localized: "Add \(n) to Day \(day)") }
        return String(localized: "Add \(n)")
    }

    private func row(_ route: Route) -> some View {
        let added = UUID(uuidString: route.id).map(alreadyAdded.contains) ?? false
        let on = selected.contains(route.id)
        return Button {
            if on { selected.removeAll { $0 == route.id } } else { selected.append(route.id) }
        } label: {
            HStack(spacing: 12) {
                RouteCoverImage(url: route.coverImageUrl, tint: NTColor.pineRaised)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(15, .semibold)).lineLimit(1)
                    Text("\(route.place) · \(String(format: "%.1f", route.distanceKM)) km")
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55)).lineLimit(1)
                    Text(route.difficulty.rawValue).font(NTFont.mono(9.5, .semibold)).foregroundStyle(route.difficulty.color)
                }
                Spacer()
                if added {
                    Text("IN TRIP").font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55))
                } else {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24)).foregroundStyle(on ? NTColor.accent : NTColor.milk(0.3))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(NTColor.pineRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? NTColor.accent : NTColor.pineLine, lineWidth: on ? 1.5 : 1))
            .opacity(added ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(added || isAdding)
    }

    private func addSelected() {
        isAdding = true
        errorMessage = nil
        Task {
            do {
                for id in selected {
                    guard let routeId = UUID(uuidString: id) else { continue }
                    try await CrewRepository.shared.addRoute(expeditionId: expeditionId, routeId: routeId, day: day)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onAdded()
            } catch {
                errorMessage = error.localizedDescription
                onAdded()
            }
            isAdding = false
        }
    }
}

/// "Add to trip" from a route's own screen: choose one of my open trips.
struct AddToTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let routeId: UUID

    @State private var trips: [Expedition] = []
    @State private var isLoading = true
    @State private var workingId: UUID?
    @State private var doneId: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if isLoading {
                        ProgressView().tint(NTColor.milk).padding(.top, 40)
                    } else if trips.isEmpty {
                        Text("You have no open trips. Create one from the Crews tab.")
                            .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.55))
                            .multilineTextAlignment(.center).padding(.top, 40)
                    } else {
                        ForEach(trips) { trip in
                            Button { add(to: trip) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: trip.tripType.icon).frame(width: 40, height: 40)
                                        .background(Circle().fill(NTColor.milk(0.08)))
                                    Text(trip.name).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                                    Spacer()
                                    if workingId == trip.id { ProgressView().tint(NTColor.milk) }
                                    else if doneId == trip.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(NTColor.sage) }
                                }
                                .padding(12)
                                .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(workingId != nil || doneId == trip.id)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Add to trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task {
            let all = (try? await CrewRepository.shared.fetchMyExpeditions()) ?? []
            trips = all.filter { $0.status == .planning || $0.status == .active }
            isLoading = false
        }
    }

    private func add(to trip: Expedition) {
        workingId = trip.id
        errorMessage = nil
        Task {
            do {
                try await CrewRepository.shared.addRoute(expeditionId: trip.id, routeId: routeId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                doneId = trip.id
            } catch {
                errorMessage = error.localizedDescription
            }
            workingId = nil
        }
    }
}

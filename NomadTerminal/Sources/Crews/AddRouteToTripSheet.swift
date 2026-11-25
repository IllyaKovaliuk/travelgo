import SwiftUI

/// Pick an existing Nomad route to add to a trip — the same published routes
/// the feed and Search show, filtered by a text query. The server only
/// accepts public, published routes (`add_route_to_expedition`).
struct AddRouteToTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expeditionId: UUID
    let alreadyAdded: Set<UUID>
    var onAdded: () -> Void

    @State private var routes: [Route] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var workingId: String?
    @State private var errorMessage: String?

    private var filtered: [Route] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return routes }
        return routes.filter { $0.title.lowercased().contains(q) || $0.place.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
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
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Add a route")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search routes")
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task {
            routes = (try? await RouteRepository.shared.fetchRoutes()) ?? []
            isLoading = false
        }
    }

    private func row(_ route: Route) -> some View {
        let added = UUID(uuidString: route.id).map(alreadyAdded.contains) ?? false
        return Button { add(route) } label: {
            HStack(spacing: 12) {
                RouteCoverImage(url: route.coverImageUrl, tint: NTColor.pineRaised)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                    Text("\(route.place) · \(String(format: "%.0f", route.distanceKM)) km")
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5)).lineLimit(1)
                }
                Spacer()
                if workingId == route.id { ProgressView().tint(NTColor.milk) }
                else { Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 20))
                        .foregroundStyle(added ? NTColor.sage : NTColor.milk(0.7)) }
            }
            .padding(10)
            .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(added || workingId != nil)
    }

    private func add(_ route: Route) {
        guard let routeId = UUID(uuidString: route.id) else { return }
        workingId = route.id
        errorMessage = nil
        Task {
            do {
                try await CrewRepository.shared.addRoute(expeditionId: expeditionId, routeId: routeId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onAdded()
            } catch {
                errorMessage = error.localizedDescription
            }
            workingId = nil
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

import SwiftUI

/// Crews tab — the groups I belong to. Reads come from RLS-scoped selects;
/// creating / joining / leaving are server RPCs (see `CrewRepository`).
struct CrewsView: View {
    @State private var items: [CrewListItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showCreate = false
    @State private var openCrew: CrewListItem?

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading && items.isEmpty {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            Button { openCrew = item } label: { crewCard(item) }
                                .buttonStyle(NTCardPressStyle())
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
                .padding(.bottom, 110)
            }
            .refreshable { await load() }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateCrewView { newId in
                Task {
                    await load()
                    openCrew = items.first { $0.id == newId }
                }
            }
        }
        .ntFullScreenCover(item: $openCrew, onDismiss: { Task { await load() } }) { item in
            CrewDetailView(crewId: item.crew.id, onClose: { openCrew = nil })
        }
    }

    private var header: some View {
        HStack {
            Text("Crews")
                .font(NTFont.heading(30, .extraBold))
            Spacer()
            Button { showCreate = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create a crew")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34))
                .foregroundStyle(NTColor.milk(0.3))
            Text(loadFailed ? "Couldn't load your crews" : "Travel better together")
                .font(NTFont.heading(20, .bold))
            Text(loadFailed
                 ? "Check your connection and pull to refresh."
                 : "A crew is a private group of friends you plan trips with. Start one and invite your people.")
                .font(NTFont.body(14, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
            if !loadFailed {
                NTAccentButton(title: "Create a crew", icon: "plus") { showCreate = true }
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func crewCard(_ item: CrewListItem) -> some View {
        HStack(spacing: 14) {
            RouteCoverImage(url: item.crew.coverImageUrl, tint: NTColor.pineRaised)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.crew.name)
                    .font(NTFont.heading(17, .bold))
                    .lineLimit(1)
                Text("\(item.memberCount) members · \(roleTitle(item.myRole))")
                    .font(NTFont.mono(10.5, .medium)).tracking(0.3)
                    .foregroundStyle(NTColor.milk(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NTColor.milk(0.35))
        }
        .padding(14)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.1), lineWidth: 1))
    }

    private func load() async {
        do {
            items = try await CrewRepository.shared.fetchMyCrews()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

func roleTitle(_ role: CrewRole) -> String {
    switch role {
    case .owner: return String(localized: "Owner")
    case .organizer: return String(localized: "Organizer")
    case .member: return String(localized: "Member")
    }
}

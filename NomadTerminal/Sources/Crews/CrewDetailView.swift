import SwiftUI

/// One crew: cover header, Upcoming / Past expeditions, and a bottom bar with
/// "New expedition" and "Invite". Roster and roles live in a sheet. Every
/// change is an RPC; Report and Block are on the crew itself and on each
/// member (App Review Guideline 1.2).
struct CrewDetailView: View {
    let crewId: UUID
    var onClose: () -> Void

    enum Segment: Hashable { case upcoming, past }

    @State private var crew: Crew?
    @State private var members: [CrewMember] = []
    @State private var expeditions: [Expedition] = []
    @State private var myId: UUID?
    @State private var isLoading = true
    @State private var segment: Segment = .upcoming

    @State private var showInvite = false
    @State private var showMembers = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showReportCrew = false
    @State private var crewReported = false
    @State private var reportUser: CrewPerson?
    @State private var blockUser: CrewPerson?
    @State private var removeUser: CrewPerson?
    @State private var transferUser: CrewPerson?
    @State private var errorMessage: String?
    @State private var showNewTrip = false
    @State private var openExpedition: Expedition?
    @State private var polls: [Poll] = []
    @State private var openPoll: Poll?
    @State private var showNewPoll = false
    @State private var tripPrefill: String?

    private var people: [UUID: CrewPerson] { Dictionary(uniqueKeysWithValues: members.map { ($0.person.id, $0.person) }) }

    private var myRole: CrewRole? { members.first { $0.person.id == myId }?.role }
    private var isManager: Bool { myRole?.isManager ?? false }
    private var isOwner: Bool { myRole == .owner }
    private var upcoming: [Expedition] { expeditions.filter { !$0.isPast } }
    private var past: [Expedition] { expeditions.filter(\.isPast) }

    var body: some View {
        ZStack(alignment: .bottom) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let crew {
                        hero(crew)
                        VStack(alignment: .leading, spacing: 16) {
                            decisions
                            CrewSegments(items: [
                                (Segment.upcoming, String(localized: "Upcoming") + (upcoming.isEmpty ? "" : " · \(upcoming.count)")),
                                (Segment.past, String(localized: "Past")),
                            ], selection: $segment)
                            expeditionsList
                        }
                        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 130)
                    } else if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 160)
                    } else {
                        Text("This crew isn't available.")
                            .font(NTFont.body(14, .medium)).foregroundStyle(NTColor.milk(0.6))
                            .frame(maxWidth: .infinity).padding(.top, 160)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await load() }

            if crew != nil { bottomBar }
            VStack { topBar; Spacer() }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: $showInvite) {
            InviteSheet(crewId: crewId, crewName: crew?.name ?? "") { showInvite = false }
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showMembers) {
            membersSheet.presentationDetents([.large]).presentationCornerRadius(32)
        }
        .sheet(isPresented: $showNewPoll) {
            CreatePollView(crewId: crewId, crewName: crew?.name ?? "") { Task { await load() } }
        }
        .ntFullScreenCover(item: $openPoll, onDismiss: { Task { await load() } }) { poll in
            PollDetailView(pollId: poll.id, crewId: crewId, expeditionId: nil, crewName: crew?.name ?? "",
                           people: people, myId: myId, canManage: isManager || poll.createdBy == myId,
                           onPlanWinner: { option in
                               tripPrefill = option.label
                               openPoll = nil
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showNewTrip = true }
                           },
                           onChanged: { Task { await load() } }, onClose: { openPoll = nil })
        }
        .sheet(isPresented: $showNewTrip, onDismiss: { tripPrefill = nil }) {
            CreateExpeditionView(crewId: crewId, prefillName: tripPrefill) { id in
                Task {
                    await load()
                    openExpedition = expeditions.first { $0.id == id }
                }
            }
        }
        .ntFullScreenCover(item: $openExpedition, onDismiss: { Task { await load() } }) { e in
            ExpeditionDetailView(expeditionId: e.id, onClose: { openExpedition = nil })
        }
        .alert("Rename crew", isPresented: $showRename) {
            TextField("Crew name", text: $renameText)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Leave this crew?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) { leave() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You'll be removed from the crew and its trips.") }
        .alert("Delete this crew?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteCrew() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the crew, its trips and its members' access for everyone.") }
        .confirmationDialog("Why are you reporting this crew?", isPresented: $showReportCrew, titleVisibility: .visible) {
            ForEach(["Spam", "Harassment", "Inappropriate content", "Other"], id: \.self) { reason in
                Button(reason) {
                    crewReported = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task { try? await RouteRepository.shared.report(.crew, id: crewId.uuidString, reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Why are you reporting this user?",
                            isPresented: Binding(get: { reportUser != nil }, set: { if !$0 { reportUser = nil } }),
                            titleVisibility: .visible) {
            ForEach(["Spam", "Harassment", "Inappropriate content", "Other"], id: \.self) { reason in
                Button(reason) {
                    if let person = reportUser {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task { try? await RouteRepository.shared.report(.user, id: person.id.uuidString, reason: reason) }
                    }
                    reportUser = nil
                }
            }
            Button("Cancel", role: .cancel) { reportUser = nil }
        }
        .alert("Block this user?", isPresented: Binding(get: { blockUser != nil }, set: { if !$0 { blockUser = nil } })) {
            Button("Block", role: .destructive) { if let p = blockUser { block(p) }; blockUser = nil }
            Button("Cancel", role: .cancel) { blockUser = nil }
        } message: {
            Text("Their routes, comments and photos will be hidden from you everywhere in Nomad. You can unblock them any time in Settings.")
        }
        .alert("Remove from crew?", isPresented: Binding(get: { removeUser != nil }, set: { if !$0 { removeUser = nil } })) {
            Button("Remove", role: .destructive) { if let p = removeUser { remove(p) }; removeUser = nil }
            Button("Cancel", role: .cancel) { removeUser = nil }
        }
        .alert("Hand over ownership?", isPresented: Binding(get: { transferUser != nil }, set: { if !$0 { transferUser = nil } })) {
            Button("Hand over") { if let p = transferUser { setRole(p, .owner) }; transferUser = nil }
            Button("Cancel", role: .cancel) { transferUser = nil }
        } message: { Text("They become the owner. You stay in the crew as an organizer.") }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            CircleIconButton(icon: "chevron.left", label: "Back", action: onClose)
            Spacer()
            if crew != nil {
                Menu {
                    Button { showMembers = true } label: { Label("Members & roles", systemImage: "person.2") }
                    if myRole != nil {
                        Button { showNewPoll = true } label: { Label("New poll", systemImage: "chart.bar") }
                    }
                    if isManager {
                        Button { renameText = crew?.name ?? ""; showRename = true } label: { Label("Rename crew", systemImage: "pencil") }
                    }
                    Button(role: .destructive) { showReportCrew = true } label: {
                        Label(crewReported ? "Reported" : "Report crew", systemImage: "flag")
                    }
                    .disabled(crewReported)
                    if isOwner {
                        Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete crew", systemImage: "trash") }
                    } else if myRole != nil {
                        Button(role: .destructive) { showLeaveConfirm = true } label: { Label("Leave crew", systemImage: "rectangle.portrait.and.arrow.right") }
                    }
                } label: {
                    CircleIconButton(icon: "ellipsis", label: "More") {}.glyph
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func hero(_ crew: Crew) -> some View {
        ZStack(alignment: .bottomLeading) {
            CrewCover(id: crew.id, url: crew.coverImageUrl)
                .frame(height: 300)
                .overlay(LinearGradient(colors: [.clear, NTColor.pine], startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom))
            VStack(alignment: .leading, spacing: 14) {
                StatusChip(text: String(localized: "Private"), icon: "lock", filled: true)
                Text(crew.name).font(NTFont.heading(36, .extraBold)).tracking(-1).lineLimit(3)
                Button { showMembers = true } label: {
                    HStack(spacing: 12) {
                        AvatarStack(people: members.map(\.person), size: 34, maxShown: 5, ring: NTColor.pine)
                        Text("\(members.count) members").font(NTFont.body(15, .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.55))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { showNewTrip = true } label: {
                Label("New expedition", systemImage: "plus")
                    .font(NTFont.body(16, .semibold)).foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(NTColor.accent, in: Capsule())
                    .shadow(color: NTColor.accent.opacity(0.5), radius: 18, y: 10)
            }
            .buttonStyle(.plain).ntPressable()
            if myRole != nil {
                // Any member can invite — the invite loop is how a crew grows.
                Button { showInvite = true } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                        .font(NTFont.body(16, .semibold)).foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 22).frame(height: 60)
                        .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain).ntPressable()
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .background(
            NTColor.pine.opacity(0.96)
                .overlay(alignment: .top) { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                .ignoresSafeArea()
        )
    }

    private var membersSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Members").font(NTFont.heading(24, .extraBold))
                Spacer()
                CircleIconButton(icon: "xmark", label: "Close", filled: true) { showMembers = false }
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) { ForEach(members) { memberRow($0) } }
            }
        }
        .padding(.horizontal, 16).padding(.top, 22)
        .background(NTColor.pineElevated.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
    }

    private func memberRow(_ member: CrewMember) -> some View {
        HStack(spacing: 12) {
            PersonAvatar(person: member.person, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.person.displayName).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                Text("@\(member.person.username)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
            Text(roleTitle(member.role).uppercased())
                .font(NTFont.mono(9.5, .semibold)).tracking(0.4)
                .foregroundStyle(member.role == .owner ? NTColor.accent : NTColor.milk(0.6))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(Capsule().stroke(member.role == .owner ? NTColor.accent : NTColor.pineLine, lineWidth: 1))
            if member.person.id != myId { memberMenu(member) }
        }
        .padding(12)
        .crewCard(radius: 14)
    }

    private func memberMenu(_ member: CrewMember) -> some View {
        Menu {
            if isOwner && member.role != .owner {
                if member.role == .member {
                    Button { setRole(member.person, .organizer) } label: { Label("Make organizer", systemImage: "star") }
                } else {
                    Button { setRole(member.person, .member) } label: { Label("Make member", systemImage: "person") }
                }
                Button { transferUser = member.person } label: { Label("Hand over ownership", systemImage: "crown") }
            }
            if isManager && member.role != .owner && (isOwner || member.role == .member) {
                Button(role: .destructive) { removeUser = member.person } label: { Label("Remove from crew", systemImage: "person.badge.minus") }
            }
            Button(role: .destructive) { reportUser = member.person } label: { Label("Report user", systemImage: "flag") }
            Button(role: .destructive) { blockUser = member.person } label: { Label("Block user", systemImage: "hand.raised") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NTColor.milk(0.6))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var decisions: some View {
        if !polls.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("Decisions")
                ForEach(polls.prefix(4)) { poll in
                    Button { openPoll = poll } label: { PollSummaryCard(poll: poll, electorate: members.count) }
                        .buttonStyle(NTCardPressStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var expeditionsList: some View {
        let list = segment == .upcoming ? upcoming : past
        if list.isEmpty {
            VStack(spacing: 8) {
                Text(segment == .upcoming ? "No trips planned yet" : "No past trips")
                    .font(NTFont.heading(18, .bold))
                Text(segment == .upcoming
                     ? "Start an expedition and your crew can build the plan together."
                     : "Finished expeditions land here.")
                    .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.6)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(list) { e in
                    Button { openExpedition = e } label: { expeditionRow(e) }
                        .buttonStyle(NTCardPressStyle())
                }
            }
        }
    }

    private func expeditionRow(_ e: Expedition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(e.shortRange + (e.dayCount.map { " · \($0) DAYS" } ?? ""))
                    .font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.55))
                Spacer()
                switch e.status {
                case .planning: StatusChip(text: String(localized: "Planning"), color: NTColor.gold)
                case .active: StatusChip(text: String(localized: "Active"), color: NTColor.sage)
                case .completed: StatusChip(text: String(localized: "Done"), color: NTColor.milk(0.6))
                case .cancelled: StatusChip(text: String(localized: "Cancelled"), color: NTColor.hard)
                }
            }
            Text(e.name).font(NTFont.heading(21, .bold)).tracking(-0.4).multilineTextAlignment(.leading).lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: e.tripType.icon).font(.system(size: 12))
                Text(e.tripType.title).font(NTFont.body(13.5))
            }
            .foregroundStyle(NTColor.milk(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .crewCard()
    }

    // MARK: Actions

    private func load() async {
        myId = try? await RouteRepository.shared.ensureSession()
        async let c = try? CrewRepository.shared.fetchCrew(id: crewId)
        async let m = try? CrewRepository.shared.fetchCrewMembers(crewId: crewId)
        async let x = try? CrewRepository.shared.fetchCrewExpeditions(crewId: crewId)
        let (crewResult, memberResult, expeditionResult) = await (c, m, x)
        crew = crewResult
        members = memberResult ?? members
        expeditions = expeditionResult ?? expeditions
        polls = ((try? await CrewLiveRepository.shared.fetchPolls(crewId: crewId, expeditionId: nil)) ?? polls)
            .sorted { ($0.isClosed ? 1 : 0, $0.id.uuidString) < ($1.isClosed ? 1 : 0, $1.id.uuidString) }
        isLoading = false
    }

    private func perform(_ work: @escaping () async throws -> Void, then: (() -> Void)? = nil) {
        Task {
            do {
                try await work()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let then { then() } else { await load() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        perform { try await CrewRepository.shared.updateCrew(id: crewId, name: name) }
    }

    private func leave() { perform({ try await CrewRepository.shared.leaveCrew(id: crewId) }, then: onClose) }
    private func deleteCrew() { perform({ try await CrewRepository.shared.deleteCrew(id: crewId) }, then: onClose) }
    private func remove(_ p: CrewPerson) { perform { try await CrewRepository.shared.removeMember(crewId: crewId, userId: p.id) } }
    private func setRole(_ p: CrewPerson, _ role: CrewRole) {
        perform { try await CrewRepository.shared.setMemberRole(crewId: crewId, userId: p.id, role: role) }
    }
    private func block(_ p: CrewPerson) { perform { try await RouteRepository.shared.blockUser(p.id.uuidString) } }
}

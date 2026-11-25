import SwiftUI

/// One crew: header, roster with roles, its expeditions, invite and
/// leave / manage actions. Every change is an RPC; Report and Block are on the
/// crew itself and on each member (App Review Guideline 1.2).
struct CrewDetailView: View {
    let crewId: UUID
    var onClose: () -> Void

    @State private var crew: Crew?
    @State private var members: [CrewMember] = []
    @State private var expeditions: [Expedition] = []
    @State private var myId: UUID?
    @State private var isLoading = true

    @State private var inviteURL: URL?
    @State private var isMakingInvite = false

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

    private var myRole: CrewRole? { members.first { $0.person.id == myId }?.role }
    private var isManager: Bool { myRole?.isManager ?? false }
    private var isOwner: Bool { myRole == .owner }

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if let crew {
                        hero(crew)
                        // Any member can invite — the invite loop is how a crew grows.
                        if myRole != nil {
                            NTAccentButton(title: isMakingInvite ? "Creating link…" : "Invite friends", icon: "person.badge.plus") { invite() }
                                .disabled(isMakingInvite)
                        }
                        membersSection
                        expeditionsSection
                    } else if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 120)
                    } else {
                        Text("This crew isn't available.")
                            .font(NTFont.body(14, .medium)).foregroundStyle(NTColor.milk(0.6))
                            .frame(maxWidth: .infinity).padding(.top, 120)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
                .padding(.bottom, 60)
            }
            .refreshable { await load() }

            topBar
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: Binding(get: { inviteURL != nil }, set: { if !$0 { inviteURL = nil } })) {
            if let inviteURL {
                // Funnel step 1: counted only when something was really shared.
                ActivityView(items: [shareMessage(inviteURL)]) { completed, activity in
                    guard completed else { return }
                    RouteRepository.shared.logEvent("crew_invite_sent", metadata: [
                        "crew_id": crewId.uuidString, "channel": activity ?? "unknown",
                    ])
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showNewTrip) {
            CreateExpeditionView(crewId: crewId) { id in
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
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.08)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            if crew != nil {
                Menu {
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
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(NTColor.milk(0.08)))
                        .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    private func hero(_ crew: Crew) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RouteCoverImage(url: crew.coverImageUrl, tint: NTColor.pineRaised)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            Text(crew.name).font(NTFont.heading(28, .extraBold))
            Text("\(members.count) members")
                .font(NTFont.mono(11, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Members")
            VStack(spacing: 8) {
                ForEach(members) { member in memberRow(member) }
            }
        }
    }

    private func memberRow(_ member: CrewMember) -> some View {
        HStack(spacing: 12) {
            PersonAvatar(person: member.person, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.person.displayName).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                Text("@\(member.person.username)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
            Text(roleTitle(member.role))
                .font(NTFont.mono(9.5, .semibold)).tracking(0.4)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(member.role == .member ? NTColor.milk(0.08) : NTColor.accent.opacity(0.25)))
            if member.person.id != myId { memberMenu(member) }
        }
        .padding(12)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
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
                .frame(width: 32, height: 32)
        }
    }

    private var expeditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Expeditions")
                Spacer()
                Button { showNewTrip = true } label: {
                    Label("New trip", systemImage: "plus")
                        .font(NTFont.body(12.5, .semibold))
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(NTColor.milk(0.1)))
                }
                .buttonStyle(.plain)
            }
            if expeditions.isEmpty {
                Text("No trips yet.")
                    .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.55))
            } else {
                VStack(spacing: 8) {
                    ForEach(expeditions) { e in
                        Button { openExpedition = e } label: { expeditionRow(e) }
                            .buttonStyle(NTCardPressStyle())
                    }
                }
            }
        }
    }

    private func expeditionRow(_ e: Expedition) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.tripType.icon)
                .font(.system(size: 16))
                .frame(width: 42, height: 42)
                .background(Circle().fill(NTColor.milk(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                Text(dateRange(e)).font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.35))
        }
        .padding(12)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(NTFont.mono(11, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.55)).textCase(.uppercase)
    }

    private func dateRange(_ e: Expedition) -> String {
        guard let start = e.startDate else { return e.tripType.title }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "UTC")
        if let end = e.endDate, end != start { return "\(f.string(from: start)) – \(f.string(from: end))" }
        return f.string(from: start)
    }

    private func shareMessage(_ url: URL) -> String {
        String(localized: "Join my crew on Nomad: \(url.absoluteString)")
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

    private func invite() {
        isMakingInvite = true
        Task {
            do {
                let code = try await CrewRepository.shared.createInvite(crewId: crewId)
                inviteURL = CrewLinks.url(forInviteCode: code)
            } catch {
                errorMessage = error.localizedDescription
            }
            isMakingInvite = false
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
